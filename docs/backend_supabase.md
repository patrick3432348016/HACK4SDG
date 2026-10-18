# Historical Backend Draft: Supabase CommunityService

> **Superseded since 2026-10-10.** The integrated schema is [001_init.sql](../supabase/migrations/001_init.sql); see the [current backend guide](../supabase/README.md) and `ios/StreetWalk/Backend/`. The SQL below is an archived design, not a deployment script. Translation changes comments only within its SQL blocks and does not establish that its policies are secure or deployed.

The 7 October design described a local prototype using `CommunityService` and `LocalCommunityService`, with labeled simulated neighbors. A future `SupabaseCommunityService` would implement the same protocol. The 8 October contract added finding requests/replies/messages/trip progress, daily summaries, leave, profiles and report withdrawal. Their call sites were connected during the 10 October integration as noted below.

The draft adapted specification section 7, which required joint confirmation by both members on day one:

| Table | Change from the initial specification | Reason |
|---|---|---|
| `walks` | One daily row per user with minutes, steps, landmarks and greeting; no exact start/end times | Daily summaries do not require exact outing times |
| `leaves` | One row per day | Simpler queries; multi-day leave uses multiple rows |
| `users`, `landmarks` | No coordinates or home-radius field | Local home-radius calculations |
| `reports` | Add `follow_up` | Notify the reporter when addressed |
| `meetups` | Add `expired` | Hide meetings still unmet after an hour |
| `neighbors` | One directed row | Remove my relationship without a removal notification |

## 1. Historical privacy design

| Data | Storage | Proposed audience |
|---|---|---|
| Raw track and cadence | Phone memory during walking, not persisted/uploaded | The user |
| Daily summary and stopping landmark | Phone plus daily upload | Self; the draft exposed a daily sentence to the circle |
| Outing | Landmark ID in `outings` | Mutual neighbors with both relevant alert switches enabled |
| Relationship | `neighbors` | Relationship participants |
| Report | Landmark-linked `reports` | Reporter; aggregates above the threshold |
| Monthly/estate totals | Views or edge functions | Community workers, management and development teams |

The original design asserted coordinate-free server data and floor/building visibility without names to non-neighbors. **Those are superseded boundaries:** current non-neighbors do not see building/floor, and mutually agreed live finding temporarily exchanges precise coordinates through a private channel. Ordinary outings remain landmark-level. All tables were intended to default-deny through RLS.

## 2. Archived tables

```sql
-- Users: anonymous Supabase sign-in, without collecting phone numbers or email.
create table users (
  id uuid primary key references auth.users on delete cascade,
  nickname text not null,             -- Nickname, visible only to neighbors in this historical design.
  block text,                         -- Building.
  floor int,
  avatar jsonb not null,              -- {mobility, color, skin, age}
  estate_id text not null,            -- Estate / map grid.
  lang text default 'zh-HK',
  created_at timestamptz default now()
);

create table landmarks (
  id text primary key,                -- Stable ID derived from OSM feature ID / type.
                                      -- Prototype selected around each 200 m home base; proposed deployment would use shared tile-wide landmarks.
  estate_id text not null,
  circle_id uuid,
  name text not null,                 -- Current name; proposed rename scope is the circle.
  has_seat boolean not null default false
);

create table circles (id uuid primary key default gen_random_uuid(), estate_id text not null, name text not null);
create table circle_members (circle_id uuid references circles, user_id uuid references users, primary key (circle_id, user_id));

-- One directed neighbor relationship per row; removing my row does not notify the peer.
create table neighbors (
  owner uuid references users on delete cascade,
  other uuid references users on delete cascade,
  since timestamptz default now(),
  send_remind boolean default true,   -- Tell the peer when I go out.
  receive_remind boolean default true,-- Tell me when the peer goes out.
  primary key (owner, other)
);

-- Both phones submit a pairing code; the server inserts two neighbor rows when matched.
create table pair_codes (
  code text not null,
  user_id uuid references users on delete cascade,
  created_at timestamptz default now(),
  primary key (code, user_id)
);

-- Landmark-only outing state; delete on returning home / hiding.
create table outings (
  user_id uuid primary key references users on delete cascade,
  landmark_id text references landmarks,
  updated_at timestamptz default now()
);

create table walks (
  user_id uuid references users on delete cascade,
  day date not null,
  minutes int not null,
  steps int not null default 0,                    -- Monthly circle step comparison.
  landmark_ids text[] not null default '{}',       -- Pass-through landmarks in the original draft.
  stop_landmark_ids text[] not null default '{}',  -- Landmarks for stops of at least 2 minutes.
  daily_line text,
  primary key (user_id, day)
);

create table leaves (user_id uuid references users on delete cascade, day date, primary key (user_id, day));

create type meetup_status as enum ('waiting', 'accepted', 'done', 'cancelled', 'expired');
create table meetups (
  id uuid primary key,
  inviter uuid not null references users,
  invitee uuid not null references users,
  at timestamptz not null,
  landmark_id text references landmarks,
  reason text,                        -- Place-selection reason.
  status meetup_status not null default 'waiting',
  updated_by uuid,                    -- Last editor; the other party must reconfirm.
  updated_at timestamptz default now()
);

create type report_kind as enum ('sunny', 'no_seat', 'rough');
create table reports (
  id uuid primary key,
  user_id uuid references users on delete cascade,
  landmark_id text references landmarks,
  kind report_kind not null,
  raw_text text,                      -- Original report wording for classification, not public display.
  follow_up text,                     -- Management/community-worker reply delivered to the reporter.
  created_at timestamptz default now()
);
```

## 3. Archived RLS policies

```sql
-- Enable RLS on every table; no policy means denial.
alter table users enable row level security;
alter table landmarks enable row level security;
alter table circles enable row level security;
alter table circle_members enable row level security;
alter table neighbors enable row level security;
alter table pair_codes enable row level security;
alter table outings enable row level security;
alter table walks enable row level security;
alter table leaves enable row level security;
alter table meetups enable row level security;
alter table reports enable row level security;

-- Security-definer helpers inspect relationship rows without recursive RLS restrictions.
create function is_mutual_neighbor(a uuid, b uuid) returns boolean
  language sql stable security definer set search_path = public as $$
  select exists (select 1 from neighbors where owner = a and other = b)
     and exists (select 1 from neighbors where owner = b and other = a) $$;

create function can_see_outing(owner_id uuid, viewer uuid) returns boolean
  language sql stable security definer set search_path = public as $$
  select exists (select 1 from neighbors s join neighbors r on s.owner = owner_id and s.other = viewer
                 and r.owner = viewer and r.other = owner_id
                 where s.send_remind and r.receive_remind) $$;

create function same_circle(a uuid, b uuid) returns boolean
  language sql stable security definer set search_path = public as $$
  select exists (select 1 from circle_members x join circle_members y using (circle_id)
                 where x.user_id = a and y.user_id = b) $$;

-- Users read/update themselves; others access circle_board.
create policy "self" on users for select using (id = auth.uid());
create policy "self update" on users for update using (id = auth.uid()) with check (id = auth.uid());

-- Only circle members may read circles.
create policy "members" on circles for select using (
  exists (select 1 from circle_members m where m.circle_id = circles.id and m.user_id = auth.uid()));
create policy "members" on circle_members for select using (same_circle(user_id, auth.uid()));

-- Same-estate landmarks are readable; circle members may update only the name column.
create policy "estate" on landmarks for select using (
  estate_id = (select estate_id from users where id = auth.uid()));
create policy "rename in circle" on landmarks for update using (
  exists (select 1 from circle_members m where m.circle_id = landmarks.circle_id and m.user_id = auth.uid()));
revoke update on landmarks from authenticated;
grant update (name) on landmarks to authenticated;

-- Owners read/update/delete their row; insertion is allowed only through link_neighbor.
create policy "own select" on neighbors for select using (owner = auth.uid());
create policy "own update" on neighbors for update using (owner = auth.uid()) with check (owner = auth.uid());
create policy "own delete" on neighbors for delete using (owner = auth.uid());
create policy "no direct insert" on neighbors for insert with check (false);
revoke update on neighbors from authenticated;
grant update (send_remind, receive_remind) on neighbors to authenticated;

create policy "own code" on pair_codes for insert with check (user_id = auth.uid());

-- Pair two code submissions within 60 seconds; consume the code once.
create function link_neighbor(p_code text) returns uuid
  language plpgsql security definer set search_path = public as $$
declare other_id uuid;
begin
  select user_id into other_id from pair_codes
   where code = p_code and user_id <> auth.uid() and created_at > now() - interval '60 seconds';
  if other_id is null then return null; end if;
  insert into neighbors (owner, other) values (auth.uid(), other_id), (other_id, auth.uid()) on conflict do nothing;
  delete from pair_codes where code = p_code;
  return other_id;
end $$;

-- Outings: owner or mutual neighbors with sender-send and viewer-receive enabled.
create policy "own outing" on outings for all using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy "neighbors see outing" on outings for select using (can_see_outing(user_id, auth.uid()));

-- Walks/leave are self-only; rankings and aggregates use the section 4 privileged interfaces.
create policy "self" on walks for all using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy "self" on leaves for all using (user_id = auth.uid()) with check (user_id = auth.uid());

-- Only mutual neighbors may meet; only the two parties read/update, without changing participant IDs.
create policy "parties read" on meetups for select using (auth.uid() in (inviter, invitee));
create policy "invite neighbour" on meetups for insert with check (
  inviter = auth.uid() and is_mutual_neighbor(inviter, invitee));
create policy "parties update" on meetups for update using (auth.uid() in (inviter, invitee))
  with check (auth.uid() in (inviter, invitee));
revoke update on meetups from authenticated;
grant update (at, landmark_id, reason, status, updated_by, updated_at) on meetups to authenticated;

-- Users access their own reports; the proposed service-role administration writes follow_up.
create policy "own reports" on reports for all using (user_id = auth.uid()) with check (user_id = auth.uid());
```

The proposed privileged `circle_board` exposed `block, floor, avatar, streak, daily_line` to circle members and `nickname` only for mutual neighbors. This is historical; current `community_board` has different visibility rules.

## 4. Proposed anonymous aggregates

- `estate_passers_today(landmark_id)`: today's passers, returning no value below five accounts.
- `circle_race(month)`: monthly sum of `walks.steps`.
- `monthly_report(estate_id, month)`: proposed edge-function output for landmark/issue groups with at least 10 people, plus walk/companion totals, without individual tracks. B's `AIService.monthlyReport` would generate text. Current implementation uses its actual RPC and distinct anonymous-account threshold; accounts are not verified unique residents.

## 5. CommunityService mapping in the draft

| Method | Proposed Supabase implementation |
|---|---|
| `circleMembers` | Query `circle_board` for my circles |
| `linkNeighbor` | Both phones exchange a code, insert `pair_codes`, then call `link_neighbor` for two relationship rows |
| `unlinkNeighbor` | Delete my directed row without notifying removal |
| `updateRemind` | Update send/receive flags |
| `publishOuting` | Upsert a landmark; delete on return |
| `sendInvite`, `respond`, `updateMeetup` | Insert/update `meetups`, observed through Realtime |
| `renameLandmark` | Update only name within the authorized circle |
| `submitReport` | Insert report text and landmark ID; never upload `pos` |
| `retractReport` | Delete my report by ID under own-report policy |
| `askToFind`, `cancelFindAsk` | Private two-party broadcast request/reply with landmark ID; callback through answer |
| `broadcast` | Short location/arrival sentence on the same channel, not persisted |
| `departForMeetup`, `endMeetupTrip` | Proposed `meetup:<id>` channel with `PartnerTrip(etaMinutes, arrived)`, no coordinates |
| `uploadDay` | Upsert daily minutes, steps, landmark arrays and greeting |
| `setLeave` | Insert/delete daily leave rows |
| `updateProfile` | Update building/floor and avatar mobility/color/skin/age |
| `passersToday`, `circleRace`, `monthlyStats`, `othersReports` | Section 4 aggregate interfaces |
| `onEvent` | Subscribe to outings, meetings and report follow-up changes |

10 October integration notes: `uploadDay` runs after `recordWalk`, including background backfill, skips demo records and sends an empty pass-through array while uploading only stopping landmarks. Renames that change the daily greeting trigger another upload. `setLeave` uploads only changed dates, including voice requests. `updateProfile` follows onboarding and profile/appearance changes.

## 6. Original effort estimate, not a current deployment instruction

1. Supabase setup, anonymous auth, schema and policies: 0.5 day.
2. Proposed `supabase-swift` integration and service implementation: 1.5 days.
3. Realtime-to-CommunityEvent mapping: 0.5 day.
4. Two-device pairing → outing → invitation tests: 1 day.

These were estimates for the old design. Current migration or live-data changes require a separately authorized deployment and validation plan.
