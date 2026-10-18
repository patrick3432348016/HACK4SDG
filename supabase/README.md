# StreetWalk backend — Supabase

- Project: `streetwalk`, Singapore (`ap-southeast-1`), free plan. The service URL and app publishable key are configured in `ios/StreetWalk/Services/BackendConfig.swift`.
- Authentication: anonymous sign-in is enabled. Residents do not need to register or provide a phone number.
- App feedback: `migrations/002_feedback.sql`, added on 17 October, creates the feedback table. Settings → Help & Feedback → Send Feedback inserts a user's own row; users cannot read the table. The team reviews feedback in Table Editor. **Deployment must be verified. The migration currently permits only yue/cmn, while the English app can send en.**
- Initial schema: `migrations/001_init.sql`. Review deployment and authorization before applying SQL. RLS protects the tables. Ordinary outing records use landmark names; profile block/floor visibility is restricted. Mutually agreed live finding separately exchanges precise coordinates through a private real-time channel.
- Permission test: `python3 -I tests/rls_test.py <url> <publishable_key>`. The earlier team report records 35 checks passing on 10 October, including QR pairing. It creates three anonymous users and prints their IDs. Run only against an authorized environment with a cleanup plan; cleanup uses `delete from auth.users where id in (...)`.
- No established APNs delivery: a free Apple developer account does not provide the required push capability. Foreground apps receive Realtime events; the app fetches updates when the system wakes it in the background.

## App integration — 10 October 2026

- Normal mode uses `ios/StreetWalk/Backend/SupabaseCommunityService.swift`; demo mode keeps simulated neighbors.
- The client uses no third-party SDK: `SupabaseAPI` handles anonymous login, refresh, PostgREST, and RPC, with session data in Keychain; `RealtimeClient` uses Phoenix protocol `vsn 1.0.0`; `Outbox` persists queued writes for later delivery.
- Foreground receiving combines Realtime and a 60-second refresh. Changes to outings/neighbors/meetups trigger a fetch; signals consume the delivered row directly. Background refresh/location wake-ups fetch once and may produce local notifications.
- On return home, set `landmark_name` to null; **do not delete the outing row**. An outing not updated for three hours is treated as ended.
- Upload original landmark names, before local renaming. If a recipient cannot match a name, show text without inventing a scene position.
- `ios/tools/backendtest.sh` runs 19 checks against the real backend: authentication, refresh, profiles, rankings, pairing, Realtime, private pair channels, and queueing. It creates two anonymous users and prints their IDs; it is not an offline test.

## Team observations — 10 October 2026

- Realtime **DELETE events expose primary keys to subscribers without row filtering**. Deleting a neighbor row can reveal the owner/other UUIDs; deleting an outing can reveal who returned home. The app avoids outing deletion. Unlinking still deletes a neighbor row, motivating proposal 1 below.
- The team reports that two mutual neighbors could join and broadcast on `pair:<a>:<b>`, while a third party received Unauthorized. This dated result is not independent verification of the current deployment.

## Proposed SQL — not confirmed as executed

The following changes require an authorized owner to review migration effects, deployment, rollback, and verification. They are not executed by this documentation update.

```sql
-- 1. Stop publishing neighbors DELETE events, which reveal the unlinked pair.
-- The app still refreshes my_neighbors every 60 seconds.
alter publication supabase_realtime drop table public.neighbors;

-- 2. Permit outing reads/inserts/updates, but prevent deletion events.
drop policy "own outing" on public.outings;
create policy "own outing read" on public.outings for select using (user_id = auth.uid());
create policy "own outing insert" on public.outings for insert with check (user_id = auth.uid());
create policy "own outing update" on public.outings for update using (user_id = auth.uid()) with check (user_id = auth.uid());

-- 3. Proposed account deletion. The current app clears selected tables,
-- de-identifies/moves the profile, then signs out; this is not complete deletion.
-- After deploying and validating this function, update the app to call delete_me.
create function public.delete_me() returns void
  language sql security definer set search_path = public, auth as $$ delete from auth.users where id = auth.uid() $$;
revoke all on function public.delete_me() from public, anon;
grant execute on function public.delete_me() to authenticated;

-- 4. Optional cleanup with pg_cron: used/old pairing codes and seven-day-old signals.
-- select cron.schedule('sw-cleanup', '17 4 * * *', $$
--   delete from public.pair_codes where created_at = 'epoch' or created_at < now() - interval '1 day';
--   delete from public.signals where created_at < now() - interval '7 days' $$);
```
