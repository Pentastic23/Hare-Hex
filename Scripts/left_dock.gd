# left_dock.gd
class_name LeftDock extends HudPlate

# The left box (menagerie/hud/DOCKS_SPEC.md, "Left box"), top left: Synergies, Items and King tabs with
# count badges, and a collapse button. Collapsed, it shrinks to a 46 px rail with an expand chevron
# and one button per tab (each with its badge); clicking either expands the box on that tab.
# Collapsed/open and the last tab are remembered in Settings (dock_collapsed, dock_tab).
# Replaces the old SynergyBox and ItemBar; the tab contents are synergy_panel.gd, item_bar.gd and
# king_panel.gd (your king's power this run; its badge lights when it waits on you).

const WIDTH := 232.0
const RAIL_WIDTH := 46.0
const POS := Vector2(10, 10)

const SynergyListScript := preload("res://Scripts/synergy_panel.gd")
const ItemListScript := preload("res://Scripts/item_bar.gd")
const KingPanelScript := preload("res://Scripts/king_panel.gd")
const TABS := ["synergies", "items", "king"]

var tab := "synergies"        # "synergies", "items" or "king"
var collapsed := false
var open_box: VBoxContainer   # header + body, while open
var rail: VBoxContainer       # while collapsed
var synergy_tab: Button
var items_tab: Button
var collapse_button: Button
var synergy_badge: Label
var items_badge: Label
var synergies                 # synergy_panel.gd
var items                     # item_bar.gd
var king                      # king_panel.gd
var king_tab: Button
var king_badge: Label
var rail_king: Button
var rail_king_badge: Label
var expand_button: Button
var rail_synergies: Button
var rail_items: Button
var rail_synergy_badge: Label
var rail_items_badge: Label
var _badge_timer := 0.0

func _ready():
	setup_plate(0, 0, 0)
	position = POS
	Settings.ensure_loaded()
	collapsed = Settings.dock_collapsed
	tab = Settings.dock_tab if Settings.dock_tab in TABS else "synergies"

	open_box = VBoxContainer.new()
	open_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	open_box.add_theme_constant_override("separation", 0)
	add_child(open_box)
	var header_margin := MarginContainer.new()
	header_margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side in ["left", "top", "right", "bottom"]:
		header_margin.add_theme_constant_override("margin_" + side, 4)
	open_box.add_child(header_margin)
	var header := HBoxContainer.new()
	header.mouse_filter = Control.MOUSE_FILTER_IGNORE
	header.add_theme_constant_override("separation", 2)
	header_margin.add_child(header)
	synergy_badge = DockKit.badge()
	synergy_tab = _tab("Synergies", synergy_badge, "Synergies on your board.")
	synergy_tab.pressed.connect(show_tab.bind("synergies"))
	header.add_child(synergy_tab)
	items_badge = DockKit.badge()
	items_tab = _tab("Items", items_badge, "Your items. Drag one onto a unit to equip it.")
	items_tab.pressed.connect(show_tab.bind("items"))
	header.add_child(items_tab)
	king_badge = DockKit.badge()
	var crown := HBoxContainer.new()   # a crown, not a word: three tabs of text don't fit the box
	crown.alignment = BoxContainer.ALIGNMENT_CENTER
	crown.add_theme_constant_override("separation", 3)
	crown.add_child(DockKit.PixelIcon.new("crown", HudStyle.GOLD, 16))
	crown.add_child(king_badge)
	king_tab = DockKit.tab(crown, 30)
	king_tab.custom_minimum_size.x = 34
	king_tab.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	king_tab.tooltip_text = Tip.wrap("King: your king's power and how it stands this run.")
	king_tab.pressed.connect(show_tab.bind("king"))
	header.add_child(king_tab)
	collapse_button = _icon_button("chev_left", Vector2(30, 30), "Collapse this box.")
	collapse_button.pressed.connect(set_collapsed.bind(true))
	header.add_child(collapse_button)
	var line := ColorRect.new()
	line.color = DockKit.LINE
	line.custom_minimum_size = Vector2(0, 1)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	open_box.add_child(line)
	var body := MarginContainer.new()
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side in ["left", "top", "right", "bottom"]:
		body.add_theme_constant_override("margin_" + side, 6)
	open_box.add_child(body)
	synergies = SynergyListScript.new()
	body.add_child(synergies)
	items = ItemListScript.new()
	body.add_child(items)
	king = KingPanelScript.new()
	body.add_child(king)

	rail = VBoxContainer.new()
	rail.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rail.add_theme_constant_override("separation", 6)
	var rail_margin := MarginContainer.new()
	rail_margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side in ["left", "top", "right", "bottom"]:
		rail_margin.add_theme_constant_override("margin_" + side, 6)
	rail_margin.add_child(rail)
	add_child(rail_margin)
	expand_button = _icon_button("chev_right", Vector2(34, 22), "Expand this box.")
	expand_button.pressed.connect(set_collapsed.bind(false))
	rail.add_child(expand_button)
	rail_synergy_badge = DockKit.badge()
	rail_synergies = _rail_button(DockKit.PixelIcon.new("hex", HudStyle.GOLD, 18), rail_synergy_badge, "Synergies")
	rail_synergies.pressed.connect(func():
		show_tab("synergies")
		set_collapsed(false))
	rail.add_child(rail_synergies)
	rail_items_badge = DockKit.badge()
	var sword := TextureRect.new()
	sword.texture = load(DockKit.ITEM_ICON_DIR + "longsword.png") if ResourceLoader.exists(DockKit.ITEM_ICON_DIR + "longsword.png") else null
	sword.custom_minimum_size = Vector2(24, 24)
	sword.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	sword.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	sword.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	sword.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rail_items = _rail_button(sword, rail_items_badge, "Items")
	rail_items.pressed.connect(func():
		show_tab("items")
		set_collapsed(false))
	rail.add_child(rail_items)
	rail_king_badge = DockKit.badge()
	rail_king = _rail_button(DockKit.PixelIcon.new("crown", HudStyle.GOLD, 18), rail_king_badge, "King")
	rail_king.pressed.connect(func():
		show_tab("king")
		set_collapsed(false))
	rail.add_child(rail_king)

	Events.items_changed.connect(_update_badges)
	Events.king_changed.connect(_on_king_changed)
	minimum_size_changed.connect(func(): _shrink.call_deferred())   # content grew or shrank
	_apply()

func _process(delta):
	_badge_timer -= delta
	if _badge_timer > 0.0:
		return
	_badge_timer = 0.25
	_update_badges()

# A prophecy to choose opens the King tab by itself (once per choice).
var _shown_choice := false
func _on_king_changed() -> void:
	_update_badges()
	var w: int = king.pending()
	if w > 0 and not _shown_choice:
		_shown_choice = true
		show_tab("king")
		if collapsed:
			set_collapsed(false)
	elif w == 0:
		_shown_choice = false

func show_tab(t: String) -> void:
	tab = t
	Settings.dock_tab = t
	Settings.save_settings()
	_apply()

func set_collapsed(on: bool) -> void:
	collapsed = on
	Settings.dock_collapsed = on
	Settings.save_settings()
	_apply()

func _apply() -> void:
	open_box.visible = not collapsed
	rail.get_parent().visible = collapsed
	synergies.visible = tab == "synergies"
	items.visible = tab == "items"
	king.visible = tab == "king"
	DockKit.set_tab_active(synergy_tab, tab == "synergies", DockKit.TAB_ACTIVE)
	DockKit.set_tab_active(items_tab, tab == "items", DockKit.TAB_ACTIVE)
	DockKit.set_tab_active(king_tab, tab == "king", DockKit.TAB_ACTIVE)
	custom_minimum_size.x = RAIL_WIDTH if collapsed else WIDTH
	_update_badges()
	_shrink.call_deferred()

# A container keeps its size when its content gets smaller; snap back to the content.
func _shrink() -> void:
	size = Vector2.ZERO
	position = POS

func _update_badges() -> void:
	if synergies == null:
		return
	var a: int = synergies.active_count
	var n: int = items.count()
	DockKit.set_badge(synergy_badge, a, tab == "synergies")
	DockKit.set_badge(items_badge, n, tab == "items")
	DockKit.set_badge(rail_synergy_badge, a, a > 0)
	DockKit.set_badge(rail_items_badge, n, n > 0)
	var w: int = king.pending()
	DockKit.set_badge(king_badge, w, w > 0)
	king_badge.visible = w > 0
	rail_king_badge.visible = w > 0
	DockKit.set_badge(rail_king_badge, w, w > 0)
	rail_king.tooltip_text = Tip.wrap("King: a choice waits for you. Click to open." if w > 0 else "King: your king's power. Click to open.")
	rail_synergies.tooltip_text = Tip.wrap("Synergies: %d active. Click to open." % a)
	rail_items.tooltip_text = Tip.wrap("Items: %d. Click to open." % n)

func _tab(label: String, badge: Label, tip: String) -> Button:
	var content := HBoxContainer.new()
	content.alignment = BoxContainer.ALIGNMENT_CENTER
	content.add_theme_constant_override("separation", 5)
	content.add_child(DockKit.tab_label(label))
	content.add_child(badge)
	var b := DockKit.tab(content, 30)
	b.tooltip_text = Tip.wrap(tip)
	return b

func _icon_button(kind: String, min_size: Vector2, tip: String) -> Button:
	var b := Button.new()
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = min_size
	b.tooltip_text = Tip.wrap(tip)
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var n := DockKit.flat(Color.TRANSPARENT)
	var h := DockKit.flat(Color(1, 1, 1, 0.06))
	b.add_theme_stylebox_override("normal", n)
	b.add_theme_stylebox_override("hover", h)
	b.add_theme_stylebox_override("pressed", h)
	b.add_theme_stylebox_override("focus", DockKit.empty_box())
	var icon := DockKit.PixelIcon.new(kind, HudStyle.MUTED, 14)
	icon.set_anchors_preset(Control.PRESET_FULL_RECT)
	b.add_child(icon)
	return b

# A 34 px square rail button with its badge at the top-right corner.
func _rail_button(icon: Control, badge: Label, tip: String) -> Button:
	var b := Button.new()
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(34, 34)
	b.tooltip_text = Tip.wrap(tip)
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.add_theme_stylebox_override("normal", DockKit.flat(DockKit.WELL))
	b.add_theme_stylebox_override("hover", DockKit.flat(DockKit.SECONDARY))
	b.add_theme_stylebox_override("pressed", DockKit.flat(DockKit.SECONDARY))
	b.add_theme_stylebox_override("focus", DockKit.empty_box())
	icon.set_anchors_preset(Control.PRESET_CENTER)
	icon.grow_horizontal = Control.GROW_DIRECTION_BOTH
	icon.grow_vertical = Control.GROW_DIRECTION_BOTH
	b.add_child(icon)
	badge.position = Vector2(22, -6)
	b.add_child(badge)
	return b
