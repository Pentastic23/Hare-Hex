# campaign_chapter.gd
class_name CampaignChapter extends Resource

@export var id: StringName
@export var display_name := ""
@export_multiline var description := ""
@export var levels: Array[CampaignLevel] = []
