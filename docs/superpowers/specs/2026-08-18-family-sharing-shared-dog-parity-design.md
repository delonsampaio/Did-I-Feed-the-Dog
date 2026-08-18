# Family Sharing — Phase 7: Shared-Dog CRUD Parity (Backlog #57)

> Status: Design / awaiting review
> Date: 2026-08-18
> Depends on: Phases 1–6 (foundation, sync engine, share lifecycle, silent push, migration + Share
> button, shared-dog logging) — all merged. Also depends on the `SharedDogStore.refresh()`
> relationship-fault fix (2026-08-18) and the `SharedPetCard` visual-parity change (2026-08-18),
> both same-day work on `main`.

## Where this sits

Phase 6 made shared dogs loggable (feeding, medication doses) but explicitly left history
browsing and editing out of scope: `SharedPetCard` was view-only beyond logging, `PetDetailView`
(meal/medication history) stayed owned-dog-only, and there was no way to edit a shared dog's
name/photo/schedule, toggle fasting, or add/edit/delete a medication once it existed. Phase 7
closes that gap: a participant on a shared dog should be able to do everything an owner can do to
that dog's *data* — logging, editing, deleting, browsing history — regardless of the
participant's own Pro entitlement. Only the share's lifecycle (stop sharing) stays owner-only.

### Confirmed decisions (brainstorm 2026-08-18)

- **Full parity, not a lighter first pass.** Filters, bulk-select delete with stock-restore,
  swipe actions, full medication CRUD, and log deletion all get ported — matching
  `PetDetailView`/`AddEditPetSheet`/`AddEditMedicationSheet` feature-for-feature.
- **Notifications, the home-screen widget, and Siri shortcuts stay out of scope this phase.**
  Each is a separate subsystem with zero shared-dog awareness today (`NotificationManager`,
  `WidgetDataWriter`, `RemindersCoordinator`, `DogFoodShortcuts` all operate on owned `Pet` only).
  Extending them is a follow-up design, not part of this one. Concretely: the new
  `EditSharedMedicationSheet` omits the "Dose Reminder" section entirely, and toggling
  `notificationsMuted`/setting a feeding schedule on a shared dog stores the value but schedules
  no local reminder.
- **Any participant, any Pro status, full data CRUD.** The existing precedent (Log Meal, Log
  Medication, Update Stock on `SharedPetCard` are already ungated) extends to editing and
  deleting. Only "Share this dog" / "Stop sharing" remain owner-gated, unchanged from Phase 5.
- **No new Core Data fields.** `SharedPet`/`SharedMedication`/`SharedFeedingEvent`/
  `SharedMedicationLog` already carry every field their owned equivalents do (built for schema
  parity in Phases 5–6). This phase is UI and wiring on the existing schema and the existing
  generic push/pull engine — confirmed during the 2026-08-18 debugging session that
  `SharedSyncEngine`/`CKRecordMapper` need no changes for new fields or new child-entity
  inserts/deletes.
- **Deleting a feeding event that deducted stock needs no explicit "restore" step.** Unlike the
  owned-dog flow (`PetDetailView`'s "Delete & Restore Portions"), a shared dog's
  `effectiveFoodStockCount` is *derived* from `feedingEvents` — removing the event automatically
  increases the derived count back up. Simpler than the owned-dog equivalent by construction.
- **Flag-gated**, as every phase has been: `SharingFeatureFlag.isFoundationEnabled`.

## Scope

### In scope

1. **`SharedPetDetailView`** (new view, mirrors `PetDetailView`) — meals tab (segmented picker,
   filter sheet by meal type/logger/date range, sort order, multi-select bulk delete, per-meal
   swipe edit/delete) and medications tab (list with add/edit, dose-log history grouped by day
   with swipe-delete). Reuses `MealType`, `LoggedBy`, and the same relative/section-date
   formatters `PetDetailView` already defines — no new formatting code.
   - Bulk/single delete of a `SharedFeedingEvent` never needs a "restore portions" branch (see
     Confirmed decisions) — deletion alone is enough, so the confirmation dialog offered here has
     one fewer option than `PetDetailView`'s.
   - Editing a `SharedFeedingEvent`'s meal type/notes mirrors `PetDetailView`'s private
     `EditEventSheet`, adapted to `SharedFeedingEvent`.
2. **`EditSharedPetSheet`** (new view, mirrors `AddEditPetSheet`, edit-only) — name, photo
   (`PhotosPicker` + the same default-avatar grid, reusing `AvatarPickerSheet`'s compression
   logic), birthday, fasting toggle, food stock (always shown, no Pro/paywall fork — unlike the
   owned editor, which locks this behind Pro), mute-notifications toggle (stored on
   `notificationsMuted`, no `NotificationManager` call — see Confirmed decisions), feeding
   schedule times (stored on `feedingScheduleTimesRaw` via the existing `feedingScheduleTimes`
   computed property, no reminder scheduling). Shared dogs are never created fresh through this
   sheet — only migration creates a `SharedPet` — so there is no "Add" mode.
3. **`EditSharedMedicationSheet`** (new view, mirrors `AddEditMedicationSheet` minus its
   "Notifications" section) — name, dose, frequency picker, delete-with-confirmation. On delete,
   nullifies `log.medication` on each of the medication's `SharedMedicationLog`s before deleting
   the medication (mirrors `AddEditMedicationSheet.delete()`'s log-preservation pattern) so dose
   history survives, matching `SharedMedicationLog.petId`/`medicationName`'s existing
   denormalization purpose.
4. **`SharedPetCard`** (modify) — the header, "Today's Meals" stat, and Recent-history rows
   become `NavigationLink(value: sharedPet)` into `SharedPetDetailView` (mirroring `PetCard`'s
   `NavigationLink(value: pet)`). The context menu gains "Edit Dog" (opens
   `EditSharedPetSheet`, ungated) and a quick Start/End Fasting toggle (ungated, mirrors
   `PetCard`'s existing context-menu fasting toggle). Existing owner-gated Share/Stop-sharing
   items are unchanged.
5. **`DashboardView`** (modify) — gains `navigationDestination(for: SharedPet.self) {
   SharedPetDetailView(pet: $0) }`, alongside the existing `navigationDestination(for: Pet.self)`.

### Out of scope (later phases, if ever)

- Local notifications/reminders, home-screen widget display, and Siri shortcuts for shared dogs
  (per-participant scheduling, badge counts, `DogFoodShortcuts` vocabulary) — a separate design.
- Real CloudKit participant identity for `loggedBy`/edit attribution (still `LoggedBy.current`,
  unchanged since Phase 6).
- Event-sourced/CRDT conflict handling beyond the existing last-write-wins push policy — editing
  a shared dog's name/photo/schedule from two devices at once resolves the same way any other
  field edit already does (`CKRecordMapper`'s client-trumps LWW on `serverRecordChanged`).
- Deleting the shared dog itself from these screens — that's already "Stop sharing"
  (owner-only, unchanged from Phase 5); this phase is about the dog's *data*, not the share.

## Components & responsibilities

| Component | Responsibility | Depends on |
|---|---|---|
| `SharedPetDetailView` | Meal/medication history: view, filter, sort, edit, delete | `SharedPet`, `SharedFeedingEvent`, `SharedMedication`, `SharedMedicationLog` |
| `EditSharedPetSheet` | Edit a shared dog's core fields | `SharedPet` |
| `EditSharedMedicationSheet` | Add/edit/delete a shared dog's medications | `SharedMedication`, `SharedMedicationLog` |
| `SharedPetCard` | Navigation entry points + quick fasting toggle + Edit Dog | all of the above |
| `DashboardView` | Routes `SharedPet` navigation values to `SharedPetDetailView` | `SharedPetDetailView` |

## Data flow

1. Tapping into a shared dog's history/stats on `SharedPetCard` pushes `SharedPetDetailView` via
   `navigationDestination(for: SharedPet.self)` — identical mechanism to the owned-dog path,
   different destination type.
2. Any edit (dog fields, a medication, a feeding event's note) mutates the existing
   `SharedPet`/`SharedMedication`/`SharedFeedingEvent` object and saves the shared `viewContext`
   — the existing Phase 2 push observer picks it up exactly like a Phase 6 log-meal save, no new
   sync code.
3. Any delete (event, medication, medication log) calls `context.delete(...)` and saves — the
   existing push observer's `NSDeletedObjectsKey` handling and `CKRecordMapper.recordID(forDeleted:)`
   path already cover this generically; confirmed during the 2026-08-18 debugging session that
   `SharedSyncEngine` doesn't special-case entity types.
4. The other device's next `fetchAllZones()` (foreground/launch/poll/silent-push, all unchanged)
   pulls the change → `SharedDogStore.refresh()` (with the same-day relationship-fault fix)
   → dashboard and any open `SharedPetDetailView` re-render from the refreshed object graph.
5. Concurrent edits to the same field (e.g. two people rename the dog at once) resolve via the
   existing `CKRecordMapper`/`SharedSyncEngine` last-write-wins policy — no new conflict code.

## Error handling

- Core Data save failures in any new sheet surface a simple alert with
  `error.localizedDescription` — never `fatalError`, matching every prior phase.
- No new offline/retry logic — same as every prior phase, the existing push/pull engine owns
  eventual delivery.
- Flag off: none of the new navigation/edit entry points render — shared dogs themselves don't
  render without the flag, per existing `DashboardView` gating (zero behavior change).

## Testing

- **Unit:**
  - `SharedPetDetailView`'s filtering/grouping logic (mirrors `PetDetailView`'s, tested the same
    way if `PetDetailView` has tests today, or fresh if not — table-driven on meal type, logger,
    date range).
  - `EditSharedPetSheet` save path — each field round-trips onto the `SharedPet` correctly,
    including feeding-schedule-times encoding via the existing `feedingScheduleTimes` computed
    property.
  - `EditSharedMedicationSheet` save/delete — mirrors `MedicationTests`/`SharedMedicationTests`
    style; delete preserves logs via `petId`/`medicationName` denormalization (already covered
    for the owned side in `MedicationTests`, needs the shared-side equivalent here).
  - Deleting a stock-deducting `SharedFeedingEvent` — `effectiveFoodStockCount` increases back up
    with no explicit restore call (regression guard for the "no restore step needed" design
    decision above).
- **Manual (two accounts, real devices, flag on) — REQUIRED:**
  1. Tap into a shared dog's history from both the Last Fed badge and the Today's Meals stat on
     both devices — same destination, same content.
  2. Edit the dog's name/photo/fasting/food-stock/schedule from a non-owner, non-Pro participant
     device → change appears on the owner's device after sync.
  3. Add a medication from a participant device → appears and is loggable from the owner's
     device; delete it from either device → disappears from both, dose log history survives.
  4. Delete a feeding event that deducted stock → `effectiveFoodStockCount` on that device
     reflects the restored portion immediately, no separate action taken.
  5. Flag off: no "Edit Dog"/fasting-toggle/navigation entry points appear on any `SharedPetCard`.

## Risks & mitigations

| Risk | Mitigation |
|---|---|
| Porting `PetDetailView`'s full surface (filters, bulk-select) is a lot of UI to keep in sync with the owned version over time | Both screens read from the same `MealType`/`LoggedBy`/formatter helpers already; divergence risk is in the two view bodies existing separately, accepted per the "full parity, ported" decision rather than a shared generic view (which the existing `Pet`-vs-`SharedPet`/SwiftData-vs-Core-Data split makes non-trivial to build safely in this phase) |
| A participant edits a field the owner didn't expect changed (e.g. birthday) | No new risk beyond what Phase 6 already accepted for logging — same LWW policy, same trust model (anyone with the share link already has full CloudKit read-write on the zone) |
| Deleting a medication with reminder-adjacent fields (`notificationsEnabled`/`reminderMinutes`) that are inert this phase | No behavior change either way — those fields are stored but unread by any shared-dog code path, since notifications are out of scope |

## Done criteria for Phase 7

- App builds (app + widget); new unit tests pass; existing suite shows no new failures beyond the
  pre-existing, unrelated baseline failures already tracked separately.
- Flag OFF: no behavior change.
- On two real accounts, real devices, flag on: a non-owner, non-Pro participant can view history,
  edit the dog, and add/edit/delete medications on a shared dog end-to-end; confirmed by the
  manual checklist.
- Phases 1–6 behavior (sync, routing, silent push, migration, owned-dog logging, shared-dog
  logging) unaffected.
