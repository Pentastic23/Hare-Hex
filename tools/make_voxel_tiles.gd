# make_voxel_tiles.gd
# Dev tool, not part of the game: bakes the voxel hex tiles (Scripts/voxel_tiles.gd) for every biome
# into res://models/tiles/<biome>/<part>.res. Seeded, so a re-bake gives the same tiles. Run from the
# project folder after changing a biome or a recipe (then --import is not needed: .res files load as is):
#   Godot_v4.7.2-stable_win64.exe --headless --path . res://tools/make_voxel_tiles.tscn
# It runs as a scene (not --script) because VoxelTiles uses the project's classes.

extends Node

func _ready():
	var t := Time.get_ticks_msec()
	var total := 0
	for biome in VoxelTiles.BIOMES:
		var dir := VoxelTiles.DIR % biome
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
		for part in VoxelTiles.PARTS:
			var mesh := VoxelTiles.make(biome, part)
			var err := ResourceSaver.save(mesh, dir + part + ".res", ResourceSaver.FLAG_COMPRESS)
			if err != OK:
				push_error("could not save %s%s.res (%d)" % [dir, part, err])
			total += 1
		print("%-14s %d parts" % [biome, VoxelTiles.PARTS.size()])
	print("baked %d tiles in %d ms" % [total, Time.get_ticks_msec() - t])
	get_tree().quit()
