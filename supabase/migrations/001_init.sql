-- StreetWalk Supabase schema v1, 2026-10-10.
-- These tables use landmark names rather than precise coordinates or unit numbers; live finding uses a separate temporary private channel.
-- Community is the home's 400 m tile_x/tile_y grid; leaderboard spans nearby 3 x 3 cells, roughly 1.2 km.
-- Enable RLS everywhere, deny without a policy, and grant only authenticated users including anonymous sign-ins.

-- Tables.

create table public.profiles (
  id uuid primary key references auth.users on delete cascade,
  nickname text not null check (char_length(nickname) between 1 and 20),
  avatar jsonb not null default '{}'::jsonb,          -- mobility / color / skin / age
  tile_x int not null,
  tile_y int not null,
  community_name text,                                -- Estate name, such as Green Garden or Queen's Hill Estate.
  block text,                                         -- Building visible only to mutual neighbors.
  floor int,                                          -- Floor visible only to mutual neighbors.
  streak int not null default 0,                      -- Streak computed and uploaded by the phone.
  streak_day date,                                    -- Date through which streak was calculated.
  lang text not null default 'zh-HK',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- One directional relationship per row; removal deletes only the owner's row without notifying the peer.
create table public.neighbors (
  owner uuid not null references public.profiles on delete cascade,
  other uuid not null references public.profiles on delete cascade,
  since timestamptz not null default now(),
  send_remind boolean not null default true,          -- Notify the peer when I go out.
  receive_remind boolean not null default true,       -- Notify me when the peer goes out.
  primary key (owner, other)
);

-- Both nearby phones submit the same one-time code to become mutual neighbors.
create table public.pair_codes (
  code text not null,
  user_id uuid not null references public.profiles on delete cascade,
  created_at timestamptz not null default now(),
  primary key (code, user_id)
);

-- Outing stores only a landmark name and is deleted on return/hiding.
create table public.outings (
  user_id uuid primary key references public.profiles on delete cascade,
  landmark_name text,
  started_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- One daily summary per user; no exact outing times or tracks.
create table public.walks (
  user_id uuid not null references public.profiles on delete cascade,
  day date not null,
  minutes int not null default 0,
  steps int not null default 0,
  stop_landmarks text[] not null default '{}',        -- Stopping landmark names.
  daily_line text,
  primary key (user_id, day)
);

create table public.leaves (
  user_id uuid not null references public.profiles on delete cascade,
  day date not null,
  primary key (user_id, day)
);

create type public.meetup_status as enum ('waiting', 'accepted', 'declined', 'done', 'cancelled', 'expired');
create table public.meetups (
  id uuid primary key default gen_random_uuid(),
  inviter uuid not null references public.profiles on delete cascade,
  invitee uuid not null references public.profiles on delete cascade,
  at timestamptz not null,
  landmark_name text,
  reason text,
  status public.meetup_status not null default 'waiting',
  updated_by uuid,
  updated_at timestamptz not null default now()
);

-- Coordinate-free neighbor signals: requests, replies, short messages, departure/arrival and nudges.
create table public.signals (
  id bigint generated always as identity primary key,
  from_user uuid not null references public.profiles on delete cascade,
  to_user uuid not null references public.profiles on delete cascade,
  kind text not null check (kind in ('find_ask', 'find_answer', 'find_cancel', 'say', 'trip', 'poke')),
  payload jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);
create index signals_to_user on public.signals (to_user, created_at desc);

create type public.report_kind as enum ('sunny', 'no_seat', 'rough', 'other');
create table public.reports (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles on delete cascade,
  tile_x int not null,
  tile_y int not null,
  landmark_name text not null,
  kind public.report_kind not null,
  raw_text text,                                      -- Original text for classification, not public display.
  follow_up text,                                     -- Management/community-worker reply written through administration.
  created_at timestamptz not null default now()
);

-- Permissions.

revoke all on all tables in schema public from anon;
revoke all on all functions in schema public from anon;
alter default privileges in schema public revoke all on tables from anon;
alter default privileges in schema public revoke all on functions from anon;

alter table public.profiles enable row level security;
alter table public.neighbors enable row level security;
alter table public.pair_codes enable row level security;
alter table public.outings enable row level security;
alter table public.walks enable row level security;
alter table public.leaves enable row level security;
alter table public.meetups enable row level security;
alter table public.signals enable row level security;
alter table public.reports enable row level security;

create function public.is_mutual_neighbor(a uuid, b uuid) returns boolean
  language sql stable security definer set search_path = public as $$
  select exists (select 1 from neighbors where owner = a and other = b)
     and exists (select 1 from neighbors where owner = b and other = a) $$;

create function public.can_see_outing(owner_id uuid, viewer uuid) returns boolean
  language sql stable security definer set search_path = public as $$
  select exists (select 1 from neighbors s join neighbors r
                   on s.owner = owner_id and s.other = viewer and r.owner = viewer and r.other = owner_id
                 where s.send_remind and r.receive_remind) $$;

-- Profiles are self-readable/writable; others access community_board or my_neighbors.
create policy "self read" on public.profiles for select using (id = auth.uid());
create policy "self insert" on public.profiles for insert with check (id = auth.uid());
create policy "self update" on public.profiles for update using (id = auth.uid()) with check (id = auth.uid());

-- Owners read, delete and change alert switches; insertion occurs only through link_neighbor.
create policy "own select" on public.neighbors for select using (owner = auth.uid());
create policy "own update" on public.neighbors for update using (owner = auth.uid()) with check (owner = auth.uid());
create policy "own delete" on public.neighbors for delete using (owner = auth.uid());
revoke insert, update on public.neighbors from authenticated;
grant update (send_remind, receive_remind) on public.neighbors to authenticated;

create policy "own code" on public.pair_codes for insert with check (user_id = auth.uid());

-- Outing visibility requires ownership or mutual relationship with sender-send and viewer-receive enabled.
create policy "own outing" on public.outings for all using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy "neighbors see outing" on public.outings for select using (public.can_see_outing(user_id, auth.uid()));

create policy "self" on public.walks for all using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy "self" on public.leaves for all using (user_id = auth.uid()) with check (user_id = auth.uid());

-- Meetups require mutual neighbors and are visible/editable only to the two parties.
create policy "parties read" on public.meetups for select using (auth.uid() in (inviter, invitee));
create policy "invite neighbour" on public.meetups for insert
  with check (inviter = auth.uid() and public.is_mutual_neighbor(inviter, invitee));
create policy "parties update" on public.meetups for update using (auth.uid() in (inviter, invitee))
  with check (auth.uid() in (inviter, invitee));
revoke update on public.meetups from authenticated;
grant update (at, landmark_name, reason, status, updated_by, updated_at) on public.meetups to authenticated;

-- Signals may be sent only to mutual neighbors and read only by sender/recipient.
create policy "send to neighbour" on public.signals for insert
  with check (from_user = auth.uid() and public.is_mutual_neighbor(from_user, to_user));
create policy "parties read" on public.signals for select using (auth.uid() in (from_user, to_user));

-- Users read only their reports and replies; aggregate through monthly_report.
create policy "own reports" on public.reports for select using (user_id = auth.uid());
create policy "own insert" on public.reports for insert with check (user_id = auth.uid());
create policy "own delete" on public.reports for delete using (user_id = auth.uid());

-- Functions.

-- Pair two submissions within 2 minutes, consume the code and return peer details.
create function public.link_neighbor(p_code text)
returns table (id uuid, nickname text, avatar jsonb, block text, floor int)
  language plpgsql security definer set search_path = public as $$
declare other_id uuid;
begin
  -- Either paired phone can query again for the peer, allowing a QR presenter to detect a completed scan.
  select pc.user_id into other_id from pair_codes pc
   where pc.code = p_code and pc.user_id <> auth.uid() and pc.created_at = 'epoch'
     and exists (select 1 from pair_codes m where m.code = p_code and m.user_id = auth.uid() and m.created_at = 'epoch')
   limit 1;
  if other_id is not null then
    return query select p.id, p.nickname, p.avatar, p.block, p.floor from profiles p where p.id = other_id;
    return;
  end if;
  -- Reject a third user once two have submitted a code.
  if (select count(*) from pair_codes pc where pc.code = p_code and pc.user_id <> auth.uid()) > 1 then return; end if;
  insert into pair_codes (code, user_id) values (p_code, auth.uid()) on conflict do nothing;
  select pc.user_id into other_id from pair_codes pc
   where pc.code = p_code and pc.user_id <> auth.uid() and pc.created_at > now() - interval '2 minutes'
   limit 1;
  if other_id is null then return; end if;
  insert into neighbors (owner, other) values (auth.uid(), other_id), (other_id, auth.uid()) on conflict do nothing;
  -- Invalidate used codes by setting both timestamps to epoch, preventing a third pairing.
  update pair_codes set created_at = 'epoch' where code = p_code;
  return query select p.id, p.nickname, p.avatar, p.block, p.floor from profiles p where p.id = other_id;
end $$;

-- Return only mutual neighbors; building/floor visibility is restricted to them.
create function public.my_neighbors()
returns table (id uuid, nickname text, avatar jsonb, block text, floor int, streak int,
               since timestamptz, send_remind boolean, receive_remind boolean,
               out_at text, out_since timestamptz, daily_line text)
  language sql stable security definer set search_path = public as $$
  select p.id, p.nickname, p.avatar, p.block, p.floor,
         case when p.streak_day >= current_date - 1 then p.streak else 0 end,
         n.since, n.send_remind, n.receive_remind,
         case when public.can_see_outing(p.id, auth.uid()) then o.landmark_name end,
         case when public.can_see_outing(p.id, auth.uid()) then o.started_at end,
         w.daily_line
    from neighbors n
    join profiles p on p.id = n.other
    left join outings o on o.user_id = p.id
    left join walks w on w.user_id = p.id and w.day = current_date
   where n.owner = auth.uid() and public.is_mutual_neighbor(auth.uid(), p.id) $$;

-- Leaderboard spans nearby 3 x 3 cells with nickname/avatar/streak for all and daily greetings for neighbors; omit building/floor.
create function public.community_board()
returns table (id uuid, nickname text, avatar jsonb, streak int, month_steps bigint,
               is_me boolean, is_neighbor boolean, daily_line text)
  language sql stable security definer set search_path = public as $$
  with me as (select tile_x, tile_y from profiles where id = auth.uid())
  select p.id, p.nickname, p.avatar,
         case when p.streak_day >= current_date - 1 then p.streak else 0 end as streak,
         coalesce((select sum(w.steps) from walks w
                    where w.user_id = p.id and w.day >= date_trunc('month', current_date)), 0),
         p.id = auth.uid(),
         public.is_mutual_neighbor(auth.uid(), p.id),
         case when p.id = auth.uid() or public.is_mutual_neighbor(auth.uid(), p.id)
              then (select w.daily_line from walks w where w.user_id = p.id and w.day = current_date) end
    from profiles p, me
   where abs(p.tile_x - me.tile_x) <= 1 and abs(p.tile_y - me.tile_y) <= 1
   order by 4 desc, p.created_at
   limit 100 $$;

-- Nearby-community passers at a landmark today; return null below five accounts.
create function public.passers_today(p_landmark text) returns int
  language sql stable security definer set search_path = public as $$
  with me as (select tile_x, tile_y from profiles where id = auth.uid()),
  c as (select count(distinct w.user_id) n from walks w join profiles p on p.id = w.user_id, me
         where w.day = current_date and p_landmark = any (w.stop_landmarks)
           and abs(p.tile_x - me.tile_x) <= 1 and abs(p.tile_y - me.tile_y) <= 1)
  select case when n >= 5 then n::int end from c $$;

-- Monthly landmark/issue aggregates require at least 10 distinct accounts and include walking totals.
create function public.monthly_report(p_month date default date_trunc('month', current_date)::date)
returns table (landmark_name text, kind public.report_kind, people bigint, walk_count bigint, walkers bigint)
  language sql stable security definer set search_path = public as $$
  with me as (select tile_x, tile_y from profiles where id = auth.uid()),
  area as (select p.id from profiles p, me where abs(p.tile_x - me.tile_x) <= 1 and abs(p.tile_y - me.tile_y) <= 1),
  stats as (select count(*) wc, count(distinct w.user_id) wk from walks w
             where w.user_id in (select id from area)
               and w.day >= p_month and w.day < (p_month + interval '1 month'))
  select r.landmark_name, r.kind, count(distinct r.user_id), stats.wc, stats.wk
    from reports r, stats
   where r.user_id in (select id from area)
     and r.created_at >= p_month and r.created_at < (p_month + interval '1 month')
   group by r.landmark_name, r.kind, stats.wc, stats.wk
  having count(distinct r.user_id) >= 10 $$;

revoke all on function public.link_neighbor(text) from public, anon;
revoke all on function public.my_neighbors() from public, anon;
revoke all on function public.community_board() from public, anon;
revoke all on function public.passers_today(text) from public, anon;
revoke all on function public.monthly_report(date) from public, anon;
grant execute on function public.link_neighbor(text) to authenticated;
grant execute on function public.my_neighbors() to authenticated;
grant execute on function public.community_board() to authenticated;
grant execute on function public.passers_today(text) to authenticated;
grant execute on function public.monthly_report(date) to authenticated;

-- Realtime delivery while the App is open.

alter publication supabase_realtime add table public.outings, public.meetups, public.signals, public.neighbors;

-- Live finding temporarily shares coordinates over private pair:<smaller UUID>:<larger UUID>, restricted to those mutual neighbors.
-- Forward coordinates through the channel without storing them in tables.
create policy "pair channel read" on realtime.messages for select to authenticated using (
  realtime.topic() like 'pair:%'
  and auth.uid()::text = any (string_to_array(substr(realtime.topic(), 6), ':'))
  and public.is_mutual_neighbor((string_to_array(substr(realtime.topic(), 6), ':'))[1]::uuid,
                                (string_to_array(substr(realtime.topic(), 6), ':'))[2]::uuid));
create policy "pair channel write" on realtime.messages for insert to authenticated with check (
  realtime.topic() like 'pair:%'
  and auth.uid()::text = any (string_to_array(substr(realtime.topic(), 6), ':'))
  and public.is_mutual_neighbor((string_to_array(substr(realtime.topic(), 6), ':'))[1]::uuid,
                                (string_to_array(substr(realtime.topic(), 6), ':'))[2]::uuid));
