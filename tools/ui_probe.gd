extends Node
## Avaliação de cada imagem do pacote ANTES de aplicá-la.
##
## Um 9-patch só quebra em tamanhos extremos: numa linha baixa a borda come o
## miolo, num quadrado pequeno os cantos se sobrepõem, e numa faixa larga a
## decoração de canto vira um risco. Este probe desenha cada peça em quatro
## tamanhos de uma vez, para o defeito aparecer aqui e não na tela do jogo.

const SIZES := [
	Vector2(880, 38),    # linha de lista (o caso mais apertado)
	Vector2(300, 120),   # cartão
	Vector2(120, 34),    # botão
	Vector2(44, 44),     # quadrado pequeno
]

func _ready() -> void:
	get_window().size = Vector2i(1600, 900)
	var bg := ColorRect.new()
	bg.color = UI.BG
	bg.theme = PrismaTheme.get_theme()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var root := UI.box(false, 24)
	root.position = Vector2(18, 14)
	bg.add_child(root)

	var left := UI.box(true, 7)
	root.add_child(left)
	left.add_child(UI.label("MOLDURAS 9-PATCH — mesma peça em 4 tamanhos", 14, UI.TEXT))
	var names := ["panel", "panel_hi", "inset", "gold", "danger", "confirm", "focus", "slot"]
	for i in range(names.size()):
		var row := UI.box(false, 8)
		left.add_child(row)
		var tag := UI.label(names[i], 11, UI.TEXT_DIM)
		tag.custom_minimum_size = Vector2(64, 0)
		row.add_child(tag)
		for s in SIZES:
			var p := PanelContainer.new()
			p.add_theme_stylebox_override("panel", UI.frame(i))
			p.custom_minimum_size = s * Vector2(0.62, 1.0)
			row.add_child(p)

	var right := UI.box(true, 10)
	root.add_child(right)
	right.add_child(UI.label("PEÇAS MONTADAS", 14, UI.TEXT))
	right.add_child(UI.label("faixa — só estica na horizontal", 11, UI.TEXT_DIM))
	for w in [520, 300, 190]:
		var b := UI.banner("Título de %d px" % w)
		b.custom_minimum_size = Vector2(w, UI.BANNER_H)
		b.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		right.add_child(b)

	right.add_child(UI.label("barra", 11, UI.TEXT_DIM))
	for v in [1.0, 0.55, 0.12]:
		var pb := UI.bar("blue", 20)
		pb.ratio = v
		pb.custom_minimum_size = Vector2(520, 20)
		right.add_child(pb)

	right.add_child(UI.label("medalhão", 11, UI.TEXT_DIM))
	var mrow := UI.box(false, 8)
	right.add_child(mrow)
	for d in [76.0, 58.0, 44.0, 32.0]:
		mrow.add_child(MonsterPortrait.medallion("faulha", "FOGO", d))
	mrow.add_child(MonsterPortrait.medallion("nevisco", "GELO", 58.0, true))

	right.add_child(UI.label("controles com o Theme aplicado", 11, UI.TEXT_DIM))
	var crow := UI.box(false, 8)
	right.add_child(crow)
	var b1 := Button.new()
	b1.text = "Button cru"
	crow.add_child(b1)
	crow.add_child(UI.button("UI.button", UI.F_BODY, Db.el_color("FOGO")))
	var le := LineEdit.new()
	le.placeholder_text = "LineEdit"
	le.custom_minimum_size = Vector2(150, 0)
	crow.add_child(le)
	var pb2 := ProgressBar.new()
	pb2.value = 60
	pb2.custom_minimum_size = Vector2(150, 0)
	crow.add_child(pb2)

	# tooltip: a engine cria esse painel sozinha a partir de `tooltip_text`.
	# Aqui ele e montado a mao com os MESMOS tipos do Theme, so para inspecao.
	right.add_child(UI.label("tooltip (TooltipPanel + TooltipLabel)", 11, UI.TEXT_DIM))
	var th := PrismaTheme.get_theme()
	var tip := PanelContainer.new()
	tip.add_theme_stylebox_override("panel", th.get_stylebox("panel", "TooltipPanel"))
	tip.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	var tl := Label.new()
	tl.text = "Faúlha — Fogo · Arcano · Meio
HP 390 · ATK 36 · DEF 15 · VEL 1.5 · PE 85

⚡ Lança de Chama — Dano alto + 4 UA de Combustão."
	tl.add_theme_color_override("font_color", th.get_color("font_color", "TooltipLabel"))
	tl.add_theme_font_size_override("font_size", th.get_font_size("font_size", "TooltipLabel"))
	tip.add_child(tl)
	right.add_child(tip)

	right.add_child(UI.label("ScrollContainer com barra", 11, UI.TEXT_DIM))
	var sc := ScrollContainer.new()
	sc.custom_minimum_size = Vector2(520, 86)
	right.add_child(sc)
	var inner := UI.box(true, 4)
	inner.custom_minimum_size = Vector2(496, 0)
	sc.add_child(inner)
	for i in range(10):
		inner.add_child(UI.label("linha %d dentro de um ScrollContainer" % i, 13))

	await get_tree().process_frame
	await get_tree().process_frame
	# Sob --headless este sinal NUNCA retoma a corrotina: o processo gira
	# para sempre e nao escreve PNG nenhum (medido em 15/09, cinco tentativas
	# de ate 540 s). A espera existe para o quadro estar DESENHADO quando a
	# imagem for lida, e so ha o que esperar quando ha desenho.
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://shots/ui_probe.png")
	print("shots/ui_probe.png")
	get_tree().quit(0)
