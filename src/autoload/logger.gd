extends Node
## Lightweight logging with levels. Registered as autoload "Log".

enum Level { DEBUG, INFO, WARN, ERROR }

var min_level: Level = Level.DEBUG


func log_msg(level: Level, tag: String, msg: String) -> void:
	if level < min_level:
		return
	print("[%s][%s] %s" % [Level.keys()[level], tag, msg])


func debug(tag: String, msg: String) -> void:
	log_msg(Level.DEBUG, tag, msg)


func info(tag: String, msg: String) -> void:
	log_msg(Level.INFO, tag, msg)


func warn(tag: String, msg: String) -> void:
	log_msg(Level.WARN, tag, msg)


func error(tag: String, msg: String) -> void:
	log_msg(Level.ERROR, tag, msg)
