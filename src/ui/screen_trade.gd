class_name ScreenTrade
extends Control
## O MERCADOR DE TROCAS: entrega um Prismon, leva outro.
##
## Pedido do autor (03/09). A regra que faz a troca ser justa: um Prismon sem
## nada equipado vale um Prismon sem nada; um que carrega item ou prato recebe
## uma oferta com a MESMA quantidade de itens e pratos — "os equivalentes,
## para que faça valer". Sem isso o Mercador seria uma armadilha, e o jogador
## aprenderia a nunca abrir a tela.
##
## SOBRE A "TELA EXTRA DE COMPARATIVO" que o autor pediu para eu avaliar: ela
## não existe, de propósito. A comparação É a decisão — não é informação de
## apoio que se consulta antes de decidir, é o próprio conteúdo da escolha. Por
## isso ela mora no PREVIEW da mesma `PickPanel` da Feira, da Cozinha e do
## Poder, lado a lado: à esquerda quem sai, à direita quem entra. Uma terceira
## tela cobraria um clique para mostrar o que já cabe onde o jogador olha.
##
## == A CARROÇA (15/09) ==
##
## O cabeçalho desta tela é o ELENCO INTEIRO, e não só quem está em oferta: o
## Mercador quer alguns dos seus bichos e não quer os outros, e essa é a
## primeira informação da sala. Quem ele quer fica aceso na cor da lona; quem
## ele não quer fica apagado, com o motivo na dica. Antes o jogador via três
## linhas de lista e não tinha como saber que o quarto Prismon nem estava em
## jogo.

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
	var price := EventGen.reroll_price("troca", _roll)
	_panel = PickPanel.new()
	_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_panel.sala = PickPanel.SALA_TROCA
	_panel.title_text = "O MERCADOR DE TROCAS"
	_panel.subtitle_text = "Escolha quem sai. O que ele carrega vai junto — e vem o equivalente."
	_panel.confirm_label = "TROCAR"
	_panel.dismiss_label = "NÃO TROCAR NADA"
	_panel.list_title = "QUEM ELE LEVARIA"
	_panel.header_builder = _carroca
	_panel.reroll_label = "  OUTRAS OFERTAS · %d Éter  " % price
	_panel.reroll_enabled = Run.ether >= price
	_panel.preview_builder = _comparar

	for o in _stock:
		var u := Run.find_by_uid(int(o["uid"]))
		if u == null:
			continue
		var sp := String(o["species"])
		var linha: Dictionary = o.duplicate()
		linha["id"] = str(u.uid)
		linha["name"] = u.display_name()
		linha["kind_label"] = "troca por %s" % Db.sp_name(sp)
		linha["color"] = String(Db.el(u.element()).get("color", "#ffffff"))
		linha["icon"] = "elem_" + u.element()
		_panel.offers.append(linha)

	if _panel.offers.is_empty():
		_panel.subtitle_text = "O Mercador não tem nada que te sirva hoje."

	_panel.chosen.connect(_trocar)
	_panel.dismissed.connect(func(): finished.emit())
	_panel.rerolled.connect(_do_reroll)
	add_child(_panel)


## O ELENCO, e o que o Mercador quer dele.
func _carroca(col: VBoxContainer) -> void:
	var querem: Dictionary = {}
	for o in _stock:
		querem[int(o["uid"])] = true

	var faixa := UI.card(UI.PANEL_HI, PickPanel.SALA_TROCA.darkened(0.35))
	# a carroça tem o tamanho do elenco: a placa encolhe até ele
	faixa.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	col.add_child(faixa)
	var v := UI.box(true, 8)
	faixa.add_child(v)
	v.add_child(UI.label("O SEU ELENCO", UI.F_SMALL,
		UI.tint_of(PickPanel.SALA_TROCA, true), HORIZONTAL_ALIGNMENT_CENTER))

	# GRADE DE QUATRO COLUNAS, e não um HFlowContainer: dentro de uma placa que
	# encolhe até o conteúdo, o HFlow reporta como mínimo a sua disposição mais
	# ESTREITA — uma coluna só — e o elenco virava uma pilha vertical. Quatro
	# porque `run.field_cap` é 8: o elenco cheio cabe em duas fileiras.
	var grade := GridContainer.new()
	grade.columns = 4
	grade.add_theme_constant_override("h_separation", 20)
	grade.add_theme_constant_override("v_separation", 8)
	v.add_child(grade)
	for u in Run.team:
		grade.add_child(_na_carroca(u, querem.has(u.uid)))


## Um Prismon do elenco, visto pelo Mercador: o retrato e o que ele carrega —
## que é exatamente o que define o valor da troca.
func _na_carroca(u: UnitInstance, quer: bool) -> Control:
	var linha := UI.box(false, 6)
	var med := MonsterPortrait.medallion(u.species_id, u.element(), 48.0)
	med.mouse_filter = Control.MOUSE_FILTER_STOP
	med.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var estado := "o Mercador não quer este hoje"
	if quer:
		estado = "o Mercador leva este"
	med.tooltip_text = "%s — %s" % [u.display_name(), estado]
	linha.add_child(med)

	var carga := UI.box(false, 3)
	carga.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	linha.add_child(carga)
	for it in u.items:
		carga.add_child(Icons.item(String(it), 16.0))
	for d in u.dishes:
		carga.add_child(Icons.dish(String(d), 16.0))
	if u.items.is_empty() and u.dishes.is_empty():
		carga.add_child(UI.label("vazio", UI.F_SMALL, UI.TEXT_DIM))

	# APAGADO É INFORMAÇÃO: o que o Mercador não quer continua à vista, para
	# a lista de três linhas não parecer o elenco inteiro.
	if not quer:
		linha.modulate = Color(1, 1, 1, 0.38)
	return linha


func _do_reroll() -> void:
	var price := EventGen.reroll_price("troca", _roll)
	if not Run.spend_ether(price):
		return
	UI.som("moeda")
	_roll += 1
	_stock = EventGen.trade_offer(_index, _roll)
	_build()


## O comparativo, lado a lado. É a tela inteira da decisão: mesma altura, mesma
## gramática dos dois lados, para a diferença saltar sem ninguém procurar.
func _comparar(o: Dictionary, v: VBoxContainer) -> void:
	var u := Run.find_by_uid(int(o["uid"]))
	if u == null:
		return
	var sp := String(o["species"])

	var row := UI.box(false, 10)
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(row)
	row.add_child(_lado("VOCÊ DÁ", u.species_id, u.element(),
		u.display_name(), u.items, u.dishes, UI.BAD))
	var seta := UI.label("→", UI.F_H1, UI.TEXT_DIM)
	seta.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(seta)
	row.add_child(_lado("VOCÊ RECEBE", sp, String(Db.sp(sp).get("element", "FOGO")),
		Db.sp_name(sp), o.get("items", []), o.get("dishes", []), UI.GOOD))


## Uma coluna do comparativo: retrato, nome, papel, e o que vem junto em ÍCONES
## com tooltip — o autor pediu ícone, não lista escrita.
func _lado(titulo: String, sp_id: String, el: String, nome: String,
		itens: Array, pratos: Array, cor: Color) -> Control:
	var card := UI.card(UI.PANEL, cor.darkened(0.45))
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# os dois lados ocupam a coluna inteira: o comparativo É a tela da decisão,
	# e um comparativo de 230 px de altura dentro de um painel de 500 lia como
	# um cartãozinho solto no alto de um vazio
	card.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var v := UI.box(true, 6)
	card.add_child(v)
	# O CONTEÚDO SE CENTRA no cartão alto, em vez de ficar pendurado no topo com
	# 250 px de vazio embaixo. Por espaçador e não por `alignment`: este VBox
	# tem um HFlowContainer dentro (a carga), cuja altura mínima depende da
	# largura — e a combinação dos dois já é receita conhecida de recálculo de
	# layout em cascata. Dois Controls expansíveis fazem o mesmo serviço sem
	# nenhuma dependência entre eixos.
	v.add_child(UI.spacer(0.0, true))
	v.add_child(UI.label(titulo, 11, cor.lightened(0.2), HORIZONTAL_ALIGNMENT_CENTER))

	var med := MonsterPortrait.medallion(sp_id, el, 76.0)
	med.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	med.tooltip_text = _ficha(sp_id, el)
	v.add_child(med)

	v.add_child(UI.label(nome, UI.F_BODY, Db.el_color(el).lightened(0.3),
		HORIZONTAL_ALIGNMENT_CENTER))
	v.add_child(UI.label("%s · %s" % [Db.el_name(el),
		Db.role_name(String(Db.sp(sp_id).get("role", "")))],
		UI.F_SMALL, UI.TEXT_DIM, HORIZONTAL_ALIGNMENT_CENTER))

	# O QUE VEM JUNTO, em ícones. Vazio dos dois lados é informação também: diz
	# que a troca é limpa, sem investimento em jogo.
	var carga := HFlowContainer.new()
	carga.alignment = FlowContainer.ALIGNMENT_CENTER
	carga.add_theme_constant_override("h_separation", 5)
	carga.add_theme_constant_override("v_separation", 4)
	v.add_child(carga)
	for it in itens:
		var i1 := Icons.item(String(it), 32.0)
		i1.mouse_filter = Control.MOUSE_FILTER_STOP
		i1.tooltip_text = "%s\n%s" % [String(Db.items[it]["name"]),
			String(Db.items[it]["text"])]
		carga.add_child(i1)
	for d in pratos:
		var d1 := Icons.dish(String(d), 32.0)
		d1.mouse_filter = Control.MOUSE_FILTER_STOP
		d1.tooltip_text = "%s\n%s" % [String(Db.dishes[d]["name"]),
			String(Db.dishes[d]["text"])]
		carga.add_child(d1)
	if itens.is_empty() and pratos.is_empty():
		carga.add_child(UI.label("sem nada equipado", UI.F_SMALL, UI.TEXT_DIM))
	v.add_child(UI.spacer(0.0, true))
	return card


func _ficha(sp_id: String, el: String) -> String:
	var s := Db.sp(sp_id)
	return "%s — %s · %s\nHP %d · ATK %d · DEF %d · VEL %.1f\n⚡ %s" % [
		Db.sp_name(sp_id), Db.el_name(el),
		Db.role_name(String(s.get("role", ""))),
		int(s.get("hp", 0)), int(s.get("atk", 0)), int(s.get("def", 0)),
		float(s.get("vel", 1.0)), String(s.get("ult", {}).get("name", ""))]


func _trocar(o: Dictionary) -> void:
	var u := Run.find_by_uid(int(o["uid"]))
	if u == null:
		return
	if Run.trade(u, String(o["species"]), o.get("items", []), o.get("dishes", [])):
		UI.som("recruta")
		finished.emit()
