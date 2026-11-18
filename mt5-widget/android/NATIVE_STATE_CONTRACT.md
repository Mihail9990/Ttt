# Native widget state contract and integration status

## Baseline incompatibility (before this change)

`RecoveryPanelView` accepts only `mode=simulation, live_trading=false`.
Its close/cancel-side buttons are permanently disabled. `native_api` returns
`NativeCoordinator.state()` directly: mode, executor_ready,
api_reconciliation_required, durable data, totals, tick. These are NOT the
simulation API's top-level settings/ranges/positions/orders/loss_history arrays.
Removing the simulation check alone would incorrectly display missing positions
and orders as absent. Durable entry observations are historical evidence, not a
fresh broker inventory. No real-mode Android build is provided by this document.

## Versioned read-only projection

Keep native internal state separate. Add a versioned `widget` object to native
state (or a dedicated read-only endpoint). Build it under session ownership and
coordinator lock, using a scoped `transport.snapshot` and durable mappings.
GET must never initialize a terminal, tick the strategy, or send/cancel orders.

Required fields:

- `schema_version: 1`, `mode: "native"` (NOT an assertion of live account type).
- `account_trade_mode: "real" | "demo" | "contest" | "unknown"`, taken from
  broker metadata, never inferred from `native` or user configuration.
- `snapshot: {status: "fresh" | "unavailable", observed_at: ISO8601 UTC,
  generation: string|null, symbol: string}`. Fresh is only after successful
  broker read and ownership/account checks before and after it. The timestamp
  records when the read completed, not when stale data was served.
- `settings`: configured distances as decimal strings. Defaults only if genuinely
  unconfigured; never silently replace missing settings for an active generation.
- `ranges`: configured range id, side, price, initial volume, lifecycle, settings.
  Label these as configured values, not actual exposure.
- `positions`, `orders`: fresh broker arrays with ticket, symbol, side, volume,
  price, SL, TP and mapped range id where provenance is verified. Unmapped owned
  exposure remains visible, with mapping status; do not hide it. Do not include
  unrelated account positions. Missing/unavailable arrays must be null, not [].
- `loss_history`: ledger rows including range id, generation, actual monetary net,
  closure and classification status. A separate read-only archive query is needed
  for past generations; current `totals()` is not complete history.
- `totals`: per range realized net, number of full SL closes, unresolved close
  classifications, cumulative losses separately defined from net result.
- `capabilities`: separate booleans `set_ranges`, `cancel_ranges` and list
  `close_cancel_range_ids`; reason codes for unavailable actions.
- `executor_ready`, `reconciliation_required`, `issues`: runtime health independent
  of transport connectivity and broker inventory. Healthy HTTP is not trading-ready.

Never derive cumulative loss from `max(0,-realized_net)`: profits would erase past
losses. Specify gross negative close totals vs net result separately. Do not show
initial configured volume as the current recovery step volume.

## Capability computation

Server computes capabilities, never client guesses from `executor_ready` alone.
Snapshot unavailable, ownership fault, account mismatch, unknown owned exposure,
interrupted API command, or unresolved checkpoints disable mutation capabilities.
`set_ranges` and `cancel_ranges` require no owned open positions and proven mapped
pending state. A clean waiting generation may permit `set_ranges` even when the
executor readiness flag is false. `close_cancel_range_ids` is computed from each
range's proven mapping and management state, not simply a position count.
All checks repeat in command handlers immediately before effects: the GET snapshot
cannot authorize a later broker action against changed state.

## Android changes after server implementation

1. Strict parser for versioned native object; retain separate simulation handling.
   Unsupported/malformed contract allows refresh only, never implicit fallback.
2. Replace demo-only labels dynamically. Display native runtime and broker account
   type separately, and show unknown rather than asserting real account type.
3. Render unavailable inventory as `Данные не подтверждены`, not `Нет`. Keep last
   snapshot visibly stale after network failure, disable mutation controls.
4. Use separate capability fields for each button; fresh check before submission.
   Fix initial volume to strategy's 0.01 or explain server rejection instead of
   allowing arbitrary starting volume inconsistent with the fixed scale.
5. Preserve no-blind-retry behavior. Persist command UUID AND exact payload before
   POST; retain across process death and network timeouts. A retry for the same
   logical command must reuse the UUID. A new UUID is not reconciliation.
6. Inspect response business outcome, not only HTTP 200. Show accepted/in-progress,
   confirmed, rejected and unresolved distinctly. Follow-up snapshot is evidence
   of state, not proof that the particular command succeeded.
7. Keep configured inputs separate from active server ranges. Failed submission
   must not make edited values look active. Confirm selected range and parameters
   through the user's own app interaction before a mutation.
8. Do not connect production mutation buttons until the native state contract,
   runner ownership/lifecycle, EA bridge and end-to-end command outcomes are tested.

## Required tests (not yet executed)

- Fresh native, simulation, unknown mode, wrong/missing schema, malformed arrays.
- Read error or stale snapshot does not render empty exposure or enable commands.
- Native+demo broker metadata is labelled demo, not real.
- Actual filled volume differs from configured/requested volume.
- Positions prevent cancel-all and replace, but independent capabilities can allow
  explicit close/cancel for a mapped range.
- Waiting generation permits new ranges despite executor_ready=false when server
  explicitly returns that capability; unresolved checkpoint does not.
- Unmapped owned position/order disables changes and remains visibly unresolved.
- Manual close preserves pending order display until broker confirms cancellation.
- Historic observations do not resurrect closed positions/pending orders.
- Partial execution and timeout preserve UUID/payload through Activity/process death;
  no new UUID or automatic resend on refresh/reconnect.
- HTTP 200 with unresolved command outcome is not presented as successful trade.
- Archive loss history survives generation change while new range counters reset.
- Integration doubles assert GET projection invokes zero order_send calls.
- Samsung overlay permission/gestures/scaling, background process lifecycle,
  Caddy HTTPS, Windows MT5 and EA compilation require environment/device testing.

This is a contract proposal and gap analysis, not a claim of integration tests or
live readiness. No broker connection or actual order was made for this analysis.

## Parser implemented in this change

`NativeWidgetState.java` validates the versioned envelope, inventory container
shape, required status fields, range ids and command capability types. It is a
state gate, not a broker-record field validator. It is consumed by `RecoveryPanelView` for native-mode gating; the parser itself
does not send commands. Snapshot timestamp
must be between now minus 15 seconds and now; device clock skew disables actions
until corrected. `copy()` provides a detached rendering object. Rendering must
still validate/format broker record details before using them.

`NativeWidgetStateTest` ran locally: 12 checks passed with ECJ and Android's JSON
implementation. The larger required integration test matrix above remains pending.
Server projection is implemented independently; see the cross-language contract
check below. Runtime integration testing is still required.

## UI wiring added

RecoveryPanelView now accepts the strict versioned native projection and uses its
separate capabilities. It displays account mode from server metadata and unknown
inventory instead of empty inventory. Starting volume is fixed at 0.01. The user
confirms a command explicitly. Before POST the app synchronously saves UUID, exact
payload, path and server URL; refresh never resends. A matching persisted receipt
with phase completed AND outcome confirmed clears the pending marker. Timeout,
unresolved business outcome or missing receipt leaves mutation controls disabled
across app restart and requires VPS reconciliation. There is deliberately no
unsafe clear/retry button. A read-only request-status endpoint and operator-guided
resolution remain to be added for recovering this local pending marker.

All Java app sources compile with ECJ (two existing deprecated display API warnings).
NativeWidgetStateTest: 12 checks pass. NativeCommandReceiptTest: 7 checks pass.
No APK produced or installed here; overlay dialog, Android lifecycle and actual
Windows MT5/EA/Caddy connections have NOT been tested. No real order was sent.

Cross-language fixture check: an actual native API projection response generated
by coordinator's broker double with open position 88 was parsed by the Java gate.
PASS: fresh inventory and disabled replace/cancel-all. Fixture retained at
`tests/fixtures/native-open-position.json`; `NativeFixtureTest` uses its snapshot
clock rather than wall time. This is a contract test, not a live broker test.

## Reviewed integration corrections

The read-only status endpoint is now used: GET `/api/recovery/commands/{UUID}`.
Pending recovery only uses the saved server URL and matching binding context.
Terminal `completed/confirmed` or `rejected/rejected` resolves pending only when
request UUID and full canonical command payload match. `not_recorded`,
`dispatching`, unknown, mismatched context or unresolved outcome never clears it.
No status check resends a POST. A malformed/auth-rejected request absent from the
journal remains unresolved; a late original POST cannot be ruled out by absence.

Native POSTs now include expected_context and expected_generation captured at
confirmation. The server checks these under its coordinator lock. The dialog
captures the immutable Api connection; later settings changes cannot redirect the
POST or its pending journal URL. The app rejects changed state before submission.
A process-wide dispatch lock serializes all view workers across service restart;
inside the lock it rechecks pending and disposed immediately before reservation
and POST. Pending clear compares the exact saved payload. Closing the overlay
cannot cancel an already dispatched command or the VPS strategy.

MainActivity now explains native trading rather than promising simulation-only.
Confirmation buttons reject obscured touches. Failed refresh marks retained
summary as stale. New NativePendingResolutionTest: 10 checks passed. Updated
context-bearing server projection fixture passed the Java parser again.

## Typed pre-dispatch refusal recovery

For 401/422 only, the native server may return a versioned, attempt-only
`not_dispatched` marker with exact method, path, UUID and SHA-256 of raw request
bytes. The client accepts it only for one durably recorded lifetime POST attempt,
validates all fields and expected reason, and saves the proof before clearing the
matching pending payload. Normal HTTP status alone is never proof. The server
suppresses this marker whenever that UUID already exists in its command journal.
No marker is synthesized by the app. Missing/malformed proof, unknown outcome,
transport error, or a non-single attempt retains pending. POST uses fixed-length
streaming and redirects are disabled; no application retry exists.

`NativeDefiniteRejectionTest`: 12 checks pass, including mutated body/path/id,
wrong phase/schema/status/reason, and more than one recorded attempt. Device and
transport-fault tests remain required; the proof is specific to this HTTP attempt,
not a claim that an arbitrary externally reused UUID can never execute.

Single-ever dispatch is additionally guarded by a separate persistent attempted
UUID ledger. Marking commits before pending reservation and sending; a UUID is
never removed when pending resolves. Repeated dialog callbacks cannot reset the
attempt count and dispatch an old UUID. A crash between ledger mark and POST can
prevent a never-sent UUID, but cannot resend it. This ledger must not be pruned
without replacing the protocol with a stronger server-side anti-replay design.

Actual server 401 and 422 fixtures passed `NativeRejectionFixtureTest` (2 cases),
retained in tests/fixtures/native-rejections.json. This checks Python/Java wire
compatibility, not Android network fault behavior.

## Explicit evidence-only reconciliation control

The panel has `Сверить журнал VPS (без повторной отправки)`. It is separate from trade command
submission and is available with a parsed native connection even if trading
pending exists. Confirmation binds its immutable connection and expected context /
generation. Its POST goes only to `/api/recovery/reconcile`, which the server
implements using evidence reads and local journal updates, never broker sends.
The client does not overwrite trading pending or replay its original POST.
A subsequent fresh state and GET original UUID status are required to resolve
pending. HTTP200 from reconciliation alone is not terminal proof. Unresolved
issues remain visible in the panel alongside the snapshot timestamp.

Final local checks for this iteration: all Java application/test sources compile;
1326 assertions across eight test mains pass, plus actual server projection and
401/422 cross-language fixtures. Network faults, lifecycle races and service
restart behavior still require Android device/instrumented testing.

Reconciliation confirmation explicitly warns that successful reconciliation may
allow the VPS to resume the previously configured strategy on later ticks. The
evidence-only guarantee applies to reconciliation itself, not future strategy activity.
