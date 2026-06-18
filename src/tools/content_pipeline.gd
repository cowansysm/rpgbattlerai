extends SceneTree
## Headless CSV content pipeline runner.
## Usage:
##   godot --headless -s res://src/tools/content_pipeline.gd -- export all
##   godot --headless -s res://src/tools/content_pipeline.gd -- export abilities
##   godot --headless -s res://src/tools/content_pipeline.gd -- import all
##   godot --headless -s res://src/tools/content_pipeline.gd -- import classes

func _init() -> void:
	var args := OS.get_cmdline_args()
	var dash_idx := args.find("--")
	var rest: PackedStringArray = args.slice(dash_idx + 1) if dash_idx >= 0 else PackedStringArray()

	if rest.size() < 1:
		_print_usage()
		quit()
		return

	var cmd: String = rest[0]
	var who: String = rest[1] if rest.size() > 1 else "all"

	if cmd not in ["export", "import"]:
		print("ERROR: Unknown command '%s'. Use 'export' or 'import'." % cmd)
		_print_usage()
		quit()
		return

	var targets: Array[String] = []
	if who == "all":
		targets.assign(EntitySchema.ENTITIES)
	elif who in EntitySchema.ENTITIES:
		targets.append(who)
	else:
		print("ERROR: Unknown entity '%s'. Valid: %s" % [who, ", ".join(EntitySchema.ENTITIES)])
		quit()
		return

	var all_errors: Array[String] = []

	for entity in targets:
		if cmd == "export":
			print("Exporting %s..." % entity)
			var errors := CsvExporter.export_entity(entity)
			if errors.is_empty():
				print("  OK → data/csv/%s.csv" % entity)
			else:
				for e in errors:
					print("  ERROR: %s" % e)
				all_errors.append_array(errors)
		elif cmd == "import":
			print("Importing %s..." % entity)
			var errors := CsvImporter.import_entity(entity)
			if errors.is_empty():
				print("  OK → data/%s.json" % entity)
			else:
				for e in errors:
					print("  ERROR: %s" % e)
				all_errors.append_array(errors)

	if all_errors.is_empty():
		print("\nDone. No errors.")
	else:
		print("\nFinished with %d error(s)." % all_errors.size())

	quit()


func _print_usage() -> void:
	print("CSV Content Pipeline")
	print("Usage: godot --headless -s res://src/tools/content_pipeline.gd -- <command> [entity]")
	print("")
	print("Commands:")
	print("  export <entity|all>  Export JSON → CSV")
	print("  import <entity|all>  Import CSV → JSON (validated)")
	print("")
	print("Entities: %s" % ", ".join(EntitySchema.ENTITIES))
