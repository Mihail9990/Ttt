extends SceneTree
## Helper for run_network_tests.py. Uses the real game scene/RPCs in two processes.
const WorldScript = preload("res://scripts/main.gd")
var world: Node3D
var role: String = ""
var output_dir: String = ""
var failures: Array[String] = []

func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--net-role="):
			role = argument.trim_prefix("--net-role=")
		elif argument.begins_with("--net-output="):
			output_dir = argument.trim_prefix("--net-output=")
	_run.call_deferred()

func require(condition: bool, reason: String) -> bool:
	if condition:
		return true
	failures.append(reason)
	push_error("GODOT NETWORK FAIL: " + reason)
	return false

func write_json(name: String, data: Dictionary) -> void:
	var file := FileAccess.open(output_dir.path_join(name), FileAccess.WRITE)
	if file == null:
		failures.append("Could not write test report: " + name)
		return
	file.store_string(JSON.stringify(data))
	file.close()

func read_json(name: String) -> Dictionary:
	var file := FileAccess.open(output_dir.path_join(name), FileAccess.READ)
	if file == null:
		return {}
	var value: Variant = JSON.parse_string(file.get_as_text())
	return value if value is Dictionary else {}

func wait_file(name: String, timeout_ms: int = 15000) -> bool:
	var deadline: int = Time.get_ticks_msec() + timeout_ms
	while not FileAccess.file_exists(output_dir.path_join(name)):
		if Time.get_ticks_msec() >= deadline:
			return false
		await create_timer(0.05).timeout
	return true

func finish(data: Dictionary, exit_code: int = 0) -> void:
	data["failures"] = failures
	data["role"] = role
	write_json(role + ".json", data)
	print("NETWORK_PEER_", role.to_upper(), "_", "PASS" if failures.is_empty() and exit_code == 0 else "FAIL")
	if world != null:
		world.multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
		world.queue_free()
	quit(exit_code if exit_code != 0 else (0 if failures.is_empty() else 1))

func _run() -> void:
	if role not in ["host", "client"] or output_dir.is_empty():
		push_error("network_peer requires --net-role=host/client and --net-output=DIR")
		quit(1)
		return
	world = WorldScript.new()
	root.add_child(world)
	await process_frame
	if role == "host":
		await run_host()
	else:
		await run_client()

func run_host() -> void:
	# This server-side edit happens BEFORE the remote peer joins. The initial
	# snapshot must include old terrain edits, not just future event RPCs.
	var island: SkyIsland = world.islands[1]
	var removed: float = island.excavate(Vector3(0, -6, 0), 2.0)
	if not require(removed > 25.0, "host setup excavation"):
		finish({}, 1)
		return
	var result: String = world.host_game()
	if not world.multiplayer.multiplayer_peer is ENetMultiplayerPeer:
		write_json("host.ready.json", {"blocked": true, "message": result})
		finish({"environment_blocked": true, "message": result}, 77)
		return
	write_json("host.ready.json", {"blocked": false, "message": result})
	if not await wait_file("client.json"):
		require(false, "client did not finish within timeout")
		finish({}, 1)
		return
	var report := read_json("client.json")
	var client_id: int = int(report.get("player_id", 0))
	require(client_id > 1 and client_id != world.NPC, "network-assigned peer identity")
	require(world.sim.players.has(client_id), "server has remote player inventory")
	require(world.players.has(client_id), "server has remote avatar")
	require(world.sim.balance(1) == 360, "spoofed player_id did not debit host")
	require(world.sim.count_item(1, "board") == 28, "spoofed player_id did not grant host goods")
	require(world.sim.balance(client_id) == 335, "server debited actual remote peer")
	require(world.sim.count_item(client_id, "board") == 38, "server granted purchased boards to actual peer")
	require(world.sim.balance(world.NPC) == 5025, "NPC received actual payment")
	require(world.islands[1].get_stamps().size() == 1, "old terrain edit remains authoritative")
	write_json("host.done.json", {"ok": failures.is_empty()})
	# Keep server connected while the client reads its acknowledgment.
	await create_timer(0.25).timeout
	finish({"client_id": client_id, "host_coins": world.sim.balance(1),
		"client_coins": world.sim.balance(client_id), "client_boards": world.sim.count_item(client_id, "board"),
		"npc_coins": world.sim.balance(world.NPC), "terrain_stamps": world.islands[1].get_stamps().size()})

func run_client() -> void:
	world.join_game("127.0.0.1")
	var deadline: int = Time.get_ticks_msec() + 15000
	while world.local_player == null or world.local_player.player_id <= 1 or not world.network_mode.contains("Подключено"):
		if Time.get_ticks_msec() >= deadline:
			require(false, "client handshake timeout: " + world.network_mode)
			finish({}, 1)
			return
		await create_timer(0.05).timeout
	var player_id: int = world.local_player.player_id
	if not require(world.players.has(1) and world.players.has(player_id), "client has host and remote avatar"):
		finish({}, 1)
		return
	if not require(world.islands.size() == 4 and world.islands[1].get_stamps().size() == 1, "late join received shared map and previous dig"):
		finish({}, 1)
		return
	require(world.islands[1].density(Vector3(0, -6, 0)) < 0.0, "late-join cavity is actual negative density")
	require(world.sim.balance(player_id) == 360, "client received starter balance")
	require(world.sim.count_item(player_id, "board") == 28, "client received starter inventory")
	var offer_id: int = 0
	for id in world.sim.listings:
		var offer: Dictionary = world.sim.listings[id]
		if not offer.closed and offer.seller == world.NPC and offer.item == "board":
			offer_id = int(id)
			break
	if not require(offer_id > 0, "NPC board listing received"):
		finish({}, 1)
		return
	# Client-side execution of the server dispatcher must have no effect.
	world._server_action(1, {"action": "trade_buy", "listing": offer_id})
	require(world.sim.balance(1) == 360 and world.sim.balance(player_id) == 360, "client cannot call local authority dispatcher")
	# Identity fields are not part of the action schema. A malicious client may
	# not use them to buy with another player's wallet or mutate its own state.
	world.request_action({"action": "trade_buy", "listing": offer_id, "player_id": 1, "id": 1})
	await create_timer(0.4).timeout
	require(world.sim.balance(1) == 360 and world.sim.count_item(1, "board") == 28, "forged identity cannot mutate host wallet or inventory")
	require(world.sim.balance(player_id) == 360 and world.sim.count_item(player_id, "board") == 28, "malformed identity command rejected without purchase")
	# A valid command carries no identity: the server must derive it from ENet.
	world.request_action({"action": "trade_buy", "listing": offer_id})
	deadline = Time.get_ticks_msec() + 7000
	while world.sim.balance(player_id) != 335 or world.sim.count_item(player_id, "board") != 38:
		if Time.get_ticks_msec() >= deadline:
			require(false, "purchase did not replicate to client")
			finish({"player_id": player_id}, 1)
			return
		await create_timer(0.05).timeout
	require(world.sim.balance(1) == 360, "client snapshot preserves host balance")
	# Replay of an already-closed offer must not duplicate goods or debit again.
	await create_timer(0.3).timeout
	world.request_action({"action": "trade_buy", "listing": offer_id})
	await create_timer(0.4).timeout
	require(world.sim.balance(player_id) == 335 and world.sim.count_item(player_id, "board") == 38, "replayed purchase cannot duplicate items")
	write_json("client.json", {"role": role, "player_id": player_id, "coins": world.sim.balance(player_id),
		"boards": world.sim.count_item(player_id, "board"), "terrain_stamps": world.islands[1].get_stamps().size(),
		"failures": failures})
	if not await wait_file("host.done.json", 5000):
		require(false, "server acknowledgment missing")
	finish({"player_id": player_id, "coins": world.sim.balance(player_id),
		"boards": world.sim.count_item(player_id, "board"), "terrain_stamps": world.islands[1].get_stamps().size()})
