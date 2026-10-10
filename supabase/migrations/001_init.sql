-- 街坊行 · Supabase 结构 v1（2026-10-10）
-- 原则：服务器上没有坐标、没有门牌；位置一律是地标名。家只在手机。
-- 社区 = 屋企所在的 400 m 格子（tile_x, tile_y），排行榜看附近 3×3 格（约 1.2 km）。
-- 所有表开 RLS，没有策略即拒绝。只给已登录（含匿名登录）用户权限。

-- ───────── 表 ─────────

create table public.profiles (
  id uuid primary key references auth.users on delete cascade,
  nickname text not null check (char_length(nickname) between 1 and 20),
  avatar jsonb not null default '{}'::jsonb,          -- mobility / color / skin / age
  tile_x int not null,
  tile_y int not null,
  community_name text,                                -- 例如「翠园」「皇后山邨」
  block text,                                         -- 座数：只有互为街坊看得到
  floor int,                                          -- 楼层：只有互为街坊看得到
  streak int not null default 0,                      -- 连续天数（手机算好上传）
  streak_day date,                                    -- streak 计到哪一日
  lang text not null default 'zh-HK',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- 街坊关系：一行一个方向。解除时只删自己那行，对方不会收到通知。
create table public.neighbors (
  owner uuid not null references public.profiles on delete cascade,
  other uuid not null references public.profiles on delete cascade,
  since timestamptz not null default now(),
  send_remind boolean not null default true,          -- 我出门话佢知
  receive_remind boolean not null default true,       -- 佢出门话我知
  primary key (owner, other)
);

-- 碰一碰：两部手机经近距离连接交换同一个一次性码，各自提交，配上就互为街坊。
create table public.pair_codes (
  code text not null,
  user_id uuid not null references public.profiles on delete cascade,
  created_at timestamptz not null default now(),
  primary key (code, user_id)
);

-- 出门状态：只有地标名。回家 / 隐身时删除。
create table public.outings (
  user_id uuid primary key references public.profiles on delete cascade,
  landmark_name text,
  started_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- 每日汇总：一人一日一行。没有几点几分、没有轨迹。
create table public.walks (
  user_id uuid not null references public.profiles on delete cascade,
  day date not null,
  minutes int not null default 0,
  steps int not null default 0,
  stop_landmarks text[] not null default '{}',        -- 落脚点地标名
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

-- 街坊之间的即时信号：问方唔方便、回覆、「我喺涼亭」、出发 / 到达、拍一拍。不含坐标。
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
  raw_text text,                                      -- 原话，只用于分类，不对外
  follow_up text,                                     -- 屋邨管理 / 社工回覆（后台写）
  created_at timestamptz not null default now()
);

-- ───────── 权限 ─────────

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

-- profiles：只读写自己；别人经 community_board() / my_neighbors() 看。
create policy "self read" on public.profiles for select using (id = auth.uid());
create policy "self insert" on public.profiles for insert with check (id = auth.uid());
create policy "self update" on public.profiles for update using (id = auth.uid()) with check (id = auth.uid());

-- neighbors：看、改提醒开关、删自己那行；不能直接插入，只能经 link_neighbor()。
create policy "own select" on public.neighbors for select using (owner = auth.uid());
create policy "own update" on public.neighbors for update using (owner = auth.uid()) with check (owner = auth.uid());
create policy "own delete" on public.neighbors for delete using (owner = auth.uid());
revoke insert, update on public.neighbors from authenticated;
grant update (send_remind, receive_remind) on public.neighbors to authenticated;

create policy "own code" on public.pair_codes for insert with check (user_id = auth.uid());

-- outings：自己全权；互为街坊且对方开「发送」、我开「接收」才看得到。
create policy "own outing" on public.outings for all using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy "neighbors see outing" on public.outings for select using (public.can_see_outing(user_id, auth.uid()));

create policy "self" on public.walks for all using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy "self" on public.leaves for all using (user_id = auth.uid()) with check (user_id = auth.uid());

-- meetups：只能约互为街坊；只有两个当事人看得到、改得到。
create policy "parties read" on public.meetups for select using (auth.uid() in (inviter, invitee));
create policy "invite neighbour" on public.meetups for insert
  with check (inviter = auth.uid() and public.is_mutual_neighbor(inviter, invitee));
create policy "parties update" on public.meetups for update using (auth.uid() in (inviter, invitee))
  with check (auth.uid() in (inviter, invitee));
revoke update on public.meetups from authenticated;
grant update (at, landmark_name, reason, status, updated_by, updated_at) on public.meetups to authenticated;

-- signals：只发给互为街坊；只有收发双方看得到。
create policy "send to neighbour" on public.signals for insert
  with check (from_user = auth.uid() and public.is_mutual_neighbor(from_user, to_user));
create policy "parties read" on public.signals for select using (auth.uid() in (from_user, to_user));

-- reports：只看自己的（含回覆）；汇总经 monthly_report()。
create policy "own reports" on public.reports for select using (user_id = auth.uid());
create policy "own insert" on public.reports for insert with check (user_id = auth.uid());
create policy "own delete" on public.reports for delete using (user_id = auth.uid());

-- ───────── 函数 ─────────

-- 碰一碰：两部手机提交同一个码，2 分钟内配上就写入两行；码只用一次。返回对方资料。
create function public.link_neighbor(p_code text)
returns table (id uuid, nickname text, avatar jsonb, block text, floor int)
  language plpgsql security definer set search_path = public as $$
declare other_id uuid;
begin
  -- 已经用呢个码配好：两边任何一方再问，都返回对方（二维码出示方靠呢个知道对方扫咗）。
  select pc.user_id into other_id from pair_codes pc
   where pc.code = p_code and pc.user_id <> auth.uid() and pc.created_at = 'epoch'
     and exists (select 1 from pair_codes m where m.code = p_code and m.user_id = auth.uid() and m.created_at = 'epoch')
   limit 1;
  if other_id is not null then
    return query select p.id, p.nickname, p.avatar, p.block, p.floor from profiles p where p.id = other_id;
    return;
  end if;
  -- 每个码只给两部手机用：已经有两个人提交过就拒绝第三个。
  if (select count(*) from pair_codes pc where pc.code = p_code and pc.user_id <> auth.uid()) > 1 then return; end if;
  insert into pair_codes (code, user_id) values (p_code, auth.uid()) on conflict do nothing;
  select pc.user_id into other_id from pair_codes pc
   where pc.code = p_code and pc.user_id <> auth.uid() and pc.created_at > now() - interval '2 minutes'
   limit 1;
  if other_id is null then return; end if;
  insert into neighbors (owner, other) values (auth.uid(), other_id), (other_id, auth.uid()) on conflict do nothing;
  -- 用过即作废：两行改成 epoch，第三个人再拿呢个码都配唔上。
  update pair_codes set created_at = 'epoch' where code = p_code;
  return query select p.id, p.nickname, p.avatar, p.block, p.floor from profiles p where p.id = other_id;
end $$;

-- 我的街坊（双方都还保留关系）。街坊才看得到座数和楼层。
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

-- 排行榜：附近 3×3 格的真人。所有人看到网名、小人、连续天数；只有街坊多看到今日一句。不出座数楼层。
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

-- 今日经过某地标的人数（附近社区），少于 5 人返回 null。
create function public.passers_today(p_landmark text) returns int
  language sql stable security definer set search_path = public as $$
  with me as (select tile_x, tile_y from profiles where id = auth.uid()),
  c as (select count(distinct w.user_id) n from walks w join profiles p on p.id = w.user_id, me
         where w.day = current_date and p_landmark = any (w.stop_landmarks)
           and abs(p.tile_x - me.tile_x) <= 1 and abs(p.tile_y - me.tile_y) <= 1)
  select case when n >= 5 then n::int end from c $$;

-- 月报：只出人数 ≥ 10 的「地标 × 反映类型」；另附散步人次。
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

-- ───────── 即时推送（App 开着时）─────────

alter publication supabase_realtime add table public.outings, public.meetups, public.signals, public.neighbors;

-- 找人时两个街坊之间临时共享位置：私有频道 pair:<较小uuid>:<较大uuid>，只放行这两个人，而且要互为街坊。
-- 位置只经这个频道即时转发，不落表。
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
