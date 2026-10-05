extends Node
## Qual e o corpo NATIVO da m6x11plus?
##
## O nome sugere 11 px (a altura da caixa alta), mas a metrica diz outra coisa:
## unitsPerEm = 1152 e cada pixel da grade ocupa 64 unidades, logo o "em" tem
## 1152/64 = 18 pixels. Se isso estiver certo, os tamanhos limpos sao multiplos
## de 18 — e os de 11 que eu adotei estao todos fora da grade.

const TXT := "Coração · REAÇÕES ×3 · Vínculo · 2886 · Éter · Muralha"


func _f(path: String, fb: Font = null) -> FontFile:
	var f := FontFile.new()
	f.load_dynamic_font(path)
	f.antialiasing = TextServer.FONT_ANTIALIASING_NONE
	f.hinting = TextServer.HINTING_NONE
	f.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_DISABLED
	if fb != null:
		f.fallbacks = [fb]
	return f


func _ready() -> void:
	get_window().size = Vector2i(1750, 1000)
	var bg := ColorRect.new()
	bg.color = UI.BG
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var plus := _f("res://assets/fonts/m6x11plus.ttf",
		_f("res://assets/fonts/PixelifySans.ttf"))

	var col := UI.box(true, 12)
	col.position = Vector2(24, 14)
	col.custom_minimum_size = Vector2(1700, 0)
	bg.add_child(col)
	col.add_child(UI.label("m6x11plus — 18 é o corpo nativo?  (upem 1152 ÷ 64 un/px = 18)", 18, UI.TEXT))

	var a: PanelContainer = UI.card(UI.PANEL, UI.GOOD)
	col.add_child(a)
	var av: BoxContainer = UI.box(true, 5)
	a.add_child(av)
	av.add_child(UI.label("MÚLTIPLOS DE 18", 14, UI.GOOD))
	for sz in [18, 36, 54]:
		av.add_child(_l(plus, sz, UI.TEXT))

	var b: PanelContainer = UI.card(UI.PANEL, UI.WARN)
	col.add_child(b)
	var bv: BoxContainer = UI.box(true, 5)
	b.add_child(bv)
	bv.add_child(UI.label("MÚLTIPLOS DE 11 — o que está no jogo agora", 14, UI.WARN))
	for sz in [22, 33, 44]:
		bv.add_child(_l(plus, sz, UI.TEXT))

	var c: PanelContainer = UI.card(UI.PANEL, UI.ACCENT)
	col.add_child(c)
	var cv: BoxContainer = UI.box(true, 5)
	c.add_child(cv)
	cv.add_child(UI.label("ESCALA CANDIDATA — 18 / 27 / 36 / 54", 14, UI.ACCENT.lightened(0.2)))
	for sz in [18, 27, 36, 54]:
		cv.add_child(_l(plus, sz, UI.TEXT))

	await get_tree().process_frame
	await get_tree().process_frame
	# Sob --headless este sinal NUNCA retoma a corrotina: o processo gira
	# para sempre e nao escreve PNG nenhum (medido em 15/09, cinco tentativas
	# de ate 540 s). A espera existe para o quadro estar DESENHADO quando a
	# imagem for lida, e so ha o que esperar quando ha desenho.
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://shots/15_corpo.png")
	print("shots/15_corpo.png")
	get_tree().quit(0)


func _l(f: Font, sz: int, c: Color) -> Label:
	var l := Label.new()
	l.text = "%2dpx  %s" % [sz, TXT]
	l.add_theme_font_override("font", f)
	l.add_theme_font_size_override("font_size", sz)
	l.add_theme_color_override("font_color", c)
	return l
