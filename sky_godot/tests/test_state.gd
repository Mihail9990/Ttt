extends SceneTree
## Runtime snapshot regression tests: no mocked scene/model/defense actors.
var checks: int = 0
var failures: int = 0
var game: Node

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("STATE TEST: " + message)

func rejected_atomically(state: Dictionary, message: String) -> void:
	var model: RefCounted = game.sim
	var before: String = JSON.stringify(game.sim.snapshot())
	var before_world: String = JSON.stringify(game._world_state())
	var loading_before: bool = game.loading
	var defense_ids: Dictionary = {}
	for id in game.defense_nodes:
		defense_ids[id] = game.defense_nodes[id].get_instance_id()
	check(not game._apply_state(state,true),message + " rejected")
	check(game.sim == model and JSON.stringify(game.sim.snapshot()) == before,message + " preserves live model")
	check(game.loading == loading_before,message + " preserves loading flag")
	check(JSON.stringify(game._world_state()) == before_world,message + " preserves world links and transient state")
	var intact: bool = game.defense_nodes.size() == defense_ids.size()
	for id in defense_ids:
		intact = intact and game.defense_nodes.has(id) and game.defense_nodes[id].get_instance_id() == defense_ids[id]
	check(intact,message + " preserves actors")

func run() -> void:
	game = load("res://scenes/main.tscn").instantiate()
	game.testing = true
	root.add_child(game)
	await physics_frame
	await physics_frame
	game.set_physics_process(false)
	game.local_player.set_physics_process(false)
	check(game.local_player != null,"real local player ready")
	var defense_id: int = game._id()
	var defense := SkyDefense.new()
	game.add_child(defense)
	defense.global_position = Vector3(2.0,2.0,3.0)
	defense.configure(defense_id,1,"drone",game)
	defense.origin = Vector3(1.0,1.5,1.0)
	defense.global_position = Vector3(4.0,2.1,3.5)
	defense.rotation = Vector3(0.0,0.4,0.0)
	defense.head.rotation = Vector3(0.2,-0.5,0.0)
	defense.clock = 7.25
	defense.cooldown = 0.45
	defense.health = 73.0
	game.defense_nodes[defense_id] = defense
	var state: Dictionary = game._world_state()
	var encoded: Dictionary = state.defenses[0]
	check(game._read_vec(encoded.position).is_equal_approx(defense.global_position),"defense serializes current position")
	check(encoded.has("origin") and game._read_vec(encoded.get("origin",[])).is_equal_approx(defense.origin),"defense serializes separate patrol origin")
	check(encoded.has("rotation") and game._read_vec(encoded.get("rotation",[])).is_equal_approx(defense.rotation),"defense serializes body orientation")
	check(encoded.has("aim") and game._read_vec(encoded.get("aim",[])).is_equal_approx(defense.head.rotation),"defense serializes aim")
	check(encoded.get("clock",-1.0) == defense.clock and encoded.get("cooldown",-1.0) == defense.cooldown,"defense serializes simulation clocks")
	var ammo: int = game.sim.count_item(1,"ammo")
	var instance: int = defense.get_instance_id()
	check(game._apply_state(JSON.parse_string(JSON.stringify(state)),true),"full JSON network state accepted")
	check(game.defense_nodes[defense_id].get_instance_id() == instance,"unchanged defense actor retained")
	check(game.defense_nodes[defense_id].global_position.is_equal_approx(Vector3(4.0,2.1,3.5)),"replicated drone pose applied")
	check(game.defense_nodes[defense_id].origin.is_equal_approx(Vector3(1.0,1.5,1.0)),"patrol origin remains independent")
	check(game.defense_nodes[defense_id].head.rotation.is_equal_approx(Vector3(0.2,-0.5,0.0)),"replicated gun aim applied")
	check(game.defense_nodes[defense_id].health == 73.0 and game.sim.count_item(1,"ammo") == ammo,"state preserves health and finite ammunition")
	check(game._apply_state(state,true),"repeated network snapshot accepted")
	check(game.defense_nodes[defense_id].get_instance_id() == instance,"repeated snapshot does not rebuild actor")
	for raw: Variant in [{},[1,1.0],[game.NPC],[123456789],[1.5],[NAN],[INF],["1"],[true],[[1]]]:
		var broken: Dictionary = state.duplicate(true)
		broken.peers = raw
		rejected_atomically(broken,"malformed peers " + str(raw))
	for field: String in ["position","origin","rotation","aim"]:
		var broken: Dictionary = state.duplicate(true)
		broken.defenses[0][field] = [0.0,NAN,0.0]
		rejected_atomically(broken,"nonfinite defense " + field)
	for field: String in ["clock","cooldown"]:
		var broken: Dictionary = state.duplicate(true)
		broken.defenses[0][field] = INF
		rejected_atomically(broken,"nonfinite defense " + field)
	var legacy: Dictionary = state.duplicate(true)
	for field: String in ["origin","rotation","aim","clock","cooldown"]:
		legacy.defenses[0].erase(field)
	check(game._apply_state(legacy),"legacy defense snapshot accepted")
	check(game.defense_nodes[defense_id].origin.is_equal_approx(game._read_vec(legacy.defenses[0].position)),"legacy position supplies patrol origin")
	check(game._apply_state(state),"current snapshot restored after legacy test")
	for id in range(1000,1150):
		game.health[id] = 100.0
	var pruned: Dictionary = game._world_state()
	check(pruned.health.size() == game.players.size(),"serialized health includes only active players")
	check(pruned.health.has("1") and not pruned.health.has("1000"),"historical health omitted")
	check(game._apply_state(pruned),"pruned snapshot remains loadable after many historical peers")
	var remote: int = 2000000000
	check(game.sim.add_player(remote,100),"large ENet ID exists in model")
	game._ensure_player(remote,false)
	game.health[remote] = 42.0
	game.pose_times[remote] = 123
	game.pose_credit[remote] = 2.0
	game.last_command[remote] = 456
	var remote_work: String = str(remote) + ":" + str(defense_id) + ":nail"
	game.pending_work[remote_work] = 2
	game.pending_work["1:" + str(defense_id) + ":nail"] = 1
	var remote_state: Dictionary = game._world_state()
	check(game._apply_state(JSON.parse_string(JSON.stringify(remote_state)),true),"large ENet ID network snapshot accepted")
	check(game.players.has(remote) and game.health[remote] == 42.0,"remote player and health retained")
	game._peer_disconnected(remote)
	check(not game.players.has(remote) and game.sim.players.has(remote),"disconnect removes actor while preserving inventory")
	check(not game.health.has(remote),"disconnect prunes transient health")
	check(not game.pose_times.has(remote) and not game.pose_credit.has(remote) and not game.last_command.has(remote),"disconnect prunes movement and command caches")
	check(not game.pending_work.has(remote_work) and game.pending_work.has("1:" + str(defense_id) + ":nail"),"disconnect prunes only departed player's construction progress")
	var crowded: Dictionary = game._world_state()
	for id in range(2000000001,2000000009):
		crowded.core.players.append({"id":id,"coins":0,"npc":false,"inventory":{}})
		crowded.peers.append(id)
	rejected_atomically(crowded,"nine simultaneous peers")
	var factory_id: int = game._id()
	check(game.sim.buy_factory(1,factory_id,"sawmill"),"factory model created")
	game.factory_positions[factory_id] = Vector3(3.0,2.0,5.0)
	game._sync_world()
	check(game.factory_nodes.has(factory_id),"factory actor created")
	var factory_instance: int = game.factory_nodes[factory_id].get_instance_id()
	game.factory_positions[factory_id] = Vector3(-4.0,3.0,6.0)
	game._sync_world()
	check(game.factory_nodes[factory_id].get_instance_id() == factory_instance,"factory reposition retains actor")
	check(game.factory_nodes[factory_id].global_position.is_equal_approx(Vector3(-4.0,3.0,6.0)),"factory actor follows authoritative position")
	var part_id: int = game._id()
	check(game.sim.place_part(1,part_id,"board",Vector3(2.0,0.03,0.2),Vector3(25.0,2.0,29.0)),"attachment part created")
	game.attachments[part_id] = 4
	game.attachments[factory_id] = 4
	game.attachments[defense_id] = 4
	game._sync_world()
	var linked: Dictionary = game._world_state()
	check(linked.attachments == {str(part_id):4,str(factory_id):4,str(defense_id):4},"part factory and defense attachments serialized")
	check(game._apply_state(JSON.parse_string(JSON.stringify(linked)),true),"attachment JSON network roundtrip accepted")
	check(game.attachments == {part_id:4,factory_id:4,defense_id:4},"attachment IDs normalized and retained")
	for raw: Variant in [[],{str(part_id):5},{str(part_id):4.5},{str(part_id + 100000):4},{str(part_id) + ".5":4},{part_id:4}]:
		var broken: Dictionary = linked.duplicate(true)
		broken.attachments = raw
		rejected_atomically(broken,"malformed attachments " + str(raw))
	for key: Variant in [factory_id,"0" + str(factory_id),str(factory_id) + ".0","+" + str(factory_id),"bad"]:
		var broken: Dictionary = linked.duplicate(true)
		broken.factory_positions = {}
		broken.factory_positions[key] = [0.0,1.0,0.0]
		rejected_atomically(broken,"noncanonical factory key " + str(key))
	for key: Variant in [1,"01","1.0","+1"," 1","bad"]:
		var broken: Dictionary = linked.duplicate(true)
		broken.health = {}
		broken.health[key] = 100.0
		rejected_atomically(broken,"noncanonical health key " + str(key))
	var collision: Dictionary = linked.duplicate(true)
	collision.defenses[0].id = int(collision.core.listings[0].id)
	rejected_atomically(collision,"defense ID colliding with core listing")
	game.attachments[part_id + 100000] = 4
	game.attachments[part_id] = 5
	game._sync_world()
	check(not game.attachments.has(part_id + 100000) and not game.attachments.has(part_id),"sync removes unknown entity and missing island links")
	game.sim.factories.erase(factory_id)
	game._sync_world()
	check(not game.factory_nodes.has(factory_id),"factory actor removed when absent from model")
	check(not game.attachments.has(factory_id) and game.attachments.get(defense_id) == 4,"sync removes deleted factory link while preserving defense link")
	game.queue_free()
	await process_frame
	print("STATE PASS: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
