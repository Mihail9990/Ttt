extends CanvasLayer
const SurfaceScript = preload("res://scripts/ui_surface.gd")
var surface: Control
func setup(game: Node) -> void:
    surface = SurfaceScript.new()
    surface.game = game
    surface.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    surface.mouse_filter = Control.MOUSE_FILTER_STOP
    add_child(surface)
