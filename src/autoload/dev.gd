extends Node
## Dev mode flag. Resolved once at boot in priority order:
## 1. --dev / --no-dev launch argument
## 2. user://dev.cfg file (contents "1" or "0")
## 3. OS.is_debug_build() (on in editor/debug, off in exports)
## Gates all dev-only tooling: Dev Tools menu, DebugReadout overlay, etc.
## Registered as autoload "Dev" after Constants.

var enabled: bool = false


func _ready() -> void:
	var args := OS.get_cmdline_args()
	if args.has("--dev"):
		enabled = true
	elif args.has("--no-dev"):
		enabled = false
	elif FileAccess.file_exists("user://dev.cfg"):
		enabled = FileAccess.get_file_as_string("user://dev.cfg").strip_edges() == "1"
	else:
		enabled = OS.is_debug_build()
	Log.info("Dev", "dev mode = %s" % enabled)
