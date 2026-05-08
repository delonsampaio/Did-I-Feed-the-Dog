# Freemium Paywall Strategy — Backlog #73

**Date:** 2026-05-08
**Status:** Planning (architecture locked, implementation pending)
**Target release:** 1.2 (post 1.1 ship)

---

## Goal

Switch from a $0.99 paid app to **free + $0.99 one-time IAP** with Family Sharing enabled. Drive installs by removing the upfront price barrier; recover revenue through a Pro upgrade triggered organically when users add a second dog.

## Strategic Position

The paywall is a **hybrid gate**, not a pure-quantity gate:

- **Primary trigger:** dog count. Attempting to add a 2nd dog opens the paywall sheet. Single-dog households get a permanent, polished experience and become reviewers / referrers.
- **Secondary feature gates:** widgets, Siri, push notifications, food stock tracking, Action Button, quick actions, app icon badge — these are Pro even for 1-dog users.

> **Pitch language must reflect the hybrid:** "Free for 1 dog with the essentials. Pro unlocks more dogs *and* power features." Don't promise a "full core experience" we don't deliver.

### Alternative considered: pure quantity gate

A purer model would give 1-dog users full feature parity (widgets, Siri, push, etc.) and gate ONLY on dog count. Cleaner narrative, weaker revenue from single-dog power users. Rejected for revenue reasons; documented here so future-us remembers we considered it.

---

## Free Tier — 1 Dog, Full Core Experience

| Feature | Reasoning |
|---|---|
| 1 dog | The natural quantity gate |
| All meal types (Breakfast, Lunch, Dinner, Snack, Treat) + Custom meals | Core logging — never gate |
| Custom meal "Deduct a portion" toggle | Part of core logging flow |
| Notes on every meal | Trust feature |
| **Custom timestamp on log** (backfill a forgotten feed) | `LogFeedingSheet` "Set custom time" — trust feature |
| **Edit/delete feeding entries** (swipe-to-edit) | Data correction, not a power feature (backlog #27, done) |
| Full feeding history (no cap) | Trust-builder; storage is cheap |
| Undo banner (shrinking timer) | Safety feature |
| 1 daily reminder time (All Dogs mode) | Habit formation; gating kills retention |
| In-app overdue indicator (red Last Fed badge) | Visual only, no push |
| **In-app low-stock banner** | Visual only; parallel to overdue indicator. Push is Pro. |
| Fasting mode | Safety / medical — never gate |
| Birthday field (data only) | Free; the push notification is Pro |
| Dog photo / avatar customization (default avatars + user upload) | Personalization hooks users |
| iCloud sync | Can't cleanly gate without a custom backend; trying creates support headaches |
| **Display name attribution** (`loggedByName` / "Your Name") | Multi-person households need this; not a power feature |
| **CloudKit sync status indicator** | Status only, free |
| Toxic Foods Guide (Safety Guide) | Safety / trust |
| Help & FAQ | Support |
| Appearance (Light/Dark/System) | Table stakes |
| Onboarding flow | Required for first launch |

## Pro Tier — $0.99 One-Time Purchase

| Feature | Reasoning |
|---|---|
| **2+ dogs** | The natural trigger — hits organically |
| Feed All Dogs (dashboard + Siri intent) | Only relevant with 2+ dogs |
| Per-dog reminder schedules | Power users with different routines per dog |
| Up to 3 reminder times (Free gets 1) | Full scheduling |
| All push notifications: overdue, low stock, birthday, **water bowl cleaning** | Compelling — "the app works for you even when closed" |
| App icon badge | Power user delight |
| Home Screen widgets (Small / Medium / Large) | High perceived value, visible daily |
| Lock Screen widgets (Circular / Rectangular / Inline) | Same |
| Siri & Shortcuts (all intents) | Power user feature |
| Action Button (supported iPhones) | Power user feature |
| Home Screen Quick Actions (long-press app icon) | Power user feature |
| Food stock tracking (Per Dog / Shared Pool / thresholds) | Nice-to-have, not core |
| **Stock-out restock prompt + Bulk Restock Sheet** | Companions to stock tracking — come along automatically |
| Update Food Stock Siri intent | Power user, depends on stock tracking |

---

## What NOT to Gate (and Why)

- **iCloud sync** — couldn't gate cleanly without a custom backend
- **Fasting mode** — safety / medical
- **Core logging (any meal type, notes, undo, edit, custom timestamp)** — the app is worthless without it
- **In-app visual indicators** (overdue, low stock banner) — push is the upgrade, visuals stay
- **Display name attribution** — household trust feature
- **Birthday field** (the data) — only the *notification* is Pro

---

## Engineering Plan

**Effort:** ~2-3 days focused work + sandbox testing pass.

### Architecture

- **`EntitlementManager`** — `@Observable` class
  - Reads `Transaction.currentEntitlements` on launch
  - Listens to `Transaction.updates` stream for live updates
  - Exposes `isPro: Bool`
- **`PaywallSheet`** — modal view
  - StoreKit 2 product fetch (`Product.products(for: ["pro_upgrade"])`)
  - Purchase flow + restore
  - Triggered from feature-gate sites
- **Feature guards** sprinkled through:
  - `DashboardView` — gate "Add Dog" when count >= 1; gate Feed All button
  - `PetCard` — gate widget-related affordances
  - `SettingsView` / `NotificationsSettingsView` — show Pro badges next to gated rows
  - `NotificationManager` — bail early in scheduling functions when not Pro
  - `DogFoodShortcuts.AppShortcutsProvider` — Siri intents check entitlement before performing
  - Widget extension — show "Upgrade to see widget" placeholder for free users (or hide widget from gallery — TBD)

### StoreKit configuration

- Single non-consumable product: `pro_upgrade` ($0.99)
- Family Sharing enabled
- Test in StoreKit configuration file before App Store Connect setup

### Existing-user migration

No migration needed. App Store treats paid → free + IAP as a separate version. Anyone who bought 1.0/1.1 keeps full access via receipt validation (or we can grant Pro to all prior purchasers via a launch-time check on `originalAppVersion`).

---

## UX Tweak: Strategic Gating

Per backlog #73 notes — keep the main dashboard free of Pro badges. Only show "Pro" lock icons (🔒) in:

- Settings → Food Stock
- Settings → Notifications (and the deeper view)
- Help & FAQ entries that describe Pro features (drives organic discovery)

Rationale: dashboard stays clean for free users, Pro discovery happens naturally via Settings exploration.

---

## Open Decisions to Lock In

- [ ] **Pure-quantity vs hybrid** — locked as **hybrid** above. Confirm before implementation.
- [ ] **Widget behavior for free users** — hide from gallery, or show with "Pro" overlay/upgrade prompt? Hide is cleaner.
- [ ] **Siri/Shortcuts behavior for free users** — block at perform time with "This is a Pro feature" dialog, or hide intents from Shortcuts gallery?
- [ ] **Existing 1.0/1.1 buyers** — auto-grant Pro via `originalAppVersion` check, or require restore-purchase flow? Auto-grant is friendlier.
- [ ] **Paywall trigger phrasing** — exact copy on the "Add second dog" sheet. Needs to feel inviting, not blocking.

---

## Order of Operations

1. **Ship 1.1** (current state — iPad widget fixes, stock-out prompt, Notifications split, FAQ updates).
2. **Lock the architecture decision** (this doc; backlog items built between now and 1.2 should assume `entitlementManager.isPro` exists).
3. **Build #73** — StoreKit 2 setup, `EntitlementManager`, paywall sheet, feature guards.
4. **Sandbox testing pass** — purchase, restore, Family Sharing.
5. **Ship 1.2** as a freemium relaunch with marketing push ("Now free, with optional Pro upgrade").

---

## References

- BACKLOG.md item #73 (App-Studio-Private repo)
- StoreKit 2 docs: https://developer.apple.com/documentation/storekit
- Existing helper sites already auditable for gates: `DashboardView`, `PetCard`, `SettingsView`, `NotificationsSettingsView`, `NotificationManager`, `DogFoodShortcuts`, `LogFeedingSheet`, `FeedAllDogsSheet`, widget extension target
