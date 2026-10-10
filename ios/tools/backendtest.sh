#!/bin/sh
# 后端客户端集成测试：打正式 Supabase（匿名登录、资料、排行榜、配对、Realtime、私有 pair 频道、续期、outbox）。
# 唔使模拟器。会留低两个匿名测试用户（最后一行印出 id），测完喺 Supabase SQL Editor：delete from auth.users where id in (...);
# 加 -v 打印每个请求。
set -e
cd "$(dirname "$0")/.."
OUT=$(mktemp -d)/backendtest
swiftc -O -o "$OUT" \
  StreetWalk/Backend/BackendJSON.swift StreetWalk/Backend/SupabaseAPI.swift StreetWalk/Backend/RealtimeClient.swift \
  StreetWalk/Backend/BackendRows.swift StreetWalk/Backend/Outbox.swift \
  tools/backendtest/main.swift
"$OUT" "$@"
