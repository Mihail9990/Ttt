extends SceneTree
const Simulation = preload("res://scripts/simulation.gd")
var checks: int = 0
var failures: Array[String] = []

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		push_error(message)

func _initialize() -> void:
	call_deferred("run")

func fresh():
	var sim = Simulation.new()
	sim.add_player(1, 1000)
	sim.add_player(2, 1000)
	sim.add_player(3, 500, true)
	return sim

func run() -> void:
	test_harvest()
	test_enet_peer_ids()
	test_building()
	test_market()
	test_houses()
	test_factory()
	test_barter()
	test_persistence()
	test_capacity_and_untrusted_saves()
	test_random_conservation()
	if failures.is_empty():
		print("SIMULATION PASS: %d checks; extraction, dimensions, fasteners, escrow, ownership, barter, production, persistence and conservation" % checks)
		quit(0)
	else:
		printerr("SIMULATION FAILED: %s" % str(failures))
		quit(1)

func test_harvest() -> void:
	var s = fresh()
	check(not s.add_player(1, 999999), "Duplicate account cannot mint money")
	check(not s.add_player(-1, 2), "Negative account rejected")
	check(s.seed_deposit(10, "timber", 3), "Finite timber deposit")
	check(not s.seed_deposit(10, "timber", 20), "Deposit ID cannot be reseeded")
	check(not s.harvest(1, 10, "shovel"), "Shovel cannot harvest timber")
	check(s.harvest(1, 10, "axe", 3), "Axe harvests finite timber")
	check(s.count_item(1, "timber") == 3 and s.deposits[10].remaining == 0, "Harvest conserves units")
	check(not s.harvest(1, 10, "axe"), "Exhausted deposit cannot mint")
	check(not s.grant(1, "board", -1), "Negative grant rejected")
	check(s.grant(1, "ammo", 4), "Ammo allowed")
	check(s.consume(1, "ammo", 1), "Consume one ammo")
	check(not s.consume(1, "ammo", 4) and s.count_item(1, "ammo") == 3, "Insufficient ammo is atomic")
	check(not s.spend_coins(1, -50), "Negative purchase cannot mint money")
	check(s.spend_coins(1, 50) and s.balance(1) == 950, "Valid spending")

func test_building() -> void:
	var s = fresh()
	s.grant(1, "board", 20)
	s.grant(1, "nail", 5)
	s.grant(1, "screw", 5)
	check(s.place_part(1, 100, "board", Vector3(2, .2, .03), Vector3(1, 2, 3), Vector3(.7, .4, .3)), "Arbitrary board orientation")
	check(s.count_item(1, "board") == 19, "Standard board costs one")
	check(s.place_part(1, 101, "board", Vector3(4, .2, .03), Vector3(1, 2, 3)), "Longer board")
	check(s.count_item(1, "board") == 17, "Longer board costs more material")
	check(not s.place_part(1, 101, "board", Vector3.ONE, Vector3.ZERO), "No duplicate construction IDs")
	check(not s.place_part(1, 102, "board", Vector3(-1, 1, 1), Vector3.ZERO), "Negative size rejected")
	check(not s.place_part(1, 102, "board", Vector3(NAN, 1, 1), Vector3.ZERO), "NaN size rejected")
	check(not s.place_part(1, 102, "board", Vector3(2, .2, .03), Vector3(INF, 0, 0)), "Infinite position rejected")
	check(not s.fasten(2, 200, 100, 101, "screw", Vector3.ZERO), "Other owner cannot consume someone else's fasteners")
	check(s.fasten(1, 200, 100, 101, "screw", Vector3(1, 2, 3)), "Individual screw connection")
	check(s.count_item(1, "screw") == 4 and s.fasteners.size() == 1, "One connection consumes one screw")
	check(not s.fasten(1, 200, 100, 101, "screw", Vector3.ZERO), "Joint replay rejected")
	check(not s.move_part(1, 100, Vector3.ZERO), "Connected part cannot move until detached")
	check(s.remove_fastener(1, 200), "Fastener can be removed")
	check(s.count_item(1, "screw") == 5, "Removed fastener returns once")
	check(not s.remove_fastener(1, 200), "No repeated fastener refund")
	check(s.fasten(1, 201, 100, 0, "nail", Vector3.ZERO), "Terrain anchor supported")
	check(s.destroy_part(100), "Damage destroys part")
	check(not s.parts.has(100) and s.fasteners.is_empty(), "Destruction removes stale fasteners")
	check(s.count_item(1, "nail") == 4 and s.count_item(1, "board") == 17, "Destroyed materials are not refunded")
	check(s.remove_part(1, 101) and s.count_item(1, "board") == 19, "Intact removable board refunds correct volume")

func test_market() -> void:
	var s = fresh()
	s.grant(1, "timber", 10)
	check(s.list_items(1, 100, "timber", 5, 70), "Market listing accepted")
	check(s.count_item(1, "timber") == 5, "Listed goods removed to escrow")
	check(not s.list_items(1, 101, "timber", 6, 1), "Cannot oversell escrowed goods")
	check(not s.purchase(1, 100), "Self trade rejected")
	check(s.purchase(2, 100), "Player buys another player's listing")
	check(s.balance(1) == 1070 and s.balance(2) == 930, "Payment transfers exactly")
	check(s.count_item(2, "timber") == 5, "Buyer receives escrow")
	check(not s.purchase(3, 100), "Consumed listing cannot be purchased again")
	check(not s.cancel_listing(1, 100), "Consumed listing cannot be refunded")
	check(s.list_items(1, 101, "timber", 5, 2), "Second listing")
	check(s.cancel_listing(1, 101) and s.count_item(1, "timber") == 5, "Cancel returns escrow once")
	check(not s.cancel_listing(1, 101), "Repeated cancel cannot duplicate")
	check(not s.list_items(1, 102, "timber", 1, -1), "Negative price rejected")
	check(s.list_items(1, 103, "timber", 1, 501), "Large valid offer")
	var before: String = JSON.stringify(s.snapshot())
	check(not s.purchase(3, 103), "Finite NPC budget rejects unaffordable purchase")
	check(before == JSON.stringify(s.snapshot()), "Failed trade changes no ledger")

func test_houses() -> void:
	var s = fresh()
	s.grant(1, "board", 10)
	s.grant(1, "screw", 3)
	s.place_part(1, 10, "board", Vector3(2, .2, .03), Vector3.ZERO)
	s.place_part(1, 11, "board", Vector3(2, .2, .03), Vector3.ONE)
	s.fasten(1, 20, 10, 11, "screw", Vector3.ZERO)
	check(not s.register_house(1, 30, [10]), "House cannot omit externally connected part")
	check(not s.register_house(1, 30, [10, 10.0]), "Mixed numeric duplicate part IDs rejected")
	check(s.register_house(1, 30, [10, 11]), "House registration")
	check(not s.register_house(1, 31, [10, 11]), "Parts cannot belong to multiple houses")
	check(s.list_house(1, 40, 30, 300), "Unique house listing")
	check(not s.fasten(1, 21, 10, 11, "screw", Vector3.ZERO), "Listed house is immutable")
	check(s.purchase(2, 40), "House purchase")
	check(s.houses[30].owner == 2 and s.parts[10].owner == 2 and s.fasteners[20].owner == 2, "House parts and connectors transfer together")
	check(not s.purchase(3, 40), "House cannot be sold twice")
	check(s.list_house(2, 41, 30, 100), "New owner may resell")
	check(s.destroy_part(10), "PvP destruction allowed through authority path")
	check(s.listings[41].closed and not s.purchase(3, 41), "Damage invalidates stale sale")
	check(s.destroy_part(11) and not s.houses.has(30), "Empty destroyed house removed")
	check(s.restore(JSON.parse_string(JSON.stringify(s.snapshot()))), "Destroyed-house history remains reloadable")
	check(not s.parts.has(10) and not s.parts.has(11), "Save cannot resurrect destroyed house")

func test_factory() -> void:
	var s = fresh()
	check(s.buy_factory(1, 100, "sawmill"), "Buy sawmill")
	check(s.balance(1) == 880, "Factory costs coins")
	s.grant(1, "timber", 2)
	check(not s.produce(1, 100), "Empty factory cannot produce")
	check(not s.deposit_factory(2, 100, "timber", 1), "Only owner may operate factory")
	check(s.deposit_factory(1, 100, "timber", 2), "Load factory stock")
	check(s.produce(1, 100, 2), "Two production batches")
	check(s.factories[100].stock.timber == 0 and s.factories[100].stock.board == 8, "Sawmill converts finite inputs")
	check(s.withdraw_factory(1, 100, "board", 8), "Collect production")
	check(s.count_item(1, "timber") == 0 and s.count_item(1, "board") == 8, "Production material conservation")
	check(not s.produce(1, 100, -3), "Negative batches rejected")
	check(s.buy_factory(1, 101, "brick_kiln"), "Buy brick kiln")
	for item: String in ["clay", "sand", "fuel"]:
		s.grant(1, item, 3)
		s.deposit_factory(1, 101, item, 3)
	check(s.produce(1, 101), "Kiln consumes clay, sand and fuel")
	check(s.factories[101].stock.clay == 1 and s.factories[101].stock.brick == 4, "Kiln exact recipe")

func test_barter() -> void:
	var s = fresh()
	s.grant(1, "board", 8)
	s.grant(2, "brick", 8)
	check(s.exchange(1, {"items": {"board": 3}, "coins": 20}, 2, {"items": {"brick": 2}, "coins": 7}), "Barter accepted")
	check(s.balance(1) == 987 and s.balance(2) == 1013, "Barter coin net")
	check(s.count_item(1, "board") == 5 and s.count_item(1, "brick") == 2 and s.count_item(2, "board") == 3, "Barter transfers both directions")
	var before: String = JSON.stringify(s.snapshot())
	check(not s.exchange(1, {"items": {"board": 6}}, 2, {}), "Barter cannot overspend")
	check(before == JSON.stringify(s.snapshot()), "Failed barter is atomic")
	check(not s.exchange(1, {}, 1, {}), "Self barter rejected")
	s.place_part(1, 10, "board", Vector3(2, .2, .03), Vector3.ZERO)
	s.register_house(1, 20, [10])
	check(not s.exchange(1, {"houses": [20, 20]}, 2, {}), "Cannot duplicate house in barter")
	check(not s.exchange(1, {"houses": [20, 20.0]}, 2, {}), "Mixed numeric duplicate house IDs rejected")
	check(s.exchange(1, {"houses": [20]}, 2, {"coins": 100}), "Unique house barter")
	check(s.houses[20].owner == 2 and s.parts[10].owner == 2, "Bartered house changes ownership")

func test_persistence() -> void:
	var s = fresh()
	s.seed_deposit(7, "clay", 15)
	s.harvest(1, 7, "shovel", 3)
	s.grant(1, "board", 10)
	s.grant(1, "screw", 5)
	s.place_part(1, 100, "board", Vector3(4, .2, .03), Vector3(-2, 1, 4), Vector3(.3, .2, .9))
	s.fasten(1, 101, 100, 0, "screw", Vector3(1, .2, 4))
	s.register_house(1, 102, [100])
	s.list_house(1, 103, 102, 100)
	s.buy_factory(1, 104, "sawmill")
	var saved: Dictionary = s.snapshot()
	var parsed: Dictionary = JSON.parse_string(JSON.stringify(saved))
	var loaded = Simulation.new()
	check(loaded.restore(parsed), "JSON-safe save restores all tables")
	check(loaded.parts[100].rotation.is_equal_approx(Vector3(.3, .2, .9)), "Rotation survives JSON round-trip")
	check(loaded.parts[100].size.is_equal_approx(Vector3(4, .2, .03)), "Size survives JSON round-trip")
	check(loaded.deposits[7].remaining == 12, "Depleted volume survives load")
	check(loaded.purchase(2, 103), "Restored house listing remains functional")
	for variant: int in range(9):
		var corrupt: Dictionary = saved.duplicate(true)
		match variant:
			0: corrupt.version = 2
			1: corrupt.players[0].coins = -1
			2: corrupt.players.append(corrupt.players[0].duplicate(true))
			3: corrupt.parts[0].owner = 9999
			4: corrupt.parts[0].position = [NAN, 0, 0]
			5: corrupt.fasteners[0].a = 9999
			6: corrupt.houses[0].parts = [100, 100]
			7: corrupt.listings[0].seller = 2
			8: corrupt.factories[0].stock = {"plutonium": 1}
		var before: String = JSON.stringify(loaded.snapshot())
		check(not loaded.restore(corrupt), "Corrupt save variant %d rejected" % variant)
		check(before == JSON.stringify(loaded.snapshot()), "Bad load %d preserves live world" % variant)

func test_random_conservation() -> void:
	var s = fresh()
	s.grant(1, "board", 200)
	s.grant(2, "board", 200)
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 72391
	for turn: int in range(500):
		var seller: int = rng.randi_range(1, 2)
		var buyer: int = 3 - seller
		var quantity: int = rng.randi_range(1, 4)
		var price: int = rng.randi_range(1, 35)
		var id: int = 1000 + turn
		if s.list_items(seller, id, "board", quantity, price):
			if rng.randi_range(0, 1) == 0:
				s.purchase(buyer, id)
			else:
				s.cancel_listing(seller, id)
		var escrow: int = 0
		for offer: Dictionary in s.listings.values():
			if not offer.closed and offer.kind == "items":
				escrow += int(offer.quantity)
		check(s.count_item(1, "board") + s.count_item(2, "board") + escrow == 400, "Random market goods conserved at %d" % turn)
		check(s.balance(1) + s.balance(2) == 2000, "Random market currency conserved at %d" % turn)

func test_capacity_and_untrusted_saves() -> void:
	var s = fresh()
	s.grant(1, "board", s.MAX_QUANTITY)
	check(not s.grant(1, "board", 1), "Inventory cannot exceed exact maximum")
	s.grant(2, "board", 5)
	check(s.exchange(1, {"items": {"board": 5}}, 2, {"items": {"board": 5}}), "Net-neutral trade at maximum capacity is valid")
	check(s.list_items(1, 900, "board", 1, 5), "Escrow creates one free inventory slot")
	s.grant(1, "board", 1)
	check(not s.cancel_listing(1, 900) and not s.listings[900].closed, "Full seller inventory preserves live escrow on failed cancel")
	check(s.purchase(2, 900), "Escrow remains purchasable after failed cancel")
	var saved: Dictionary = s.snapshot()
	for variant: int in range(9):
		var corrupt: Dictionary = saved.duplicate(true)
		match variant:
			0: corrupt.players[0].coins = "100"
			1: corrupt.players[0].coins = true
			2: corrupt.players[0].inventory = {"board": 0.5}
			3: corrupt.players[0].inventory = [1, 2]
			4: corrupt.players[0].id = INF
			5: corrupt.players[0].id = 1.5
			6: corrupt.players[0].extra = {"nested": [1, 2, 3]}
			7: corrupt.players[0].erase("coins")
			8: corrupt.players = ["invalid record"]
		var before: String = JSON.stringify(s.snapshot())
		check(not s.restore(corrupt), "Untrusted save variant %d rejected cleanly" % variant)
		check(before == JSON.stringify(s.snapshot()), "Untrusted save variant %d leaves state unchanged" % variant)
	var limited = fresh()
	for id: int in range(100, 100 + limited.MAX_RECORDS - 3):
		limited.seed_deposit(id, "soil", 1)
	check(limited.deposits.size() + limited.players.size() == limited.MAX_RECORDS, "Reach bounded record capacity")
	check(not limited.seed_deposit(999999, "soil", 1), "New deposit blocked at record budget")
	check(not limited.add_player(999999, 1), "New account blocked at record budget")
	check(limited.harvest(1, 100, "shovel"), "Existing records remain usable at capacity")

func test_enet_peer_ids() -> void:
	var s = fresh()
	const PEER: int = 2000000000
	check(s.add_player(PEER, 400), "ENet peer ID above one billion is supported")
	check(s.add_player(2147483647, 1), "Maximum positive signed32-bit ENet peer ID is supported")
	check(not s.add_player(2147483648, 1), "Out-of-range ENet identity rejected")
	check(s.grant(PEER, "board", 5), "Remote inventory")
	check(s.place_part(PEER, 100, "board", Vector3(2, .2, .03), Vector3.ZERO), "Large peer ID owns construction")
	check(s.register_house(PEER, 101, [100]), "Large peer ID owns house")
	check(s.list_items(PEER, 102, "board", 2, 50), "Remote seller listing")
	check(s.purchase(1, 102), "Host buys from large peer ID")
	check(s.balance(PEER) == 450 and s.count_item(1, "board") == 2, "Remote trade completes exactly")
	var loaded = Simulation.new()
	check(loaded.restore(JSON.parse_string(JSON.stringify(s.snapshot()))), "Large ENet IDs survive JSON snapshot restoration")
	check(loaded.players.has(PEER) and loaded.parts[100].owner == PEER and loaded.houses[101].owner == PEER, "Restored ownership retains large ENet peer ID")
	check(loaded.list_house(PEER, 103, 101, 100) and loaded.purchase(1, 103), "Restored remote house remains tradable")
	check(loaded.parts[100].owner == 1, "Remote house purchase transfers ownership")
