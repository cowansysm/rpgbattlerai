class_name TerrainProps
extends Resource
## Properties for a single terrain type. Drives movement cost,
## impassability, line-of-sight blocking, and cover.

@export var id: String
@export var move_cost: int = 1
@export var impassable: bool = false
@export var blocks_los: bool = false
@export var cover: int = 0
@export var los_height: int = 0
