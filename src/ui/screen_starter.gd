class_name ScreenStarter
extends Control
## Escolha dos INICIAIS: o jogador monta a dupla que abre a jornada.
## A tela ensina o sistema antes do primeiro combate: ao marcar dois, ela mostra
## quais REAÇÕES a dupla produz — a decisão já é sobre a máquina, não só sobre
## a criatura bonita.

signal confirmed(ids: Array)

var _picked: Array = []
var _cards: Dictionary = {}
var _rx_row: HFlowContainer
var _hint: Label
var _btn: Button


## A SALA DOS INICIAIS: verde-musgo de criadouro. É a única tela em que ninguém
## está lutando e ninguém está comprando — só escolhendo com quem começar.
## Vem de `data/paleta.json` (salas.iniciais) desde 17/09.
static var SALA: Color:
	get: return UI.cor_da_sala("iniciais")


func _ready() -> void:
	add_child(UI.luz_de_sala(SALA))
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var col := UI.box(true, 12)
	col.custom_minimum_size = Vector2(1300, 0)
	center.add_child(col)

	# LARGURA ÚNICA DA FAIXA (UI.BANNER_W = 1180, a mesma BAR_W do combate).
	# Eram seis larguras medidas, de 688 a 1412 px, para o único elemento que
	# aparece em todas as telas — aqui ela vinha esticada nos 1300 da coluna.
	var bn := UI.banner("ESCOLHA SEUS INICIAIS", SALA)
	bn.custom_minimum_size.x = UI.BANNER_W
	bn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	col.add_child(bn)
	col.add_child(UI.label("Dois companheiros abrem a jornada. Os outros aparecem pelo caminho.",
		13, UI.TEXT_DIM, HORIZONTAL_ALIGNMENT_CENTER))
	col.add_child(UI.spacer(4, false))

	var row := UI.box(false, 12)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_child(row)
	for id in Db.base_species:
		var c := _card(String(id))
		_cards[String(id)] = c
		row.add_child(c)

	col.add_child(UI.spacer(6, false))
	var rx_head := UI.box(false, 8)
	rx_head.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_child(rx_head)
	rx_head.add_child(UI.label("O QUE ESTA DUPLA PRODUZ", 11, UI.TEXT_DIM))
	_rx_row = HFlowContainer.new()
	_rx_row.alignment = FlowContainer.ALIGNMENT_CENTER
	_rx_row.add_theme_constant_override("h_separation", 14)
	col.add_child(_rx_row)
	_hint = UI.label("", 12, UI.TEXT_DIM, HORIZONTAL_ALIGNMENT_CENTER)
	col.add_child(_hint)

	_btn = UI.button_confirmar("  COMEÇAR A JORNADA  ", UI.F_H2)
	_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_btn.custom_minimum_size = Vector2(420, 0)
	_btn.disabled = true
	_btn.pressed.connect(func(): confirmed.emit(_picked.duplicate()))
	col.add_child(_btn)
	_refresh()


func _card(id: String) -> Control:
	var s := Db.sp(id)
	var el := String(s.get("element", "FOGO"))
	var c := Db.el_color(el)

	# CardButton, nao Button com filhos ancorados. Esta era a QUARTA aparicao do
	# mesmo padrao (cozinha, seletor de Prismon, recruta, e aqui): um filho
	# ancorado no retangulo do Button ignora o content_margin do StyleBox
	# 9-patch, entao o conteudo encosta na moldura ou vaza por cima dela, e o
	# Button nao cresce com o conteudo — a altura tinha de ser adivinhada a mao
	# (era Vector2(238, 214), um numero que so valia para o texto de hoje).
	# A LAJOTA É DO CRIADOURO, O FEIXE É DA CRIATURA. A matéria do cartão
	# carrega o verde do lugar (era `UI.PANEL`, a mesma lajota roxa das outras
	# nove telas); quem continua dizendo Fogo, Gelo ou Raio é a aresta, o nome e
	# o ícone — ou seja, o que o jogador está comparando não perdeu cor nenhuma.
	var card := CardButton.make(UI.materia_da_sala(UI.PANEL, SALA), c)
	card.custom_minimum_size = Vector2(238, 0)
	card.tooltip_text = _detail(id)
	card.clicked.connect(_toggle.bind(id))

	var v := card.body
	v.add_theme_constant_override("separation", 6)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	var port := MonsterPortrait.make(id, el, 64.0)
	port.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	v.add_child(port)
	v.add_child(UI.label(Db.sp_name(id), UI.F_H2, c.lightened(0.3),
		HORIZONTAL_ALIGNMENT_CENTER))

	# Mesma grade de duas colunas do cartao de recruta: as duas linhas de
	# informacao centradas como BLOCO, com o icone na MESMA coluna. Centradas
	# uma a uma, os dois icones caiam em x diferentes porque as frases tem
	# larguras diferentes.
	var info := GridContainer.new()
	info.columns = 2
	info.add_theme_constant_override("h_separation", 7)
	info.add_theme_constant_override("v_separation", 4)
	info.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	v.add_child(info)
	var px := UI.icon_px(UI.F_SMALL)
	info.add_child(Icons.element(el, px))
	info.add_child(_info_line("%s · %s" % [Db.el_name(el),
		Db.role_name(String(s.get("role", "")))], UI.TEXT_DIM))
	info.add_child(Icons.node("g_sword", px, UI.ACCENT.lightened(0.2)))
	info.add_child(_info_line(String(s.get("ult", {}).get("name", "")),
		UI.ACCENT.lightened(0.2)))
	return card


## Linha da grade de informacao: encostada no icone da coluna ao lado em vez
## de flutuar acima dele.
func _info_line(text: String, color: Color) -> Label:
	var l := UI.label(text, UI.F_SMALL, color)
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return l


func _detail(id: String) -> String:
	var s := Db.sp(id)
	return "%s — %s · %s · %s\nHP %d · ATK %d · DEF %d · VEL %.1f · PE %d\nAplica %d UA por golpe\n\n⚡ %s — %s" % [
		Db.sp_name(id), Db.el_name(String(s.get("element", ""))),
		Db.role_name(String(s.get("role", ""))), String(s.get("stance", "")),
		int(s.get("hp", 0)), int(s.get("atk", 0)), int(s.get("def", 0)),
		float(s.get("vel", 1.0)), int(s.get("pe", 0)), int(s.get("ua_per_hit", 2)),
		String(s.get("ult", {}).get("name", "")), String(s.get("ult", {}).get("text", ""))]


func _toggle(id: String) -> void:
	if _picked.has(id):
		_picked.erase(id)
	elif _picked.size() < 2:
		_picked.append(id)
	else:
		# terceiro clique: troca o mais antigo — sem estado de erro
		_picked.pop_front()
		_picked.append(id)
	_refresh()


func _refresh() -> void:
	for id in _cards.keys():
		# o proprio cartao sabe se pintar de selecionado — nada de trocar
		# StyleBox por fora, que era como a moldura de escolha divergia da
		# usada pela cozinha e pelo seletor de Prismon
		var card: CardButton = _cards[id]
		card.set_selected(_picked.has(id))

	for c in _rx_row.get_children():
		_rx_row.remove_child(c)
		c.queue_free()
	_btn.disabled = _picked.size() != 2
	if _picked.size() < 2:
		_hint.text = "Escolha %d criatura(s)." % (2 - _picked.size())
		return
	var els: Array = []
	for id in _picked:
		var e := String(Db.sp(String(id)).get("element", ""))
		if not els.has(e):
			els.append(e)
	var links := Db.reactions_between(els)
	var seen: Dictionary = {}
	for l in links:
		var rid := String(l["reaction"]["id"])
		if seen.has(rid):
			continue
		seen[rid] = true
		var r := UI.box(false, 5)
		var ic := Icons.node("rx_" + rid, 16.0)
		if ic.texture != null:
			r.add_child(ic)
		r.add_child(UI.label(String(l["reaction"]["name"]), UI.F_BODY,
			Color(String(l["reaction"]["color"])).lightened(0.15)))
		_rx_row.add_child(r)
	if seen.is_empty():
		_hint.text = "Essa dupla não produz reações sozinha — vai depender dos recrutas do caminho."
	else:
		_hint.text = "Reações vêm de elementos diferentes se atingindo. Os recrutas do caminho ampliam a máquina."
