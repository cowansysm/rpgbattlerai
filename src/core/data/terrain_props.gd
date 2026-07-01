class_name TerrainProps
extends Resource
## Properties for a single terrain type. Drives movement cost,
## impassability, line-of-sight blocking, cover, and terrain effects.
## Alpha A0 adds hazard damage, status-on-enter, occupant modifiers,
## water tagging, and free-form terrain tags.

@export var id: String
@export var move_cost: int = 1
@export var impassable: bool = false
@export var blocks_los: bool = false
@export var cover: int = 0
@export var los_height: int = 0

# --- Alpha A0 additions ---
@export var damage_on_enter: int = 0           ## Damage dealt when a unit enters the tile
@export var damage_per_turn: int = 0           ## Damage dealt at the start of an occupant's activation
@export var status_on_enter: Dictionary = {}   ## {status_id: String, duration: int} or {}
@export var occupant_modifiers: Array = []     ## [{key: String, value: int}, ...]
@export var is_water: bool = false             ## Tags the tile as water
@export var terrain_tags: Array[String] = []   ## Free-form classification (e.g., "hazard", "forest")

# --- Alpha A16 additions ---
@export var affinities: Dictionary = {}        ## {element: tier_name} e.g. {"holy": "weak"}
