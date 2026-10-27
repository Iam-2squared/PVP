extends Control
## UI-only relative chart. Raw values are listed above; this is not a stat cap.

var values: Dictionary = {}
const KEYS := ["筋力", "耐久力", "精神力", "HP", "MP", "回復力", "敏捷力", "器用さ"]


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)


func _draw() -> void:
	var center := size * 0.5
	var radius := minf(size.x * 0.34, size.y * 0.34)
	var font := get_theme_default_font()
	var maximum := 1.0
	for value in values.values():
		maximum = maxf(maximum, float(value))
	for step in range(1, 5):
		var ring := PackedVector2Array()
		for i in range(9):
			ring.append(center + Vector2.from_angle(-PI / 2 + (i % 8) * TAU / 8) * radius * step / 4.0)
		draw_polyline(ring, Color("33444b"), 1, true)
	var polygon := PackedVector2Array()
	for i in range(8):
		var direction := Vector2.from_angle(-PI / 2 + i * TAU / 8)
		draw_line(center, center + direction * radius, Color("33444b"), 1, true)
		polygon.append(center + direction * radius * clampf(float(values.get(KEYS[i], 0)) / maximum, 0, 1))
		var text_size := font.get_string_size(KEYS[i], HORIZONTAL_ALIGNMENT_LEFT, -1, 12)
		var point := center + direction * (radius + 18) - text_size * 0.5 + Vector2(0, 9)
		draw_string(font, point, KEYS[i], HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color("9badb0"))
	if maximum > 1 or values.values().any(func(value: Variant) -> bool: return float(value) > 0):
		draw_colored_polygon(polygon, Color(0.45, 0.74, 0.72, 0.22))
		polygon.append(polygon[0])
		draw_polyline(polygon, Color("82bcb5"), 1.5, true)
	else:
		draw_circle(center, 3, Color("82bcb5"))
