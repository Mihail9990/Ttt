extends SceneTree
var game: Node
var frame: int = 0
func _initialize() -> void:
	call_deferred("setup")
func setup() -> void:
	game = load("res://scenes/main.tscn").instantiate()
	game.testing = true
	root.add_child(game)
	game.local_player.set_input_blocked(true)
	game.local_player.global_position = Vector3(16,4,9)
	game.local_player.look_at(Vector3(0,1,0),Vector3.UP)
	game.local_player.camera.rotation = Vector3(-0.08,0,0)
	game.local_player.set_tool("driver")
	# Show real authored materials and individual joints in the actual game scene.
	game.sim.place_part(1,7777,"board",Vector3(2.0,0.08,0.3),Vector3(13.8,1.8,7.0),Vector3(0,0.3,0))
	game.sim.fasten(1,7778,7777,0,"screw",Vector3(13.8,1.84,7.0))
	game._sync_world()
	game.hud.visible = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	process_frame.connect(render_frame)
func render_frame() -> void:
	frame += 1
	print("SKY_PREVIEW_FRAME ",frame)
	if frame<3: return
	process_frame.disconnect(render_frame)
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	if image==null or image.is_empty():
		push_error("No rendered viewport image")
		quit(1)
		return
	var destination := ProjectSettings.globalize_path("res://Artifacts/Preview")
	DirAccess.make_dir_recursive_absolute(destination)
	var error := image.save_png(destination+"/gameplay.png")
	if error!=OK:
		push_error("Preview save failed")
		quit(1)
		return
	print("SKY_RENDER_PREVIEW_OK ",destination+"/gameplay.png")
	quit(0)
