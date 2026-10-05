extends Node
## Mostruário de TODOS os ícones mapeados em data/icons.json, com o nome ao lado.
## É a conferência de que cada nome caiu na imagem certa — o mapa foi feito a
## partir de um índice visual, não da ordem do README do pacote.

func _ready() -> void:
	get_window().size = Vector2i(1600, 900)
	var bg := ColorRect.new()
	bg.color = UI.BG
	bg.theme = PrismaTheme.get_theme()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var col := UI.box(true, 4)
	col.position = Vector2(16, 10)
	bg.add_child(col)
	col.add_child(UI.label("ÍCONES — Shikashi (conteúdo) e Kenney Board Game (glifos de sistema)",
		14, UI.TEXT))

	var grid := GridContainer.new()
	grid.columns = 6
	grid.add_theme_constant_override("h_separation", 16)
	grid.add_theme_constant_override("v_separation", 3)
	col.add_child(grid)

	var names: Array = Db.icons.get("icons", {}).keys()
	names.sort()
	for n in names:
		grid.add_child(_cell(String(n), Color.WHITE))
	for n2 in Db.icons.get("files", {}).keys():
		grid.add_child(_cell(String(n2), Db.el_color("RAIO")))

	var missing: Array = []
	for n3 in names:
		if Icons.tex(String(n3)) == null:
			missing.append(String(n3))
	col.add_child(UI.label("faltando: " + (", ".join(missing) if missing else "nenhum"),
		12, UI.BAD if not missing.is_empty() else UI.GOOD))

	await get_tree().process_frame
	await get_tree().process_frame
	# Sob --headless este sinal NUNCA retoma a corrotina: o processo gira
	# para sempre e nao escreve PNG nenhum (medido em 15/09, cinco tentativas
	# de ate 540 s). A espera existe para o quadro estar DESENHADO quando a
	# imagem for lida, e so ha o que esperar quando ha desenho.
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://shots/icon_probe.png")
	print("shots/icon_probe.png  —  %d ícones, %d faltando" % [names.size(), missing.size()])
	get_tree().quit(0)


func _cell(name: String, tint: Color) -> Control:
	var row := UI.box(false, 6)
	row.add_child(Icons.node(name, 26.0, tint))
	row.add_child(UI.label(name, 11, UI.TEXT_DIM))
	return row
