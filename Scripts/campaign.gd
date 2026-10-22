# campaign.gd
class_name Campaign extends Resource

# Chapters in order, each with levels in order. Levels unlock one after another:
# the very first level is always open, every other level needs the one before it completed.

@export var display_name := ""
@export var chapters: Array[CampaignChapter] = []

func all_levels() -> Array[CampaignLevel]:
	var out: Array[CampaignLevel] = []
	for ch in chapters:
		if ch == null:
			continue
		for level in ch.levels:
			if level != null:
				out.append(level)
	return out

func find_level(id: StringName) -> CampaignLevel:
	for level in all_levels():
		if level.id == id:
			return level
	return null

func next_level(level: CampaignLevel) -> CampaignLevel:
	var list := all_levels()
	var i := list.find(level)
	if i == -1 or i + 1 >= list.size():
		return null
	return list[i + 1]

# The next level in the same chapter, or null at the end of a chapter (runs don't cross chapters).
func next_in_chapter(level: CampaignLevel) -> CampaignLevel:
	var ch := chapter_of(level)
	if ch == null:
		return null
	var i := ch.levels.find(level)
	if i == -1 or i + 1 >= ch.levels.size():
		return null
	return ch.levels[i + 1]

func first_of_chapter(level: CampaignLevel) -> CampaignLevel:
	var ch := chapter_of(level)
	if ch == null or ch.levels.is_empty():
		return level
	return ch.levels[0]

func chapter_of(level: CampaignLevel) -> CampaignChapter:
	for ch in chapters:
		if ch != null and ch.levels.has(level):
			return ch
	return null

# Authoring check for the whole campaign: every level's validate() plus duplicate ids.
func validate() -> PackedStringArray:
	var out: PackedStringArray = []
	var ids := {}
	for ch in chapters:
		if ch == null:
			out.append("Campaign: empty chapter slot")
			continue
		if ch.id == &"":
			out.append("Chapter '%s': missing id" % ch.display_name)
		if ch.levels.is_empty():
			out.append("Chapter '%s': no levels" % ch.display_name)
	for level in all_levels():
		if level.id != &"" and ids.has(level.id):
			out.append("Level id '%s' is used twice (save progress would mix them up)" % level.id)
		ids[level.id] = true
		out.append_array(level.validate())
	return out

func is_unlocked(level: CampaignLevel) -> bool:
	var list := all_levels()
	var i := list.find(level)
	if i <= 0:
		return i == 0
	return SaveGame.is_level_complete(list[i - 1].id)
