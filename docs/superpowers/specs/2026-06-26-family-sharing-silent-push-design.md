# Family Sharing — Phase 4: Silent Push (Backlog #57)

> Status: Design / awaiting review
> Date: 2026-06-26
> Depends on: Phases 1–3 (all merged). Uses the Phase 2/3 engine's `fetchAllZones()`.
> Skill: `ios-cloudkit-custom-sharing` — subscriptions in a non-NSPCKC container.

## Where this sits

Phases 1–3 built the shared store, the custom sync engine, and cross-account sharing —
all driven on launch, foreground, and a 20-second foreground poll. Phase 4 adds **silent
push** so a change on one device wakes the other's app in the background and runs the existing
`fetchAllZones()` within seconds, instead of waiting for the poll. **No new sync logic** — push
is only a faster *trigger* for the pull path that already exists.

### Confirmed decisions (brainstorm 2026-06-26)

- **Scope = silent-push delivery only.** Two `CKDatabaseSubscription`s + APNs registration +
  a background push handler that calls `fetchAllZones()`. No new sync behavior.
- **Keep a slower poll as a backstop.** Lengthen the foreground poll from 20s to **75s**
  (iOS silent push is best-effort/throttled/coalesced, so a slow poll guarantees eventual
  freshness). Launch + foreground fetch stay.
- **Flag-gated** by `SharingFeatureFlag.isFoundationEnabled` — flag off ⇒ no registration, no
  subscriptions, no push handling; behavior identical to today.
- **No NSPCKC.** The sharedsync container has no `NSPersistentCloudKitContainer`, so we register
  a plain `CKDatabaseSubscription` with `shouldSendContentAvailable = true` and our own IDs —
  no Core-Data-internal-subscription trick needed.

## Why two subscriptions

A `CKDatabaseSubscription` fires when any zone in that database changes:

- **privateCloudDatabase** subscription → wakes an **owner** when a **participant** edits a dog
  the owner owns (the zone lives in the owner's private DB).
- **sharedCloudDatabase** subscription → wakes a **participant** when the owner (or another
  participant) edits the shared zone.

Both are needed for bidirectional real-time. The handler is identical for both: run
`fetchAllZones()` (which already scans both databases).

## Scope

### In scope

1. **Push Notifications capability (`aps-environment`).** Add to the app target's entitlements.
   - Dev/device testing: `aps-environment = development`.
   - **Release/TestFlight/App Store requires `production`.** Adding the capability via Xcode's
     "Signing & Capabilities → Push Notifications" manages this per-build-configuration
     automatically; if edited by hand, the value must be flipped to `production` for archives.
     (The widget target already ships `production`.) This is called out as a **release
     checklist item**, not a code concern.
   - The `remote-notification` `UIBackgroundMode` is **already present** in the app Info.plist.

2. **`SharedSyncPushSubscriptions`** (new) — `@MainActor` helper:
   - `registerIfNeeded() async` — saves a `CKDatabaseSubscription` to the sharedsync
     `privateCloudDatabase` (id `"sharedsync-private-db"`) and one to its `sharedCloudDatabase`
     (id `"sharedsync-shared-db"`), each with `notificationInfo.shouldSendContentAvailable = true`
     (silent, no alert/badge/sound). Idempotent: a `UserDefaults` "registered" flag guards
     against re-saving on every launch; a save failure clears the flag so the next launch
     retries. Saving a subscription with an existing ID is itself idempotent server-side.
   - No-op unless `SharingFeatureFlag.isFoundationEnabled`.

3. **APNs registration + push handling** (added to the existing `QuickActionAppDelegate`):
   - `application(_:didFinishLaunchingWithOptions:)` (add if absent) → when the flag is on,
     `UIApplication.shared.registerForRemoteNotifications()`.
   - `application(_:didRegisterForRemoteNotificationsWithDeviceToken:)` → log only (CloudKit
     uses the token server-side; we don't forward it). `…didFailToRegisterForRemoteNotifications…`
     → log.
   - `application(_:didReceiveRemoteNotification:fetchCompletionHandler:)` → when the flag is on,
     parse `CKNotification(fromRemoteNotificationDictionary:)`; if it belongs to our sharedsync
     container (subscription id matches one of ours, or container id matches), run
     `Task { @MainActor in await SharedSyncEngine.shared.fetchAllZones(); completion(.newData) }`;
     otherwise `completion(.noData)`. Flag off → `completion(.noData)` immediately.

4. **Poll change** — in the app's foreground poll (`Did_I_Feed_The_Dog_App.swift`), change the
   sleep interval from 20s to **75s**. Launch fetch and `scenePhase == .active` fetch unchanged.

5. **Registration wiring** — call `SharedSyncPushSubscriptions.registerIfNeeded()` from
   `SharedSyncEngine.start()` (already flag-gated and already the single "sharing turns on" entry
   point), after the initial fetch is kicked off.

### Out of scope (later phases)

- First-share migration + the real Pro-gated in-app Share button (Phase 5).
- Participant "leave"; `loggedBy` attribution; `foodStockCount` merge.
- Any user-visible (alerting) notifications for shared-dog activity — this phase is **silent**
  background sync only.
- Retrying/queuing pushes the OS drops (the poll backstop covers that).

## Components & responsibilities

| Component | Responsibility | Depends on |
|---|---|---|
| `aps-environment` entitlement | Enable APNs for the app target | — |
| `SharedSyncPushSubscriptions` | Create the two DB subscriptions once (idempotent) | CKContainer, UserDefaults, flag |
| `QuickActionAppDelegate` additions | Register for APNs; route silent pushes → fetchAllZones | SharedSyncEngine, flag |
| `Did_I_Feed_The_Dog_App` poll | Lengthen backstop poll to 75s | flag |
| `SharedSyncEngine.start()` | Kick subscription registration | SharedSyncPushSubscriptions |

## Data flow

1. Flag on → `SharedSyncEngine.start()` kicks `fetchAllZones()` **and**
   `SharedSyncPushSubscriptions.registerIfNeeded()`; the app registers for remote notifications.
2. Device A writes to a shared dog → CloudKit → APNs delivers a silent push to Device B.
3. Device B (backgrounded or foregrounded): `didReceiveRemoteNotification` → our-notification
   check passes → `fetchAllZones()` pulls the change → `.sharedRemoteChangeApplied` → dashboard
   refreshes → `completion(.newData)`.
4. If a push is dropped/delayed, the 75s foreground poll (or next launch/foreground) catches up.

## Error handling

- **Flag off:** no registration, no subscriptions saved, push handler returns `.noData`
  immediately, poll guard already fails — zero CloudKit/APNs activity.
- **Subscription save failure:** log; clear the "registered" flag so the next launch retries.
  Sharing still works via launch/foreground/poll in the meantime.
- **APNs registration failure** (e.g., simulator, no entitlement in a misconfigured build):
  log; the app degrades to poll-driven sync. Never `fatalError`.
- **Foreign / non-sharedsync push:** handler returns `.noData` without touching the engine.
- **`fetchAllZones()` is internally flag-guarded and coalesced** (Phase 2), so a burst of pushes
  collapses into at most one in-flight sync plus one queued.

## Testing

- **Unit:**
  - `SharedSyncPushSubscriptions` "register once" guard: given the UserDefaults flag set, it does
    not re-save; on a simulated failure it clears the flag so a retry happens. (Inject a
    UserDefaults; the live `database.modifySubscriptions` is not unit-tested.)
  - A pure helper `isOurSharedSyncNotification(subscriptionID:)` (or equivalent) returning whether
    a notification's subscription id is one of our two ids — unit-tested with both ids and a
    foreign id.
- **Manual (REAL DEVICE — required; silent push does NOT work on the simulator):** two accounts,
  both flag on, Device B backgrounded (app not foregrounded, launched from home screen per the
  skill's gotcha #6): edit a shared dog on A → B's dashboard reflects it within seconds of
  reopening / while backgrounded the fetch runs. Confirm: (a) push wakes B and applies the change;
  (b) with the flag off, no push is requested and no subscription exists; (c) same-account and
  cross-account sync from Phases 2–3 still work.

## Risks & mitigations

| Risk | Mitigation |
|---|---|
| Silent push throttled/dropped by iOS | 75s foreground poll + launch/foreground fetch backstop |
| `aps-environment` wrong for release | Release checklist item: `production` for archives (Xcode capability manages per-config) |
| Push handler runs sync when flag off | Flag guard first in the handler; `.noData` immediately |
| Re-registering subscription every launch | UserDefaults "registered" guard; retry only on failure |
| Simulator can't receive push | Manual validation explicitly requires a real device |
| Handling a foreign push | Subscription-id/container check before touching the engine |

## Done criteria for Phase 4

- App builds (app + widget); new unit tests pass; existing suite shows no new failures.
- Flag OFF: no APNs registration, no subscriptions, push handler is a `.noData` no-op —
  behavior identical to today.
- On two accounts, real devices, flag on: an edit on one device is applied on the other via
  silent push (validated manually); the 75s poll remains a working backstop; Phases 2–3 sync
  unaffected.
- `aps-environment` present for the app target (`development` in dev), with the `production`
  release requirement documented.
