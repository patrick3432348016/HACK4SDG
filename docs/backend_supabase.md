# 后端草案：Supabase 实现 CommunityService

> **2026-10-10 起已过时**：真后端已经接上，表结构以 `supabase/migrations/001_init.sql` 为准，App 点用见 `supabase/README.md`、`ios/StreetWalk/Backend/`。下面保留做历史参考。

状态（旧）：**未实现，原型阶段是单机演示**（2026-10-07 定）。App 里所有"要和别人同步"的操作都经过 `CommunityService` 协议（`ios/StreetWalk/Store/Community.swift`）。现在用的是 `LocalCommunityService`：数据只存在手机，圈里的其他人是「示範街坊」，界面上标了「示範」。

上线时新写一个 `SupabaseCommunityService`，实现同一个协议。2026-10-08 起找人（问对方、对方回覆、播送、出门 / 途中 / 到达）、每日汇总、请假、个人资料、撤回反映也都在协议里了；其中每日汇总、请假、个人资料的调用点还没接上（见 §5 末尾）。本文是它的表结构、权限规则和对应关系。

表以规格 §7 初稿为底（§7 写明"第 1 天两人一起确认"），按隐私原则做了这些改动：

| 表 | 和 §7 的差异 | 理由 |
|---|---|---|
| `walks` | 一人一日一行（分钟、步数、经过的地标、落脚点地标、当天一句），没有开始结束时间 | 服务器只要每日汇总，不需要知道几点几分在外面 |
| `leaves` | 一日一行（等同起止日期） | 查询简单；多日请假就是多行 |
| `users`、`landmarks` | 没有坐标，没有"家附近范围" | 服务器上不存任何坐标；家附近范围只在手机判断 |
| `reports` | 加 `follow_up` | F10：落实后通知反映的人 |
| `meetups` | 状态加 `expired` | 过时一个钟都冇碰头，收埋 |
| `neighbors` | 一个方向一行 | 解除时只删自己那行，对方不会收到通知 |

## 1. 隐私边界

| 数据 | 存在哪里 | 谁能看到 |
|---|---|---|
| 原始轨迹、步频 | 只在散步期间留在手机内存，不存盘、不上传 | 只有自己 |
| 每日散步汇总、落脚点地标 | 手机；上传当日汇总 | 自己；同圈的人只看到"今日行到 X"一句 |
| 出门状态 | `outings`，只有地标 id，没有坐标 | 只有双方互为街坊、对方开了"发送"、我开了"接收"时 |
| 街坊关系 | `neighbors` | 关系两端的人 |
| 反映 | `reports`，挂在地标上 | 本人；月报只出人数 ≥ 10 的汇总 |
| 月报、全邨数字 | 由视图 / 边缘函数汇总 | 社工、屋邨管理、新发展区团队 |

规则：

- 服务器上没有任何坐标，位置一律是地标 id。
- 非街坊之间看不到名字、照片、门牌；排行榜上只见座数、楼层和卡通小人。
- 所有表默认拒绝访问（RLS 全开），只按下面第 3 节的策略放行。

## 2. 表

```sql
-- 用户：匿名登录（Supabase anonymous sign-in），不收电话号码和电邮。
create table users (
  id uuid primary key references auth.users on delete cascade,
  nickname text not null,             -- 例如"陳太"，只有街坊看得到
  block text,                         -- 座数
  floor int,
  avatar jsonb not null,              -- {mobility, color, skin, age}
  estate_id text not null,            -- 屋邨（地图格子）
  lang text default 'zh-HK',
  created_at timestamptz default now()
);

create table landmarks (
  id text primary key,                -- 由地图要素（OSM id / 类型）推导的稳定 id
                                      -- 原型按各自屋企 200 m 底座挑；上线前改为按整格挑全邨共用的一组
  estate_id text not null,
  circle_id uuid,
  name text not null,                 -- 当前名字（改名后同圈生效）
  has_seat boolean not null default false
);

create table circles (id uuid primary key default gen_random_uuid(), estate_id text not null, name text not null);
create table circle_members (circle_id uuid references circles, user_id uuid references users, primary key (circle_id, user_id));

-- 街坊关系：按"一行一个方向"存，解除时只删自己那行，对方不会收到通知。
create table neighbors (
  owner uuid references users on delete cascade,
  other uuid references users on delete cascade,
  since timestamptz default now(),
  send_remind boolean default true,   -- 我出门话佢知
  receive_remind boolean default true,-- 佢出门话我知
  primary key (owner, other)
);

-- 碰一碰配对码：两部手机各提交一次，同一个码配上就由服务器写入两行 neighbors。
create table pair_codes (
  code text not null,
  user_id uuid references users on delete cascade,
  created_at timestamptz default now(),
  primary key (code, user_id)
);

-- 出门状态：只有地标，回家时删除（= 隐身）。
create table outings (
  user_id uuid primary key references users on delete cascade,
  landmark_id text references landmarks,
  updated_at timestamptz default now()
);

create table walks (
  user_id uuid references users on delete cascade,
  day date not null,
  minutes int not null,
  steps int not null default 0,                    -- 圈对圈按月比步数
  landmark_ids text[] not null default '{}',       -- 经过的地标
  stop_landmark_ids text[] not null default '{}',  -- 落脚点（停留 ≥ 2 分钟）对应的地标
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
  reason text,                        -- AI 选点理由
  status meetup_status not null default 'waiting',
  updated_by uuid,                    -- 最后改的人；对方要再确认
  updated_at timestamptz default now()
);

create type report_kind as enum ('sunny', 'no_seat', 'rough');
create table reports (
  id uuid primary key,
  user_id uuid references users on delete cascade,
  landmark_id text references landmarks,
  kind report_kind not null,
  raw_text text,                      -- 原话，只在汇总前给 AI 分类，不对外
  follow_up text,                     -- 屋邨管理 / 社工的回覆，会推送给反映的人
  created_at timestamptz default now()
);
```

## 3. 权限规则（RLS）

```sql
-- 全部表都开 RLS：没有策略就是拒绝。
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

-- 判断函数用 security definer：策略里的子查询不受对方那张表的 RLS 影响（否则读不到对方的 neighbors 行）。
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

-- users：只看到、改到自己；别人只能经 circle_board 视图看。
create policy "self" on users for select using (id = auth.uid());
create policy "self update" on users for update using (id = auth.uid()) with check (id = auth.uid());

-- 圈：只有圈内成员看到。
create policy "members" on circles for select using (
  exists (select 1 from circle_members m where m.circle_id = circles.id and m.user_id = auth.uid()));
create policy "members" on circle_members for select using (same_circle(user_id, auth.uid()));

-- 地标：同屋邨可看；同圈成员可以改名（只开放 name 一栏）。
create policy "estate" on landmarks for select using (
  estate_id = (select estate_id from users where id = auth.uid()));
create policy "rename in circle" on landmarks for update using (
  exists (select 1 from circle_members m where m.circle_id = landmarks.circle_id and m.user_id = auth.uid()));
revoke update on landmarks from authenticated;
grant update (name) on landmarks to authenticated;

-- 街坊关系：看、改、删自己那行；不能直接插入，只能经 link_neighbor() 配对。
create policy "own select" on neighbors for select using (owner = auth.uid());
create policy "own update" on neighbors for update using (owner = auth.uid()) with check (owner = auth.uid());
create policy "own delete" on neighbors for delete using (owner = auth.uid());
create policy "no direct insert" on neighbors for insert with check (false);
revoke update on neighbors from authenticated;
grant update (send_remind, receive_remind) on neighbors to authenticated;

create policy "own code" on pair_codes for insert with check (user_id = auth.uid());

-- 碰一碰：两部手机提交同一个码，60 秒内配上就写入两行；码只用一次。
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

-- 出门状态：自己；或者对方开了"发送"、我开了"接收"、双方互为街坊。
create policy "own outing" on outings for all using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy "neighbors see outing" on outings for select using (can_see_outing(user_id, auth.uid()));

-- 散步、请假：只有本人；排行榜和匿名汇总走第 4 节的 security definer 视图 / 函数。
create policy "self" on walks for all using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy "self" on leaves for all using (user_id = auth.uid()) with check (user_id = auth.uid());

-- 约会：只能约互为街坊的人（F5 / F7）；只有两个当事人看得到、改得到；不能改双方是谁。
create policy "parties read" on meetups for select using (auth.uid() in (inviter, invitee));
create policy "invite neighbour" on meetups for insert with check (
  inviter = auth.uid() and is_mutual_neighbor(inviter, invitee));
create policy "parties update" on meetups for update using (auth.uid() in (inviter, invitee))
  with check (auth.uid() in (inviter, invitee));
revoke update on meetups from authenticated;
grant update (at, landmark_id, reason, status, updated_by, updated_at) on meetups to authenticated;

-- 反映：只看自己的；follow_up 由社工后台（service role）写。
create policy "own reports" on reports for all using (user_id = auth.uid()) with check (user_id = auth.uid());
```

排行榜由 security definer 视图 `circle_board` 提供：同圈成员输出 `block, floor, avatar, streak, daily_line`；只有 `is_mutual_neighbor(auth.uid(), member)` 为真时，才多输出 `nickname`。

## 4. 匿名汇总（k 匿名）

- `estate_passers_today(landmark_id)`：今日经过某地标的人数，少于 5 人返回空。App 里对应「今朝 N 人經過…」。
- `circle_race(month)`：圈内总步数（`walks.steps` 按月加总）。
- `monthly_report(estate_id, month)`：边缘函数。只输出人数 ≥ 10 的「地标 × 反映类型」，以及散步人次、一齐行次数；不输出个人轨迹。结果交给 B 的 `AIService.monthlyReport` 生成文字。

## 5. CommunityService 方法 → Supabase

| 方法 | 实现 |
|---|---|
| `circleMembers` | `select * from circle_board where circle_id in (我的圈)` |
| `linkNeighbor` | 碰一碰时两部手机经 MultipeerConnectivity 交换同一个配对码，各自 `insert into pair_codes` 再调用 `link_neighbor(code)`，服务器写入两行 |
| `unlinkNeighbor` | `delete from neighbors where owner = me and other = id`（不通知对方） |
| `updateRemind` | `update neighbors set send_remind, receive_remind` |
| `publishOuting` | `upsert outings`（地标）/ `delete`（回家隐身） |
| `sendInvite` / `respond` / `updateMeetup` | `insert` / `update meetups`；对方用 Realtime 订阅 `meetups` 收到变化 |
| `renameLandmark` | `update landmarks set name`（同圈生效；策略限同圈成员、只开放 name 一栏） |
| `submitReport` | `insert into reports`（`Report.rawText` → `raw_text`；`pos` 不上传，只传 `landmark_id`） |
| `retractReport` | `delete from reports where id = … and user_id = auth.uid()`（策略 "own reports" 已允许） |
| `askToFind` / `cancelFindAsk` | Realtime Broadcast（两人私有频道，Realtime Authorization 只放行两个当事人，只传地标 id）；对方撳「好 / 唔方便」后回传，App 按 `answer` 回调处理 |
| `broadcast` | 同一频道发一句「我喺X」/「我就到X」，不落表 |
| `departForMeetup` / `endMeetupTrip` | `meetup:<id>` 频道：我出门 + 大约几分钟；对方出门、途中、到达时回传 `PartnerTrip(etaMinutes, arrived)`（可以多次），不落表、不传坐标 |
| `uploadDay` | `upsert walks (user_id, day, minutes, steps, landmark_ids, stop_landmark_ids, daily_line)` |
| `setLeave` | `insert` / `delete from leaves` |
| `updateProfile` | `update users set block, floor, avatar`（avatar 存 mobility、color、skin、age） |
| `passersToday` / `circleRace` / `monthlyStats` / `othersReports` | 上面第 4 节的视图和函数 |
| `onEvent` | Realtime：订阅 `outings`（街坊出门）、`meetups`（约会变化）、`reports.follow_up`（反映回覆） |

调用点（2026-10-10 合并时接上）：`uploadDay` 在每次 `recordWalk` 之后（含锁屏补记；示範纪录不传；经过的地标只留手机，`landmark_ids` 暂时传空，只传落脚点），改名令今日一句变了再传一次；`setLeave` 在请假、撤回时逐日传真正变了的日子（含语音「聽日請假」）；`updateProfile` 在完成首次使用、设置页改楼层 / 小人 / 年纪 / 肤色之后。

## 6. 上线步骤（估计）

1. 建 Supabase 项目，执行上面的 SQL（表、全部 RLS 策略、三个判断函数、`link_neighbor`），开匿名登录：0.5 天。
2. 加 `supabase-swift`，写 `SupabaseCommunityService`：1.5 天。
3. Realtime 推送接到 `CommunityEvent`：0.5 天。
4. 两部真机测试碰一碰 → 出门提醒 → 约人：1 天。
