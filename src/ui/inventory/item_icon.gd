class_name ItemIcon
extends Control
## Hand-drawn item icons (no image assets yet), readable at 48-96 px.
## One silhouette per item family, so a sword never looks like a dagger.

const STEEL: Color = Color("c9d0d9")
const STEEL_DARK: Color = Color("7d8794")
const WOOD: Color = Color("8a5a32")
const LEATHER: Color = Color("6e4a2f")
const BRASS: Color = Color("d2a856")
const STRING: Color = Color("e8e0cf")

var item_id: String = "":
	set(value):
		item_id = value
		queue_redraw()
var dimmed: bool = false:
	set(value):
		dimmed = value
		modulate = Color(1, 1, 1, 0.45) if value else Color.WHITE

func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _p(x: float, y: float) -> Vector2:
	# Icons are authored on a 100 x 100 grid.
	var unit: float = minf(size.x, size.y) / 100.0
	var offset: Vector2 = (size - Vector2.ONE * minf(size.x, size.y)) * 0.5
	return offset + Vector2(x, y) * unit

func _w(width: float) -> float:
	return maxf(1.0, width * minf(size.x, size.y) / 100.0)

func _poly(points: Array[Vector2], color: Color) -> void:
	var packed: PackedVector2Array = []
	for point: Vector2 in points:
		packed.append(_p(point.x, point.y))
	draw_colored_polygon(packed, color)

func _draw() -> void:
	if item_id.is_empty():
		return
	match item_id:
		"longsword", "shortsword": _sword(item_id == "longsword")
		"dagger": _dagger()
		"battleaxe": _axe()
		"mace": _mace()
		"quarterstaff": _staff()
		"spear": _spear()
		"shortbow": _bow()
		"light_crossbow": _crossbow()
		"shield": _shield()
		"leather", "chain_shirt", "chain_mail": _armor()
		"potion_of_healing": _potion()
		_: draw_circle(_p(50, 50), _w(30), STEEL_DARK)

func _sword(long: bool) -> void:
	var tip: float = 8.0 if long else 22.0
	_poly([Vector2(74, 26), Vector2(100 - tip, tip), Vector2(78, 30), Vector2(36, 72), Vector2(32, 68)], STEEL)
	draw_line(_p(76, 28), _p(36, 68), STEEL_DARK, _w(2))
	draw_line(_p(24, 60), _p(42, 78), BRASS, _w(7))
	draw_line(_p(32, 70), _p(16, 86), LEATHER, _w(7))
	draw_circle(_p(14, 88), _w(5), BRASS)

func _dagger() -> void:
	_poly([Vector2(62, 38), Vector2(80, 20), Vector2(66, 42), Vector2(44, 64), Vector2(40, 60)], STEEL)
	draw_line(_p(34, 52), _p(50, 68), BRASS, _w(6))
	draw_line(_p(42, 62), _p(28, 76), LEATHER, _w(7))
	draw_circle(_p(26, 78), _w(4), BRASS)

func _axe() -> void:
	draw_line(_p(26, 88), _p(64, 18), WOOD, _w(7))
	_poly([Vector2(56, 22), Vector2(80, 10), Vector2(92, 34), Vector2(78, 50), Vector2(62, 40)], STEEL)
	draw_line(_p(80, 12), _p(90, 34), Color.WHITE, _w(2))

func _mace() -> void:
	draw_line(_p(28, 86), _p(60, 36), WOOD, _w(7))
	draw_circle(_p(66, 28), _w(16), STEEL_DARK)
	for angle: float in [0.0, 1.57, 3.14, 4.71, 0.78, 2.35, 3.93, 5.5]:
		draw_line(_p(66, 28), _p(66, 28) + Vector2.from_angle(angle) * _w(22), STEEL, _w(5))
	draw_circle(_p(66, 28), _w(10), STEEL)

func _staff() -> void:
	draw_line(_p(22, 92), _p(74, 14), WOOD, _w(7))
	draw_circle(_p(76, 12), _w(9), Color("7fb4e8"))
	draw_arc(_p(76, 12), _w(12), 0, TAU, 24, BRASS, _w(2))

func _spear() -> void:
	draw_line(_p(16, 92), _p(72, 26), WOOD, _w(5))
	_poly([Vector2(68, 30), Vector2(90, 8), Vector2(78, 36)], STEEL)
	draw_line(_p(64, 30), _p(74, 40), BRASS, _w(4))

func _bow() -> void:
	draw_arc(_p(28, 50), _w(46), -1.15, 1.15, 24, WOOD, _w(7))
	draw_line(_p(46, 8), _p(46, 92), STRING, _w(1.5))
	draw_line(_p(20, 50), _p(92, 50), STEEL_DARK, _w(3))
	_poly([Vector2(92, 50), Vector2(82, 44), Vector2(82, 56)], STEEL)

func _crossbow() -> void:
	draw_line(_p(50, 18), _p(50, 92), WOOD, _w(9))
	draw_arc(_p(50, 52), _w(40), -2.6, -0.54, 24, STEEL_DARK, _w(6))
	draw_line(_p(16, 32), _p(84, 32), STRING, _w(1.5))
	draw_line(_p(50, 10), _p(50, 40), STEEL, _w(3))

func _shield() -> void:
	_poly([Vector2(20, 18), Vector2(80, 18), Vector2(80, 50), Vector2(50, 90), Vector2(20, 50)], Color("5c3a2a"))
	_poly([Vector2(26, 24), Vector2(74, 24), Vector2(74, 49), Vector2(50, 82), Vector2(26, 49)], Color("8f2f2b"))
	draw_line(_p(50, 24), _p(50, 82), BRASS, _w(4))
	draw_line(_p(26, 44), _p(74, 44), BRASS, _w(4))

func _armor() -> void:
	var tint: Color = LEATHER if item_id == "leather" else STEEL_DARK
	_poly([Vector2(30, 14), Vector2(42, 20), Vector2(58, 20), Vector2(70, 14), Vector2(88, 30),
		Vector2(78, 46), Vector2(72, 42), Vector2(72, 88), Vector2(28, 88), Vector2(28, 42),
		Vector2(22, 46), Vector2(12, 30)], tint)
	if item_id != "leather":
		for row: int in range(4):
			draw_line(_p(32, 34 + row * 13), _p(68, 34 + row * 13), STEEL, _w(2))
	else:
		draw_line(_p(50, 24), _p(50, 86), tint.darkened(0.4), _w(2))
	draw_line(_p(28, 80), _p(72, 80), BRASS, _w(4))

func _potion() -> void:
	draw_circle(_p(50, 62), _w(26), Color("3a1418"))
	draw_circle(_p(50, 64), _w(22), Color("c3313b"))
	draw_circle(_p(42, 56), _w(6), Color(1, 1, 1, 0.45))
	draw_rect(Rect2(_p(42, 22), _p(58, 40) - _p(42, 22)), Color("b9d2dc"))
	draw_rect(Rect2(_p(40, 14), _p(60, 24) - _p(40, 14)), WOOD)
