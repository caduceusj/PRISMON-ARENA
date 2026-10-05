extends Node
## Mostra a dica em tres tamanhos de texto. O tooltip so aparece sob o cursor,
## entao ele nunca apareceria num print automatico — este probe o forca.

func _ready() -> void:
	get_window().size = Vector2i(1000, 620)
	var bg := ColorRect.new()
	bg.theme = PrismaTheme.get_theme()
	bg.color = UI.BG
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var textos := [
		"Curto",
		"Presa Rachada — +12 ATK",
		"Pinto-Raio — Raio · Arcano · Meio\nHP 380 · ATK 34 · DEF 14 · VEL 1.7 · PE 88\nAplica 2 UA por golpe\n\n⚡ Arco Voltaico — Encadeia entre 3 inimigos aplicando 2 UA de Carga.",
	]
	var x := 30.0
	for t in textos:
		var camada := TooltipLayer.new()
		bg.add_child(camada)
		await get_tree().process_frame
		camada._mostrar(String(t))
		# o tamanho so existe depois do layout: dois quadros, como no jogo
		await get_tree().process_frame
		await get_tree().process_frame
		camada._painel.reset_size()
		camada._painel.position = Vector2(x, 40.0)
		camada._painel.modulate.a = 1.0
		camada._painel.scale = Vector2.ONE
		camada.set_process(false)
		print("  texto de %d chars -> painel %.0f x %.0f"
			% [String(t).length(), camada._painel.size.x, camada._painel.size.y])
		x += camada._painel.size.x + 20.0
	await get_tree().process_frame
	await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png("res://docs/probe_tip.png")
	get_tree().quit()
