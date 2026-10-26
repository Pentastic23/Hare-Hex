# shop_slot.gd
class_name ShopSlot extends Button

# One unit card in the shop bar (shop_panel.gd), in the style of the shop mockup in the Art assets
# folder ("autochess ui"): a dark slate card with the unit's portrait in a well (a cost-colour edge
# under it), the name, its traits, a gold coin with the cost, and three pips for the copies you
# already own toward the next star. The card is edged and faintly tinted in its cost colour (grey, green,
# blue, purple, gold); planned units (team planner) get a gold outline and a star instead.
# A bought (empty) slot shows a dim silhouette. Click to buy, or drag the card onto the board: it is bought
# and, in prep, put on the tile you drop it on (else it goes to the bench as usual).

const W := 140.0
const H := 64.0
const PORTRAIT := 52.0
const CARD := Color("1d2030")
const CARD_EDGE := Color("2c3249")
const SILHOUETTE_DIR := "res://textures/ui/shop/unit_silhouette_%d.png"

var offer: UnitData
var planned := false          # in the team plan
var index := 0                # 0-4, picks the silhouette shown while empty
var well: PanelContainer
var portrait: TextureRect
var name_label: Label
var tags_label: Label
var cost_label: Label
var coin: Control
var pips: Control
var star_label: Label
var flash_label: Label
var _info: VBoxContainer

func _ready():
	focus_mode = Control.FOCUS_NONE
	custom_minimum_size = Vector2(W, H)
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	text = ""
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.set_anchors_preset(Control.PRESET_FULL_RECT)
	row.offset_left = 6
	row.offset_top = 6
	row.offset_right = -14   # room for the planned star in the corner
	row.offset_bottom = -6
	row.add_theme_constant_override("separation", 7)
	add_child(row)
	well = DockKit.well(Vector2(PORTRAIT, PORTRAIT))
	well.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(well)
	portrait = TextureRect.new()
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	portrait.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	well.add_child(portrait)
	_info = VBoxContainer.new()
	_info.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_info.add_theme_constant_override("separation", 0)
	row.add_child(_info)
	name_label = _clipped(DockKit.text(12, HudStyle.INK))
	_info.add_child(name_label)
	tags_label = _clipped(DockKit.text(10, HudStyle.MUTED))
	_info.add_child(tags_label)
	var spacer := Control.new()
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_info.add_child(spacer)
	var bottom := HBoxContainer.new()
	bottom.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bottom.add_theme_constant_override("separation", 4)
	_info.add_child(bottom)
	coin = DockKit.Coin.new(12)
	bottom.add_child(coin)
	cost_label = HudStyle.number(18, HudStyle.INK)
	cost_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bottom.add_child(cost_label)
	var fill := Control.new()
	fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fill.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bottom.add_child(fill)
	pips = DockKit.Pips.new(3)
	pips.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bottom.add_child(pips)
	star_label = DockKit.text(11, HudStyle.GOLD)
	star_label.text = "★"
	star_label.position = Vector2(W - 13, 1)
	add_child(star_label)
	flash_label = DockKit.text(12, HudStyle.INK)
	flash_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	flash_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	flash_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	flash_label.add_theme_stylebox_override("normal", DockKit.flat(Color(0.04, 0.045, 0.07, 0.88), 3))
	flash_label.visible = false
	add_child(flash_label)
	Events.team_plan_changed.connect(_update_text)
	Events.king_changed.connect(_update_text)   # a Royal Discount starting or running out changes the price
	_update_text()

func _clipped(l: Label) -> Label:
	l.clip_text = true
	l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	l.custom_minimum_size.x = 10
	return l

func show_offer(d: UnitData):
	offer = d
	disabled = false
	_update_text()

func clear_offer():
	offer = null
	disabled = true
	_update_text()

# Card contents and style. Units in the team plan get a gold outline and a star.
func _update_text():
	if name_label == null:
		return
	planned = offer != null and SaveGame.team_plan().has(offer.display_name)
	var has := offer != null
	_info.visible = has
	star_label.visible = planned
	if has:
		name_label.text = offer.display_name
		var tags: PackedStringArray = []
		for t in offer.tags:
			tags.append(String(t))
		tags_label.text = " · ".join(tags)
		var price := GameState.me.price(offer)   # the Chaos King's Royal Discount can take 1 off
		cost_label.text = str(price)
		cost_label.add_theme_color_override("font_color", HudStyle.GOLD if price < offer.cost else HudStyle.INK)
		portrait.texture = DockKit.portrait(offer)
		portrait.modulate = Color.WHITE
		well.add_theme_stylebox_override("panel", DockKit.well_box(DockKit.COST_COLORS.get(offer.cost, HudStyle.NEUTRAL), 3))
		tooltip_text = Tip.wrap("%s (%d gold)\n%s%s%s\nClick to buy, or drag it onto the board." % [offer.display_name, price, ", ".join(tags), Abilities.tooltip_line(offer), "\nIn your team plan." if planned else ""])
		refresh_owned()
	else:
		var p := SILHOUETTE_DIR % (index % 5 + 1)
		portrait.texture = load(p) if ResourceLoader.exists(p) else null
		portrait.modulate = Color(1, 1, 1, 0.5)
		well.add_theme_stylebox_override("panel", DockKit.well_box())
		tooltip_text = ""
	var cost_col: Color = DockKit.COST_COLORS.get(offer.cost, CARD_EDGE) if has else CARD_EDGE
	var bg := CARD.lerp(cost_col, 0.12) if has else CARD.darkened(0.25)
	var n := DockKit.flat(bg, 3)
	n.set_border_width_all(2 if has else 1)
	n.border_color = HudStyle.GOLD if planned else (cost_col.darkened(0.15) if has else CARD_EDGE)
	var h := n.duplicate() as StyleBoxFlat
	h.bg_color = bg.lightened(0.06)
	var p2 := n.duplicate() as StyleBoxFlat
	p2.bg_color = DockKit.WELL
	add_theme_stylebox_override("normal", n)
	add_theme_stylebox_override("hover", h)
	add_theme_stylebox_override("pressed", p2)
	add_theme_stylebox_override("hover_pressed", p2)
	add_theme_stylebox_override("disabled", n)
	add_theme_stylebox_override("focus", DockKit.empty_box())

# Pips: 1-star copies of this unit you own (board and bench), toward the 3 that merge.
func refresh_owned():
	if offer == null or pips == null:
		return
	var n := 0
	if not is_inside_tree():
		return
	var board := get_tree().get_first_node_in_group("board") as Board
	if board != null:
		for u in board.all_player_units():
			if u.data != null and u.data.display_name == offer.display_name and u.star == 1:
				n += 1
	pips.set_filled(mini(n, 3))

func _pressed():
	if offer == null:
		return
	if GameState.me.gold < GameState.me.price(offer):
		_flash("Not enough gold")
		return
	var gm := get_tree().get_first_node_in_group("game_manager")
	var in_prep: bool = gm == null or gm.phase == Events.Phase.PREP
	var board := get_tree().get_first_node_in_group("board") as Board
	# During combat a purchase lands on the bench, so only a merge with bench copies makes room.
	if board != null and board.first_free_bench() == -1 and not board.would_complete_merge(offer, not in_prep):
		_flash("Bench full")
		return
	Events.unit_bought.emit(offer)
	clear_offer()   # also forgets the offer, so a team plan change can't bring its name back

# Dragging the card out of the shop: its portrait follows the pointer; letting go anywhere off the shop
# bar buys it (see _notification).
func _get_drag_data(_at: Vector2) -> Variant:
	if offer == null or disabled:
		return null
	var ghost := TextureRect.new()
	ghost.texture = DockKit.portrait(offer)
	ghost.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	ghost.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	ghost.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	ghost.size = Vector2(56, 56)
	ghost.position = -ghost.size * 0.5
	ghost.modulate.a = 0.85
	var holder := Control.new()
	holder.add_child(ghost)
	set_drag_preview(holder)
	_dragging = true
	return {"shop_offer": offer}

var _dragging := false

func _notification(what: int) -> void:
	if what != NOTIFICATION_DRAG_END or not _dragging:
		return
	_dragging = false
	if get_viewport().gui_is_drag_successful() or offer == null:
		return
	var bar := get_parent()
	while bar != null and not bar.name == "ShopPanel":
		bar = bar.get_parent()
	var m := get_viewport().get_mouse_position()
	if not get_viewport().get_visible_rect().has_point(m):
		return   # let go off the window (a touch long press slides the pointer away to read a tooltip)
	if bar is Control and (bar as Control).get_global_rect().has_point(m):
		return   # let go over the shop bar: nothing
	var dc := get_tree().current_scene.get_node_or_null("DragController") if get_tree().current_scene != null else null
	var d := offer
	var before := _bench_units()
	_pressed()   # the same checks (gold, bench room) and the same purchase as a click
	if offer == null and dc != null and dc.has_method("place_bought"):
		dc.place_bought(d, before)   # in prep: onto the tile under the pointer

func _bench_units() -> Array:
	var board := get_tree().get_first_node_in_group("board") as Board
	return board.bench.filter(func(u): return u != null) if board != null else []

func _flash(msg: String):
	flash_label.text = msg
	flash_label.visible = true
	await get_tree().create_timer(0.8).timeout
	if flash_label.text == msg:   # a newer message keeps its own timer
		flash_label.visible = false

# For checks: what the card says ("" when empty).
func shown_name() -> String:
	return name_label.text if offer != null else ""
