extends Node3D
## One short-lived, occluded reaction bubble per person. Original Kenney CC0 art.

const TEXTURES := {
	"happy": preload("res://art/emotes/emote_faceHappy.png"),
	"angry": preload("res://art/emotes/emote_faceAngry.png"),
	"sad": preload("res://art/emotes/emote_faceSad.png"),
	"alert": preload("res://art/emotes/emote_exclamation.png"),
	"question": preload("res://art/emotes/emote_question.png"),
	"wave": preload("res://art/emotes/emote_dots3.png"),
	"music": preload("res://art/emotes/emote_music.png"),
	"cash": preload("res://art/emotes/emote_cash.png")
}

static func play(actor: Node3D, kind: String, duration: float = 2.4) -> Node3D:
	if not is_instance_valid(actor) or not actor.is_inside_tree(): return null
	if kind in ["exclamation", "detected", "report"]: kind = "alert"
	if not TEXTURES.has(kind): return null
	var old := actor.get_node_or_null("NPCEmote")
	if old:
		actor.remove_child(old)
		old.queue_free()
	var holder := Node3D.new()
	holder.name = "NPCEmote"
	holder.position.y = 3.25
	var model: Node3D = actor.get_meta("model") if actor.has_meta("model") else null
	if is_instance_valid(model): holder.position.y += model.position.y
	holder.set_meta("surface_base_y", 3.25)
	holder.set_meta("emote_kind", kind)
	actor.add_child(holder)
	var sprite := Sprite3D.new()
	sprite.texture = TEXTURES[kind]
	sprite.pixel_size = 0.039
	sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	sprite.shaded = false
	sprite.no_depth_test = false
	sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	sprite.modulate.a = 0.0
	sprite.scale = Vector3.ONE * 0.7
	holder.add_child(sprite)
	var tween := holder.create_tween()
	tween.set_parallel(true)
	tween.tween_property(sprite, "modulate:a", 1.0, 0.12)
	tween.tween_property(sprite, "scale", Vector3.ONE, 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.chain().tween_interval(maxf(0.15, duration - 0.55))
	tween.chain().tween_property(sprite, "modulate:a", 0.0, 0.35)
	tween.parallel().tween_property(sprite, "position:y", 0.24, 0.35)
	tween.chain().tween_callback(holder.queue_free)
	return holder
