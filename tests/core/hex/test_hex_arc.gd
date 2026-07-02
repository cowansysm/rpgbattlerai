extends GutTest
## Tests for A19 arc classification in Hex: arc_of and arc_between.


# --- arc_of: all 6 facings x representative approaches ---

func test_arc_of_front_same_direction() -> void:
	# Target facing dir 0; attack comes from dir 0 (straight at face) -> FRONT
	assert_eq(Hex.arc_of(0, 0), Hex.Arc.FRONT)


func test_arc_of_front_left_adjacent() -> void:
	# Target facing dir 0; attack comes from dir 1 (+1 diff) -> FRONT
	assert_eq(Hex.arc_of(1, 0), Hex.Arc.FRONT)


func test_arc_of_front_right_adjacent() -> void:
	# Target facing dir 0; attack comes from dir 5 (-1 diff = +5 mod 6) -> FRONT
	assert_eq(Hex.arc_of(5, 0), Hex.Arc.FRONT)


func test_arc_of_flank_left() -> void:
	# Target facing dir 0; attack comes from dir 2 (+2 diff) -> FLANK
	assert_eq(Hex.arc_of(2, 0), Hex.Arc.FLANK)


func test_arc_of_flank_right() -> void:
	# Target facing dir 0; attack comes from dir 4 (+4 = -2 diff) -> FLANK
	assert_eq(Hex.arc_of(4, 0), Hex.Arc.FLANK)


func test_arc_of_rear() -> void:
	# Target facing dir 0; attack comes from dir 3 (+3 diff) -> REAR
	assert_eq(Hex.arc_of(3, 0), Hex.Arc.REAR)


func test_arc_of_facing_1_front() -> void:
	# Target faces dir 1; attack from dir 1 -> FRONT
	assert_eq(Hex.arc_of(1, 1), Hex.Arc.FRONT)


func test_arc_of_facing_1_rear() -> void:
	# Target faces dir 1; attack from dir 4 (diff=3) -> REAR
	assert_eq(Hex.arc_of(4, 1), Hex.Arc.REAR)


func test_arc_of_facing_1_flank() -> void:
	# Target faces dir 1; attack from dir 3 (diff=2) -> FLANK
	assert_eq(Hex.arc_of(3, 1), Hex.Arc.FLANK)


func test_arc_of_facing_3_front() -> void:
	# Target faces dir 3; attack from dir 3 -> FRONT
	assert_eq(Hex.arc_of(3, 3), Hex.Arc.FRONT)


func test_arc_of_facing_3_rear() -> void:
	# Target faces dir 3; attack from dir 0 (diff=3) -> REAR
	assert_eq(Hex.arc_of(0, 3), Hex.Arc.REAR)


func test_arc_of_facing_5_front() -> void:
	# Target faces dir 5; attack from dir 5 -> FRONT
	assert_eq(Hex.arc_of(5, 5), Hex.Arc.FRONT)


func test_arc_of_facing_5_flank() -> void:
	# Target faces dir 5; attack from dir 1 (diff=2) -> FLANK
	assert_eq(Hex.arc_of(1, 5), Hex.Arc.FLANK)


func test_arc_of_facing_5_rear() -> void:
	# Target faces dir 5; attack from dir 2 (diff=3) -> REAR
	assert_eq(Hex.arc_of(2, 5), Hex.Arc.REAR)


func test_arc_of_all_diffs() -> void:
	# diff 0,1,5 = FRONT; diff 2,4 = FLANK; diff 3 = REAR
	# Test each diff exhaustively against target_facing = 0
	assert_eq(Hex.arc_of(0, 0), Hex.Arc.FRONT, "diff 0 = FRONT")
	assert_eq(Hex.arc_of(1, 0), Hex.Arc.FRONT, "diff 1 = FRONT")
	assert_eq(Hex.arc_of(2, 0), Hex.Arc.FLANK, "diff 2 = FLANK")
	assert_eq(Hex.arc_of(3, 0), Hex.Arc.REAR,  "diff 3 = REAR")
	assert_eq(Hex.arc_of(4, 0), Hex.Arc.FLANK, "diff 4 = FLANK")
	assert_eq(Hex.arc_of(5, 0), Hex.Arc.FRONT, "diff 5 = FRONT")


# --- arc_between convenience helper ---

func test_arc_between_front() -> void:
	# Target at (0,0) facing dir 0 (+q direction).
	# Attacker at (2,0) -> direction_toward((0,0),(2,0)) = dir 0 -> diff 0 -> FRONT
	var result: int = Hex.arc_between(Vector2i(2, 0), Vector2i(0, 0), 0)
	assert_eq(result, Hex.Arc.FRONT)


func test_arc_between_rear() -> void:
	# Target at (0,0) facing dir 0. Attacker at (-2,0).
	# direction_toward((0,0),(-2,0)) = dir 3 -> diff 3 -> REAR
	var result: int = Hex.arc_between(Vector2i(-2, 0), Vector2i(0, 0), 0)
	assert_eq(result, Hex.Arc.REAR)


func test_arc_between_flank() -> void:
	# Target at (0,0) facing dir 0. Use attacker at (-1,-2) to force dir 2 approach.
	# direction_toward((0,0),(-1,-2)): diff=(-1,-2). dir2=(0,-1) wins: dot=2.
	# arc_of(2, 0): diff=(2-0)%6=2 -> FLANK
	var result: int = Hex.arc_between(Vector2i(-1, -2), Vector2i(0, 0), 0)
	assert_eq(result, Hex.Arc.FLANK)


func test_arc_between_same_position_is_front() -> void:
	# Self-target: direction_toward returns 0 by convention -> FRONT
	var result: int = Hex.arc_between(Vector2i(0, 0), Vector2i(0, 0), 0)
	assert_eq(result, Hex.Arc.FRONT)
