extends Node
## A LISTA CORTA LINHA NO MEIO?
##
## Na loja "La Condutora" aparecia pela metade, e na preparacao "Presa Rachada"
## tambem — o que le como quebrado, nao como rolavel. Aqui se mede a caixa de
## rolagem e as linhas dentro dela, para saber QUANTO sobra e nao chutar.

func _ready() -> void:
	Juice.enabled = false
	get_window().size = Vector2i(1600, 900)
	var bg := ColorRect.new()
	bg.theme = PrismaTheme.build()
	bg.color = UI.BG
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	Run.start_run(99)
	Run.set_starting_team(["sheep", "apollo"])
	var tela := ScreenShop.new()
	tela.setup(EventGen.shop_offer(4), 4)
	tela.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.add_child(tela)
	for i in 6:
		await get_tree().process_frame

	var scroll := _achar(tela, "ScrollContainer") as ScrollContainer
	if scroll == null:
		print("nao achei o ScrollContainer")
		get_tree().quit(1)
		return
	print("caixa de rolagem: %.0f px de altura" % scroll.size.y)
	var lista: Control = null
	for f in scroll.get_children():
		if f is Control:
			lista = _primeiro_vbox(f)
	if lista == null:
		print("nao achei a lista")
		get_tree().quit(1)
		return
	var passo := 0.0
	var n := 0
	for r in lista.get_children():
		if r is Control and (r as Control).size.y > 1.0:
			n += 1
			if n == 1:
				passo = (r as Control).size.y
			print("   linha %d  y=%.0f  altura=%.0f  fim=%.0f%s" % [n,
				(r as Control).position.y, (r as Control).size.y,
				(r as Control).position.y + (r as Control).size.y,
				"   <- CORTADA" if (r as Control).position.y
					+ (r as Control).size.y > scroll.size.y + 0.5 else ""])
	var sep: float = float(lista.get_theme_constant("separation"))
	var pitch: float = passo + sep
	var cabem: float = (scroll.size.y + sep) / maxf(pitch, 1.0)
	print("passo da linha: %.0f px (linha %.0f + separacao %.0f)" % [pitch, passo, sep])
	print("cabem %.2f linhas" % cabem)

	var falhas := 0
	# A LINHA NAO PODE PASSAR DE ROW_H. Se o conteudo crescer, a conta de
	# linhas inteiras deixa de fechar e a ultima volta a sair cortada — e
	# ninguem percebe ate virar print.
	if absf(passo - PickPanel.ROW_H) > 0.5:
		falhas += 1
		print("  LINHA FORA: %.0f px, mas PickPanel.ROW_H e %.0f"
			% [passo, PickPanel.ROW_H])
	# a caixa tem de caber um numero INTEIRO de linhas
	if absf(cabem - round(cabem)) > 0.02:
		falhas += 1
		print("  CAIXA FORA: cabem %.2f linhas — a fracao e a linha cortada" % cabem)
	print("=> %s" % ("OK" if falhas == 0 else "FALHOU (%d)" % falhas))
	get_tree().quit(0 if falhas == 0 else 1)


func _achar(no: Node, classe: String) -> Node:
	if no.get_class() == classe:
		return no
	for f in no.get_children():
		var r := _achar(f, classe)
		if r != null:
			return r
	return null


func _primeiro_vbox(no: Node) -> Control:
	if no is VBoxContainer and no.get_child_count() > 0:
		return no as Control
	for f in no.get_children():
		var r := _primeiro_vbox(f)
		if r != null:
			return r
	return null
