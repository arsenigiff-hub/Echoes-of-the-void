class_name SolarCellGrid
extends RefCounted
## Layout of the large solar wings: 11 columns x 2 rows per wing.
##
## The x values are the real frame divider centers measured from
## solar-array-wing-deployed_1_001/002 and expressed in the local space of
## solar-array-wing-deployed_3_001/002. Both wings share the same layout.
## The z limits match the solar-cell surface, the beam splits it into two rows.

const COLUMNS := 11
const ROWS := 2
const CELL_X: Array[float] = [
	-0.946, -0.777, -0.598, -0.424, -0.250, -0.076,
	0.098, 0.272, 0.446, 0.619, 0.793, 0.967,
]
const Z_EDGE := 0.761
const Z_BEAM := 0.042

const BROKEN_FORE := {
	0: [2, 6, 9],
	1: [3, 7, 10],
}
const BROKEN_AFT := {
	0: [1, 5, 8],
	1: [4, 6, 11],
}


## Cell rectangle in surface-local XZ. Row 0 is the +Z row (screen top).
static func rect(column: int, row: int) -> Rect2:
	var index := clampi(column - 1, 0, COLUMNS - 1)
	var left := CELL_X[index]
	var right := CELL_X[index + 1]
	if row == 0:
		return Rect2(left, Z_BEAM, right - left, Z_EDGE - Z_BEAM)
	return Rect2(left, -Z_EDGE, right - left, Z_EDGE - Z_BEAM)


static func center(column: int, row: int) -> Vector3:
	var cell := rect(column, row)
	return Vector3(cell.get_center().x, 0.0, cell.get_center().y)


static func cell_key(column: int, row: int) -> String:
	return "%d:%d" % [row, column]


static func broken_cells(wing_id: String) -> Array[Dictionary]:
	var pattern: Dictionary = BROKEN_FORE if wing_id == "fore" else BROKEN_AFT
	var cells: Array[Dictionary] = []
	for row in ROWS:
		for column in pattern[row]:
			cells.append({"column": int(column), "row": row})
	return cells
