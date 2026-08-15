# Family Sharing — Phase 6: Shared-Dog Logging (Backlog #57)

> Status: Design / awaiting review
> Date: 2026-08-15
> Depends on: Phases 1–5 (foundation, sync engine, share lifecycle, silent push, migration + Share button) — all merged.

## Where this sits

Phases 1–5 built the full sharing pipeline — parallel Core Data + CloudKit store, custom sync
engine, cross-account share lifecycle, silent push, and first-share migration with a real Share
button — but `SharedPetCard` has been view-only the entire time. There is no way to log a
feeding or medication dose on a shared dog anywhere in the app, even though participants already
have CloudKit-level read-write access to the zone. Phase 6 closes that gap: it's what makes
family sharing actually usable day-to-day, not just shareable.

### Confirmed decisions (brainstorm 2026-08-15)

- **Scope: both feeding and medication logging** for shared dogs, in one phase (not split further).
- **`loggedBy` reuses the existing local mechanism** (`LoggedBy.current` — a typed name or device
  name, app-group `UserDefaults`-backed). No CloudKit user-discovery, no real cross-account
  identity lookup. Same attribution quality owned dogs already have; good enough to tell family
  members apart, not a security boundary.
- **No mutable, concurrently-written counters on the shared side.** `foodStockCount` and
  `todaysFeedingCount`/`lastFeedingDate` stop being authoritative stored fields for display
  purposes and become values *derived* from the `feedingEvents` relationship each time they're
  read. Two devices logging concurrently each create an independent new `SharedFeedingEvent`
  record — CloudKit has nothing to conflict on, so both land and both get summed. This replaces
  a conflict-resolution problem with a structural non-problem, rather than adding merge logic.
- **Medication's `lastGivenDate` keeps last-writer-wins**, matching owned-dog medication logging
  today and the Phase 5 spec's deferred-item wording, which named stock specifically (a
  runaway-drift risk under concurrent use) and not medication timestamps (a low-stakes
  due/not-due flip, already accepted as-is for owned dogs).
- **Restocking a shared dog's food is a rare, single-actor action** — a mutated field
  (`foodStockCount`) plus a new `foodStockBaselineDate` marking when it was set, with
  last-writer-wins accepted if two people restock at literally the same moment. Not
  event-sourced like feeding logs; the concurrency risk profile doesn't justify that complexity.
- **No shared-dog history browsing this phase.** `PetDetailView` (meal/medication history list)
  stays owned-dog-only; `SharedPetCard` gets logging entry points (sheets), not a navigation
  destination into history. A future phase can add shared-dog history browsing if wanted.
- **Flag-gated**, as every phase has been: `SharingFeatureFlag.isFoundationEnabled`.

## Scope

### In scope

1. **`foodStockBaselineDate: Date?`** — new optional attribute on `SharedPet`
   (`SharedDataModel.swift`, `SharedManagedObjects.swift`). Additive, optional, no default-value
   conflict — Core Data's automatic lightweight migration (already enabled by default on
   `NSPersistentStoreDescription`, and `SharedDataStack` never overrides
   `shouldInferMappingModelAutomatically`/`shouldMigrateStoreAutomatically` to `false`) handles
   existing installs with no new migration code.

2. **`SharedPet.effectiveFoodStockCount: Int`** (new computed property, not part of
   `DogDisplayable`) — `max(0, Int(foodStockCount) - deductedSinceBaseline)`, where
   `deductedSinceBaseline` sums `portionsDeducted` across `feedingEvents` timestamped after
   `foodStockBaselineDate` (or all events, if `foodStockBaselineDate` is nil — i.e. never
   restocked since the field was introduced).

3. **`DogDisplayable` conformance changes** (`Sharing/DogDisplayable.swift`) — `SharedPet`'s
   `todaysFeedingCount` changes from reading `todaysFeedingCountRaw` to counting `feedingEvents`
   timestamped since local midnight. `SharedPet` gains an explicit `lastFeedingDate` override
   (currently falls through to the stored `@NSManaged` field) that returns the max timestamp
   across `feedingEvents`. The stored `todaysFeedingCountRaw`/`lastFeedingDate` fields remain in
   the model (harmless, unread) — no migration needed to remove them.

4. **`SharedFeedingLogService`** (new, `Sharing/SharedFeedingLogService.swift`) — mirrors
   `FeedingLogService`'s signature shape:
   `static func logFeeding(for pet: SharedPet, mealLabel: String, deductsStock: Bool, timestamp: Date = .now, notes: String = "", logger: String, in context: NSManagedObjectContext) throws -> SharedFeedingEvent`.
   Creates a `SharedFeedingEvent`, sets `portionsDeducted` when `deductsStock` (mirroring
   `FeedingEvent`'s semantics — a resolved-meal-type/toggle-driven portion count, not a raw
   bool), stamps a fresh `ckRecordName`, sets `pet = pet`, saves. Does **not** touch
   `foodStockCount` — deduction is entirely reflected via the new event, read back out through
   `effectiveFoodStockCount`.

5. **`LogSharedFeedingSheet`** (new view, mirrors `LogFeedingSheet`) — same UI shape (meal-type
   chips + custom, deduct-a-portion toggle, optional custom timestamp, notes with recent-meal
   suggestions pulled from the `SharedPet`'s own `feedingEvents`). Calls
   `SharedFeedingLogService.logFeeding(... logger: LoggedBy.current ...)`.

6. **Shared-dog restock sheet** (new, small view) — presents `effectiveFoodStockCount` as the
   current value, lets the user set a new count, writes `pet.foodStockCount =
   Int64(newCount); pet.foodStockBaselineDate = .now` on save (existing `SharedPet` object,
   existing `ckRecordName` — no new record, picked up by the existing push observer like any
   other field edit).

7. **`SharedMedicationLog` creation + `SharedMedication.lastGivenDate` update** — inline in a new
   **`LogSharedMedicationSheet`** view (mirrors `LogMedicationSheet`'s inline pattern: no
   dedicated service layer, matching the owned-dog precedent). Builds a `SharedMedicationLog`
   with a stamped `ckRecordName`, `loggedBy = LoggedBy.current`, `medicationName`/`petId` set
   from the medication/pet at log time (mirroring `MedicationLog`'s denormalization), sets
   `medication.lastGivenDate = timestamp` directly, saves.

8. **`SharedPetCard`** (modify) — becomes interactive: adds "Log Meal" / "Log Medication" entry
   points (buttons or a tap target, following the visual language of `PetCard`'s existing feed
   button) presenting the two new sheets. Flag-gated (redundant given upstream gating, matching
   every prior phase's defense-in-depth convention).

### Out of scope (later phases, if ever)

- Shared-dog meal/medication history browsing (a `SharedPetDetailView` equivalent to
  `PetDetailView`).
- Real CloudKit participant identity for `loggedBy` (user-discovery, permissions, caching).
- Event-sourced/CRDT restocking (concurrent-restock conflict handling beyond last-writer-wins).
- Undo for a logged shared-dog feeding/medication (owned dogs have this via `PetCard`'s
  `onFed`/undo-toast mechanism; shared dogs don't get it this phase).
- Low-stock notifications / stock-out prompts for shared dogs (owned-dog-only today via
  `AppSettings.stockOutPromptEnabled`, `NotificationManager`'s low-stock scheduling).

## Components & responsibilities

| Component | Responsibility | Depends on |
|---|---|---|
| `foodStockBaselineDate` | Marks when the stock counter was last manually set | `SharedDataModel`, `SharedManagedObjects` |
| `SharedPet.effectiveFoodStockCount` | Derived current stock (baseline − deducted-since-baseline) | `feedingEvents` relationship |
| `DogDisplayable` (SharedPet) | Derived `todaysFeedingCount`/`lastFeedingDate` | `feedingEvents` relationship |
| `SharedFeedingLogService` | Create `SharedFeedingEvent`, stamp `ckRecordName`, set `loggedBy` | `SharedPet`, `LoggedBy` |
| `LogSharedFeedingSheet` | UI for logging a shared-dog feeding | `SharedFeedingLogService` |
| Shared-dog restock sheet | UI for setting a new stock baseline | `SharedPet.effectiveFoodStockCount` |
| `LogSharedMedicationSheet` | UI for logging a shared-dog medication dose | `SharedMedication`, `SharedMedicationLog`, `LoggedBy` |
| `SharedPetCard` | Real logging entry points, flag-gated | all of the above |

## Data flow

1. Owner or participant taps "Log Meal" on a shared dog → `LogSharedFeedingSheet` →
   `SharedFeedingLogService.logFeeding` creates a `SharedFeedingEvent` with a fresh
   `ckRecordName` and `loggedBy = LoggedBy.current` → saves the shared `viewContext` → the
   existing Phase 2 push observer uploads it automatically (unchanged sync code).
2. The other device's next `fetchAllZones()` (foreground/launch/poll/silent-push, all unchanged)
   pulls the new event → `SharedDogStore` refreshes → dashboard re-renders →
   `effectiveFoodStockCount`/`todaysFeedingCount`/`lastFeedingDate` recompute automatically since
   they read the now-larger `feedingEvents` set live. No merge step anywhere in this path.
3. Two devices logging within the same sync window each create their own event (different
   `ckRecordName`s) — nothing conflicts, both events land, both get summed on next read.
4. Restock: writes `foodStockCount` + `foodStockBaselineDate` on the existing `SharedPet` —
   normal field-edit push, existing `ckRecordName`, same observer path as any other edit.
   Concurrent restocks: last-write-wins (accepted — see Confirmed decisions).
5. Medication: "Log Medication" → `LogSharedMedicationSheet` → builds a `SharedMedicationLog` +
   sets `medication.lastGivenDate` directly → saves → pushed the same way. Concurrent doses:
   last-write-wins on `lastGivenDate` (accepted).

## Error handling

- Core Data save failures (either sheet) surface a simple alert with `error.localizedDescription`
  — never `fatalError`, matching every prior phase's error-handling convention.
- No new offline/retry logic: a logged event sits locally (and is immediately reflected in the
  logging device's own derived counts, since Core Data's `viewContext` sees its own uncommitted
  writes) until the next successful push — entirely the existing Phase 2–4 engine's job.
- Flag off: `SharedPetCard`'s new entry points aren't shown — zero behavior change, matching
  every prior phase's Done criteria.

## Testing

- **Unit:**
  - `SharedFeedingLogService.logFeeding` — event fields set correctly (`portionsDeducted`
    resolution, `ckRecordName` stamped, `loggedBy` set, `pet` relationship wired).
  - `SharedPet.effectiveFoodStockCount` — table-driven: no events, events all before baseline,
    events all after baseline, mixed, no baseline set (nil) with events present.
  - `DogDisplayable` `SharedPet.todaysFeedingCount`/`lastFeedingDate` — events spanning
    yesterday/today, empty set, single event.
  - `SharedMedicationLog` creation path (inline in the sheet's logic, tested the same way
    `LogMedicationSheet`'s owned-dog equivalent would be, if it had tests — this phase adds the
    first tests for this pattern on either side, owned or shared).
- **Manual (two accounts, real devices, flag on) — REQUIRED:**
  1. Both devices log feedings for the same shared dog within a short window (before either
     syncs) → after sync, both events appear on both devices; stock and today's-count reflect
     the sum, not just one side's write.
  2. Restock on one device → other device shows the new baseline after sync.
  3. Log a medication dose from either device → the other device's "next due" reflects it
     (last-writer-wins accepted if truly concurrent).
  4. Flag off: no logging entry points appear on any `SharedPetCard` (though none should render
     at all, since shared dogs themselves are flag-gated upstream).

## Risks & mitigations

| Risk | Mitigation |
|---|---|
| Summing `feedingEvents` on every read gets slow at scale | Household data volumes (a handful of dogs, dozens–hundreds of events) make this cheap; the owned-dog side already does equivalent in-memory relationship computation (`recentFeedings`, `lastFeedingEvent`) at the same scale |
| Stored `todaysFeedingCountRaw`/`lastFeedingDate` fields become silently stale/unread | Documented in this spec; harmless dead data, no migration needed to remove them, a later cleanup phase can drop them once confidently unused |
| Concurrent restock races (rare) | Accepted last-writer-wins, documented; feeding logs (the common case) don't have this risk at all |
| Medication `lastGivenDate` races (rare) | Accepted last-writer-wins, matching owned-dog behavior already |
| New Core Data attribute breaks existing installs | Additive optional attribute; `NSPersistentStoreDescription` migration options default to enabled and are never overridden to `false` in `SharedDataStack` |

## Done criteria for Phase 6

- App builds (app + widget); new unit tests pass; existing suite shows no new failures.
- Flag OFF: no behavior change — `SharedPetCard` shows no logging entry points (dogs themselves
  don't render without the flag, per existing `DashboardView` gating).
- On two real accounts, real devices, flag on: feeding and medication logging on a shared dog
  works end-to-end in both directions; concurrent feeding logs from both devices are never lost
  (both counted in the derived stock/today's-count); confirmed by the manual checklist.
- Phases 1–5 behavior (sync, routing, silent push, migration, owned-dog logging) unaffected — no
  changes to `FeedingLogService`, `LogFeedingSheet`, `LogMedicationSheet`, or any owned-dog model.
