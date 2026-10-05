class_name ScreenKitchen
extends Control
## A Cozinha: pratos pagos em ÉTER, e o jogador escolhe QUAL Prismon come
## (revisão 31/08, pedido do autor: "a comida deve alimentar somente um dos
## prismons em específico").
##
## A moeda virou Éter em 03/09, a pedido do autor: "junta tudo pra ser comprado
## via éter". A despensa era uma segunda moeda que só comprava comida — dava
## para acumular ingrediente de um elemento e nunca ver o prato dele no
## cardápio, e o contador no topo da tela media algo que ninguém sabia ler.
##
## Antes o prato ia para quem tivesse menos pratos — automático e sem decisão.
## Agora escolher o prato é meia decisão; a outra metade é para quem, porque o
## Estômago é limitado e o bônus é permanente.
##
## ESTRUTURA (03/09, autor: "faça a visualização das comidas igual as da loja
## e a de escolher um novo poder"): a mesma `PickPanel` — lista à esquerda,
## preview à direita. É onde ela rende mais, porque num prato a descrição É a
## decisão ("+10 ATK permanente" contra "muda a Afinidade da unidade"), e na
## lista antiga ela vinha espremida em duas linhas dentro do cartão.
##
## == O FOGO (15/09) ==
##
## Esta tela e a Feira tinham a MESMA caixa de conteúdo, ao pixel — 954x604 em
## (323,148) — e a revisão resumiu: "não há cenografia, não há fogo". Pior, a
## hierarquia estava invertida: no painel de quem come, a barra VERDE GRANDE era
## HP (que a Cozinha não altera) e o número que de fato decide, o Estômago, era
## cinza e pequeno.
##
## O cabeçalho desta tela é a MESA POSTA: um lugar por Prismon, com as vagas de
## Estômago desenhadas como vagas — as cheias com o prato que está lá, as livres
## com a célula `UI.slot()`, que é aresta tracejada e miolo na cor da mesa e lê
## como buraco. É a informação que a tela inteira existe para gastar, e agora
## ela aparece ANTES de o jogador escolher o prato, não depois.

signal finished

var _stock: Array = []
var _roll := 0
var _index := 0
var _picked := ""
var _panel: PickPanel


func setup(stock: Array, index: int) -> void:
	_stock = stock
	_index = index


func _ready() -> void:
	_build()


func _build() -> void:
	if _panel != null:
		# APAGA E DEPOIS LIBERA. `queue_free` e adiado ate o fim do quadro,
		# entao o painel antigo ficaria mais um quadro na arvore por baixo do
		# novo -- e a luz de sala e ADITIVA, logo a sala piscaria com o dobro
		# da forca a cada reconstrucao. `visible` e nao `remove_child` porque
		# isto roda DENTRO da emissao do `pressed` de um botao que vive no
		# painel antigo: esconder nao mexe na arvore, destacar mexe.
		_panel.visible = false
		_panel.queue_free()
	var price := EventGen.reroll_price("cozinha", _roll)
	_panel = PickPanel.new()
	_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_panel.sala = PickPanel.SALA_COZINHA
	_panel.title_text = "A PANELA ESTÁ NO FOGO"
	_panel.confirm_label = "COZINHAR"
	_panel.dismiss_label = "APAGAR O FOGO"
	_panel.list_title = "O CARDÁPIO"
	_panel.header_builder = _mesa_posta
	# O renovar da Cozinha fica na COLUNA e não no cabeçalho, ao contrário da
	# Feira: aqui o cabeçalho é a mesa, e trocar o cardápio é assunto do
	# cardápio. São duas telas parecidas que resolvem a mesma peça de dois
	# jeitos — que é exatamente o que faltava entre elas.
	_panel.reroll_label = "  TROCAR O CARDÁPIO · %d Éter  " % price
	_panel.reroll_enabled = Run.ether >= price

	for o in _stock:
		if bool(o.get("cooked", false)):
			continue
		var id := String(o["id"])
		var linha: Dictionary = o.duplicate()
		linha["kind_label"] = _kind_label(id)
		linha["icon"] = "dish_" + id
		linha["price"] = Run.dish_price(id)
		linha["color"] = String(Db.dishes[id].get("color", "#5cd6a0"))
		var why := _blocker(id)
		if why != "":
			linha["blocked"] = why
		_panel.offers.append(linha)

	_panel.chosen.connect(func(o): _open_picker(String(o["id"])))
	_panel.dismissed.connect(func(): finished.emit())
	_panel.rerolled.connect(_do_reroll)
	add_child(_panel)


## A MESA POSTA: um lugar por Prismon, e em cada lugar as vagas de Estômago.
##
## O Estômago é o teto de tudo que esta sala faz e ele nunca foi desenhado —
## aparecia como "estômago 1/3" em cinza pequeno, dentro do painel que abre
## DEPOIS de escolher o prato. Aqui ele é a primeira coisa embaixo do título,
## em forma e não em número: vaga cheia mostra o prato que está nela, vaga
## livre é a célula vaga do kit.
func _mesa_posta(col: VBoxContainer) -> void:
	var faixa := UI.card(UI.PANEL_HI, PickPanel.SALA_COZINHA.darkened(0.35))
	# ENCOLHE ATÉ O CONTEÚDO: uma placa da largura da mesa, e não uma barra de
	# 1180 px com dois medalhões perdidos no meio. É outra diferença de forma
	# entre esta tela e a Feira, cuja bolsa PRECISA da largura toda (o saldo
	# mora à esquerda e o renovar à direita).
	faixa.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	col.add_child(faixa)
	var v := UI.box(true, 8)
	faixa.add_child(v)
	v.add_child(UI.label("QUEM AINDA COME", UI.F_SMALL,
		UI.tint_of(PickPanel.SALA_COZINHA, true), HORIZONTAL_ALIGNMENT_CENTER))

	# GRADE DE DUAS COLUNAS, e não um HFlowContainer: dentro de uma placa que
	# encolhe até o conteúdo, o HFlow reporta como mínimo a sua disposição mais
	# ESTREITA — uma coluna só — e a mesa virava uma pilha. A grade não depende
	# da largura disponível, então a mesa tem sempre dois lados, com uma equipe
	# de dois ou de oito.
	var grade := GridContainer.new()
	grade.columns = 2
	grade.add_theme_constant_override("h_separation", 18)
	grade.add_theme_constant_override("v_separation", 8)
	v.add_child(grade)
	for u in Run.team:
		grade.add_child(_lugar(u))


## Um lugar na mesa: o retrato e as vagas de Estômago dele.
func _lugar(u: UnitInstance) -> Control:
	var cor := Db.el_color(u.element())
	var row := UI.box(false, 8)
	var med := MonsterPortrait.medallion(u.species_id, u.element(), 40.0)
	med.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	med.mouse_filter = Control.MOUSE_FILTER_STOP
	med.tooltip_text = "%s — Estômago %d/%d" % [u.display_name(),
		u.dishes_eaten(), u.estomago()]
	row.add_child(med)
	var vagas := UI.box(false, 4)
	vagas.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(vagas)
	for i in range(u.estomago()):
		vagas.add_child(_vaga(String(u.dishes[i]) if i < u.dishes.size() else "", cor))
	return row


## Uma vaga de Estômago. Cheia mostra o prato; livre é `UI.slot()` — aresta
## tracejada e miolo na cor da mesa, que lê como buraco e não como objeto.
## O conteúdo das duas tem o MESMO tamanho (16 px), então as caixas batem.
func _vaga(dish_id: String, cor: Color) -> Control:
	var p: PanelContainer = UI.slot() if dish_id == "" else UI.card(UI.LAJOTA_HI, cor)
	var mid := CenterContainer.new()
	p.add_child(mid)
	if dish_id == "":
		mid.add_child(UI.spacer(16.0, false))
	else:
		var ic := Icons.dish(dish_id, 16.0)
		ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
		mid.add_child(ic)
		p.tooltip_text = String(Db.dishes.get(dish_id, {}).get("name", ""))
	return p


## A palavra sob o nome. Separa o que ALIMENTA (bônus permanente, limitado pelo
## Estômago) do que REESCREVE (afinidade, esquecimento) — são duas coisas com
## regras diferentes, e a lista é onde essa diferença tem de aparecer.
func _kind_label(dish_id: String) -> String:
	return "Nutrição" if Db.dish_is_nutrition(dish_id) else "Transmutação"


## Por que não dá para cozinhar. Dito na cara — um botão apagado sem motivo é a
## mesma tela sem a informação que importa.
##
## A falta de Éter saiu daqui: ela vale para toda oferta com preço e mora em
## `PickPanel._motivo`, que é o que unificou a Feira com esta tela. Aqui ficam
## as três recusas que são da Cozinha, e duas delas são NOVAS — nasceram da
## regra de 15/09 e, sem esta função, apareceriam como um COZINHAR que não faz
## nada.
func _blocker(dish_id: String) -> String:
	if not Run.team.filter(func(u): return Run.unit_accepts(u, dish_id)).is_empty():
		return ""
	if String(Db.dishes.get(dish_id, {}).get("effect", "")) == "set_element":
		return "todos já têm um Núcleo — a Afinidade deles não muda mais"
	if Db.dish_is_nutrition(dish_id) \
			and Run.team.filter(func(u): return u.dishes.has(dish_id)).size() == Run.team.size():
		return "toda a equipe já comeu este prato — ele não acumula"
	return "nenhum Prismon com espaço no Estômago"


func _do_reroll() -> void:
	var price := EventGen.reroll_price("cozinha", _roll)
	if not Run.spend_ether(price):
		return
	UI.som("moeda")
	_roll += 1
	_stock = EventGen.kitchen_offer(_index, _roll)
	_picked = ""
	_build()


## O painel de escolha: aparece só quando há prato escolhido, escurece o
## fundo e sempre oferece Cancelar.
func _open_picker(dish_id: String) -> void:
	if _blocker(dish_id) != "" or not Run.can_afford_dish(dish_id):
		return
	_picked = dish_id
	var pk := PickerOverlay.new()
	pk.setup("Quem come %s?" % String(Db.dishes[dish_id]["name"]),
		"A comida alimenta um Prismon só, e o efeito é permanente.",
		func(u): return Run.unit_accepts(u, dish_id),
		func(u): return _estomago_de(u, dish_id))
	pk.picked.connect(func(u):
		pk.queue_free()
		_serve(u))
	pk.cancelled.connect(func():
		pk.queue_free()
		_picked = "")
	add_child(pk)


## O NÚMERO QUE DECIDE, e por isso ele é o que o painel escreve grande (ver
## `PickerOverlay`). "estômago 1/3" responde a pergunta da tela; "100% de HP"
## não responde nada, porque a Cozinha não mexe em HP.
func _estomago_de(u: UnitInstance, dish_id: String) -> String:
	if String(Db.dishes.get(dish_id, {}).get("effect", "")) == "set_element" and u.has_core():
		return "já usa um Núcleo"
	if Db.dish_is_nutrition(dish_id) and u.dishes.has(dish_id):
		return "já comeu este prato"
	return "Estômago %d/%d" % [u.dishes_eaten(), u.estomago()]


func _serve(u: UnitInstance) -> void:
	if _picked == "":
		return
	# GUISADO CROMÁTICO: "muda a Afinidade da unidade para o elemento
	# ESCOLHIDO" — e não havia onde escolher. `Run.cook()` recebia `pick`
	# vazio, caía em `forced_element = element()` e o prato não fazia nada:
	# cobrava o Éter, dizia que a Afinidade mudou, e a criatura continuava
	# igual. Agora o elemento é perguntado, como o autor pediu para os itens.
	if String(Db.dishes[_picked].get("effect", "")) == "set_element":
		var ep := ElementPicker.new()
		ep.setup("%s vira o quê?" % u.display_name(),
			"A Afinidade muda para sempre — e com ela as reações da equipe.",
			u.element())
		ep.picked.connect(func(el):
			ep.queue_free()
			_cozinhar(u, String(el)))
		ep.cancelled.connect(func():
			ep.queue_free()
			_picked = "")
		add_child(ep)
		return
	_cozinhar(u, "")


func _cozinhar(u: UnitInstance, pick: String) -> void:
	if _picked == "" or Run.cook(_picked, u, pick) == "":
		return
	UI.som("moeda")
	for o in _stock:
		if String(o["id"]) == _picked:
			o["cooked"] = true
	_picked = ""
	_build()
