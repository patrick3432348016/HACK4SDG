# 街坊行后端（Supabase）

- 项目：`streetwalk`，新加坡机房（ap-southeast-1），免费版。地址和 App 用的 publishable key 写在 `ios/StreetWalk/Services/BackendConfig.swift`。
- 登录：匿名登录（Authentication → Sign In / Providers → Allow anonymous sign-ins 已开）。用户唔使注册、唔使电话。
- 「提意见」：`migrations/002_feedback.sql`（2026-10-17 新加，**要喺 SQL Editor 执行一次**）。App 设定 → 帮助与反馈 → 给我们提意见，写字撳「发送」插入 `feedback` 表；用户只可以插入自己嘅，冇读权限。团队喺 Table Editor 睇。
- 结构：`migrations/001_init.sql`，喺 Supabase 网页的 SQL Editor 执行。所有表开 RLS；服务器上冇坐标、冇门牌，位置一律系地标名；座数楼层只有互为街坊先睇到。
- 测试：`python3 -I tests/rls_test.py <url> <publishable_key>`，用三个匿名用户跑 35 项权限检查（2026-10-10 全过，含二维码配对）。测试会留低三个匿名用户，测完喺 SQL Editor 删：`delete from auth.users where id in (...)`（脚本最后一行印出 id）。
- 冇推送：免费苹果开发者账号用唔到 APNs。对方 App 开住时经 Realtime 即时收到；App 喺后台被系统叫醒时补拉。

## App 点用（2026-10-10 接上）

- 关咗演示模式（设置 → 演示模式）就用真后端：`ios/StreetWalk/Backend/SupabaseCommunityService.swift`。演示模式照用示範街坊。
- 客户端自己写（唔用第三方包）：`SupabaseAPI`（匿名登录、续期、PostgREST、RPC，登录状态存钥匙圈）、`RealtimeClient`（Phoenix 协议 vsn 1.0.0）、`Outbox`（写入排队，离线之后自动补送）。
- 收：App 开住时 Realtime（outings / neighbors / meetups 变咗就重新拉；signals 直接用推过嚟嘅行）+ 每 60 秒补拉；后台被叫醒（BGAppRefreshTask、定位唤醒）拉一次，有新嘢出本地通知。
- 出门状态：回家时 `landmark_name` 改成 null，**唔删行**（见下面 DELETE 事件）。出门超过 3 个钟冇更新，对方当佢返咗屋企。
- 地标名一律用改名前嘅原名上传；对方地图上冇同名地标就只显示文字。
- 测试：`ios/tools/backendtest.sh`（打正式后端 19 项：登录、续期、资料、排行榜、配对、Realtime、私有 pair 频道、排队）。会留低两个匿名用户，最后一行印出 id。

## 实测发现（2026-10-10）

- Realtime 嘅 **DELETE 事件唔经 RLS**：订阅咗某个表嘅所有人都会收到被删行嘅主键。即系 `neighbors` 有人解除街坊时，附近任何订阅者都见到 (owner, other) 两个 uuid；`outings` 删行会泄露边个返咗屋企。App 已经避开 outings 删行；`neighbors` 解除只能删行，建议执行下面第 1 条。
- 私有频道 `pair:<a>:<b>`：两个互为街坊可以加入、互相 broadcast；第三者加入收到 Unauthorized（实测通过）。

## 建议执行嘅 SQL（未执行，等负责人喺 SQL Editor 跑）

```sql
-- 1. 私隐：neighbors 唔再经 Realtime 推（DELETE 事件会泄露边两个人解除街坊）。App 每 60 秒补拉 my_neighbors，唔受影响。
alter publication supabase_realtime drop table public.neighbors;

-- 2. outings 只准改、唔准删（防止其他客户端删行触发会泄露嘅 DELETE 事件）。
drop policy "own outing" on public.outings;
create policy "own outing read" on public.outings for select using (user_id = auth.uid());
create policy "own outing insert" on public.outings for insert with check (user_id = auth.uid());
create policy "own outing update" on public.outings for update using (user_id = auth.uid()) with check (user_id = auth.uid());

-- 3. 「清除我嘅紀錄」真正删帐户（而家 App 只删得 walks / leaves / reports / outings / neighbors，profiles 冇删除权限，
--    所以将资料改做「已離開」搬去冇人嘅格子再登出）。加咗呢个函数之后 App 可以改用 rpc('delete_me')。
create function public.delete_me() returns void
  language sql security definer set search_path = public, auth as $$ delete from auth.users where id = auth.uid() $$;
revoke all on function public.delete_me() from public, anon;
grant execute on function public.delete_me() to authenticated;

-- 4. 清理（可选，要开 pg_cron）：用过嘅配对码、7 日前嘅信号。
-- select cron.schedule('sw-cleanup', '17 4 * * *', $$
--   delete from public.pair_codes where created_at = 'epoch' or created_at < now() - interval '1 day';
--   delete from public.signals where created_at < now() - interval '7 days' $$);
```
