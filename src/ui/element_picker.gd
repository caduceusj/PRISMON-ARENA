class_name ElementPicker
extends Control
## Escolher UM elemento, em painel adjacente — o irmão do `PickerOverlay`.
##
## Existe porque o Guisado Cromático "muda a Afinidade da unidade para o
## elemento escolhido" e **não havia onde escolher**: `Run.cook()` recebia
## `pick` vazio, caía em `u.forced_element = u.element()` e o prato não fazia
## nada. Era um defeito silencioso — o Éter era cobrado, a mensagem dizia que
## a Afinidade mudou, e a criatura continuava igual.
##
## Mesma gramática do PickerOverlay: véu que diz "resolva isto primeiro",
## título, opções grandes e CANCELAR sempre disponível.
##
## A AURA VAI ESCRITA (15/09). A revisão achou que "a metade 'aura sozinha' do
## combate nunca é explicada — e a frase que explicaria já está escrita nos
## dados, intocada". Aqui é onde ela mais faz falta: escolher a Afinidade É
## escolher a aura que a criatura passa a aplicar, e o painel dizia só o nome
## do elemento. Agora cada opção traz o nome da aura e o que ela faz sozinha
## (`passive_text` de `data/elements.json`), que é a informação de que a decisão
## precisa.

signal picked(element_id: String)
signal cancelled

var _title := ""
var _sub := ""
var _skip := ""          # elemento a esconder (o atual da criatura)


func setup(title: String, subtitle: String, skip_element: String = "") -> void:
	_title = title
	_sub = subtitle
	_skip = skip_element


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
	var card := UI.card(UI.PANEL_HI, UI.ACCENT)
	center.add_child(card)
	var v := UI.box(true, 12)
	card.add_child(v)

	v.add_child(UI.label(_title, UI.F_H1, UI.GOLD, HORIZONTAL_ALIGNMENT_CENTER))
	if _sub != "":
		v.add_child(UI.label(_sub, UI.F_SMALL, UI.TEXT_DIM, HORIZONTAL_ALIGNMENT_CENTER))

	var row := UI.box(false, 10)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_child(row)
	for e in Db.slice_elements:
		var el := String(e)
		if el == _skip:
			continue
		row.add_child(_chip(el))

	var out := UI.button_secundario("  CANCELAR  ")
	out.pressed.connect(func(): cancelled.emit())
	v.add_child(out)


## Um elemento: ícone grande, o nome e a AURA que ele aplica. A decisão é "qual
## cor esta criatura passa a ser" — e cor, neste jogo, é a aura que ela deixa no
## inimigo. Sem a segunda parte, a escolha é só estética.
func _chip(el: String) -> Control:
	var c := Db.el_color(el)
	var dados := Db.el(el)
	var aura := Db.aura_name(String(dados.get("aura_id", "")))
	var card := CardButton.make(UI.PANEL, c)
	card.custom_minimum_size = Vector2(170, 0)
	card.tooltip_text = "%s — %s" % [Db.el_name(el), aura]
	card.clicked.connect(func(): picked.emit(el))

	var v := card.body
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	var ic := Icons.element(el, 48.0)
	ic.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	v.add_child(ic)
	v.add_child(UI.label(Db.el_name(el), UI.F_BODY, c.lightened(0.3),
		HORIZONTAL_ALIGNMENT_CENTER))
	v.add_child(UI.label(aura, UI.F_SMALL, UI.TEXT_DIM,
		HORIZONTAL_ALIGNMENT_CENTER))
	var passiva := String(dados.get("passive_text", ""))
	if passiva != "":
		v.add_child(UI.label(passiva, UI.F_SMALL, c.darkened(0.1),
			HORIZONTAL_ALIGNMENT_CENTER))
	return card
