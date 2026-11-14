extends Node3D

const SAVE_PATH := "user://sky_world_v2.json"
const NPC := 9000000
const PORT := 27777
const MAX_PARTS := 800
const MAX_DEFENSES := 32
const ITEMS := ["soil","clay","sand","stone","timber","board","brick","ore","metal","nail","screw","fuel","ammo"]
var sim := SkySimulation.new()
var local_player: SkyPlayer
var hud: SkyHUD
var notice: String = "Добро пожаловать. Выбери инструмент и исследуй свой остров."
var players: Dictionary = {}
var islands: Dictionary = {}
var island_owners: Dictionary = {}
var resource_nodes: Dictionary = {}
var part_nodes: Dictionary = {}
var defense_nodes: Dictionary = {}
var health: Dictionary = {}
var factory_positions: Dictionary = {}
var factory_nodes: Dictionary = {}
var part_health: Dictionary = {}
var attachments: Dictionary = {}
var pilot_player: int = 0
var pending_work: Dictionary = {}
var last_command: Dictionary = {}
var pose_times: Dictionary = {}
var pose_credit: Dictionary = {}
var testing: bool = false
var next_id: int = 10000
var save_clock: float = 0.0
var state_clock: float = 0.0
var dirty: bool = false
var save_allowed: bool = true
var network_mode: String = "Одиночная игра"
var pilot_island: int = 0
var damage_flash: float = 0.0
var loading: bool = false

func _ready() -> void:
	name = "SkyWorld"
	SkyArt.build_environment(self)
	_create_island(1,41,24.0,Vector3.ZERO,1)
	_create_island(2,48,18.0,Vector3(64,8,-16),0)
	_create_island(3,55,19.0,Vector3(-62,14,-60),0)
	_create_island(4,66,10.0,Vector3(25,1,29),1)
	_seed_economy()
	_seed_resources()
	_create_dock()
	_create_helm()
	if not OS.get_cmdline_user_args().has("--fresh"):
		_load_world()
	_ensure_player(1,true)
	hud = SkyHUD.new()
	add_child(hud)
	hud.setup(self)
	_sync_world()
	multiplayer.peer_connected.connect(_peer_connected)
	multiplayer.peer_disconnected.connect(_peer_disconnected)
	multiplayer.connected_to_server.connect(_connected)
	multiplayer.connection_failed.connect(_connection_failed)
	multiplayer.server_disconnected.connect(_server_lost)
	print("SKY_GODOT_READY")

func is_authority() -> bool:
	return multiplayer.multiplayer_peer is OfflineMultiplayerPeer or multiplayer.is_server()

func _create_island(id: int, seed_value: int, radius_value: float, point: Vector3, owner: int) -> void:
	if islands.has(id): return
	var island := SkyIsland.new()
	island.name = "Island_%d" % id
	add_child(island)
	island.position = point
	island.configure(seed_value,radius_value)
	island.set_surface_materials(SkyArt.material("ground"),SkyArt.material("rock"))
	islands[id] = island
	island_owners[id] = owner

func _seed_economy() -> void:
	if sim.players.has(NPC): return
	sim.add_player(NPC,5000,true)
	for item in ITEMS:
		sim.grant(NPC,item,200)
	for item in ["board","brick","nail","screw","fuel","sand","metal","ammo"]:
		for batch in range(3):
			sim.list_items(NPC,_id(),item,10,25 if item in ["board","metal","ammo"] else 15)

func _seed_resources() -> void:
	var island: SkyIsland = islands[1]
	var rng := RandomNumberGenerator.new()
	rng.seed = 144
	for index in range(20):
		var angle := rng.randf_range(0.0,TAU)
		var radius_value := rng.randf_range(8.0,19.0)
		var point := Vector3(cos(angle)*radius_value,0,sin(angle)*radius_value)
		point.y = island.top_height(point.x,point.z)
		var deposit: int = 100+index
		var kind: String = "timber" if index < 14 else ("ore" if index%3 == 0 else "stone")
		if not sim.deposits.has(deposit): sim.seed_deposit(deposit,kind,10 if kind == "timber" else 8)
		var node := SkyResource.new()
		island.add_child(node)
		node.position = point
		node.rotation.y = rng.randf_range(0,TAU)
		node.configure(deposit,kind,int(sim.deposits[deposit].remaining),rng.randf_range(3.6,5.2) if kind == "timber" else 1.0)
		resource_nodes[deposit] = node

func _box(parent: Node3D, size: Vector3, point: Vector3, material: String, solid: bool = true) -> Node3D:
	var root: Node3D = StaticBody3D.new() if solid else Node3D.new()
	parent.add_child(root)
	root.position = point
	var visual := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	visual.mesh = mesh
	visual.material_override = SkyArt.material(material)
	root.add_child(visual)
	if solid:
		var collider := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = size
		collider.shape = shape
		root.add_child(collider)
		root.set_meta("anchor",true)
	return root

func _create_dock() -> void:
	var island: SkyIsland = islands[1]
	for index in range(22):
		_box(island,Vector3(3.2,0.12,0.27),Vector3(17.5,0.15,2.5+index*0.29),"wood")
	for z in [2.5,5.5,8.5]:
		for x in [16.0,19.0]:
			_box(island,Vector3(0.14,1.6,0.14),Vector3(x,0.6,z),"wood")
	_box(island,Vector3(0.12,0.12,6.3),Vector3(16,1.2,5.5),"wood")
	_box(island,Vector3(0.12,0.12,6.3),Vector3(19,1.2,5.5),"wood")
	for index in range(6):
		_box(island,Vector3(1.8,0.035,0.18),Vector3(14.0,0.15+index*0.04,5.5),"wood")
	var label := Label3D.new()
	label.text = "НЕБЕСНЫЕ ОСТРОВА\nПричал • Рынок: M"
	label.font_size = 44
	label.pixel_size = 0.007
	label.position = Vector3(16.5,2.8,2.0)
	island.add_child(label)

func _create_helm() -> void:
	var island: SkyIsland = islands[4]
	var helm := _box(island,Vector3(0.7,1.0,0.6),Vector3(0,0.5,0),"metal")
	helm.set_meta("helm",4)
	var label := Label3D.new()
	label.text = "ЛЕТАЮЩИЙ ОСТРОВ\nE: управление • WASD: полёт\nПробел: выше • Ctrl: ниже"
	label.position = Vector3(0,2.0,0)
	label.font_size = 30
	label.pixel_size = 0.004
	island.add_child(label)

func _ensure_player(id: int, controlled: bool = false) -> SkyPlayer:
	if players.has(id): return players[id]
	if not sim.players.has(id):
		sim.add_player(id,360)
		for entry in [["board",28],["brick",32],["nail",40],["screw",40],["fuel",12],["timber",4],["clay",8],["sand",4],["ammo",36]]:
			sim.grant(id,entry[0],entry[1])
	var player := SkyPlayer.new()
	player.name = "Player_%d" % id
	add_child(player)
	player.configure(id,controlled,self)
	var home: int = 0
	for island_id in island_owners:
		if int(island_owners[island_id])==id:
			home = int(island_id)
			break
	if home==0:
		for island_id in island_owners:
			if int(island_owners[island_id])==0:
				home = int(island_id)
				island_owners[home] = id
				break
	if home==0 and is_authority() and islands.size()<12:
		home = 5
		while islands.has(home): home += 1
		var angle: float = float(home)*2.399963
		_create_island(home,70+home,18.0,Vector3(cos(angle)*125.0,8.0+home,sin(angle)*125.0),id)
	var spawn := Vector3(-6+float(id%3),3,4)
	if home>0:
		var land: SkyIsland = islands[home]
		spawn += land.global_position
		spawn.y = land.global_position.y+land.top_height(-4,4)+3.0
	player.global_position = spawn
	players[id] = player
	if not health.has(id): health[id] = 100.0
	if controlled: local_player = player
	return player

func _id() -> int:
	var result := next_id
	next_id += 1
	return result

func _physics_process(delta: float) -> void:
	if not is_authority(): return
	save_clock += delta
	state_clock += delta
	for id in defense_nodes:
		defense_nodes[id].server_tick(delta)
	if local_player != null and pilot_island > 0:
		_move_pilot(delta)
	if (dirty or not defense_nodes.is_empty()) and state_clock > 0.25:
		state_clock = 0
		_broadcast_state()
	if save_clock > 45.0 and not testing:
		save_clock = 0
		_save_world()

func mark_dirty() -> void:
	dirty = true

func get_local_stats() -> Dictionary:
	var id: int = local_player.player_id if is_instance_valid(local_player) else 1
	return {"coins":sim.balance(id),"health":health.get(id,100.0),"inventory":sim.players.get(id,{}).get("inventory",{}),"network":network_mode,"notice":notice,"pilot":pilot_island}

func get_offers() -> Array:
	var result: Array = []
	for key in sim.listings:
		var offer: Dictionary = sim.listings[key]
		if offer.closed: continue
		var row := offer.duplicate(true)
		row["id"] = key
		row["npc"] = int(offer.seller) == NPC
		result.append(row)
	return result

func request_action(command: Dictionary) -> void:
	if not is_instance_valid(local_player): return
	if is_authority():
		_server_action(local_player.player_id,command)
	else:
		if multiplayer.multiplayer_peer.get_connection_status()!=MultiplayerPeer.CONNECTION_CONNECTED: return
		send_player_pose(local_player.player_id,local_player.global_position,local_player.rotation.y,local_player.camera.rotation.x)
		_submit_action.rpc_id(1,command)

@rpc("any_peer","call_remote","reliable")
func _submit_action(command: Dictionary) -> void:
	if is_authority(): _server_action(multiplayer.get_remote_sender_id(),command)

func _trace(id: int, reach: float = 6.0) -> Dictionary:
	if not players.has(id): return {}
	var player: SkyPlayer = players[id]
	var eye := player.get_eye()
	var direction := player.get_aim()
	var query := PhysicsRayQueryParameters3D.create(eye,eye+direction*reach)
	query.exclude = [player.get_rid()]
	return get_world_3d().direct_space_state.intersect_ray(query)

func _server_action(id: int, command: Dictionary) -> void:
	if not is_authority() or not players.has(id) or command.size()>16: return
	var now := Time.get_ticks_msec()
	if now-int(last_command.get(id,0)) < 180: return
	last_command[id] = now
	if not _valid_command(command): return
	var action := str(command.get("action",""))
	var ok := false
	match action:
		"use": ok = _use(id,command)
		"interact": ok = _interact(id)
		"trade_buy", "house_buy": ok = sim.purchase(id,int(command.get("listing",0)))
		"trade_sell": ok = _sell(id,command)
		"trade_cancel": ok = sim.cancel_listing(id,int(command.get("listing",0)))
		"house_release": ok = _house_release(id)
		"factory_buy": ok = _factory_buy(id,str(command.get("kind","")))
		"factory_run": ok = _factory_run(id,int(command.get("factory",0)))
		"house_list": ok = _house_list(id,int(command.get("price",1000)))
		"defense_buy": ok = _buy_defense(id,str(command.get("kind","")))
		"save":
			if id == 1: ok = _save_world()
		"remove": ok = _remove(id)
		_: _notify(id,"Неизвестное действие")
	if not ok and not sim.last_error.is_empty(): _notify(id,sim.last_error)
	_sync_world()
	_broadcast_state()

func _use(id: int, command: Dictionary) -> bool:
	var tool := str(command.get("tool",""))
	var hit := _trace(id,80.0 if tool=="rifle" else 6.0)
	if hit.is_empty():
		_notify(id,"Подойди ближе и наведи прицел на объект")
		return false
	var collider: Object = hit.collider
	if tool == "build": return _place(id,command,hit)
	if tool == "rifle":
		if not sim.consume(id,"ammo",1): return false
		_damage_hit(hit,24.0,id)
		_notify(id,"Выстрел")
		return true
	if collider.has_meta("island"):
		var island: SkyIsland = collider.get_meta("island")
		var point: Vector3 = hit.position-hit.normal*0.25
		var item := island.material_at(point)
		var hard: bool = item in ["stone","ore"]
		if tool != ("pickaxe" if hard else "shovel"):
			_notify(id,"Для породы нужна кирка" if hard else "Для грунта нужна лопата")
			return false
		if sim.count_item(id,item)>999999000: return false
		var volume := island.excavate(point,1.0)
		if volume<=0:
			_notify(id,"Нового материала здесь нет или достигнут лимит выемок")
			return false
		var deposit := _id()
		var units := clampi(int(volume/0.1),1,32)
		sim.seed_deposit(deposit,item,units)
		var result := sim.harvest(id,deposit,tool,units)
		_notify(id,"Добыто: %s × %d" % [item,units])
		return result
	if collider.has_meta("deposit_id"):
		var deposit := int(collider.get_meta("deposit_id"))
		var result := sim.harvest(id,deposit,tool,1)
		if result: _notify(id,"Получен ресурс: %s" % sim.deposits[deposit].item)
		return result
	if collider.has_meta("part_id"):
		var part: SkyBuildPart = collider
		if tool in ["hammer","driver"] and part.owner_id == id: return _fasten(id,part,hit,tool)
		if tool in ["axe","pickaxe","hammer"]:
			_damage_hit(hit,18.0,id)
			return true
	if tool in ["axe","pickaxe","hammer"]:
		_damage_hit(hit,18.0,id)
		return true
	return false

func _read_vec(raw: Variant, limit: float = 100000.0) -> Vector3:
	if not raw is Array or raw.size()!=3: return Vector3(INF,INF,INF)
	for value in raw:
		if not (value is int or value is float) or not is_finite(float(value)) or absf(float(value))>limit:
			return Vector3(INF,INF,INF)
	return Vector3(float(raw[0]),float(raw[1]),float(raw[2]))

func _place(id: int, command: Dictionary, hit: Dictionary) -> bool:
	if sim.parts.size()>=MAX_PARTS: return false
	var kind := str(command.get("build_kind","board"))
	if not kind in ["board","brick","beam"]: return false
	var size := _read_vec(command.get("size",[]),6.0)
	var angles := _read_vec(command.get("rotation",[]),TAU*100)
	if not size.is_finite() or not angles.is_finite(): return false
	if size.x<0.03 or size.y<0.005 or size.z<0.005: return false
	if kind == "brick": size = Vector3(0.25,0.065,0.12)
	angles.y += players[id].rotation.y
	var basis := Basis.from_euler(angles)
	var normal: Vector3 = hit.normal
	var extent := (absf(normal.dot(basis.x))*size.x+absf(normal.dot(basis.y))*size.y+absf(normal.dot(basis.z))*size.z)*0.5
	var point: Vector3 = hit.position+normal*(extent+0.008)
	var part := _id()
	var result := sim.place_part(id,part,"brick" if kind == "brick" else "board",size,point,angles)
	if result:
		attachments[part] = _support_island(hit.collider,hit.position)
		_notify(id,"Деталь установлена. Закрепи её в месте соединения.")
	return result

func _fasten(id: int, part: SkyBuildPart, hit: Dictionary, tool: String) -> bool:
	var item := "nail" if tool == "hammer" else "screw"
	if part.joint_count>=32 or sim.count_item(id,item)<1:
		_notify(id,"Нужен крепёж: %s" % item)
		return false
	for joint in sim.fasteners.values():
		if int(joint.a)==part.part_id and Vector3(joint.position).distance_to(hit.position)<0.025:
			_notify(id,"Выбери новое место для крепления")
			return false
	var local_normal := part.global_basis.inverse() * Vector3(hit.normal)
	var axis: int = local_normal.abs().max_axis_index()
	var thickness: float = part.size[axis]
	var query := PhysicsRayQueryParameters3D.create(hit.position+hit.normal*0.015,hit.position-hit.normal*(thickness+0.06))
	query.exclude = [players[id].get_rid(),part.get_rid()]
	var support := get_world_3d().direct_space_state.intersect_ray(query)
	if support.is_empty():
		_notify(id,"За доской должна находиться опора вплотную к ней")
		return false
	var body: Object = support.collider
	if not (body.has_meta("part_id") or body.has_meta("island") or body.has_meta("anchor")): return false
	var other: int = int(body.get_meta("part_id",0))
	var work_key := "%d:%d:%s" % [id,part.part_id,item]
	pending_work[work_key] = int(pending_work.get(work_key,0))+1
	if int(pending_work[work_key])<3:
		_notify(id,"Крепление: %d / 3" % pending_work[work_key])
		return true
	pending_work.erase(work_key)
	var result := sim.fasten(id,_id(),part.part_id,other,item,hit.position)
	if result: _notify(id,"Гвоздь забит" if item == "nail" else "Саморез закручен")
	return result

func _remove(id: int) -> bool:
	var hit := _trace(id)
	if hit.is_empty() or not hit.collider.has_meta("part_id"): return false
	var part := int(hit.collider.get_meta("part_id"))
	for key in sim.fasteners:
		if int(sim.fasteners[key].a)==part and int(sim.fasteners[key].owner)==id:
			var result := sim.remove_fastener(id,key)
			if result: _notify(id,"Крепёж снят и возвращён в инвентарь")
			return result
	var result := sim.remove_part(id,part)
	if result: _notify(id,"Деталь разобрана, материал возвращён")
	return result

func _sell(id: int, command: Dictionary) -> bool:
	var item := str(command.get("item",""))
	if not item in ITEMS: return false
	var quantity := int(command.get("quantity",1))
	var price := int(command.get("price",quantity*2))
	var listing := _id()
	if not sim.list_items(id,listing,item,quantity,price): return false
	if bool(command.get("npc",false)) and price<=quantity*2 and sim.purchase(NPC,listing):
		_notify(id,"Торговец купил товар за %d монет" % price)
	else:
		_notify(id,"Объявление размещено для покупателей")
	return true

func _factory_buy(id: int, kind: String) -> bool:
	if not kind in ["sawmill","brick_kiln","smelter"]: return false
	var hit := _trace(id)
	if hit.is_empty():
		_notify(id,"Выбери место на острове для предприятия")
		return false
	var factory := _id()
	if not sim.buy_factory(id,factory,kind): return false
	factory_positions[factory] = hit.position+Vector3.UP*0.1
	attachments[factory] = _support_island(hit.collider,hit.position)
	_notify(id,"Предприятие установлено. Загрузить сырьё и запустить можно в разделе производства.")
	return true

func _factory_run(id: int, factory: int) -> bool:
	if not sim.factories.has(factory) or int(sim.factories[factory].owner)!=id: return false
	var backup := sim.snapshot()
	var recipe: Dictionary = SkySimulation.RECIPES[sim.factories[factory].kind]
	for item in recipe["in"]:
		var needed := maxi(0,int(recipe["in"][item])-int(sim.factories[factory].stock.get(item,0)))
		if needed>0 and not sim.deposit_factory(id,factory,item,needed):
			var error := sim.last_error
			sim.restore(backup)
			_notify(id,"Не хватает сырья: %s (%s)" % [item,error])
			return false
	if not sim.produce(id,factory,1):
		sim.restore(backup)
		return false
	for item in recipe["out"]:
		if not sim.withdraw_factory(id,factory,item,int(recipe["out"][item])):
			sim.restore(backup)
			return false
	_notify(id,"Продукция получена и добавлена в инвентарь")
	return true

func _house_list(id: int, price: int) -> bool:
	var hit := _trace(id)
	if hit.is_empty() or not hit.collider.has_meta("part_id"):
		_notify(id,"Наведи прицел на свой дом: в продажу войдут соединённые детали")
		return false
	var first := int(hit.collider.get_meta("part_id"))
	if not sim.parts.has(first) or int(sim.parts[first].owner)!=id: return false
	var backup := sim.snapshot()
	var house := int(sim.parts[first].house)
	if house == 0:
		var selected: Array = [first]
		var cursor := 0
		while cursor<selected.size():
			var current: int = selected[cursor]
			for joint in sim.fasteners.values():
				var next: int = int(joint.b) if int(joint.a)==current else int(joint.a) if int(joint.b)==current else 0
				if next>0 and not selected.has(next): selected.append(next)
			cursor += 1
		house = _id()
		if not sim.register_house(id,house,selected): return false
	var result := sim.list_house(id,_id(),house,price)
	if result: _notify(id,"Дом выставлен на продажу вместе со всеми соединёнными деталями")
	else:
		var reason := sim.last_error
		sim.restore(backup)
		sim.last_error = reason
	return result

func _buy_defense(id: int, kind: String) -> bool:
	var prices := {"guard":80,"turret":120,"drone":160}
	if not prices.has(kind) or defense_nodes.size()>=MAX_DEFENSES: return false
	var hit := _trace(id)
	if hit.is_empty():
		_notify(id,"Наведи прицел на любое подходящее место своего острова")
		return false
	var land_id := _support_island(hit.collider,hit.position)
	if int(island_owners.get(land_id,0))!=id:
		_notify(id,"Размещать охрану можно в любом месте своего острова")
		return false
	if not sim.spend_coins(id,int(prices[kind])): return false
	var node := SkyDefense.new()
	add_child(node)
	node.global_position = hit.position
	var defense := _id()
	node.configure(defense,id,kind,self)
	defense_nodes[defense] = node
	attachments[defense] = _support_island(hit.collider,hit.position)
	_notify(id,"Охрана размещена. Боеприпасы расходуются из запаса владельца.")
	return true

func _damage_hit(hit: Dictionary, amount: float, attacker: int) -> void:
	var body: Object = hit.collider
	if body is SkyPlayer:
		damage_player(body.player_id,amount,attacker)
	elif body is SkyBuildPart:
		if body.receive_damage(amount): sim.destroy_part(body.part_id)
		else: sim.parts[body.part_id].health = body.health
	elif body is SkyDefense:
		body.health = maxf(0,body.health-amount)
		if body.health<=0:
			defense_nodes.erase(body.unit_id)
			body.queue_free()
	mark_dirty()

func damage_player(id: int, amount: float, _attacker: int) -> void:
	if not is_authority() or not players.has(id) or not is_finite(amount) or amount<=0: return
	health[id] = maxf(0,float(health.get(id,100.0))-amount)
	if float(health[id])<=0:
		health[id] = 100.0
		var spawn := Vector3(-6,4,4)
		players[id].global_position = spawn
		players[id].velocity = Vector3.ZERO
		if multiplayer.multiplayer_peer is ENetMultiplayerPeer:
			_respawn.rpc(id,spawn)
		_notify(id,"Ты побеждён. Возрождение на стартовом острове.")
	mark_dirty()

@rpc("authority","call_remote","reliable")
func _respawn(id: int, point: Vector3) -> void:
	if players.has(id):
		players[id].global_position = point
		players[id].velocity = Vector3.ZERO

func _notify(id: int, message: String) -> void:
	if local_player != null and id == local_player.player_id: notice = message
	elif multiplayer.multiplayer_peer is ENetMultiplayerPeer: _notice_remote.rpc_id(id,message)

@rpc("authority","call_remote","reliable")
func _notice_remote(message: String) -> void:
	notice = message

func _sync_world() -> void:
	for id in resource_nodes:
		if sim.deposits.has(id): resource_nodes[id].set_remaining(int(sim.deposits[id].remaining))
	for id in part_nodes.keys():
		if not sim.parts.has(id):
			part_nodes[id].queue_free()
			part_nodes.erase(id)
	for id in sim.parts:
		if not part_nodes.has(id):
			var node := SkyBuildPart.new()
			add_child(node)
			part_nodes[id] = node
		var node: SkyBuildPart = part_nodes[id]
		node.configure(id,sim.parts[id])
		node.health = float(sim.parts[id].health)
		node.update_joints(sim.fasteners)
	for id in factory_nodes.keys():
		if not sim.factories.has(id):
			factory_nodes[id].queue_free()
			factory_nodes.erase(id)
	for id in sim.factories:
		if not factory_nodes.has(id):
			var root := _box(self,Vector3(1.6,0.9,1.0),factory_positions.get(id,Vector3(8,1,4)),"brick")
			var label := Label3D.new()
			label.position.y = 1.0
			label.font_size = 36
			label.pixel_size = 0.004
			root.add_child(label)
			factory_nodes[id] = root
		var factory_node: Node3D = factory_nodes[id]
		factory_node.global_position = factory_positions.get(id,Vector3(8,1,4))
		for child in factory_node.get_children():
			if child is Label3D:
				child.text = {"sawmill":"Лесопилка","brick_kiln":"Кирпичная печь","smelter":"Плавильня"}.get(sim.factories[id].kind,"")
	for id in factory_positions.keys():
		if not sim.factories.has(id): factory_positions.erase(id)
	for id in attachments.keys():
		if (not sim.parts.has(id) and not sim.factories.has(id) and not defense_nodes.has(id)) or not islands.has(attachments[id]):
			attachments.erase(id)

func host_game() -> String:
	if multiplayer.multiplayer_peer is ENetMultiplayerPeer: return "Сеть уже запущена"
	var peer := ENetMultiplayerPeer.new()
	var error := peer.create_server(PORT,8)
	if error != OK: return "Не удалось открыть порт %d (%d)" % [PORT,error]
	multiplayer.multiplayer_peer = peer
	network_mode = "Общая карта • Хост :%d" % PORT
	return network_mode

func join_game(address: String) -> String:
	address = address.strip_edges()
	if address.is_empty() or address.length()>200: return "Укажи адрес хоста"
	if multiplayer.multiplayer_peer is ENetMultiplayerPeer: return "Сеть уже запущена"
	var peer := ENetMultiplayerPeer.new()
	var error := peer.create_client(address,PORT)
	if error != OK: return "Не удалось подключиться (%d)" % error
	multiplayer.multiplayer_peer = peer
	network_mode = "Подключение…"
	return network_mode

func _connected() -> void:
	for player in players.values(): player.queue_free()
	players.clear()
	local_player = null
	_ready_client.rpc_id(1)
	network_mode = "Общая карта • Подключено"

@rpc("any_peer","call_remote","reliable")
func _ready_client() -> void:
	if not is_authority(): return
	var id := multiplayer.get_remote_sender_id()
	if id<=1 or id==NPC or players.size()>=8: return
	_ensure_player(id,false)
	_broadcast_state()

func _peer_connected(_id_value: int) -> void:
	pass # Client explicitly requests the initial state after its scene is ready.

func _peer_disconnected(id: int) -> void:
	if players.has(id):
		if local_player == players[id]: local_player = null
		players[id].queue_free()
		players.erase(id)
	health.erase(id)
	pose_times.erase(id)
	pose_credit.erase(id)
	last_command.erase(id)
	for key in pending_work.keys():
		if str(key).begins_with(str(id)+":"): pending_work.erase(key)
	if pilot_player == id:
		pilot_island = 0
		pilot_player = 0
	if is_authority(): _broadcast_state()

func _connection_failed() -> void:
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	network_mode = "Не удалось подключиться"
	if local_player == null: _ensure_player(1,true)

func _server_lost() -> void:
	network_mode = "Соединение с хостом потеряно"
	# Do not become an authority over a cached remote world or overwrite its local save.
	save_allowed = false
	if local_player != null: local_player.set_input_blocked(true)

func send_player_pose(id: int, point: Vector3, yaw: float, pitch_value: float) -> void:
	if not point.is_finite() or not is_finite(yaw) or not is_finite(pitch_value): return
	if multiplayer.multiplayer_peer.get_connection_status()!=MultiplayerPeer.CONNECTION_CONNECTED: return
	if is_authority():
		if multiplayer.multiplayer_peer is ENetMultiplayerPeer: _relay_pose.rpc(id,point,yaw,pitch_value)
	else:
		_submit_pose.rpc_id(1,point,yaw,pitch_value)

@rpc("any_peer","call_remote","unreliable_ordered",1)
func _submit_pose(point: Vector3, yaw: float, pitch_value: float) -> void:
	if not is_authority() or not point.is_finite() or point.abs().max_axis_index()<0 or point.length()>10000 or not is_finite(yaw) or not is_finite(pitch_value): return
	var id := multiplayer.get_remote_sender_id()
	if not players.has(id): return
	var now := Time.get_ticks_msec()
	var elapsed := clampf(float(now-int(pose_times.get(id,now-100)))/1000.0,0.0,0.5)
	pose_times[id] = now
	var allowed := minf(8.0,float(pose_credit.get(id,0.5))+25.0*elapsed)
	pose_credit[id] = allowed
	var distance: float = players[id].global_position.distance_to(point)
	if distance>allowed:
		_respawn.rpc_id(id,id,players[id].global_position)
		return
	pose_credit[id] = allowed-distance
	players[id].global_position = point
	players[id].rotation.y = wrapf(yaw,-PI,PI)
	players[id].camera.rotation.x = clampf(pitch_value,-1.5,1.5)
	_relay_pose.rpc(id,point,yaw,pitch_value)

@rpc("authority","call_remote","unreliable_ordered",1)
func _relay_pose(id: int, point: Vector3, yaw: float, pitch_value: float) -> void:
	if local_player != null and id==local_player.player_id: return
	if players.has(id) and point.is_finite() and is_finite(yaw) and is_finite(pitch_value):
		players[id].global_position = point
		players[id].rotation.y = yaw
		players[id].camera.rotation.x = pitch_value

func _world_state() -> Dictionary:
	var land: Array = []
	for id in islands:
		var island: SkyIsland = islands[id]
		land.append({"id":id,"seed":island.seed,"radius":island.radius,"position":_vec(island.position),"owner":island_owners.get(id,0),"stamps":island.get_stamps()})
	var defenses: Array = []
	for id in defense_nodes:
		var node: SkyDefense = defense_nodes[id]
		defenses.append({"id":id,"owner":node.owner_id,"kind":node.kind,"health":node.health,"position":_vec(node.global_position),"origin":_vec(node.origin),"rotation":_vec(node.global_rotation),"aim":_vec(node.head.rotation),"clock":node.clock,"cooldown":maxf(0.0,node.cooldown)})
	var factories: Dictionary = {}
	for id in sim.factories: factories[str(id)] = _vec(factory_positions.get(id,Vector3(8,1,4)))
	var hp: Dictionary = {}
	var active: Array = []
	for id in players:
		if not sim.players.has(id) or bool(sim.players[id].npc): continue
		active.append(id)
		hp[str(id)] = health.get(id,100.0)
	var links: Dictionary = {}
	for id in attachments:
		if (sim.parts.has(id) or sim.factories.has(id) or defense_nodes.has(id)) and islands.has(attachments[id]): links[str(id)] = attachments[id]
	return {"schema":2,"next_id":next_id,"core":sim.snapshot(),"islands":land,"defenses":defenses,"factory_positions":factories,"health":hp,"peers":active,"attachments":links}

func _vec(value: Vector3) -> Array:
	return [value.x,value.y,value.z]

func _broadcast_state() -> void:
	dirty = false
	if multiplayer.multiplayer_peer is ENetMultiplayerPeer and is_authority(): _receive_state.rpc(_world_state())

@rpc("authority","call_remote","reliable")
func _receive_state(data: Dictionary) -> void:
	if is_authority(): return
	if not _apply_state(data,true):
		notice = "Получено некорректное состояние мира"

func _apply_state(data: Dictionary, network: bool = false) -> bool:
	if data.get("schema")!=2 or not data.get("core") is Dictionary or not data.get("islands") is Array or not data.get("defenses") is Array: return false
	var candidate := SkySimulation.new()
	if not candidate.restore(data.core): return false
	var raw_next: Variant = data.get("next_id",0)
	if not _whole(raw_next,10000,1000000000): return false
	var highest := 9999
	for table in [candidate.deposits,candidate.parts,candidate.fasteners,candidate.listings,candidate.houses,candidate.factories]:
		for id in table: highest = maxi(highest,int(id))
	if int(raw_next)<=highest or candidate.parts.size()>MAX_PARTS or data.islands.size()>12 or data.islands.size()<4 or data.defenses.size()>MAX_DEFENSES: return false
	var raw_peers: Variant = data.get("peers",[])
	if not raw_peers is Array or raw_peers.size()>8: return false
	var active: Array[int] = []
	for raw_id in raw_peers:
		if not _whole(raw_id,1,SkySimulation.MAX_ID): return false
		var id := int(raw_id)
		if active.has(id) or not candidate.players.has(id) or bool(candidate.players[id].npc): return false
		active.append(id)
	var island_ids: Dictionary = {}
	for entry in data.islands:
		if not entry is Dictionary or not _whole(entry.get("id"),1,12) or island_ids.has(int(entry.id)): return false
		island_ids[int(entry.id)] = true
		if not _whole(entry.get("seed"),0,1000000) or not _whole(entry.get("owner"),0,SkySimulation.MAX_ID): return false
		if int(entry.owner)!=0 and not candidate.players.has(int(entry.owner)): return false
		if not _number(entry.get("radius")) or float(entry.radius)<5.0 or float(entry.radius)>40.0: return false
		if not _read_vec(entry.get("position",[]),10000).is_finite() or not entry.get("stamps") is Array or entry.stamps.size()>128: return false
		var validator := SkyIsland.new()
		validator.radius = float(entry.radius)
		for stamp in entry.stamps:
			if not stamp is Dictionary or not _number(stamp.get("radius")): validator.free(); return false
			var center := _read_vec(stamp.get("center",[]),100)
			if not validator._valid_stamp(center,float(stamp.radius)): validator.free(); return false
		validator.free()
	for id in [1,2,3,4]:
		if not island_ids.has(id): return false
	var defense_ids: Dictionary = {}
	for entry in data.defenses:
		if not entry is Dictionary or not _whole(entry.get("id"),10000,int(raw_next)-1) or defense_ids.has(int(entry.id)): return false
		var id := int(entry.id)
		for table in [candidate.deposits,candidate.parts,candidate.fasteners,candidate.listings,candidate.houses,candidate.factories]:
			if table.has(id): return false
		defense_ids[id] = true
		if not _whole(entry.get("owner"),1,SkySimulation.MAX_ID) or not candidate.players.has(int(entry.owner)) or not entry.get("kind") in ["guard","turret","drone"]: return false
		if not _number(entry.get("health")) or float(entry.health)<=0 or float(entry.health)>100 or not _read_vec(entry.get("position",[]),10000).is_finite(): return false
		if entry.has("origin") and not _read_vec(entry.origin,10000).is_finite(): return false
		for field in ["rotation","aim"]:
			if entry.has(field) and not _read_vec(entry[field],TAU*100.0).is_finite(): return false
		if not _number(entry.get("clock",0.0)) or float(entry.get("clock",0.0))<0.0 or float(entry.get("clock",0.0))>1000000000.0: return false
		if not _number(entry.get("cooldown",0.0)) or float(entry.get("cooldown",0.0))<0.0 or float(entry.get("cooldown",0.0))>60.0: return false
	var factory_data: Variant = data.get("factory_positions",{})
	if not factory_data is Dictionary or factory_data.size()>100: return false
	for key in factory_data:
		if not key is String or key.length()>10 or not key.is_valid_int(): return false
		var id := int(key)
		if str(id)!=key or not candidate.factories.has(id) or not _read_vec(factory_data[key],10000).is_finite(): return false
	var hp: Variant = data.get("health",{})
	if not hp is Dictionary or hp.size()>100: return false
	for key in hp:
		if not key is String or key.length()>10 or not key.is_valid_int(): return false
		var id := int(key)
		if str(id)!=key or not candidate.players.has(id) or not _number(hp[key]) or float(hp[key])<0 or float(hp[key])>100: return false
	var raw_links: Variant = data.get("attachments",{})
	if not raw_links is Dictionary or raw_links.size()>1000: return false
	var links: Dictionary = {}
	for key in raw_links:
		if not key is String or key.length()>10 or not key.is_valid_int(): return false
		var id := int(key)
		if str(id)!=key or not (candidate.parts.has(id) or candidate.factories.has(id) or defense_ids.has(id)): return false
		if not _whole(raw_links[key],1,12) or not island_ids.has(int(raw_links[key])): return false
		links[id] = int(raw_links[key])
	# Every fallible payload check is complete before replacing any live state.
	loading = true
	sim = candidate
	next_id = int(raw_next)
	attachments = links
	for id in islands.keys():
		if not island_ids.has(id):
			islands[id].queue_free()
			islands.erase(id)
			island_owners.erase(id)
	for entry in data.islands:
		var id := int(entry.id)
		if not islands.has(id): _create_island(id,int(entry.seed),float(entry.radius),_read_vec(entry.position),int(entry.owner))
		var island: SkyIsland = islands[id]
		if island.seed!=int(entry.seed) or not is_equal_approx(island.radius,float(entry.radius)): island.configure(int(entry.seed),float(entry.radius))
		island.position = _read_vec(entry.position)
		island_owners[id] = int(entry.owner)
		if island.get_stamps()!=entry.stamps: island.restore_stamps(entry.stamps)
	for id in defense_nodes.keys():
		if not defense_ids.has(id):
			defense_nodes[id].free()
			defense_nodes.erase(id)
	for entry in data.defenses:
		var id := int(entry.id)
		if defense_nodes.has(id) and (defense_nodes[id].owner_id!=int(entry.owner) or defense_nodes[id].kind!=str(entry.kind)):
			defense_nodes[id].free()
			defense_nodes.erase(id)
		if not defense_nodes.has(id):
			var created := SkyDefense.new()
			add_child(created)
			created.global_position = _read_vec(entry.position)
			created.configure(id,int(entry.owner),str(entry.kind),self)
			defense_nodes[id] = created
		var node: SkyDefense = defense_nodes[id]
		node.global_position = _read_vec(entry.position)
		node.origin = _read_vec(entry.get("origin",entry.position))
		node.global_rotation = _read_vec(entry.get("rotation",[0.0,0.0,0.0]),TAU*100.0)
		node.head.rotation = _read_vec(entry.get("aim",[0.0,0.0,0.0]),TAU*100.0)
		node.clock = float(entry.get("clock",0.0))
		node.cooldown = float(entry.get("cooldown",0.0))
		node.health = float(entry.health)
	factory_positions.clear()
	for key in factory_data: factory_positions[int(key)] = _read_vec(factory_data[key])
	health.clear()
	for id in active: health[id] = float(hp.get(str(id),100.0))
	if network:
		var own := multiplayer.get_unique_id()
		for id in players.keys():
			if not active.has(id):
				if local_player == players[id]: local_player = null
				players[id].queue_free()
				players.erase(id)
		for id in active: _ensure_player(id,id==own)
	loading = false
	_sync_world()
	return true

func _save_world(destination: String = SAVE_PATH) -> bool:
	if not is_authority() or not save_allowed or loading: return false
	var payload := JSON.stringify(_world_state())
	var temporary := destination+".tmp"
	var file := FileAccess.open(temporary,FileAccess.WRITE)
	if file==null: return false
	file.store_string(payload)
	file.flush()
	file.close()
	if FileAccess.file_exists(destination):
		var backup_error := DirAccess.copy_absolute(destination,destination+".bak")
		if backup_error!=OK: return false
	var error := DirAccess.rename_absolute(temporary,destination)
	if error!=OK: return false
	notice = "Мир сохранён"
	return true

func _load_world(source: String = SAVE_PATH) -> bool:
	if not FileAccess.file_exists(source): return true
	save_allowed = false
	var file := FileAccess.open(source,FileAccess.READ)
	if file==null or file.get_length()>24*1024*1024: return false
	var decoded: Variant = JSON.parse_string(file.get_as_text())
	if not decoded is Dictionary or not _apply_state(decoded):
		notice = "Сохранение не прочитано. Исходный файл сохранён, автозапись отключена."
		return false
	save_allowed = true
	return true

func _number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value))

func _whole(value: Variant, low: int, high: int) -> bool:
	return _number(value) and float(value)>=low and float(value)<=high and floor(float(value))==float(value)

func _house_release(id: int) -> bool:
	var hit := _trace(id)
	if hit.is_empty() or not hit.collider.has_meta("part_id"): return false
	var part := int(hit.collider.get_meta("part_id"))
	if not sim.parts.has(part) or int(sim.parts[part].owner)!=id: return false
	var house := int(sim.parts[part].house)
	if house==0: return false
	var listing := int(sim.houses[house].listing)
	if listing>0 and not sim.cancel_listing(id,listing): return false
	var result := sim.unregister_house(id,house)
	if result: _notify(id,"Дом снят с продажи. Детали снова доступны для перестройки.")
	return result

func _support_island(body: Object, point: Vector3) -> int:
	if body.has_meta("island"):
		var land: SkyIsland = body.get_meta("island")
		for island_id in islands:
			if islands[island_id]==land: return int(island_id)
	if body.has_meta("part_id"): return int(attachments.get(int(body.get_meta("part_id")),0))
	var current: Node = body as Node
	while current!=null:
		for island_id in islands:
			if current==islands[island_id]: return int(island_id)
		current = current.get_parent()
	return _island_at(point)

func _island_at(point: Vector3) -> int:
	var best: int = 0
	var distance: float = INF
	for island_id in islands:
		var island: SkyIsland = islands[island_id]
		var local := island.to_local(point)
		if Vector2(local.x,local.z).length()>island.radius: continue
		var gap := absf(local.y-island.top_height(local.x,local.z))
		if gap<5.0 and gap<distance:
			distance = gap
			best = int(island_id)
	return best

func _interact(id: int) -> bool:
	if pilot_island>0:
		if pilot_player!=id: return false
		pilot_island = 0
		pilot_player = 0
		_notify(id,"Управление островом завершено")
		return true
	var hit := _trace(id)
	if hit.is_empty(): return false
	if hit.collider.has_meta("helm"):
		var island_id := int(hit.collider.get_meta("helm"))
		# The initial mobile base belongs to the host; remote piloting is a later control channel.
		if id!=1 or int(island_owners.get(island_id,0))!=id: return false
		pilot_island = island_id
		pilot_player = id
		_notify(id,"Управление островом: WASD, Пробел — выше, Ctrl — ниже. E — выйти.")
		return true
	return false

func _move_pilot(delta: float) -> void:
	if local_player==null or pilot_player!=local_player.player_id or not islands.has(pilot_island): return
	var input: Vector2 = local_player.get_move_input()
	var move := Basis(Vector3.UP,local_player.rotation.y)*Vector3(input.x,0,input.y)
	move.y = (1.0 if Input.is_action_pressed("jump") or local_player.ascend_held else 0.0)-(1.0 if Input.is_physical_key_pressed(KEY_CTRL) or local_player.descend_held else 0.0)
	var shift := move.limit_length()*4.0*delta
	if shift.is_zero_approx(): return
	var island: SkyIsland = islands[pilot_island]
	if (island.position+shift).length()>2000: return
	var passengers: Array = []
	for id in players:
		if id==pilot_player or _island_at(players[id].global_position)==pilot_island: passengers.append(id)
	island.position += shift
	for id in passengers:
		players[id].global_position += shift
		players[id].velocity = Vector3.ZERO
		if int(id)!=1 and multiplayer.multiplayer_peer is ENetMultiplayerPeer:
			_respawn.rpc_id(int(id),int(id),players[id].global_position)
	for id in attachments:
		if int(attachments[id])!=pilot_island: continue
		if sim.parts.has(id): sim.parts[id].position += shift
		if factory_positions.has(id): factory_positions[id] += shift
		if defense_nodes.has(id):
			defense_nodes[id].origin += shift
			defense_nodes[id].global_position += shift
	for joint in sim.fasteners.values():
		if int(attachments.get(int(joint.a),0))==pilot_island: joint.position += shift
	_sync_world()
	mark_dirty()

func _valid_command(command: Dictionary) -> bool:
	var action: Variant = command.get("action")
	if not action is String or action.length()>32: return false
	var allowed := ["action","tool","build_kind","size","rotation","listing","factory","price","item","quantity","npc","kind"]
	for key in command:
		if not key is String or not key in allowed: return false
	for key in ["tool","build_kind","item","kind"]:
		if command.has(key) and (not command[key] is String or command[key].length()>32): return false
	for key in ["listing","factory"]:
		if command.has(key) and not _whole(command[key],1,SkySimulation.MAX_ID): return false
	if action in ["trade_buy","house_buy","trade_cancel"] and not command.has("listing"): return false
	if action=="factory_run" and not command.has("factory"): return false
	if command.has("price") and not _whole(command.price,1,SkySimulation.MAX_COINS): return false
	if command.has("quantity") and not _whole(command.quantity,1,SkySimulation.MAX_QUANTITY): return false
	if command.has("npc") and not command.npc is bool: return false
	return true

func _notification(what: int) -> void:
	if what in [NOTIFICATION_WM_CLOSE_REQUEST,NOTIFICATION_APPLICATION_PAUSED] and is_inside_tree() and not testing:
		_save_world()
