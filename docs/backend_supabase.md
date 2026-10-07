# 后端草案：Supabase 实现 CommunityService

状态：**未实现，原型阶段是单机演示**（2026-10-07 定）。App 里所有"要和别人同步"的操作都经过 `CommunityService` 协议（`ios/StreetWalk/Store/Community.swift`）。现在用的是 `LocalCommunityService`：数据只存在手机，圈里的其他人是「示範街坊」，界面上标了「示範」。

上线时新写一个 `SupabaseCommunityService`，实现同一个协议，App 其他部分都不用改。本文是它的表结构、权限规则和对应关系。表的字段沿用规格 §7。

## 1. 隐私边界

| 数据 | 存在哪里 | 谁能看到 |
|---|---|---|
| 原始轨迹、步频 | 只在手机（`LocalStore`） | 只有自己 |
| 每日散步分钟、经过的地标 | 手机；上传当日汇总 | 同圈的人只看到"今日行到 X"一句 |
| 出门状态 | `outings`，只有地标 id，没有坐标 | 只有开了"接收"的街坊 |
| 街坊关系 | `neighbors` | 关系两端的人 |
| 反映 | `reports`，挂在地标上 | 本人；月报只出人数 ≥ 10 的汇总 |
| 月报、全邨数字 | 由视图 / 边缘函数汇总 | 社工、屋邨管理、新发展区团队 |

规则：

- 服务器上没有任何坐标，位置一律是地标 id。
- 非街坊之间看不到名字、照片、门牌。

## 2. 表

```sql
-- 用户：匿名登录（Supabase anonymous sign-in），不收电话号码和电邮。
create table users (
  id uuid primary key references auth.users on delete cascade,
  nickname text not null,             -- 例如"陳太"，只有街坊看得到
  block text,                         -- 座数
  floor int,
  avatar jsonb not null,              -- {mobility, color}
  estate_id text not null,            -- 屋邨（地图格子）
  lang text default 'zh-HK',
  created_at timestamptz default now()
);

create table landmarks (
  id text primary key,                -- 例如 'park-0'，由地图格子推导，同一格每部手机一样
  estate_id text not null,
  name text not null,                 -- 当前名字（改名后同圈生效）
  has_seat boolean not null default false,
  circle_id uuid
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

-- 出门状态：只有地标，回家时删除（= 隐身）。
create table outings (
  user_id uuid primary key references users on delete cascade,
  landmark_id text references landmarks,
  updated_at timestamptz default now()
);

create table walks (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references users on delete cascade,
  day date not null,
  minutes int not null,
  landmark_ids text[] not null default '{}',
  daily_line text
);

create table leaves (user_id uuid references users, day date, primary key (user_id, day));

create type meetup_status as enum ('waiting', 'accepted', 'done', 'cancelled', 'expired');
create table meetups (
  id uuid primary key,
  inviter uuid references users,
  invitee uuid references users,
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

## 3. 权限规则（RLS 要点）

```sql
alter table neighbors enable row level security;
create policy "own rows" on neighbors for all using (owner = auth.uid());

-- 只有"对方把我当街坊、开了发送"，而且"我把对方当街坊、开了接收"时，才看得到对方的出门状态。
alter table outings enable row level security;
create policy "neighbors can see outing" on outings for select using (
  user_id = auth.uid() or exists (
    select 1 from neighbors a join neighbors b on a.owner = outings.user_id and a.other = auth.uid()
      and b.owner = auth.uid() and b.other = outings.user_id
    where a.send_remind and b.receive_remind));
create policy "own outing" on outings for all using (user_id = auth.uid());

-- 约会：只有两个当事人。
alter table meetups enable row level security;
create policy "parties" on meetups for all using (auth.uid() in (inviter, invitee));

-- 反映：只看自己的；汇总走下面的视图。
alter table reports enable row level security;
create policy "own reports" on reports for all using (user_id = auth.uid());
```

非街坊在排行榜上只显示楼层：`users` 不直接开放给同圈的人，排行榜由视图 `circle_board` 提供，只输出 `floor, avatar, streak, daily_line`；只有已是街坊的人，才会多一个 `nickname`。

## 4. 匿名汇总（k 匿名）

- `estate_passers_today(landmark_id)`：今日经过某地标的人数，少于 5 人返回空。App 里对应「今朝 N 人經過…」。
- `circle_race(month)`：圈内总步数。
- `monthly_report(estate_id, month)`：边缘函数。只输出人数 ≥ 10 的「地标 × 反映类型」，以及散步人次、一齐行次数；不输出个人轨迹。结果交给 B 的 `AIService.monthlyReport` 生成文字。

## 5. CommunityService 方法 → Supabase

| 方法 | 实现 |
|---|---|
| `circleMembers` | `select * from circle_board where circle_id in (我的圈)` |
| `linkNeighbor` | 碰一碰成功后两部手机各 `insert into neighbors`（凭证经 MultipeerConnectivity 交换，服务器校验双方都提交了同一个配对码） |
| `unlinkNeighbor` | `delete from neighbors where owner = me and other = id`（不通知对方） |
| `updateRemind` | `update neighbors set send_remind, receive_remind` |
| `publishOuting` | `upsert outings`（地标）/ `delete`（回家隐身） |
| `sendInvite` / `respond` / `updateMeetup` | `insert` / `update meetups`；对方用 Realtime 订阅 `meetups` 收到变化 |
| `renameLandmark` | `update landmarks set name`（同圈生效；RLS 限同圈成员） |
| `submitReport` | `insert into reports` |
| `passersToday` / `circleRace` / `monthlyStats` / `othersReports` | 上面第 4 节的视图和函数 |
| `onEvent` | Realtime：订阅 `outings`（街坊出门）、`meetups`（约会变化）、`reports.follow_up`（反映回覆） |

## 6. 上线步骤（估计）

1. 建 Supabase 项目，执行上面的 SQL，开匿名登录：0.5 天。
2. 加 `supabase-swift`，写 `SupabaseCommunityService`：1.5 天。
3. Realtime 推送接到 `CommunityEvent`：0.5 天。
4. 两部真机测试碰一碰 → 出门提醒 → 约人：1 天。
