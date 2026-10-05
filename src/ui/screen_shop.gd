class_name ScreenShop
extends Control
## A Feira: itens PERMANENTES, pagos em Éter. Três ofertas e um botão de
## renovar — a comida saiu daqui e virou o momento de Cozinha (revisão 31/08).
##
## A banca não filtra por quem você tem: itens de assinatura aparecem mesmo sem
## o dono na equipe, e aí ficam à vista mas fora de alcance. É deliberado — a
## loja mostra o que existe no mundo, não um catálogo montado para você, e ver
## a Cauda de Brasa sem ter o Apollo é uma informação sobre o próximo recruta.
##
## ESTRUTURA (revisão 03/09, autor, a partir da loja do *How Many Dudes*):
## lista à esquerda com nome e tipo, PREVIEW à direita com o ícone grande e a
## descrição embaixo. A montagem vive em `PickPanel` porque o momento de Poder
## usa exatamente a mesma tela — o jogador aprende a ler uma vez só.
##
## == A BANCA (15/09) ==
##
## A revisão mediu esta tela e a Cozinha com a MESMA caixa de conteúdo, ao
## pixel: 954x604 em (323,148). O que faltava era a banca. Ela existe agora em
## três coisas que só esta tela tem:
##
##   * a BOLSA no alto — a moeda em 48 px, o saldo em 36, e o preço de renovar
##     ao lado dela, porque renovar é a única compra desta tela que não é um
##     item. Ela sai da coluna da lista (onde era só mais um botão) e vira o
##     cabeçalho, que é onde um mercador poria o dinheiro;
##   * a luz âmbar de lamparina (`PickPanel.SALA_FEIRA`);
##   * a coluna da esquerda se chama A BANCA, e a saída, IR EMBORA.

signal finished

var _stock: Array = []
var _roll := 0
var _index := 0
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
	_panel = PickPanel.new()
	_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_panel.sala = PickPanel.SALA_FEIRA
	_panel.title_text = "FEIRA DE PASSAGEM"
	_panel.confirm_label = "COMPRAR"
	_panel.dismiss_label = "IR EMBORA"
	_panel.list_title = "A BANCA"
	_panel.header_builder = _bolsa
	# `reroll_label` fica VAZIO: nesta tela o renovar mora na bolsa, junto do
	# dinheiro que ele custa. Ver `_bolsa`.

	for o in _stock:
		if bool(o.get("sold", false)):
			continue
		var linha: Dictionary = o.duplicate()
		linha["kind_label"] = _kind_label(o)
		linha["icon"] = ("relic_" if String(o["kind"]) == "relic" else "item_") + String(o["id"])
		var why := _blocker(o)
		if why != "":
			linha["blocked"] = why
		_panel.offers.append(linha)

	_panel.chosen.connect(_buy)
	_panel.dismissed.connect(func(): finished.emit())
	add_child(_panel)


## A BOLSA: quanto você tem, e o que custa ver outra banca.
##
## O Éter estava no HUD lá em cima, em 32 px, e o preço da compra aqui embaixo,
## em 16 — a revisão mediu 10 px de tinta na moeda da loja contra 23 no HUD,
## "metade do tamanho justamente onde se gasta dinheiro". Aqui a moeda é a
## maior coisa da tela depois do título, porque é o recurso que esta sala
## consome.
func _bolsa(col: VBoxContainer) -> void:
	var price := EventGen.reroll_price("loja", _roll)
	var faixa := UI.card(UI.PANEL_HI, PickPanel.SALA_FEIRA.darkened(0.35))
	col.add_child(faixa)
	var row := UI.box(false, 12)
	faixa.add_child(row)

	row.add_child(Icons.node("ether", UI.icon_px(UI.F_TITLE), UI.GOLD))
	var saldo := UI.label(str(Run.ether), UI.F_H1, UI.GOLD)
	saldo.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(saldo)
	var nome := UI.label("de Éter na bolsa", UI.F_SMALL, UI.TEXT_DIM)
	nome.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(nome)

	row.add_child(UI.spacer(0.0, true))
	var rr := UI.button_secundario("  RENOVAR A BANCA · %d Éter  " % price, UI.F_SMALL)
	rr.disabled = Run.ether < price
	rr.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	rr.pressed.connect(_do_reroll)
	row.add_child(rr)


## A palavra sob o nome, na lista. É o que a referência do autor mostra
## ("Consumível" / "Relíquia") e o que responde "que tipo de coisa é essa"
## antes de o jogador abrir o preview.
func _kind_label(o: Dictionary) -> String:
	if String(o["kind"]) == "relic":
		return "Relíquia"
	var raridade := String(o.get("tag", ""))
	return ("Item · %s" % raridade) if raridade != "" else "Item"


func _do_reroll() -> void:
	var price := EventGen.reroll_price("loja", _roll)
	if not Run.spend_ether(price):
		return
	UI.som("moeda")
	_roll += 1
	_stock = EventGen.shop_offer(_index, _roll)
	_build()


## Por que não dá para comprar — dito na cara, não escondido num botão apagado.
##
## A falta de Éter NÃO entra aqui: ela vale para toda oferta com preço em toda
## tela, e por isso mora em `PickPanel._motivo`. Aqui ficam só as recusas que
## são desta tela.
func _blocker(o: Dictionary) -> String:
	if String(o["kind"]) != "item":
		return ""
	var id := String(o["id"])
	if not Run.team.filter(func(u): return u.accepts_item(id)).is_empty():
		return ""
	# o retrato ao lado do nome já diz DE QUEM é o item; aqui basta dizer
	# que você não tem esse bicho
	var dono := String(o.get("owner", ""))
	if dono != "" and Run.team.filter(func(u): return u.base_id() == dono).is_empty():
		return "você não tem esse Prismon"
	# UM NÚCLEO POR CRIATURA (regra de 15/09 em `UnitInstance.accepts_item`).
	# Sem esta linha a recusa nova aparecia como um COMPRAR que não fazia nada:
	# a tela some com o destino da lista e o jogador não tem como saber por quê.
	if UnitInstance.item_sets_element(id):
		return "todos já têm um Núcleo — é um por criatura"
	return "nenhum Prismon com espaço de item"


func _buy(o: Dictionary) -> void:
	if _blocker(o) != "" or not Run.spend_ether(int(o["price"])):
		return
	UI.som("moeda")
	if String(o["kind"]) == "relic":
		Run.add_relic(String(o["id"]))
		_vendido(o)
		return

	# QUEM RECEBE É ESCOLHA DO JOGADOR (autor, 03/09). O item ia direto para
	# quem tivesse menos itens — automático, e invisível. Nos Núcleos isso era
	# grave: "Muda a Afinidade da unidade" reescrevia o elemento de um Prismon
	# sorteado pela contagem de itens, mudando a matriz de reações inteira sem
	# ninguém decidir nada. Onde há mais de um destino possível, pergunta-se.
	var id := String(o["id"])
	var podem: Array = Run.team.filter(func(u): return u.accepts_item(id))
	if podem.size() <= 1:
		_dar(id, podem[0])
		_vendido(o)
		return

	var pk := PickerOverlay.new()
	pk.setup("Quem leva %s?" % String(o["name"]), _porque(id),
		func(u): return u.accepts_item(id),
		func(u): return _efeito_em(id, u))
	pk.picked.connect(func(u):
		pk.queue_free()
		_dar(id, u)
		_vendido(o))
	pk.cancelled.connect(func():
		# devolve o Éter: cancelar não pode custar nada, senão o painel vira
		# uma armadilha e o jogador para de abrir
		pk.queue_free()
		Run.add_ether(int(o["price"])))
	add_child(pk)


## A linha de apoio do painel. Nos Núcleos ela avisa o que está em jogo.
func _porque(id: String) -> String:
	if Db.items.get(id, {}).get("mods", {}).has("set_element"):
		return "A Afinidade muda para sempre — e com ela as reações da equipe. Um Núcleo por criatura."
	return String(Db.items.get(id, {}).get("text", ""))


## O que este item faz NAQUELE Prismon. Num Núcleo é a troca de elemento
## escrita na cara ("Gelo → Fogo"); no resto, o estado do inventário dele.
func _efeito_em(id: String, u: UnitInstance) -> String:
	if UnitInstance.item_sets_element(id) and u.has_core():
		return "já usa um Núcleo"
	if not u.accepts_item(id):
		return "sem espaço de item (%d/%d)" % [u.items.size(), u.item_slots()]
	var novo := String(Db.items.get(id, {}).get("mods", {}).get("set_element", ""))
	if novo != "":
		if novo == u.element():
			return "já é de %s" % Db.el_name(novo)
		return "%s → %s" % [Db.el_name(u.element()), Db.el_name(novo)]
	return "itens %d/%d" % [u.items.size(), u.item_slots()]


func _dar(id: String, u: UnitInstance) -> void:
	u.items.append(id)
	Run.team_changed.emit()


func _vendido(o: Dictionary) -> void:
	for x in _stock:
		if String(x["id"]) == String(o["id"]):
			x["sold"] = true
	_build()
