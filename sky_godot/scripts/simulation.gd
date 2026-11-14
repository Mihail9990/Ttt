class_name SkySimulation
extends RefCounted
## Deterministic server-owned rules. The scene validates reach, contact and RPC identity.
## All dimensions and positions are metres. No client can call grant/restore directly.
const ITEMS: Array[String] = ["soil", "clay", "sand", "stone", "timber", "board", "brick", "ore", "metal", "nail", "screw", "fuel", "ammo"]
const MAX_ID: int = 2147483647
const MAX_QUANTITY: int = 1000000000
const MAX_COINS: int = 9000000000000
const MAX_RECORDS: int = 20000
const RECORD_FIELDS: Dictionary = {
	"players": ["coins", "npc", "inventory"],
	"deposits": ["item", "remaining"],
	"parts": ["owner", "material", "size", "position", "rotation", "units", "house", "health"],
	"fasteners": ["owner", "a", "b", "item", "position"],
	"listings": ["seller", "kind", "item", "quantity", "price", "house", "closed"],
	"houses": ["owner", "parts", "listing"],
	"factories": ["owner", "kind", "stock"]
}
const FACTORY_PRICES: Dictionary = {"sawmill": 120, "brick_kiln": 160, "smelter": 200}
const RECIPES: Dictionary = {
	"sawmill": {"in": {"timber": 1}, "out": {"board": 4}},
	"brick_kiln": {"in": {"clay": 2, "sand": 1, "fuel": 1}, "out": {"brick": 4}},
	"smelter": {"in": {"ore": 2, "fuel": 1}, "out": {"metal": 1}}
}
var players: Dictionary = {}
var deposits: Dictionary = {}
var parts: Dictionary = {}
var fasteners: Dictionary = {}
var listings: Dictionary = {}
var houses: Dictionary = {}
var factories: Dictionary = {}
var last_error: String = ""

func _fail(message: String) -> bool:
	last_error = message
	return false

func _ok() -> bool:
	last_error = ""
	return true

func _room() -> bool:
	return players.size() + deposits.size() + parts.size() + fasteners.size() + listings.size() + houses.size() + factories.size() < MAX_RECORDS

func _valid_id(value: Variant) -> bool:
	return _whole(value, 1, MAX_ID)

func _whole(value: Variant, low: int, high: int) -> bool:
	if not (value is int or value is float):
		return false
	var number: float = float(value)
	return is_finite(number) and number >= low and number <= high and floor(number) == number

func _amount(value: int) -> bool:
	return value > 0 and value <= MAX_QUANTITY

func _finite_vector(value: Vector3) -> bool:
	return value.is_finite() and value.abs().max_axis_index() >= 0 and value.abs()[value.abs().max_axis_index()] <= 100000.0

func _valid_size(value: Vector3) -> bool:
	return value.is_finite() and value.x >= 0.005 and value.y >= 0.005 and value.z >= 0.005 and value.x <= 20.0 and value.y <= 20.0 and value.z <= 20.0

func _inventory_valid(inventory: Variant) -> bool:
	if not inventory is Dictionary or inventory.size() > ITEMS.size():
		return false
	for key: Variant in inventory:
		if not key is String or not key in ITEMS or not _whole(inventory[key], 0, MAX_QUANTITY):
			return false
	return true

func count_item(player: int, item: String) -> int:
	if not players.has(player):
		return 0
	return int(players[player].inventory.get(item, 0))

func balance(player: int) -> int:
	return int(players[player].coins) if players.has(player) else 0

func add_player(player: int, coins: int, npc: bool = false) -> bool:
	if not _room() or not _valid_id(player) or players.has(player) or coins < 0 or coins > MAX_COINS:
		return _fail("Invalid or duplicate player")
	players[player] = {"coins": coins, "npc": npc, "inventory": {}}
	return _ok()

func grant(player: int, item: String, quantity: int) -> bool:
	if not players.has(player) or not item in ITEMS or not _amount(quantity) or count_item(player, item) > MAX_QUANTITY - quantity:
		return _fail("Invalid grant or inventory capacity")
	players[player].inventory[item] = count_item(player, item) + quantity
	return _ok()

func consume(player: int, item: String, quantity: int) -> bool:
	if not players.has(player) or not item in ITEMS or not _amount(quantity) or count_item(player, item) < quantity:
		return _fail("Not enough inventory to consume")
	players[player].inventory[item] = count_item(player, item) - quantity
	return _ok()

func spend_coins(player: int, amount: int) -> bool:
	if not players.has(player) or amount <= 0 or amount > MAX_COINS or balance(player) < amount:
		return _fail("Not enough coins")
	players[player].coins = balance(player) - amount
	return _ok()

func seed_deposit(deposit: int, item: String, quantity: int) -> bool:
	if not _room() or not _valid_id(deposit) or deposits.has(deposit) or not item in ["soil", "clay", "sand", "stone", "timber", "ore"] or not _amount(quantity):
		return _fail("Invalid deposit")
	deposits[deposit] = {"item": item, "remaining": quantity}
	return _ok()

func harvest(player: int, deposit: int, tool: String, quantity: int = 1) -> bool:
	if not players.has(player) or not deposits.has(deposit) or not _amount(quantity):
		return _fail("Unknown deposit or player")
	var d: Dictionary = deposits[deposit]
	var required: String = "axe" if d.item == "timber" else "pickaxe" if d.item in ["stone", "ore"] else "shovel"
	if tool != required or int(d.remaining) < quantity or count_item(player, d.item) > MAX_QUANTITY - quantity:
		return _fail("Wrong tool, exhausted deposit or inventory full")
	players[player].inventory[d.item] = count_item(player, d.item) + quantity
	d.remaining = int(d.remaining) - quantity
	return _ok()

func material_cost(material: String, size: Vector3) -> int:
	if not _valid_size(size):
		return 0
	var volumes: Dictionary = {"board": 0.012, "brick": 0.00195, "stone": 0.01, "metal": 0.001}
	if not volumes.has(material):
		return 0
	var cost: int = maxi(1, int(ceil(size.x * size.y * size.z / float(volumes[material]) - 0.00001)))
	return cost if cost <= MAX_QUANTITY else 0

func place_part(player: int, part: int, material: String, size: Vector3, position: Vector3, rotation: Vector3 = Vector3.ZERO) -> bool:
	var units: int = material_cost(material, size)
	if not _room() or not players.has(player) or not _valid_id(part) or parts.has(part) or units == 0 or not _finite_vector(position) or not _finite_vector(rotation):
		return _fail("Invalid part geometry")
	if count_item(player, material) < units:
		return _fail("Not enough building material")
	players[player].inventory[material] = count_item(player, material) - units
	parts[part] = {"owner": player, "material": material, "size": size, "position": position, "rotation": rotation, "units": units, "house": 0, "health": 100.0}
	return _ok()

func _house_locked(house: int) -> bool:
	return house != 0 and houses.has(house) and int(houses[house].listing) != 0

func _connected(part: int) -> bool:
	for joint: Dictionary in fasteners.values():
		if int(joint.a) == part or int(joint.b) == part:
			return true
	return false

func move_part(player: int, part: int, position: Vector3, rotation: Vector3 = Vector3.ZERO) -> bool:
	if not parts.has(part) or parts[part].owner != player or not _finite_vector(position) or not _finite_vector(rotation):
		return _fail("Invalid move or ownership")
	if parts[part].house != 0 or _connected(part):
		return _fail("Remove connectors before moving")
	parts[part].position = position
	parts[part].rotation = rotation
	return _ok()

func remove_part(player: int, part: int) -> bool:
	if not players.has(player) or not parts.has(part) or parts[part].owner != player:
		return _fail("Not the part owner")
	var p: Dictionary = parts[part]
	if p.house != 0 or _connected(part) or count_item(player, p.material) > MAX_QUANTITY - int(p.units):
		return _fail("Part is connected or inventory full")
	players[player].inventory[p.material] = count_item(player, p.material) + int(p.units)
	parts.erase(part)
	return _ok()

func fasten(player: int, joint: int, part_a: int, part_b: int, item: String, position: Vector3) -> bool:
	if not _room() or not players.has(player) or not _valid_id(joint) or fasteners.has(joint) or not parts.has(part_a) or (part_b != 0 and not parts.has(part_b)):
		return _fail("Unknown or duplicate joint")
	if part_a == part_b or not item in ["nail", "screw"] or not _finite_vector(position):
		return _fail("Invalid joint")
	if parts[part_a].owner != player or (part_b != 0 and parts[part_b].owner != player):
		return _fail("Not the joint owner")
	if (part_b != 0 and parts[part_a].house != parts[part_b].house) or _house_locked(parts[part_a].house):
		return _fail("Assembly is locked")
	if count_item(player, item) < 1:
		return _fail("No fasteners in inventory")
	players[player].inventory[item] = count_item(player, item) - 1
	fasteners[joint] = {"owner": player, "a": part_a, "b": part_b, "item": item, "position": position}
	return _ok()

func remove_fastener(player: int, joint: int) -> bool:
	if not fasteners.has(joint) or not players.has(player) or fasteners[joint].owner != player:
		return _fail("Not the fastener owner")
	var f: Dictionary = fasteners[joint]
	if _house_locked(parts[f.a].house) or count_item(player, f.item) == MAX_QUANTITY:
		return _fail("Assembly is locked or inventory full")
	players[player].inventory[f.item] = count_item(player, f.item) + 1
	fasteners.erase(joint)
	return _ok()

func destroy_part(part: int) -> bool:
	if not parts.has(part):
		return _fail("Unknown destroyed part")
	var house: int = int(parts[part].house)
	for key: Variant in fasteners.keys():
		var f: Dictionary = fasteners[key]
		if int(f.a) == part or int(f.b) == part:
			fasteners.erase(key)
	if house != 0 and houses.has(house):
		var h: Dictionary = houses[house]
		if int(h.listing) != 0:
			listings[h.listing].closed = true
			h.listing = 0
		h.parts.erase(part)
		if h.parts.is_empty():
			houses.erase(house)
	parts.erase(part)
	return _ok()

func register_house(player: int, house: int, part_ids: Array) -> bool:
	if not _room() or not players.has(player) or not _valid_id(house) or houses.has(house) or part_ids.is_empty() or part_ids.size() > 1024:
		return _fail("Invalid house")
	var seen: Dictionary = {}
	for key: Variant in part_ids:
		if not _valid_id(key) or seen.has(int(key)) or not parts.has(int(key)) or parts[int(key)].owner != player or parts[int(key)].house != 0:
			return _fail("Invalid house parts or ownership")
		seen[int(key)] = true
	for f: Dictionary in fasteners.values():
		if int(f.b) != 0 and seen.has(int(f.a)) != seen.has(int(f.b)):
			return _fail("A connector links outside the house")
	houses[house] = {"owner": player, "parts": seen.keys(), "listing": 0}
	for key: int in part_ids:
		parts[key].house = house
	return _ok()

func unregister_house(player: int, house: int) -> bool:
	if not houses.has(house) or houses[house].owner != player or _house_locked(house):
		return _fail("House is locked or not owned")
	for key: int in houses[house].parts:
		parts[key].house = 0
	houses.erase(house)
	return _ok()

func list_items(seller: int, listing: int, item: String, quantity: int, price: int) -> bool:
	if not _room() or not players.has(seller) or not _valid_id(listing) or listings.has(listing) or not item in ITEMS or not _amount(quantity) or price <= 0 or price > MAX_COINS:
		return _fail("Invalid listing")
	if count_item(seller, item) < quantity:
		return _fail("Not enough goods")
	players[seller].inventory[item] = count_item(seller, item) - quantity
	listings[listing] = {"seller": seller, "kind": "items", "item": item, "quantity": quantity, "price": price, "house": 0, "closed": false}
	return _ok()

func list_house(seller: int, listing: int, house: int, price: int) -> bool:
	if not _room() or not players.has(seller) or not _valid_id(listing) or listings.has(listing) or not houses.has(house) or houses[house].owner != seller or _house_locked(house) or price <= 0 or price > MAX_COINS:
		return _fail("Invalid house listing")
	listings[listing] = {"seller": seller, "kind": "house", "item": "soil", "quantity": 0, "price": price, "house": house, "closed": false}
	houses[house].listing = listing
	return _ok()

func _give_house(house: int, owner: int) -> void:
	houses[house].owner = owner
	houses[house].listing = 0
	for part: int in houses[house].parts:
		parts[part].owner = owner
	for f: Dictionary in fasteners.values():
		if parts[f.a].house == house:
			f.owner = owner

func purchase(buyer: int, listing: int) -> bool:
	if not players.has(buyer) or not listings.has(listing):
		return _fail("Unknown buyer or listing")
	var offer: Dictionary = listings[listing]
	var seller: int = int(offer.seller)
	var price: int = int(offer.price)
	if offer.closed or seller == buyer or balance(buyer) < price or balance(seller) > MAX_COINS - price:
		return _fail("Closed listing, self trade or insufficient balance")
	if offer.kind == "items":
		if count_item(buyer, offer.item) > MAX_QUANTITY - int(offer.quantity):
			return _fail("Buyer inventory full")
		players[buyer].inventory[offer.item] = count_item(buyer, offer.item) + int(offer.quantity)
	else:
		if not houses.has(offer.house) or houses[offer.house].owner != seller or int(houses[offer.house].listing) != listing:
			return _fail("House is no longer available")
		_give_house(offer.house, buyer)
	players[buyer].coins = balance(buyer) - price
	players[seller].coins = balance(seller) + price
	offer.closed = true
	return _ok()

func cancel_listing(seller: int, listing: int) -> bool:
	if not listings.has(listing) or listings[listing].seller != seller or listings[listing].closed:
		return _fail("Listing cannot be cancelled")
	var offer: Dictionary = listings[listing]
	if offer.kind == "items":
		if count_item(seller, offer.item) > MAX_QUANTITY - int(offer.quantity):
			return _fail("Inventory full")
		players[seller].inventory[offer.item] = count_item(seller, offer.item) + int(offer.quantity)
	elif houses.has(offer.house):
		houses[offer.house].listing = 0
	offer.closed = true
	return _ok()

func _valid_offer(player: int, offer: Dictionary) -> bool:
	if not players.has(player) or not _inventory_valid(offer.get("items", {})) or not _whole(offer.get("coins", 0), 0, MAX_COINS) or not offer.get("houses", []) is Array:
		return false
	if balance(player) < int(offer.get("coins", 0)) or offer.get("houses", []).size() > 1024:
		return false
	for item: String in offer.get("items", {}):
		if count_item(player, item) < int(offer.items[item]):
			return false
	var seen: Dictionary = {}
	for id: Variant in offer.get("houses", []):
		if not _valid_id(id) or seen.has(int(id)) or not houses.has(int(id)) or houses[int(id)].owner != player or _house_locked(int(id)):
			return false
		seen[int(id)] = true
	return true

func exchange(first: int, first_offer: Dictionary, second: int, second_offer: Dictionary) -> bool:
	if first == second or not _valid_offer(first, first_offer) or not _valid_offer(second, second_offer):
		return _fail("Invalid barter")
	var first_coins: int = balance(first) - int(first_offer.get("coins", 0)) + int(second_offer.get("coins", 0))
	var second_coins: int = balance(second) - int(second_offer.get("coins", 0)) + int(first_offer.get("coins", 0))
	if first_coins > MAX_COINS or second_coins > MAX_COINS:
		return _fail("Barter exceeds currency capacity")
	for item: String in ITEMS:
		var a: int = count_item(first, item) - int(first_offer.get("items", {}).get(item, 0)) + int(second_offer.get("items", {}).get(item, 0))
		var b: int = count_item(second, item) - int(second_offer.get("items", {}).get(item, 0)) + int(first_offer.get("items", {}).get(item, 0))
		if a > MAX_QUANTITY or b > MAX_QUANTITY:
			return _fail("Barter inventory full")
	players[first].coins = first_coins
	players[second].coins = second_coins
	for item: String in ITEMS:
		var out_a: int = int(first_offer.get("items", {}).get(item, 0))
		var out_b: int = int(second_offer.get("items", {}).get(item, 0))
		players[first].inventory[item] = count_item(first, item) - out_a + out_b
		players[second].inventory[item] = count_item(second, item) - out_b + out_a
	for house: int in first_offer.get("houses", []):
		_give_house(house, second)
	for house: int in second_offer.get("houses", []):
		_give_house(house, first)
	return _ok()

func buy_factory(player: int, factory: int, kind: String) -> bool:
	if not _room() or not players.has(player) or not _valid_id(factory) or factories.has(factory) or not FACTORY_PRICES.has(kind):
		return _fail("Invalid factory")
	var price: int = int(FACTORY_PRICES[kind])
	if balance(player) < price:
		return _fail("Not enough coins for factory")
	players[player].coins = balance(player) - price
	factories[factory] = {"owner": player, "kind": kind, "stock": {}}
	return _ok()

func deposit_factory(player: int, factory: int, item: String, quantity: int) -> bool:
	return _transfer_factory(player, factory, item, quantity, true)

func withdraw_factory(player: int, factory: int, item: String, quantity: int) -> bool:
	return _transfer_factory(player, factory, item, quantity, false)

func _transfer_factory(player: int, factory: int, item: String, quantity: int, depositing: bool) -> bool:
	if not players.has(player) or not factories.has(factory) or factories[factory].owner != player or not item in ITEMS or not _amount(quantity):
		return _fail("Invalid factory transfer")
	var stock: Dictionary = factories[factory].stock
	var available: int = count_item(player, item) if depositing else int(stock.get(item, 0))
	var destination: int = int(stock.get(item, 0)) if depositing else count_item(player, item)
	if available < quantity or destination > MAX_QUANTITY - quantity:
		return _fail("Not enough stock or capacity")
	if depositing:
		players[player].inventory[item] = available - quantity
		stock[item] = destination + quantity
	else:
		stock[item] = available - quantity
		players[player].inventory[item] = destination + quantity
	return _ok()

func produce(player: int, factory: int, batches: int = 1) -> bool:
	if not factories.has(factory) or factories[factory].owner != player or not _amount(batches) or batches > 1000000:
		return _fail("Invalid production request")
	var f: Dictionary = factories[factory]
	var recipe: Dictionary = RECIPES[f.kind]
	var stock: Dictionary = f.stock
	for item: String in recipe["in"]:
		if int(stock.get(item, 0)) < int(recipe["in"][item]) * batches:
			return _fail("Factory needs raw materials")
	for item: String in recipe["out"]:
		if int(stock.get(item, 0)) > MAX_QUANTITY - int(recipe["out"][item]) * batches:
			return _fail("Factory output storage full")
	for item: String in recipe["in"]:
		stock[item] = int(stock.get(item, 0)) - int(recipe["in"][item]) * batches
	for item: String in recipe["out"]:
		stock[item] = int(stock.get(item, 0)) + int(recipe["out"][item]) * batches
	return _ok()

func snapshot() -> Dictionary:
	var result: Dictionary = {"version": 1}
	for table: String in ["players", "deposits", "parts", "fasteners", "listings", "houses", "factories"]:
		var values: Dictionary = get(table)
		var records: Array = []
		for id: int in values:
			var record: Dictionary = {"id": id}
			for field: String in RECORD_FIELDS[table]:
				if values[id].has(field):
					var value: Variant = values[id][field]
					record[field] = value.duplicate(true) if value is Array or value is Dictionary else value
			for key: String in ["size", "position", "rotation"]:
				if record.has(key) and record[key] is Vector3:
					var vector: Vector3 = record[key]
					record[key] = [vector.x, vector.y, vector.z]
			records.append(record)
		result[table] = records
	return result

func _load_vector(raw: Variant) -> Variant:
	if not raw is Array or raw.size() != 3:
		return null
	for component: Variant in raw:
		if not (component is int or component is float) or not is_finite(float(component)):
			return null
	var vector: Vector3 = Vector3(float(raw[0]), float(raw[1]), float(raw[2]))
	return vector if _finite_vector(vector) else null

func restore(data: Dictionary) -> bool:
	if not _whole(data.get("version", 0), 1, 1):
		return _fail("Unsupported save version")
	var candidate = get_script().new()
	var total: int = 0
	for table: String in ["players", "deposits", "parts", "fasteners", "listings", "houses", "factories"]:
		var array: Variant = data.get(table)
		if not array is Array:
			return _fail("Missing save table")
		total += array.size()
		if total > MAX_RECORDS:
			return _fail("Save entry budget exceeded")
		var values: Dictionary = candidate.get(table)
		for value: Variant in array:
			if not value is Dictionary or not _valid_id(value.get("id")):
				return _fail("Invalid save record")
			var id: int = int(value.id)
			if values.has(id):
				return _fail("Duplicate save record")
			if value.size() > RECORD_FIELDS[table].size() + 1:
				return _fail("Unknown saved fields")
			var record: Dictionary = {}
			for key: Variant in value:
				if key == "id":
					continue
				if not key is String or not key in RECORD_FIELDS[table]:
					return _fail("Unknown saved field")
				if value[key] is String and value[key].length() > 32:
					return _fail("Saved string too large")
				record[key] = value[key]
			for required_field: String in RECORD_FIELDS[table]:
				if not record.has(required_field):
					return _fail("Missing saved field")
			for field: String in ["owner", "coins", "remaining", "units", "house", "a", "b", "seller", "quantity", "price", "listing"]:
				if record.has(field):
					if not _whole(record[field], 0, MAX_COINS):
						return _fail("Invalid saved integer")
					record[field] = int(record[field])
			for field: String in ["inventory", "stock"]:
				if record.has(field):
					if not _inventory_valid(record[field]):
						return _fail("Invalid saved inventory")
					record[field] = record[field].duplicate()
					for item: String in record[field]:
						record[field][item] = int(record[field][item])
			if table == "houses":
				if not record.get("parts") is Array or record.parts.size() > 1024:
					return _fail("Invalid house parts")
				var normalized_parts: Array = []
				for part_id: Variant in record.parts:
					if not _valid_id(part_id):
						return _fail("Invalid house part ID")
					normalized_parts.append(int(part_id))
				record.parts = normalized_parts
			if table in ["parts", "fasteners"]:
				for key: String in (["size", "position", "rotation"] if table == "parts" else ["position"]):
					var vector: Variant = _load_vector(record.get(key))
					if vector == null:
						return _fail("Invalid saved geometry")
					record[key] = vector
			values[id] = record
	if not candidate._validate_state():
		return _fail("Inconsistent save state")
	players = candidate.players
	deposits = candidate.deposits
	parts = candidate.parts
	fasteners = candidate.fasteners
	listings = candidate.listings
	houses = candidate.houses
	factories = candidate.factories
	return _ok()

func _validate_state() -> bool:
	for p: Dictionary in players.values():
		if not _whole(p.get("coins"), 0, MAX_COINS) or not p.get("npc") is bool or not _inventory_valid(p.get("inventory")):
			return false
	for d: Dictionary in deposits.values():
		if not d.get("item") in ["soil", "clay", "sand", "stone", "timber", "ore"] or not _whole(d.get("remaining"), 0, MAX_QUANTITY):
			return false
	for key: int in parts:
		var p: Dictionary = parts[key]
		if not _valid_id(p.get("owner")) or not players.has(int(p.owner)) or not p.get("size") is Vector3 or not _valid_size(p.size) or not p.get("position") is Vector3 or not p.get("rotation") is Vector3:
			return false
		if not p.get("material") is String or not _whole(p.get("units"), 1, MAX_QUANTITY) or material_cost(p.material, p.size) != int(p.units) or not _whole(p.get("house"), 0, MAX_ID):
			return false
		if not (p.get("health", 100.0) is float or p.get("health", 100.0) is int) or not is_finite(float(p.get("health", 100))) or float(p.get("health", 100)) <= 0 or float(p.get("health", 100)) > 100:
			return false
		if int(p.house) != 0 and (not houses.has(int(p.house)) or not houses[int(p.house)].get("parts", []) is Array or not key in houses[int(p.house)].get("parts", [])):
			return false
	for f: Dictionary in fasteners.values():
		if not _valid_id(f.get("owner")) or not players.has(int(f.owner)) or not _valid_id(f.get("a")) or not _whole(f.get("b"), 0, MAX_ID) or not parts.has(int(f.a)) or (int(f.b) != 0 and not parts.has(int(f.b))):
			return false
		if int(f.a) == int(f.b) or not f.get("item") in ["nail", "screw"] or not f.get("position") is Vector3 or parts[int(f.a)].owner != int(f.owner):
			return false
		if int(f.b) != 0 and (parts[int(f.b)].owner != int(f.owner) or parts[int(f.a)].house != parts[int(f.b)].house):
			return false
	for id: int in houses:
		var h: Dictionary = houses[id]
		if not _valid_id(h.get("owner")) or not players.has(int(h.owner)) or not h.get("parts") is Array or h.parts.is_empty() or h.parts.size() > 1024 or not _whole(h.get("listing"), 0, MAX_ID):
			return false
		var seen: Dictionary = {}
		for key: Variant in h.parts:
			if not _valid_id(key) or seen.has(int(key)) or not parts.has(int(key)) or parts[int(key)].house != id or parts[int(key)].owner != int(h.owner):
				return false
			seen[int(key)] = true
		if int(h.listing) != 0 and (not listings.has(int(h.listing)) or listings[int(h.listing)].get("closed", true) or listings[int(h.listing)].get("house") != id or listings[int(h.listing)].get("seller") != int(h.owner)):
			return false
	for id: int in listings:
		var l: Dictionary = listings[id]
		if not _valid_id(l.get("seller")) or not players.has(int(l.seller)) or not _whole(l.get("price"), 1, MAX_COINS) or not l.get("closed") is bool or not l.get("kind") in ["items", "house"]:
			return false
		if l.kind == "items":
			if not l.get("item") in ITEMS or not _whole(l.get("quantity"), 1, MAX_QUANTITY) or l.get("house") != 0:
				return false
		elif not _valid_id(l.get("house")) or (not l.closed and (not houses.has(int(l.house)) or houses[int(l.house)].owner != int(l.seller) or houses[int(l.house)].listing != id)):
			return false
	for f: Dictionary in factories.values():
		if not _valid_id(f.get("owner")) or not players.has(int(f.owner)) or not f.get("kind") in FACTORY_PRICES or not _inventory_valid(f.get("stock")):
			return false
	return true
