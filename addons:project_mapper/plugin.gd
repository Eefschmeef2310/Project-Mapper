@tool
extends EditorPlugin

var _dock: EditorDock
var _view = preload("uid://dnna7ajx7urn5")
var _settings_dirty: bool = false

const SETTINGS_PATH = "res://addons/project_mapper/project_mapper_settings.tres"

func _enter_tree() -> void:
	_view = _view.instantiate()
	_view.settings.changed.connect(func(): _settings_dirty = true)

	# --- EditorDock setup ---
	_dock = EditorDock.new()
	_dock.title = "Project Mapper"
	_dock.default_slot = EditorDock.DOCK_SLOT_BOTTOM
	_dock.available_layouts = EditorDock.DOCK_LAYOUT_HORIZONTAL \
			| EditorDock.DOCK_LAYOUT_FLOATING

	_dock.add_child(_view)

	add_dock(_dock)
	_dock.make_visible()

func _exit_tree() -> void:
	if _settings_dirty:
		ResourceSaver.save(_view.settings, SETTINGS_PATH)

	remove_dock(_dock)
	_dock.queue_free()
	
func _load_or_create_settings() -> ProjectMapperSettings:
	if ResourceLoader.exists(SETTINGS_PATH):
		return load(SETTINGS_PATH) as ProjectMapperSettings
	var s := ProjectMapperSettings.new()
	DirAccess.make_dir_recursive_absolute(SETTINGS_PATH.get_base_dir())
	ResourceSaver.save(s, SETTINGS_PATH)
	return s
