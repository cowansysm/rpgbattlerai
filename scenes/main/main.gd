extends Node
## Minimal entry point. Boots, logs GameData summary, renders nothing.

func _ready() -> void:
	Log.info("Main", "Boot OK")
	# Demonstrate accessor usage with a sample character
	var archer := GameData.get_character("human_archer")
	if archer:
		var stats := GameData.get_final_stats("human_archer")
		Log.info("Main", "Sample: %s (BP %d, final HP %d, Move %d)" % [
			archer.display_name, archer.bp,
			stats.effective("hp") if stats else -1,
			stats.effective_move() if stats else -1])
	else:
		Log.warn("Main", "Sample character 'human_archer' not found")
