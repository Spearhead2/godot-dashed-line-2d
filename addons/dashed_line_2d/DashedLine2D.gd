@tool
@icon("res://Addons/dashed_line_2d/DashedLine2D.png")
class_name DashedLine2D
extends Node2D
## ═════════════════════════════════════════════════════════════════════════════
## DASHED LINE 2D
##
## Draws a dashed polyline with per-segment width and color control.
##
## Width:
##   width          — base width in pixels
##   width_curve    — optional Curve sampled 0→1 along total arc length.
##                    Output multiplies base width.  Flat at 1.0 = uniform.
##
## Color:
##   default_color  — base color (used when gradient is null)
##   gradient       — optional Gradient sampled 0→1 along total arc length.
##                    When set, overrides default_color per-segment.
##
## Animation:
##   flow_direction — -1 / 0 / 1
##   flow_speed     — pixels per second
##
## Both curve and gradient are sampled at the midpoint of each dash segment
## so the visual transition is smooth across the whole line.
## ═════════════════════════════════════════════════════════════════════════════

# ── Geometry ──────────────────────────────────────────────────────────────────
@export var points : PackedVector2Array = PackedVector2Array():
	set(v): points = v; _arc_dirty = true; queue_redraw()

@export var closed : bool = false:
	set(v): 
		closed = v
		queue_redraw()

# ── Width ─────────────────────────────────────────────────────────────────────
@export var width       : float = 2.0:
	set(v): width = v; queue_redraw()

## Sampled 0→1 along the polyline's arc length.  Output multiplies width.
@export var width_curve : Curve = null:
	set(v):
		if width_curve and width_curve.changed.is_connected(_on_curve_changed):
			width_curve.changed.disconnect(_on_curve_changed)
		width_curve = v
		if width_curve:
			width_curve.changed.connect(_on_curve_changed)
		queue_redraw()

# ── Color ─────────────────────────────────────────────────────────────────────
@export var default_color : Color = Color.WHITE:
	set(v): default_color = v; queue_redraw()

## Sampled 0→1 along the polyline's arc length.  Overrides default_color.
@export var gradient : Gradient = null:
	set(v):
		if gradient and gradient.changed.is_connected(_on_gradient_changed):
			gradient.changed.disconnect(_on_gradient_changed)
		gradient = v
		if gradient:
			gradient.changed.connect(_on_gradient_changed)
		queue_redraw()

# ── Dash pattern ──────────────────────────────────────────────────────────────
@export var dash_length : float = 20.0:
	set(v): dash_length = maxf(1.0, v); queue_redraw()

@export var gap_length  : float = 40.0:
	set(v): gap_length  = maxf(1.0, v); queue_redraw()

# ── Animation ─────────────────────────────────────────────────────────────────
@export var flow : float = 0.0

# ── Internal ──────────────────────────────────────────────────────────────────
var _offset    : float = 0.0
var _arc_dirty : bool  = true
## Cumulative arc lengths per vertex: _arc[i] = distance from points[0] to points[i].
var _arc       : PackedFloat64Array = PackedFloat64Array()
var _total_len : float              = 0.0


# ── Lifecycle ─────────────────────────────────────────────────────────────────

func _process(delta: float) -> void:
	if not is_zero_approx(flow):
		var pattern : float = dash_length + gap_length
		_offset = fmod(_offset - flow * delta, pattern)
		if _offset < 0.0: _offset += pattern
		queue_redraw()


func _draw() -> void:
	if points.size() < 2: return


	_rebuild_arc_if_needed()
	
	var intern_pts : PackedVector2Array = PackedVector2Array(points)

	if points.size() > 2 and closed:
		intern_pts.append(points[0])
	
	if _total_len < 0.0001: return

	var pattern : float = dash_length + gap_length
	var phase   : float = fmod(_offset, pattern)

	for seg in range(intern_pts.size() - 1):
		var a       : Vector2 = intern_pts[seg]
		var b       : Vector2 = intern_pts[seg + 1]
		var seg_vec : Vector2 = b - a
		var seg_len : float   = seg_vec.length()
		if seg_len < 0.0001: continue
		var seg_dir : Vector2 = seg_vec / seg_len

		## Arc position at the start of this segment (for sampling curve/gradient).
		var arc_start : float = _arc[seg]

		var traveled : float = 0.0

		while traveled < seg_len:
			var in_dash    : bool  = phase < dash_length
			var phase_left : float = dash_length - phase if in_dash \
				else pattern - phase
			var step : float = minf(phase_left, seg_len - traveled)

			if in_dash:
				var p0 : Vector2 = a + seg_dir * traveled
				var p1 : Vector2 = a + seg_dir * (traveled + step)

				## Sample at the midpoint of this dash for smooth transitions.
				var mid_arc : float = arc_start + traveled + step * 0.5
				var t       : float = clampf(mid_arc / _total_len, 0.0, 1.0)

				var w   : float = width * (_sample_width(t))
				var col : Color = _sample_color(t)

				draw_line(p0, p1, col, w, true)

			traveled += step
			phase    += step
			if phase >= pattern:
				phase -= pattern


# ── Arc length cache ──────────────────────────────────────────────────────────

func _rebuild_arc_if_needed() -> void:
	if not _arc_dirty: return
	_arc_dirty = false
	_arc.resize(points.size())
	_arc[0]    = 0.0
	_total_len = 0.0
	for i in range(1, points.size()):
		_total_len   += points[i].distance_to(points[i - 1])
		_arc[i]       = _total_len


func _on_curve_changed()    -> void: queue_redraw()
func _on_gradient_changed() -> void: queue_redraw()


# ── Sampling ──────────────────────────────────────────────────────────────────

func _sample_width(t: float) -> float:
	if width_curve == null: return 1.0
	return width_curve.sample_baked(t)


func _sample_color(t: float) -> Color:
	if gradient == null: return default_color
	return gradient.sample(t)


# ── Public API ────────────────────────────────────────────────────────────────

func set_points(new_points: PackedVector2Array) -> void:
	points = new_points

func add_point(pt: Vector2) -> void:
	points.append(pt)
	_arc_dirty = true
	queue_redraw()

func set_point_position(idx: int, pt: Vector2) -> void:
	if idx < 0 or idx >= points.size(): return
	points[idx] = pt
	_arc_dirty  = true
	queue_redraw()

func clear_points() -> void:
	points     = PackedVector2Array()
	_arc_dirty = true
	queue_redraw()

func reset_flow() -> void:
	_offset = 0.0
	queue_redraw()
