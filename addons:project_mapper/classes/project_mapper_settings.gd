@tool
class_name ProjectMapperSettings
extends Resource

static func _make_flat(color: Color, border: Color = Color.TRANSPARENT, border_width: int = 0) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = color
	s.set_corner_radius_all(3)
	s.set_content_margin_all(4)
	if border_width > 0:
		s.border_color = border
		s.set_border_width_all(border_width)
	return s

# ---------------------------------------------------------------------------
# Node Styles
# ---------------------------------------------------------------------------
@export_group("Node Styles")

@export var node_panel_builtin: StyleBoxFlat = _make_flat(Color(0.12, 0.12, 0.15, 0.45), Color(0.3, 0.3, 0.35), 1):
	set(v): node_panel_builtin = v; emit_changed()

@export var node_titlebar_builtin: StyleBoxFlat = _make_flat(Color(0.15, 0.15, 0.2, 0.45), Color(0.3, 0.3, 0.35), 1):
	set(v): node_titlebar_builtin = v; emit_changed()
	
@export_group("Node Colors")

@export var builtin_modulate: Color = Color(1.0, 1.0, 1.0, 0.45):
	set(v): builtin_modulate = v; emit_changed()

@export var autoload_color: Color = Color(1.0, 0.88, 0.2, 1.0):
	set(v): autoload_color = v; emit_changed()

# ---------------------------------------------------------------------------
# Highlight Colours
# ---------------------------------------------------------------------------
@export_group("Connection Colours")

@export var highlight_pink_color: Color = Color(1.0, 0.27, 0.6, 1.0):
	set(v): highlight_pink_color = v; emit_changed()

## Used for inbound call edges and the caller node border
@export var call_edge_color: Color = Color(0.2, 0.6, 1.0):
	set(v): call_edge_color = v; emit_changed()

## Used for outbound call edges and the callee node border
@export var call_edge_out_color: Color = Color(0.2, 0.9, 0.4):
	set(v): call_edge_out_color = v; emit_changed()

# ---------------------------------------------------------------------------
# Arrow Overlay
# ---------------------------------------------------------------------------
@export_group("Arrows")

@export var arrow_size: float = 28.0:
	set(v): arrow_size = v; emit_changed()

@export var arrow_outline_size: float = 8.0:
	set(v): arrow_outline_size = v; emit_changed()

@export var arrow_outline_color: Color = Color(0, 0, 0, 1.0):
	set(v): arrow_outline_color = v; emit_changed()

# ---------------------------------------------------------------------------
# Font Colours
# ---------------------------------------------------------------------------
@export_group("Font Variations")
@export var bold_font : FontVariation

@export_group("Font Colours")

@export var font_variable: Color = Color(0.8, 0.8, 0.8):
	set(v): font_variable = v; emit_changed()

@export var font_override: Color = Color(0.6, 0.9, 1.0):
	set(v): font_override = v; emit_changed()

@export var font_missing_super: Color = Color(1.0, 0.6, 0.1):
	set(v): font_missing_super = v; emit_changed()

@export var font_todo_header: Color = Color(1.0, 0.75, 0.2):
	set(v): font_todo_header = v; emit_changed()

@export var font_todo_item: Color = Color(0.75, 0.75, 0.55):
	set(v): font_todo_item = v; emit_changed()

@export var font_hover: Color = Color(1.0, 1.0, 1.0):
	set(v): font_hover = v; emit_changed()

# ---------------------------------------------------------------------------
# Layout
# ---------------------------------------------------------------------------
@export_group("Layout")

@export var h_sep: int = 200:
	set(v): h_sep = v; emit_changed()

@export var v_sep: int = 50:
	set(v): v_sep = v; emit_changed()
