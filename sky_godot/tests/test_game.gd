extends SceneTree
var checks: int = 0
var failures: int = 0
var game: Node
func _initialize() -> void:
	call_deferred("run")
func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("GAME TEST: "+message)
func aim_down(point: Vector3) -> void:
	game.local_player.global_position = point
	game.local_player.velocity = Vector3.ZERO
	game.local_player.rotation = Vector3.ZERO
	game.local_player.camera.rotation.x = -PI*0.5
	game.local_player.look_pitch = -PI*0.5
func run() -> void:
	game = load("res://scenes/main.tscn").instantiate()
	game.testing = true
	root.add_child(game)
	await physics_frame
	await physics_frame
	check(game.islands.size()==4,"four organic islands")
	check(game.resource_nodes.size()==20,"real resource nodes")
	check(game.local_player!=null and game.hud!=null,"player and touchHUD ready")
	check(game.sim.balance(1)==360,"starter economy")
	aim_down(Vector3(0,2,0))
	await physics_frame
	var hit: Dictionary = game._trace(1)
	check(not hit.is_empty(),"real physics ray reaches terrain")
	var soil: int = game.sim.count_item(1,"soil")
	check(game._use(1,{"tool":"shovel"}),"actual terrain excavation")
	check(game.sim.count_item(1,"soil")>soil,"excavation rewards removedvolume")
	aim_down(Vector3(4,2,4))
	await physics_frame
	var boards: int = game.sim.count_item(1,"board")
	check(game._use(1,{"tool":"build","build_kind":"board","size":[2.0,0.03,0.2],"rotation":[0.0,0.0,0.0]}),"free board placement")
	game._sync_world()
	await physics_frame
	var part: int = int(game.sim.parts.keys()[0])
	check(game.part_nodes.has(part),"part has actual mesh and collision")
	check(game.sim.count_item(1,"board")==boards-1,"volume priced board consumed")
	var nails: int = game.sim.count_item(1,"nail")
	for index in range(3):
		check(game._use(1,{"tool":"hammer"}),"hammer physicalcontact work %d" % index)
	game._sync_world()
	check(game.sim.fasteners.size()==1,"one individual fastener")
	check(game.sim.count_item(1,"nail")==nails-1,"nail consumed exactlyonce")
	check(game.part_nodes[part].joint_count==1,"visible fastenerhead")
	await physics_frame
	check(game._remove(1),"remove actualfastener")
	check(game._remove(1),"dismantle board")
	game._sync_world()
	check(game.sim.count_item(1,"board")==boards,"dismantle conserves material")
	aim_down(Vector3(4,2,4))
	await physics_frame
	check(game._use(1,{"tool":"build","build_kind":"board","size":[2.0,0.03,0.2],"rotation":[0.0,0.0,0.0]}),"house build fixture")
	game._sync_world()
	await physics_frame
	check(not game._house_list(1,0),"failed house listing rejected")
	check(game.sim.houses.is_empty(),"failed listing releases temporary grouping")
	check(game._house_list(1,100),"connected house listed")
	check(game._house_release(1),"house listing withdrawn for remodeling")
	check(game.sim.houses.is_empty(),"house details editable again")
	var offer: Dictionary = game.get_offers()[0]
	var coins: int = game.sim.balance(1)
	check(game.sim.purchase(1,int(offer.id)),"market purchase")
	check(game.sim.balance(1)==coins-int(offer.price),"market payment")
	check(not game.sim.purchase(1,int(offer.id)),"duplicatepurchase rejected")
	check(game._sell(1,{"item":"timber","quantity":1,"price":2,"npc":true}),"NPC buy order")
	check(not game._valid_command({"action":"trade_sell","quantity":{},"price":1}),"RPC dictionaryquantity rejected")
	check(not game._valid_command({"action":"trade_buy","listing":1.5}),"fractional IDs rejected")
	aim_down(Vector3(5,2,4))
	await physics_frame
	check(game._factory_buy(1,"sawmill"),"buy sawmill")
	var factory: int = int(game.sim.factories.keys()[0])
	var timber: int = game.sim.count_item(1,"timber")
	check(game._factory_run(1,factory),"produce actualboardbatch")
	check(game.sim.count_item(1,"timber")==timber-1,"production consumes input")
	game._sync_world()
	aim_down(Vector3(2,2,4))
	await physics_frame
	check(game._buy_defense(1,"turret"),"optional defenseplacement anywhere")
	check(game.defense_nodes.size()==1,"functional defense actor")
	var state: Dictionary = game._world_state()
	var balance_before: int = game.sim.balance(1)
	check(game._apply_state(JSON.parse_string(JSON.stringify(state))),"full world JSON roundtrip")
	check(game.sim.balance(1)==balance_before,"worldrestore currency conserved")
	var broken: Dictionary = state.duplicate(true)
	broken.islands[0].stamps = [{"center":[100000,0,0],"radius":1.0}]
	check(not game._apply_state(broken),"corrupt world terrain rejectedatomically")
	check(game.sim.balance(1)==balance_before,"rejected world preserves live economy")
	var destination := "user://sky_test_save.json"
	check(game._save_world(destination),"real save file written")
	check(game._load_world(destination),"real save file read")
	for suffix in ["",".bak",".tmp"]:
		if FileAccess.file_exists(destination+suffix): DirAccess.remove_absolute(destination+suffix)
	game.queue_free()
	await process_frame
	print("GAME PASS: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
