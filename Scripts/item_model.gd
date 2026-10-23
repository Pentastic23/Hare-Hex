# item_model.gd
class_name ItemModel extends RefCounted

# Small voxel models of items (items v2), shown above the units that hold them. Each model is built
# from the item's icon (textures/ui/items/<id>.png, via DockKit.item_icon): the icon is sampled on a
# 16 x 16 grid and every opaque pixel becomes a coloured cube, two cubes deep, so the model matches
# the art and the units' voxel style. Built once per item and shared by every unit; an item without
# an icon gets a plain cube in its colour.

const GRID := 16
const SIZE := 0.34          # world width of a model
const DEPTH := 2            # cubes deep

static var _meshes := {}    # item id -> Mesh
static var _plain: StandardMaterial3D
static var _glow: StandardMaterial3D

static func mesh_for(item: ItemData) -> Mesh:
	if _meshes.has(item.id):
		return _meshes[item.id]
	var mesh: Mesh = null
	var tex := DockKit.item_icon(item)
	if tex != null:
		mesh = _voxelize(tex.get_image())
	if mesh == null:
		var box := BoxMesh.new()
		box.size = Vector3.ONE * SIZE * 0.6
		mesh = box
	_meshes[item.id] = mesh
	return mesh

# Vertex-coloured, lit; `glow` adds a soft emission (an item in an active resonance).
static func material(glow := false) -> StandardMaterial3D:
	if _plain == null:
		_plain = StandardMaterial3D.new()
		_plain.vertex_color_use_as_albedo = true
		_plain.roughness = 0.8
		_glow = _plain.duplicate() as StandardMaterial3D
		_glow.emission_enabled = true
		_glow.emission = Color(1.0, 0.85, 0.45)
		_glow.emission_energy_multiplier = 0.6
	return _glow if glow else _plain

static func _voxelize(src: Image) -> Mesh:
	if src == null or src.is_empty():
		return null
	var img := src.duplicate() as Image
	if img.is_compressed():
		img.decompress()
	img.convert(Image.FORMAT_RGBA8)
	var step := float(img.get_width()) / GRID
	var voxel := SIZE / GRID
	var filled := {}
	for y in GRID:
		for x in GRID:
			var c := img.get_pixel(int((x + 0.5) * step), int((y + 0.5) * step))
			if c.a > 0.5:
				filled[Vector2i(x, y)] = c
	if filled.is_empty():
		return null
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var origin := Vector3(-SIZE / 2.0, SIZE / 2.0, -voxel * DEPTH / 2.0)
	for key in filled:
		var p: Vector2i = key
		var col: Color = filled[p]
		for z in DEPTH:
			var base := origin + Vector3(p.x * voxel, -(p.y + 1) * voxel, z * voxel)
			# Only faces that aren't hidden by a neighbour: front, back, and the outline sides.
			var faces: Array = []
			if z == DEPTH - 1:
				faces.append(Vector3.BACK)
			if z == 0:
				faces.append(Vector3.FORWARD)
			if not filled.has(p + Vector2i(1, 0)):
				faces.append(Vector3.RIGHT)
			if not filled.has(p + Vector2i(-1, 0)):
				faces.append(Vector3.LEFT)
			if not filled.has(p + Vector2i(0, -1)):
				faces.append(Vector3.UP)
			if not filled.has(p + Vector2i(0, 1)):
				faces.append(Vector3.DOWN)
			for n in faces:
				_face(st, base, voxel, n, col.darkened(0.25) if n == Vector3.LEFT or n == Vector3.DOWN else col)
	st.generate_normals()
	return st.commit()

# One cube face (two triangles) of the cube at `base` (its minimum corner), facing `n`.
static func _face(st: SurfaceTool, base: Vector3, s: float, n: Vector3, c: Color) -> void:
	var corners: Array[Vector3]
	match n:
		Vector3.BACK:
			corners = [Vector3(0, 0, 1), Vector3(1, 0, 1), Vector3(1, 1, 1), Vector3(0, 1, 1)]
		Vector3.FORWARD:
			corners = [Vector3(1, 0, 0), Vector3(0, 0, 0), Vector3(0, 1, 0), Vector3(1, 1, 0)]
		Vector3.RIGHT:
			corners = [Vector3(1, 0, 1), Vector3(1, 0, 0), Vector3(1, 1, 0), Vector3(1, 1, 1)]
		Vector3.LEFT:
			corners = [Vector3(0, 0, 0), Vector3(0, 0, 1), Vector3(0, 1, 1), Vector3(0, 1, 0)]
		Vector3.UP:
			corners = [Vector3(0, 1, 1), Vector3(1, 1, 1), Vector3(1, 1, 0), Vector3(0, 1, 0)]
		_:
			corners = [Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(1, 0, 1), Vector3(0, 0, 1)]
	var v: Array[Vector3] = []
	for k in corners:
		v.append(base + k * s)
	st.set_color(c)
	for i in [0, 1, 2, 0, 2, 3]:
		st.add_vertex(v[i])
