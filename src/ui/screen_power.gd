class_name ScreenPower
extends Control
## O momento de PODER: a Mão do Domador ganha um Ativo novo.
##
## Pedido do autor (03/09). A run passou a começar com UM poder — o Meteoro —
## em vez dos três; os outros dois se ganham aqui, até o teto de
## `run.max_actives`. Antes a única agência do jogador dentro do combate já
## vinha pronta na primeira tela e nunca crescia.
##
## Não custa Éter: isto é progressão, não compra. Por isso o botão diz
## APRENDER e não há preço na lista — mas a ESTRUTURA é a mesma da Feira
## (lista à esquerda, preview à direita), porque quem já leu uma sabe ler a
## outra sem reaprender nada.
##
## == DUAS ESCOLHAS SEGUIDAS (15/09) ==
##
## O Acaso voltou à sequência e tomou o lugar do segundo momento de Poder, então
## restou UM — e 1 poder inicial + 1 aprendido para em 2, com o teto de 3 slots
## inalcançável na run de verdade. `momentos.poder.escolhas` (hoje 2) resolve
## isso aqui, na tela: o jogador escolhe, a lista se refaz e ele escolhe de novo.
##
## Duas coisas que o laço precisa e que não são óbvias:
##
##   * o SUBTÍTULO diz qual das duas está em curso. Sem isso a segunda oferta
##     parece um bug — a tela "não fechou" depois de aprender;
##   * o `roll` da segunda oferta é o número de escolhas já feitas, então a
##     semente muda; e o pool de `EventGen.power_offer` já filtra o que o
##     jogador acabou de aprender, então a segunda oferta nunca repete a
##     primeira.

signal finished

var _stock: Array = []
var _index := 0
var _feitas := 0
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
	var total := EventGen.power_escolhas()
	var teto := int(Db.run_cfg("max_actives", 3))
	var cheia: bool = Run.active_slots_free() <= 0

	_panel = PickPanel.new()
	_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_panel.sala = PickPanel.SALA_PODER
	_panel.title_text = "UM PODER NOVO"
	_panel.confirm_label = "APRENDER"
	_panel.dismiss_label = "NÃO APRENDER NADA"
	_panel.list_title = "O QUE SE PODE APRENDER"
	_panel.header_builder = _mao_do_domador
	if cheia:
		_panel.subtitle_text = "A Mão do Domador está cheia (%d de %d)." % [
			Run.actives.size(), teto]
	else:
		_panel.subtitle_text = "Escolha %d de %d." % [mini(_feitas + 1, total), total]

	for o in _stock:
		var linha: Dictionary = o.duplicate()
		linha["kind_label"] = "Poder · %d⚡" % int(o.get("cost", 0))
		if cheia:
			linha["blocked"] = "a Mão do Domador já está cheia"
		_panel.offers.append(linha)

	_panel.chosen.connect(_aprender)
	_panel.dismissed.connect(func(): finished.emit())
	add_child(_panel)


## A MÃO DO DOMADOR, desenhada: um slot por vaga de `run.max_actives`.
##
## É a cenografia desta sala e também a única resposta honesta à pergunta "por
## que estou escolhendo isto duas vezes?". As vagas cheias mostram o poder que
## está nelas; as livres usam `UI.slot()`, que lê como buraco — e o buraco que
## some depois de aprender é o retorno do gesto.
func _mao_do_domador(col: VBoxContainer) -> void:
	var faixa := UI.card(UI.PANEL_HI, PickPanel.SALA_PODER.darkened(0.35))
	# a mão tem o tamanho da mão: a placa encolhe até as três vagas
	faixa.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	col.add_child(faixa)
	var v := UI.box(true, 8)
	faixa.add_child(v)
	v.add_child(UI.label("A MÃO DO DOMADOR", UI.F_SMALL,
		UI.tint_of(PickPanel.SALA_PODER, true), HORIZONTAL_ALIGNMENT_CENTER))

	var row := UI.box(false, 12)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_child(row)
	for i in range(int(Db.run_cfg("max_actives", 3))):
		row.add_child(_vaga(String(Run.actives[i]) if i < Run.actives.size() else ""))


func _vaga(active_id: String) -> Control:
	if active_id == "":
		var vago := UI.slot()
		var mid := CenterContainer.new()
		vago.add_child(mid)
		mid.add_child(UI.label("vaga", UI.F_SMALL, UI.TEXT_DIM))
		return vago
	var a: Dictionary = Db.actives.get(active_id, {})
	var cor := Color(String(a.get("color", "#7d6cf0")))
	var p := UI.card(UI.LAJOTA_HI, cor)
	p.tooltip_text = "%s — %s" % [String(a.get("name", "")), String(a.get("text", ""))]
	var row := UI.box(false, 8)
	p.add_child(row)
	var ic := Icons.active(active_id, 32.0)
	ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(ic)
	var nm := UI.label(String(a.get("name", "")), UI.F_SMALL, cor.lightened(0.3))
	nm.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(nm)
	return p


## Aprendeu um. Se ainda falta escolha E ainda há vaga E ainda há o que
## aprender, a tela se refaz com a oferta seguinte em vez de emitir `finished`.
func _aprender(o: Dictionary) -> void:
	if not Run.learn_active(String(o["id"])):
		return
	_feitas += 1
	if _feitas >= EventGen.power_escolhas() or Run.active_slots_free() <= 0:
		finished.emit()
		return
	_stock = EventGen.power_offer(_index, _feitas)
	if _stock.is_empty():
		finished.emit()
		return
	_build()
