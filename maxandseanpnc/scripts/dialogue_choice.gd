extends Resource
class_name DialogueChoice
## One selectable dialogue option and the character's response.
## Create these as DialogueChoice resources and assign them to an NPC.

@export var id: StringName = &""
@export_multiline var option_text: String = ""
@export_multiline var response_text: String = ""
