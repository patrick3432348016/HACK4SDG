#!/bin/sh
# Live Supabase client integration: anonymous auth, profiles, board, pairing, Realtime, private channels, refresh and outbox.
# No simulator required. Creates two anonymous users and prints IDs; authorized cleanup can delete those exact test users afterward.
# -v logs each request.
set -e
cd "$(dirname "$0")/.."
OUT=$(mktemp -d)/backendtest
swiftc -O -o "$OUT" \
  StreetWalk/Backend/BackendJSON.swift StreetWalk/Backend/SupabaseAPI.swift StreetWalk/Backend/RealtimeClient.swift \
  StreetWalk/Backend/BackendRows.swift StreetWalk/Backend/Outbox.swift \
  tools/backendtest/main.swift
"$OUT" "$@"
