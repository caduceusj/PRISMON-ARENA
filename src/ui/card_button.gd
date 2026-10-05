class_name CardButton
extends PanelContainer
## Cartão clicável que dimensiona pelo CONTEÚDO e respeita a margem da moldura.
##
## O padrão anterior era um `Button` com os filhos ancorados no retângulo dele.
## Isso tem dois defeitos que apareceram juntos na Cozinha:
##
##   1. Filho ancorado IGNORA o `content_margin` do StyleBox. A moldura 9-patch
##      reserva 12 px de borda, o conteúdo começa em x=0, e o ícone do prato
##      saía por cima da borda — os "ícones vazando".
##   2. `Button` não cresce com o conteúdo. Uma descrição de duas linhas
##      transbordava a altura fixa.
##
## Aqui o PanelContainer desenha a moldura E mede o conteúdo (é um container,
## então honra o content_margin); um Button transparente por cima captura o
## clique sem participar do layout.
##
## TRÊS ESTADOS VISÍVEIS (04/09, pedido do autor: "coloque a cor da stylebox
## pra mudar quando coloco um hover"). Repouso, sob o mouse e escolhido são
## molduras diferentes — não só escalas diferentes. A cor é o sinal que se lê
## sem mover o mouse de novo para conferir.

signal clicked

var body: VBoxContainer
var _hit: Button
var _bg: Color
var _border: Color
var _on := false
var _hover := false


## O cartão sai da fábrica JÁ MONTADO. Construir em _ready() significa que
## `body` só existe depois de entrar na árvore — quem chamasse `card.body`
## antes de anexar pegava null.
static func make(bg: Color = UI.PANEL, border: Color = UI.LINE) -> CardButton:
	var c := CardButton.new()
	c._bg = bg
	c._border = border
	c._paint()

	c.body = UI.box(true, 3)
	c.body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.add_child(c.body)

	# o botão vive FORA do fluxo: ancorado por cima, sem influir na medida
	c._hit = Button.new()
	c._hit.flat = true
	c._hit.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# ACEITA FOCO DE TECLADO (16/09). Era FOCUS_NONE, e era o unico motivo
	# pelo qual nao dava para jogar uma run sem mouse: a segunda tela do
	# jogo ja e uma lista de CardButton. O `ui_accept` do Godot dispara
	# `pressed` sozinho, entao nao ha o que ligar do lado do clique.
	c._hit.focus_mode = Control.FOCUS_ALL
	c._hit.pressed.connect(func(): c.clicked.emit())
	c.add_child(c._hit)

	# O HOVER É ESCUTADO NUM LUGAR SÓ: o botão de cima. Ligá-lo também no
	# painel fazia um disparar a saída enquanto o outro disparava a entrada, e
	# os dois tweens brigavam pela mesma escala — era o hover "travado".
	c._hit.mouse_entered.connect(func():
		c._hover = true
		c._paint()
		UI.som("hover"))
	c._hit.mouse_exited.connect(func():
		c._hover = false
		c._paint())
	c._hit.pressed.connect(func(): UI.som("clique"))
	# O FOCO PINTA COMO O HOVER. Sao a mesma pergunta — 'qual e a que
	# voce esta apontando?' — e responder com duas aparencias diferentes
	# faria o jogador aprender duas. Quem chega pelo teclado ve o mesmo
	# feixe engordar que quem chega pelo mouse.
	c._hit.focus_entered.connect(func():
		c._hover = true
		c._paint())
	c._hit.focus_exited.connect(func():
		c._hover = c._hit.is_hovered()
		c._paint())
	Juice.make_reactive(c, c._hit)
	return c


func set_disabled(v: bool) -> void:
	if _hit != null:
		_hit.disabled = v
	modulate = Color(1, 1, 1, 0.55 if v else 1.0)


func set_selected(v: bool) -> void:
	if _on == v:
		return
	_on = v
	_paint()
	if v:
		Juice.pulse(self, 1.03)


## MENOS QUADRADOS (03/09): numa lista, cada cartão desenhava a própria moldura
## dentro da moldura do painel dentro da moldura da tela — três retângulos
## aninhados por linha. A moldura passou a ser o sinal de SELEÇÃO: a linha em
## repouso é só ícone e texto sobre o fundo.
##
## `framed = true` volta ao comportamento antigo, para os cartões que existem
## sozinhos (recruta, iniciais, prato) e precisam da moldura para ter forma.
var framed := true

## A LINHA DE LISTA PERDE A CAIXA POR COMPLETO (direção de arte, 15/09).
##
## Do Demonschool se aprende que lista não precisa de caixa: hierarquia por
## tipo, alinhamento e uma barra de acento, zero recipientes. O projeto já tinha
## tido metade desse insight aqui (a moldura só na seleção) e parou no meio — em
## repouso a linha ainda ganhava um retângulo colorido a 10%.
##
## Agora a identidade da linha é UMA FORMA SÓ em três espessuras:
##   repouso     feixe de 3 px na aresta esquerda
##   sob o mouse o feixe engorda para 6 px e a lajota acende por trás
##   escolhida   a linha vira recipiente e ABRE O CORTE (a célula C_FOCUS, que
##               é o mesmo feixe descendo a aresta inteira)
##
## O conteúdo NÃO se move entre os três: o content_margin é fixo em 18/12, então
## os 3 px a mais do hover crescem para dentro do próprio feixe e nenhuma linha
## de texto desliza. Era o que acontecia com a moldura aparecendo do nada.
const FEIXE_REPOUSO := 3
const FEIXE_HOVER := 6
const PAD_H := 18
const PAD_V := 12


func _paint() -> void:
	if _on:
		add_theme_stylebox_override("panel",
			UI.frame(UI.C_FOCUS, _border, PAD_H, PAD_V))
		return
	if framed:
		if _hover:
			# SOB O MOUSE a lajota SOBE: a célula erguida troca a sombra de 3 px
			# pela de 5 e sobe 2. É o mesmo gesto do botão, na escala do cartão.
			add_theme_stylebox_override("panel",
				UI.frame(UI.C_PANEL_HI, _border, PAD_H, PAD_V))
		else:
			add_theme_stylebox_override("panel",
				UI.frame(UI.C_PANEL, _border, PAD_H, PAD_V,
					Color(_bg.r, _bg.g, _bg.b, 1.0)))
		return
	var liso := StyleBoxFlat.new()
	liso.bg_color = Color(UI.LAJOTA.r, UI.LAJOTA.g, UI.LAJOTA.b, 0.9 if _hover else 0.0)
	liso.set_corner_radius_all(0)
	liso.border_width_left = FEIXE_HOVER if _hover else FEIXE_REPOUSO
	liso.border_color = UI.tint_of(_border, true)
	liso.content_margin_left = PAD_H
	liso.content_margin_right = PAD_H
	liso.content_margin_top = PAD_V
	liso.content_margin_bottom = PAD_V
	add_theme_stylebox_override("panel", liso)


## Linha de lista: sem moldura em repouso. Ver a nota em `_paint`.
func as_list_row() -> CardButton:
	framed = false
	_paint()
	return self
