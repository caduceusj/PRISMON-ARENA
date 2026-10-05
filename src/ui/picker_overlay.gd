class_name PickerOverlay
extends Control
## Painel adjacente de escolha de Prismon (revisão 31/08, pedido do autor:
## "aparece uma tela a mais em que você escolhe entre os prismons, com botão
## de cancelar").
##
## Antes a segunda coluna vivia sempre na tela, ocupando espaço mesmo sem nada
## escolhido. Agora ela só existe quando há uma decisão pendente, escurece o
## fundo para dizer "resolva isto primeiro", e sempre dá saída.
##
## == A HIERARQUIA ESTAVA INVERTIDA (15/09) ==
##
## Achado da revisão, medido em `07e_cozinha_escolha.png`: "na cozinha, a barra
## verde GRANDE é HP; o número que decide (Estômago) é cinza e pequeno". A
## Cozinha não mexe em HP — a pergunta da tela é quem tem vaga no Estômago, e
## essa resposta estava em 18 px de cinza ao lado de uma barra de 120 px em
## verde saturado.
##
## A correção é de tipografia, não de conteúdo: o que a `why` devolve é sempre o
## número que decide (Estômago na Cozinha, slots de item na Feira), e ele passa
## a ser a maior coisa da linha. O HP continua, porque saber que um Prismon está
## em 30% muda uma decisão de investimento — mas como nota de rodapé, numa barra
## de 80 px e uma porcentagem pequena.

signal picked(u: UnitInstance)

## Altura NATIVA das texturas de barra (assets/ui/bar_*.png sao 18 px).
## Esticar 18 para 14, como estava, borra o grão da barra — é a mesma regra que
## o lint cobra na chamada de `PrismaBar.make`, e ela vale para a caixa também.
const BAR_H := 18
const BAR_W := 80.0
signal cancelled

var _title := ""
var _sub := ""
var _filter: Callable
var _why: Callable


## `filter` diz quem PODE ser escolhido; `why` explica quem não pode — e, em
## quem pode, dá o NÚMERO QUE DECIDE. É ele que a linha escreve grande.
func setup(title: String, subtitle: String, filter: Callable, why: Callable) -> void:
	_title = title
	_sub = subtitle
	_filter = filter
	_why = why


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var veil := ColorRect.new()
	veil.color = Color(0, 0, 0, 0.62)
	veil.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	veil.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(veil)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var card := UI.card(Color("#1c1830"), UI.ACCENT.darkened(0.4))
	card.custom_minimum_size = Vector2(560, 0)
	center.add_child(card)
	var col := UI.box(true, 8)
	card.add_child(col)

	col.add_child(UI.label(_title, UI.F_H2, UI.GOLD, HORIZONTAL_ALIGNMENT_CENTER))
	if _sub != "":
		col.add_child(UI.wrap(_sub, UI.F_SMALL, UI.TEXT_DIM))
	col.add_child(UI.spacer(4, false))

	for u in Run.team:
		col.add_child(_row(u))

	col.add_child(UI.spacer(6, false))
	# CANCELAR é recuar: roxo, e a altura de casa (UI.BTN_H) em vez dos 42 px
	# soltos de antes.
	var cancel := UI.button_secundario("  CANCELAR  ")
	cancel.pressed.connect(func(): cancelled.emit())
	col.add_child(cancel)


func _row(u: UnitInstance) -> Control:
	var ok: bool = _filter.call(u)
	var el := u.element()
	var card := CardButton.make(UI.PANEL, Db.el_color(el))
	card.clicked.connect(func(): picked.emit(u))

	var row := UI.box(false, 10)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.body.add_child(row)
	# medalhao: `make` mede a largura pela silhueta da especie, entao o nome
	# de cada linha comecava num x diferente e a coluna ficava serrilhada
	var port := MonsterPortrait.medallion(u.species_id, el, 44.0)
	port.mouse_filter = Control.MOUSE_FILTER_IGNORE
	port.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(port)

	var v := UI.box(true, 1)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(v)
	# O NOME identifica; o NÚMERO decide. Por isso o nome vai em corpo pequeno
	# e o número em F_H2 — é a inversão descrita no topo do arquivo.
	v.add_child(UI.label(u.display_name(), UI.F_SMALL, Db.el_color(el).lightened(0.3)))
	v.add_child(UI.label(String(_why.call(u)), UI.F_H2,
		UI.TEXT if ok else UI.BAD))

	# O HP VIROU NOTA DE RODAPÉ: a barra caiu de 120 para 80 px e a
	# porcentagem, de branca para cinza. Continua na linha porque um Prismon em
	# 30% muda uma decisão de investimento — mas não é a pergunta da tela.
	var lado := UI.box(true, 2)
	lado.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(lado)
	var bar := PrismaBar.make(_fill(u), BAR_H)
	bar.custom_minimum_size = Vector2(BAR_W, BAR_H)
	bar.set_value(u.hp_ratio, 1.0)
	lado.add_child(bar)
	lado.add_child(UI.label("%d%% de HP" % roundi(u.hp_ratio * 100.0), UI.F_SMALL,
		UI.TEXT_DIM, HORIZONTAL_ALIGNMENT_RIGHT))

	card.set_disabled(not ok)
	return card


static func _fill(u: UnitInstance) -> String:
	if u.hp_ratio > 0.6:
		return "green"
	return "yellow" if u.hp_ratio > 0.25 else "red"
