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

### Additional UX Refinements
- **Sunk Cost Conversion:** Show the paywall *after* the user fills out the 2nd dog's profile and taps "Save", rather than blocking them immediately on "Add Dog".
- **Family Sharing Highlight:** Explicitly call out "One purchase covers your whole family" on the paywall sheet.
- **Onboarding Soft-Pitch:** Add a final, skippable screen to the initial onboarding flow outlining Pro features with a low-friction $0.99 upgrade option.
- **Tease Push Notifications:** Add a subtle banner below the in-app "Last Fed" indicator for free users saying "Want to be notified when it's time? Unlock Pro."

---

## Decisions Locked In

- **Hybrid gate** — confirmed (vs pure-quantity). Pitch language must reflect it.
- **Widget behavior for free users** — *show in gallery normally; render with subtle upgrade copy when added*. A widget showing "1 of your dogs" + footer text like "Add more dogs with Pro" works as a passive billboard without reading as an ad. **Avoid** rendering the widget as a pure paywall surface — that earns 1-star reviews.
- **Siri / Shortcuts for free users** — *intents stay discoverable in the Shortcuts app and via Siri*. When a free user invokes a Pro intent, return a polite dialog: "This feature requires Did I Feed The Dog Pro. Open the app to upgrade." Hiding intents kills discovery.
- **Existing 1.0 / 1.1 buyers** — *auto-grant Pro* via `Bundle.main.appStoreReceiptURL` + `originalAppVersion` check at launch. Forcing a restore flow on people who already paid generates negative reviews. Mark them as Pro silently, no announcement needed.
- **Paywall trigger** — fire on **Save**, not on **Add Dog tap** (sunk-cost UX, see below).

## Conversion UX Tactics

These are the small details that turn a $0.99 paywall from skippable to convertible.

### 1. Sunk-cost paywall trigger

When a free user with 1 dog taps "Add Dog", let them complete the entire `AddEditPetSheet` flow (name, birthday, photo, meal schedule). Show the paywall sheet **only when they tap Save**. Copy: "Save Spike to your pack — upgrade to Pro to unlock multiple dogs." After purchase, the second pet record is committed and they land back on the dashboard with both dogs visible.

Rationale: by the time the user has invested 30+ seconds entering their dog's profile, sunk-cost psychology shifts the decision from "should I pay?" to "should I throw away what I just built?"

### 2. Family Sharing prominence

The IAP has Family Sharing enabled. Surface this on the paywall sheet as a **headline bullet**: "One purchase covers your whole family." For a household-management app, this is the #1 silent objection ("will my partner have to pay too?") and a major conversion driver.

### 3. Onboarding soft-pitch

The last screen of `OnboardingView` should be a **skippable** Pro pitch — outline the upgrade, list 3-4 highest-leverage Pro features (Unlimited Dogs, Widgets, Siri, Notifications), show the price + Family Sharing note, with a prominent "Maybe Later" dismissal. High-intent power users often pay before they've even finished setup, but only if they know the option exists. Skipping is friction-free.

### 4. Light push-notification tease (with restraint)

When a free user hits a single moment where push would help — e.g., the **first time** their card flips to Overdue in-app — show a one-time banner: "Want a notification next time? Unlock Pro." Store a `seenOverdueTeaseAt` timestamp so it appears at most once per user.

> **Important:** do *not* sprinkle these teases throughout the UI. One well-placed banner converts; ten of them feels nagging and triggers backlash. The dashboard, last-fed badge, and feeding history should stay tease-free.

## Telemetry — Track What Triggers Conversions

Add lightweight, **on-device** counters (no third-party analytics SDK, no PII, no network calls) to surface which gates drive purchases. Stored in App Group UserDefaults so widgets can also bump counters if relevant.

Counters to track:
- `paywallShownFrom_addSecondDog` — primary trigger fires
- `paywallShownFrom_notifications` — user toggled a Pro notification
- `paywallShownFrom_widget` — widget add or first render
- `paywallShownFrom_siri` — Siri invocation hit a Pro gate
- `paywallShownFrom_onboarding` — soft-pitch shown
- `paywallConvertedFrom_<source>` — purchase completed after a paywall fired from that source

After the freemium relaunch, surface these counters in a hidden Settings → About → Stats screen (or just read them via Xcode debug session). If 80% of conversions are coming from the notifications gate rather than dog-count, that's a marketing/positioning insight worth acting on (e.g., reframe Pro as "Never miss a feeding").

## Price Evolution

**Launch 1.2 at $0.99.** The goal of the relaunch is to *prove the freemium pivot drives install volume*. Cheap-and-cheerful pricing minimizes purchase friction during the proof phase.

Once installs are flowing and conversion rate is measurable (~1-2 months post-launch):
1. **Test $2.99 in 1.3 or 1.4** — the feature set (unlimited dogs + widgets + Siri + push + Action Button + stock tracking) is genuinely worth more than $0.99. Most "lifetime unlock" iOS apps in this category sit at $2.99-$4.99.
2. **Existing buyers grandfather automatically** via StoreKit — anyone who paid $0.99 keeps Pro forever, no controversy.
3. **No A/B testing needed** — Apple doesn't easily support price A/B at the App Store level. Just pick a date, raise the price, and watch conversion rate vs install rate to validate.

## App Store Optimization (ASO) Changes

Going from Paid to Free re-ranks the app meaningfully — different algorithm bucket, different impression sources, likely a download spike. Things to update in App Store Connect **as part of the 1.2 release**:

- **First screenshot**: add a "Free for 1 Dog" badge / overlay at the top.
- **Subtitle / promotional text**: lead with "Free pet feeding tracker — Pro adds multi-dog, widgets, and Siri."
- **Description**: rewrite the opening paragraph to reflect the new pricing.
- **Keywords**: add "free pet tracker," "multi-dog," "household pet sharing," etc. — terms that match free-tier search behavior.
- **What's New** for 1.2: lead with "Now free!" and list the iPad widget fixes / freemium pivot.

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
