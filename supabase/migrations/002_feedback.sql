-- 街坊行：App 内「提意见」（设定 → 帮助与反馈 → 给我们提意见）。
-- 喺 Supabase 网页 SQL Editor 执行一次（001_init.sql 之后）。未执行之前 App 发送会失败，草稿会保留喺手机。
--
-- 权限：登录（匿名）用户只可以插入自己嘅意见；冇 select / update / delete 规则 = 任何 App 用户都读唔到、改唔到（包括自己嘅）。
-- 开发团队喺 Supabase 网页 Table Editor 或者 SQL Editor 睇：
--   select created_at, lang, app_version, device, os, demo, body from public.feedback order by created_at desc;
-- 唔存位置；user_id 只系匿名帐户 id（冇电话、冇电邮）。用户删匿名帐户时一齐删（on delete cascade）。

create table public.feedback (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references auth.users on delete cascade,
  body text not null check (char_length(btrim(body)) between 1 and 2000),
  lang text check (lang in ('yue', 'cmn')),
  app_version text check (char_length(app_version) <= 40),
  device text check (char_length(device) <= 60),
  os text check (char_length(os) <= 40),
  demo boolean not null default false,
  created_at timestamptz not null default now()
);
create index feedback_created on public.feedback (created_at desc);

alter table public.feedback enable row level security;
revoke all on public.feedback from anon;

-- 同 001 一样靠 RLS：只有呢一条插入规则，读 / 改 / 删冇规则 = 全部拒绝。
create policy "insert own feedback" on public.feedback for insert to authenticated
  with check (user_id = auth.uid());
