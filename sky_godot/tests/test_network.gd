extends SceneTree
## Actual two-process integration entry point. Requires Python3 on the test host.
## Direct equivalent: python3 sky_godot/tests/run_network_tests.py
## This is an executable integration test, not a simulated network mock.
func _initialize() -> void:
	var output: Array = []
	var python: String = "python" if OS.get_name() == "Windows" else "python3"
	var runner: String = ProjectSettings.globalize_path("res://tests/run_network_tests.py")
	var result: int = OS.execute(python, [runner, "--godot", OS.get_executable_path()], output, true)
	for text in output:
		print(text)
	quit(result)
