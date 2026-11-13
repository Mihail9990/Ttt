# Sky Islands authoritative gameplay core

`WorldModel.h` is standard C++17 with no engine or third-party dependency. It is
included by the Unreal module, and the same implementation is exercised by the
standalone tests. Run `bash sky_islands/Tests/run_core_tests.sh` from repository
root. This check does **not** compile the Unreal module or exercise rendering.

## Stable identifiers and units

All entity identifiers use `SkyCore::Id` (`int64_t`, strictly positive). Separate
entity maps have separate id namespaces. `partB == 0` is the special world/terrain
anchor for a fastener. Runtime entity allocation must not recycle ids while a
client may still have an old command in flight. Listings remain archived after
purchase/cancellation, making duplicate purchase requests harmless.

`Item` values are fixed: Soil=0, Clay=1, Sand=2, Stone=3, Timber=4, Board=5,
Brick=6, Ore=7, Metal=8, Nail=9, Screw=10, Fuel=11. `Tool`: Shovel=0, Axe=1,
Pickaxe=2. `FactoryKind`: Sawmill=0, BrickKiln=1, Smelter=2. Do not reorder these
values without a save migration.

Positions and dimensions are **metres**; Unreal's normal actor transforms are
centimetres, so the adapter converts at the boundary. A board inventory unit is
0.012 m³ (2 m × 0.2 m × 0.03 m). Brick, stone and metal units have their own
reference volumes in `MaterialCost`. Arbitrary rectangular part dimensions cost
the ceiling of their volume in material units, with a minimum of one unit.
Consequently changing the dimensions cannot turn one board into unlimited
building material. Visual rotation and cut/shape meshes belong to the engine
adapter. This core does not implement arbitrary mesh cutting.

## Main operations

- Setup: `AddPlayer`, `Grant`, `SeedDeposit`. Granting supplies is an **admin-only
  mint**, never a client RPC. NPCs are ordinary accounts with `npc=true`, finite
  stock and finite coins.
- Harvest: `Harvest(player, deposit, tool, quantity)`. Deposits are depleted by
  exactly the quantity credited. Shovels extract soil/clay/sand, axes timber,
  pickaxes stone/ore. No partial grant happens on failure.
- Building: `PlacePart`, `MovePart`, `RemovePart`. `Fasten` creates an individual
  screw/nail record joining two owned parts, or a part and terrain. Removing a
  connection recovers one fastener. Moving/removing a still-connected part is
  rejected. `RegisterHouse` groups a closed selection of parts for sale;
  `UnregisterHouse` lets its owner release an unlisted assembly for remodeling.
- PvP destruction: `DestroyPart` is **authority-only**, after the engine validates
  actual damage. It removes related connectors without refund, closes an active
  house listing, updates surviving parts and removes an empty assembly. Closed
  historical listings cannot sell or resurrect destroyed parts.
- Items: `PublishItems` moves the entire bundle into escrow; `Purchase` transfers
  that bundle and the **whole listing price** atomically. `CancelListing` returns
  escrow only once. Prices are not per-item. Self-purchase is rejected.
- Unique houses: `PublishHouse` reserves ownership of the real assembly.
  `Purchase` transfers the house, constituent parts and fasteners together.
  Listed assemblies cannot be edited through ordinary construction methods.
- Barter: `Exchange(first, firstOffer, second, secondOffer)` simultaneously
  exchanges item bundles, unique houses and optional coin supplements. Both
  offers are fully validated before either participant changes.
- Production: `BuyFactory`, `DepositFactory`, `Produce`, `WithdrawFactory`.
  Sawmill batches use 1 Timber → 4 Board; brick kilns 2 Clay + 1 Sand + 1 Fuel →
  4 Brick; smelters 2 Ore + 1 Fuel → 1 Metal. Factory purchase prices are explicit
  NPC currency sinks. Runtime time scheduling is separate from recipe execution;
  `Produce` never advances a clock by itself.

Every mutating operation returns `Status`, which has `.error`, `.Ok()` and an
explicit bool conversion. Failure leaves valid live state unchanged.

## Server boundary

The core owns inventory, balances, deposits, part material accounting, joints,
unique object ownership, marketplace escrow and factory recipes. The Unreal
server must additionally validate **authenticated actor identity**, actual tool
possession/equipping, reach, line of sight, tool cooldown, contact/surface checks,
island permissions, world bounds, hits/damage and all timestamps. In particular,
`Fasten` does not perform a scene collision query, and `DestroyPart` does not
accept client-authored damage facts. Never forward a client-supplied player id
or expose `Grant`, `Restore` or public state mutation through an RPC.

## Persistence

`Model.state` is a public `Snapshot` for trusted adapters. Its maps/structs are
plain standard-library values; write access is not a gameplay command. Use
`Restore(snapshot)` rather than assigning unvalidated loaded data.

`Serialize(std::ostream&)` and `Deserialize(std::istream&)` use `SKYCORE 1` and
17-digit double precision. Deserialization is capped at 16 MiB, 100,000 records
per collection and 500,000 aggregate records, including inventories/house member
ids. Duplicate keys, unsupported versions, truncation, trailing junk, invalid
geometry, negative balances and broken ownership references are rejected. The
live model changes only after full validation. Save bytes should be placed in an
engine SaveGame/container with the accompanying world geometry and rotations;
this text is not a substitute for those transforms.

## Verified behavior

The executable tests cover depletion and tool matching; material-volume costs;
independent fasteners and terrain anchors; house transfer and remodeling;
destruction of listed buildings and persistence without resurrection; NPC/player
escrow, cancellation and replay; failed-trade atomicity and overflow; barter;
factory stock accounting; malformed save input; and repeated random market
transactions conserving coins and material.
