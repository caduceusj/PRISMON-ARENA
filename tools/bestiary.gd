extends Node
## Mostruário das 5 criaturas: idle, os 6 quadros de walk e os 18 de attack,
## com o QUADRO DE DANO destacado — é a conferência visual de que o golpe sai
## no quadro que o autor pediu (13/11/11/11/12).

class Strip extends Control:
	var species := "apollo"
	var anim := "attack"
	var frame_px := 44.0
	var hit := -1

	func _draw() -> void:
		var n := MonsterArt.frames_of(anim)
		for i in range(n):
			var x: float = float(i) * (frame_px + 4.0) + frame_px * 0.5
			if i == hit - 1:
				draw_rect(Rect2(x - frame_px * 0.5 - 2, 0, frame_px + 4, frame_px + 4),
					Color(1.0, 0.35, 0.3, 0.25))
				draw_rect(Rect2(x - frame_px * 0.5 - 2, 0, frame_px + 4, frame_px + 4),
					Color(1.0, 0.45, 0.35), false, 2.0)
			MonsterArt.draw_anim(self, species, anim, i,
				Vector2(x, frame_px * 0.55), frame_px * 0.9, -1.0)


func _ready() -> void:
	get_window().size = Vector2i(1600, 900)
	var bg := ColorRect.new()
	bg.color = UI.BG
	bg.theme = PrismaTheme.get_theme()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var col := UI.box(true, 4)
	col.position = Vector2(18, 10)
	bg.add_child(col)
	col.add_child(UI.label("ELENCO DE TESTE — 5 criaturas · quadro de dano destacado no ataque", 15, UI.TEXT))

	for id in ["apollo", "coalla", "hipocampo", "pinto_raio", "sheep"]:
		var c: Dictionary = Db.anims["creatures"][id]
		var row := UI.box(false, 10)
		col.add_child(row)
		var head := UI.box(true, 0)
		head.custom_minimum_size = Vector2(150, 0)
		row.add_child(head)
		head.add_child(UI.label(Db.sp_name(id), UI.F_H2,
			Db.el_color(String(Db.sp(id).get("element", "FOGO")))))
		head.add_child(UI.label("%s · golpe no quadro %d" % [
			String(Db.sp(id).get("role", "")), int(c["hit_frame"])], 10, UI.TEXT_DIM))
		var strip := Strip.new()
		strip.species = id
		strip.anim = "attack"
		strip.hit = int(c["hit_frame"])
		strip.custom_minimum_size = Vector2(18.0 * 48.0, 52.0)
		strip.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		row.add_child(strip)

		var row2 := UI.box(false, 10)
		col.add_child(row2)
		var pad := Control.new()
		pad.custom_minimum_size = Vector2(150, 0)
		row2.add_child(pad)
		var walk := Strip.new()
		walk.species = id
		walk.anim = "walk"
		walk.custom_minimum_size = Vector2(6.0 * 48.0, 46.0)
		walk.frame_px = 38.0
		walk.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		row2.add_child(walk)
		var idle := Strip.new()
		idle.species = id
		idle.anim = "idle"
		idle.custom_minimum_size = Vector2(12.0 * 42.0, 46.0)
		idle.frame_px = 38.0
		idle.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		row2.add_child(idle)

	await get_tree().process_frame
	await get_tree().process_frame
	# Sob --headless este sinal NUNCA retoma a corrotina: o processo gira
	# para sempre e nao escreve PNG nenhum (medido em 15/09, cinco tentativas
	# de ate 540 s). A espera existe para o quadro estar DESENHADO quando a
	# imagem for lida, e so ha o que esperar quando ha desenho.
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://shots/12_bestiario.png")
	print("shots/12_bestiario.png")
	get_tree().quit(0)
