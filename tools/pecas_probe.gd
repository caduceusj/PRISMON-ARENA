extends Node
## FOLHA DE PECAS para o documento da artista.
##
## Recortar peca de um print da tela dava recorte torto — borda cortada, meio
## botao de fora. Aqui cada peca e construida pelas MESMAS funcoes que o jogo
## usa e desenhada numa placa propria, sobre fundo neutro, com o rotulo ao lado
## e o tamanho medido impresso no terminal. Nada de recorte: a captura e a
## janela inteira, entao nao ha retangulo para errar.

const FUNDO := Color(0.09, 0.08, 0.13)
const LARG := 960
const ALT := 620

var _raiz: ColorRect


func _ready() -> void:
	Juice.enabled = false
	get_window().size = Vector2i(LARG, ALT)
	DirAccess.make_dir_recursive_absolute("res://docs/pecas")
	Run.start_run(7)
	Run.set_starting_team(["sheep", "apollo"])

	await _placa("botoes", _monta_botoes)
	await _placa("paineis", _monta_paineis)
	await _placa("barras", _monta_barras)
	await _placa("linhas", _monta_linhas)
	await _placa("icones", _monta_icones)
	get_tree().quit(0)


func _placa(arquivo: String, monta: Callable) -> void:
	if _raiz != null:
		_raiz.queue_free()
		await get_tree().process_frame
	_raiz = ColorRect.new()
	_raiz.theme = PrismaTheme.build()
	_raiz.color = FUNDO
	_raiz.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_raiz)

	var m := MarginContainer.new()
	m.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for lado in ["left", "right", "top", "bottom"]:
		m.add_theme_constant_override("margin_" + lado, 30)
	_raiz.add_child(m)
	var col := UI.box(true, 18)
	m.add_child(col)
	monta.call(col)

	for i in 6:
		await get_tree().process_frame
	print("[%s]" % arquivo)
	_medir(col)
	get_viewport().get_texture().get_image().save_png(
		"res://docs/pecas/%s.png" % arquivo)


## Imprime o tamanho de cada peca marcada com a meta "peca".
func _medir(no: Node) -> void:
	if no is Control and no.has_meta("peca"):
		var c := no as Control
		print("  %-28s %.0f x %.0f px" % [String(no.get_meta("peca")),
			c.size.x, c.size.y])
	for f in no.get_children():
		_medir(f)


## Uma linha da placa: o rotulo a esquerda, a peca a direita.
func _item(col: Control, rotulo: String, peca: Control, nome: String) -> void:
	var linha := UI.box(false, 20)
	var r := UI.label(rotulo, UI.F_SMALL, UI.TEXT_DIM)
	r.custom_minimum_size = Vector2(220, 0)
	r.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	linha.add_child(r)
	var berco := CenterContainer.new()
	berco.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	berco.add_child(peca)
	linha.add_child(berco)
	peca.set_meta("peca", nome)
	col.add_child(linha)


func _monta_botoes(col: Control) -> void:
	col.add_child(UI.label("BOTÕES", UI.F_H1, UI.GOLD))
	var estados := [["parado", "normal"], ["sob o cursor", "hover"],
		["apertado", "pressed"], ["desligado", "disabled"]]
	for e in estados:
		var b := UI.button("  COMPRAR  ", UI.F_BODY, UI.ACCENT)
		if String(e[1]) != "normal":
			b.add_theme_stylebox_override("normal", b.get_theme_stylebox(String(e[1])))
		_item(col, String(e[0]), b, "botão %s" % String(e[0]))
	var c := UI.button("  LUTAR!  ", UI.F_H2, UI.GOOD)
	_item(col, "de confirmar", c, "botão de confirmar")
	var d := UI.button("  DISPENSAR  ", UI.F_BODY)
	_item(col, "secundário", d, "botão secundário")


func _monta_paineis(col: Control) -> void:
	col.add_child(UI.label("PAINÉIS", UI.F_H1, UI.GOLD))
	var casos := [["cartão", UI.card()], ["destaque", UI.card_gold()]]
	for c in casos:
		var p: PanelContainer = c[1]
		var v := UI.box(true, 6)
		v.add_child(UI.label("FORMAÇÃO PREVISTA", UI.F_SMALL, UI.TEXT_DIM))
		v.add_child(UI.label("Conteúdo do painel", UI.F_BODY, UI.TEXT))
		p.add_child(v)
		p.custom_minimum_size = Vector2(340, 0)
		_item(col, String(c[0]), p, "painel %s" % String(c[0]))


func _monta_barras(col: Control) -> void:
	col.add_child(UI.label("BARRAS", UI.F_H1, UI.GOLD))
	for cor in ["green", "red", "blue", "yellow"]:
		var b := PrismaBar.make(cor, 18)
		b.custom_minimum_size = Vector2(340, 18)
		b.set_value(0.68, 1.0)
		_item(col, "%s · 18 px" % cor, b, "barra %s 18 px" % cor)
	var g := PrismaBar.make("green", 36)
	g.custom_minimum_size = Vector2(340, 36)
	g.set_value(0.68, 1.0)
	_item(col, "green · 36 px", g, "barra green 36 px")


func _monta_linhas(col: Control) -> void:
	col.add_child(UI.label("LINHAS DE LISTA", UI.F_H1, UI.GOLD))
	var ofertas := EventGen.shop_offer(4)
	for est in [["parada", false], ["escolhida", true]]:
		var l := _linha_solta(ofertas[0], bool(est[1]))
		_item(col, String(est[0]), l, "linha %s" % String(est[0]))
	if ofertas.size() > 1:
		var l2 := _linha_solta(ofertas[1], false)
		_item(col, "outra oferta", l2, "linha (outro item)")


func _linha_solta(o: Dictionary, ligada: bool) -> Control:
	var cor := UI.ACCENT
	var card := CardButton.make(UI.PANEL, cor).as_list_row()
	card.custom_minimum_size = Vector2(430, 90)
	card.set_selected(ligada)
	var row := UI.box(false, 10)
	card.body.add_child(row)
	row.add_child(Icons.node(String(o.get("icon", "ether")), 32.0, cor))
	var v := UI.box(true, 1)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(v)
	v.add_child(UI.label(String(o.get("name", "Item")), UI.F_BODY, cor.lightened(0.3)))
	v.add_child(UI.label(String(o.get("kind_label", "Item · Comum")), UI.F_SMALL, UI.TEXT_DIM))
	var pr := UI.box(false, 4)
	pr.alignment = BoxContainer.ALIGNMENT_END
	pr.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	pr.add_child(Icons.node("ether", 16.0, UI.GOLD))
	pr.add_child(UI.label(str(int(o.get("price", 11))), UI.F_BODY, UI.GOLD))
	row.add_child(pr)
	return card


func _monta_icones(col: Control) -> void:
	col.add_child(UI.label("ÍCONES · 32 px", UI.F_H1, UI.GOLD))
	# Db.icons e o arquivo inteiro: o mapa de nomes esta em `icons`, e os PNGs
	# soltos em `files`. Pegar as chaves do topo devolvia cinco secoes.
	var nomes: Array = []
	for k in Db.icons.get("icons", {}).keys():
		nomes.append(String(k))
	for k in Db.icons.get("files", {}).keys():
		nomes.append(String(k))
	nomes.sort()
	var grade := GridContainer.new()
	grade.columns = 14
	grade.add_theme_constant_override("h_separation", 16)
	grade.add_theme_constant_override("v_separation", 16)
	var n := 0
	for id in nomes:
		if n >= 70:
			break
		var ic := Icons.node(String(id), 32.0, UI.TEXT)
		if ic == null:
			continue
		grade.add_child(ic)
		n += 1
	col.add_child(grade)
	print("  %d ícones desenhados (de %d no mapa)" % [n, nomes.size()])
