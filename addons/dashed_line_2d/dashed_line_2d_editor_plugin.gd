@tool
extends EditorPlugin
## ═════════════════════════════════════════════════════════════════════════════
## DASHED LINE 2D EDITOR PLUGIN
##
## Correct transform chain for Godot 4 EditorPlugin 2D canvas:
##
##   canvas_transform  = get_editor_interface()
##                         .get_editor_viewport_2d()
##                         .get_canvas_transform()
##
##   This encodes the current pan and zoom of the 2D editor viewport.
##
##   To draw a node-local point onto the overlay:
##     screen_pos = canvas_transform * node.get_global_transform() * local_pt
##
##   To convert a mouse position back to node-local space:
##     local_pt = (canvas_transform * node.get_global_transform())
##                  .affine_inverse() * mouse_pos
##
##   Hit radius must be divided by canvas zoom so handles stay
##   pixel-constant regardless of zoom level.
## ═════════════════════════════════════════════════════════════════════════════

const POINT_RADIUS      : float = 7.0
const POINT_COLOR       : Color = Color(0.9, 0.9, 0.9, 0.9)
const POINT_SEL_COLOR   : Color = Color(1.0, 0.8, 0.0, 1.0)
const POINT_HOVER_COLOR : Color = Color(1.0, 1.0, 0.4, 0.8)
const LINE_COLOR        : Color = Color(1.0, 1.0, 1.0, 0.35)
const ADD_COLOR         : Color = Color(0.3, 1.0, 0.3, 0.9)

var _node         : DashedLine2D          = null
var _undo         : EditorUndoRedoManager = null
var _selected_idx : int     = -1
var _hover_idx    : int     = -1
var _insert_idx   : int     = -1
var _insert_pos   : Vector2 = Vector2.ZERO
var _dragging     : bool    = false
var _drag_start   : Vector2 = Vector2.ZERO


# ── Plugin lifecycle ──────────────────────────────────────────────────────────

func _enter_tree() -> void:
	_undo = get_undo_redo()


func _exit_tree() -> void:
	_node = null


func _handles(object: Object) -> bool:
	return object is DashedLine2D


func _edit(object: Object) -> void:
	if object is DashedLine2D:
		_node         = object as DashedLine2D
		_selected_idx = -1
		_hover_idx    = -1
		_insert_idx   = -1
		_dragging     = false
	else:
		_node = null
	update_overlays()


func _make_visible(visible: bool) -> void:
	if not visible: _node = null
	update_overlays()


# ── Transform helpers ─────────────────────────────────────────────────────────

## The editor 2D canvas transform — encodes current pan and zoom.
func _canvas_t() -> Transform2D:
	return get_editor_interface().get_editor_viewport_2d().get_global_canvas_transform()


## Full transform: node-local → overlay screen pixels.
func _world_to_screen_t() -> Transform2D:
	return _canvas_t() * _node.get_global_transform_with_canvas()


## Convert a node-local point to overlay screen position.
func _to_screen(local_pt: Vector2) -> Vector2:
	return _world_to_screen_t() * local_pt


## Convert an overlay screen position to node-local space.
func _to_local(screen_pt: Vector2) -> Vector2:
	return _world_to_screen_t().affine_inverse() * screen_pt


## Hit radius in node-local space — keeps handles pixel-constant at any zoom.
func _hit_r() -> float:
	return POINT_RADIUS / _canvas_t().get_scale().x


# ── Drawing ───────────────────────────────────────────────────────────────────

func _forward_canvas_draw_over_viewport(overlay: Control) -> void:
	if _node == null or not is_instance_valid(_node): return

	var pts : PackedVector2Array = _node.points

	# Guide lines between points.
	for i in range(pts.size() - 1):
		overlay.draw_line(
			_to_screen(pts[i]),
			_to_screen(pts[i + 1]),
			LINE_COLOR, 1.0
		)

	# Insert-point preview (hover on a segment).
	if _insert_idx >= 0:
		overlay.draw_circle(
			_to_screen(_insert_pos),
			POINT_RADIUS * 0.75,
			ADD_COLOR
		)

	# Point handles.
	for i in pts.size():
		var sp  : Vector2 = _to_screen(pts[i])
		var col : Color   = POINT_SEL_COLOR   if i == _selected_idx \
						else POINT_HOVER_COLOR if i == _hover_idx \
						else POINT_COLOR
		overlay.draw_circle(sp, POINT_RADIUS, col)
		overlay.draw_arc(sp, POINT_RADIUS, 0.0, TAU, 20,
			Color(0.0, 0.0, 0.0, 0.5), 1.5)


# ── Input ─────────────────────────────────────────────────────────────────────

func _forward_canvas_gui_input(event: InputEvent) -> bool:
	if _node == null or not is_instance_valid(_node): return false

	if event is InputEventMouseMotion:
		return _on_motion(event as InputEventMouseMotion)
	if event is InputEventMouseButton:
		return _on_button(event as InputEventMouseButton)
	return false


func _on_motion(event: InputEventMouseMotion) -> bool:
	var local : Vector2 = _to_local(event.position)

	if _dragging and _selected_idx >= 0:
		_node.points[_selected_idx] = local
		_node.queue_redraw()
		update_overlays()
		return true

	var prev_hover  := _hover_idx
	_hover_idx       = _nearest_point(local)
	_insert_idx      = -1

	if _hover_idx == -1:
		var seg     := _nearest_segment(local)
		_insert_idx  = seg[0]
		_insert_pos  = seg[1]

	if _hover_idx != prev_hover:
		update_overlays()

	return false


func _on_button(event: InputEventMouseButton) -> bool:
	var local : Vector2 = _to_local(event.position)

	# ── Left ──────────────────────────────────────────────────────────────────
	if event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			var idx := _nearest_point(local)
			if idx >= 0:
				_selected_idx = idx
				_drag_start   = _node.points[idx]
				_dragging     = true
			else:
				_add_point(local, _node.points.size())
				_selected_idx = _node.points.size() - 1
				_drag_start   = local
				_dragging     = true
			update_overlays()
			return true
		else:
			if _dragging and _selected_idx >= 0:
				var final_pos : Vector2 = _node.points[_selected_idx]
				if final_pos.distance_squared_to(_drag_start) > 0.01:
					_commit_move(_selected_idx, _drag_start, final_pos)
			_dragging = false
			update_overlays()
			return true

	# ── Right ─────────────────────────────────────────────────────────────────
	if event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
		var idx := _nearest_point(local)
		if idx >= 0:
			_delete_point(idx)
			_selected_idx = -1
		else:
			var seg := _nearest_segment(local)
			if seg[0] >= 0:
				_add_point(seg[1], seg[0] + 1)
		_insert_idx = -1
		update_overlays()
		return true

	return false


# ── Undo-aware point operations ───────────────────────────────────────────────

func _add_point(local_pos: Vector2, at: int) -> void:
	var old_pts : PackedVector2Array = _node.points.duplicate()
	var new_pts : PackedVector2Array = PackedVector2Array()
	for i in at:
		new_pts.append(old_pts[i] if i < old_pts.size() else local_pos)
	new_pts.append(local_pos)
	for i in range(at, old_pts.size()):
		new_pts.append(old_pts[i])

	_undo.create_action("Add DashedLine2D Point")
	_undo.add_do_property(_node,   "points", new_pts)
	_undo.add_undo_property(_node, "points", old_pts)
	_undo.add_do_method(_node,   "queue_redraw")
	_undo.add_undo_method(_node, "queue_redraw")
	_undo.commit_action()


func _delete_point(idx: int) -> void:
	var old_pts : PackedVector2Array = _node.points.duplicate()
	var new_pts : PackedVector2Array = PackedVector2Array()
	for i in old_pts.size():
		if i != idx: new_pts.append(old_pts[i])

	_undo.create_action("Delete DashedLine2D Point")
	_undo.add_do_property(_node,   "points", new_pts)
	_undo.add_undo_property(_node, "points", old_pts)
	_undo.add_do_method(_node,   "queue_redraw")
	_undo.add_undo_method(_node, "queue_redraw")
	_undo.commit_action()


func _commit_move(idx: int, from: Vector2, to: Vector2) -> void:
	var old_pts : PackedVector2Array = _node.points.duplicate()
	var new_pts : PackedVector2Array = old_pts.duplicate()
	old_pts[idx] = from
	new_pts[idx] = to

	_undo.create_action("Move DashedLine2D Point")
	_undo.add_do_property(_node,   "points", new_pts)
	_undo.add_undo_property(_node, "points", old_pts)
	_undo.add_do_method(_node,   "queue_redraw")
	_undo.add_undo_method(_node, "queue_redraw")
	_undo.commit_action()


# ── Spatial queries ───────────────────────────────────────────────────────────

func _nearest_point(local_pos: Vector2) -> int:
	var r2   : float = _hit_r() * _hit_r()
	var best : int   = -1
	for i in _node.points.size():
		var d2 : float = local_pos.distance_squared_to(_node.points[i])
		if d2 < r2:
			r2   = d2
			best = i
	return best


func _nearest_segment(local_pos: Vector2) -> Array:
	var pts     : PackedVector2Array = _node.points
	var thresh2 : float              = (_hit_r() * 2.0) * (_hit_r() * 2.0)
	var best_d2 : float              = thresh2
	var best_i  : int                = -1
	var best_p  : Vector2            = Vector2.ZERO

	for i in range(pts.size() - 1):
		var a   : Vector2 = pts[i]
		var b   : Vector2 = pts[i + 1]
		var ab  : Vector2 = b - a
		var ab2 : float   = ab.dot(ab)
		if ab2 < 1e-6: continue
		var t   : float   = clampf((local_pos - a).dot(ab) / ab2, 0.0, 1.0)
		var cl  : Vector2 = a + ab * t
		var d2  : float   = local_pos.distance_squared_to(cl)
		if d2 < best_d2:
			best_d2 = d2
			best_i  = i
			best_p  = cl

	return [best_i, best_p]
