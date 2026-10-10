# 街坊行后端（Supabase）

- 项目：`streetwalk`，新加坡机房（ap-southeast-1），免费版。地址和 App 用的 publishable key 写在 `ios/StreetWalk/Services/BackendConfig.swift`。
- 登录：匿名登录（Authentication → Sign In / Providers → Allow anonymous sign-ins 已开）。用户唔使注册、唔使电话。
- 结构：`migrations/001_init.sql`，喺 Supabase 网页的 SQL Editor 执行。所有表开 RLS；服务器上冇坐标、冇门牌，位置一律系地标名；座数楼层只有互为街坊先睇到。
- 测试：`python3 -I tests/rls_test.py <url> <publishable_key>`，用三个匿名用户跑 33 项权限检查（2026-10-10 全过）。测试会留低三个匿名用户，测完喺 SQL Editor 删：`delete from auth.users where id in (...)`（脚本最后一行印出 id）。
- 冇推送：免费苹果开发者账号用唔到 APNs。对方 App 开住时经 Realtime 即时收到；App 喺后台被系统叫醒时补拉。
