class_name PrismaTheme
extends RefCounted
## O Theme do PRISMA, montado uma vez e herdado por toda a árvore.
##
## Por que um Theme e não overrides por nó: `add_theme_stylebox_override` só
## alcança os nós que a gente cria à mão. Tudo que o Godot instancia sozinho —
## o painel de TOOLTIP, as barras de rolagem do ScrollContainer, o LineEdit, o
## ProgressBar, os separadores — continuava com o cinza padrão da engine. Era
## isso que fazia a interface parecer "meio aplicada".

## Espessura da barra de rolagem. Larga de propósito: ela é a única pista
## de que existe conteúdo abaixo da dobra.
const SCROLL_W := 14

static var _cached: Theme = null


static func get_theme() -> Theme:
	if _cached == null:
		_cached = build()
	return _cached


## Joga fora o Theme assado, para que o proximo `get_theme()` o remonte.
##
## O Theme nao guarda uma referencia a paleta: ele guarda os StyleBox e as
## cores JA RESOLVIDOS, copiados de `UI` no momento em que foi montado. Trocar
## de paleta sem chamar isto deixaria o tooltip, a barra de rolagem, o
## LineEdit, o ProgressBar e todo botao sem override na cor ANTIGA -- metade da
## tela nova e metade da velha, e sem erro nenhum para acusar.
##
## Quem chama e `Db._load_paleta()`, logo depois de `UI.aplicar_paleta()`.
static func esquecer() -> void:
	_cached = null


## Fontes (revisão 31/08, fonte escolhida pelo autor):
##   Pixel Sans Serif — a fonte da UI. Desenha MUITO maior e mais nítida que a
##     Pixelify no mesmo tamanho nominal, e tem todos os acentos do português.
##     Não tem os símbolos (★ ⚡ ❄ ◆ →), por isso a Pixelify entra como
##     FALLBACK: o Godot busca nela o glifo que falta na principal.
##   Pixeled — só os dígitos do dano (é a fonte que o autor enviou).
##   ATENÇÃO DE LICENÇA: a Pixel Sans Serif é "free for personal use" no
##   dafont — serve para protótipo, mas trava um lançamento comercial.
##   Ver assets/CREDITOS.md.
static var body_font: FontFile = null
static var digit_font: FontFile = null


## POR QUE `preload` E NAO `load_dynamic_font` (03/09, bug de exportacao
## relatado pelo autor: "quando to exportando a fonte que eu coloquei nao ta
## indo").
##
## `FontFile.load_dynamic_font(caminho)` le o arquivo .ttf CRU do disco. Isso
## funciona no editor, onde o arquivo esta la — e falha em silencio no jogo
## exportado, porque o Godot empacota os recursos IMPORTADOS (o .fontdata em
## .godot/imported/), nao os arquivos-fonte. No build o caminho simplesmente
## nao existe, a fonte nao carrega, e tudo cai no tipo padrao da engine sem
## nenhum erro visivel.
##
## `preload` pega o recurso importado, que vai no pacote. Em troca, os ajustes
## de rasterizacao (antialiasing, hinting, subpixel) deixam de ser feitos aqui
## e passam a viver nos arquivos .ttf.import — que e onde eles pertencem, ja
## que sao decisoes de IMPORTACAO. Os tres estao em zero: sem suavizacao, sem
## hinting, sem posicionamento subpixel, que e o que uma fonte de pixel pede.
const TTF_BODY := preload("res://assets/fonts/m6x11plus.ttf")
const TTF_SYMBOLS := preload("res://assets/fonts/PixelifySans.ttf")
const TTF_DIGITS := preload("res://assets/fonts/Pixeled.ttf")


## A fonte do corpo, garantidamente carregada.
##
## Existe porque `UI.label` precisa dela para montar a FontVariation dos rotulos
## em caixa alta (+1 de espacamento entre glifos), e o Theme pode ainda nao ter
## sido construido quando o primeiro rotulo e criado.
static func fonte_corpo() -> FontFile:
	_load_fonts()
	return body_font


static func _load_fonts() -> void:
	if body_font != null:
		return
	body_font = TTF_BODY
	digit_font = TTF_DIGITS
	# A m6x11plus nao tem os simbolos (estrela, raio, floco, losango, seta) —
	# nem a Pixelify tem, na verdade: eles vem do fallback do SISTEMA. A
	# Pixelify entra na cadeia mesmo assim porque fornece o ponto medio (·) e
	# o travessao (—), que a m6x11plus tambem nao tem e que aparecem em quase
	# toda linha de texto do jogo.
	if body_font.fallbacks.is_empty():
		body_font.fallbacks = [TTF_SYMBOLS]


static func build() -> Theme:
	_load_fonts()
	var t := Theme.new()
	t.default_font = body_font
	t.default_font_size = UI.fs(UI.F_BODY)

	_panels(t)
	_buttons(t)
	_text(t)
	_bars(t)
	_scroll(t)
	_tooltip(t)
	_containers(t)
	return t


# --- painéis ---------------------------------------------------------------

static func _panels(t: Theme) -> void:
	for type_name in ["PanelContainer", "Panel"]:
		t.set_stylebox("panel", type_name, UI.frame(UI.C_PANEL, UI.LINE))
	t.set_stylebox("panel", "PopupPanel", UI.frame(UI.C_PANEL_HI, UI.LINE))
	t.set_stylebox("panel", "PopupMenu", UI.frame(UI.C_PANEL_HI, UI.LINE))


# --- botões ----------------------------------------------------------------

## O MESMO desenho de `UI.button`, para os Button que a engine (ou uma tela)
## cria sem passar pelo kit. O estado vem da ELEVACAO da lajota, nao da cor:
## repouso em repouso, hover ERGUIDA (sobe 2 px, sombra vai a 5), apertado
## AFUNDADA (some a sombra e o rotulo desce 3 px). Ver a nota em ui.gd.
static func _buttons(t: Theme) -> void:
	t.set_stylebox("normal", "Button",
		UI.frame(UI.C_PANEL, UI.LINE, UI.BTN_PAD_H, UI.BTN_PAD_V, UI.LAJOTA_HI))
	t.set_stylebox("hover", "Button",
		UI.frame(UI.C_PANEL_HI, UI.LINE, UI.BTN_PAD_H, UI.BTN_PAD_V, UI.ARESTA))
	var ap := UI.frame(UI.C_INSET, UI.LINE, UI.BTN_PAD_H, UI.BTN_PAD_V, UI.LAJOTA)
	ap.content_margin_top += UI.BTN_AFUNDA
	ap.content_margin_bottom -= UI.BTN_AFUNDA
	t.set_stylebox("pressed", "Button", ap)
	t.set_stylebox("disabled", "Button",
		UI.frame(UI.C_PANEL, Color(0.30, 0.30, 0.36), UI.BTN_PAD_H, UI.BTN_PAD_V, UI.MESA))
	# FOCO VISIVEL (16/09). Era StyleBoxEmpty: um botao alcancado pelo
	# teclado nao mostrava absolutamente nada, o que tornava a navegacao
	# por teclado inutil mesmo depois de possivel. A celula erguida e a
	# mesma do hover — de novo, a mesma pergunta, a mesma resposta.
	t.set_stylebox("focus", "Button",
		UI.frame(UI.C_PANEL_HI, UI.LINE, UI.BTN_PAD_H, UI.BTN_PAD_V, UI.ARESTA))
	t.set_color("font_color", "Button", UI.TEXT)
	t.set_color("font_hover_color", "Button", Color.WHITE)
	t.set_color("font_pressed_color", "Button", Color.WHITE)
	t.set_color("font_disabled_color", "Button", UI.TEXT_DIM.darkened(0.35))
	t.set_font_size("font_size", "Button", UI.fs(UI.F_BODY))


# --- texto e entrada -------------------------------------------------------

static func _text(t: Theme) -> void:
	t.set_color("font_color", "Label", UI.TEXT)
	t.set_font_size("font_size", "Label", UI.fs(UI.F_BODY))
	t.set_color("default_color", "RichTextLabel", UI.TEXT)

	# campo de texto e uma lajota AFUNDADA: o que recebe digitacao esta abaixo da
	# superficie, e isso e a mesma gramatica do botao apertado
	t.set_stylebox("normal", "LineEdit", UI.frame(UI.C_INSET, UI.LINE))
	t.set_stylebox("focus", "LineEdit", UI.frame(UI.C_INSET, UI.ACCENT))
	t.set_stylebox("read_only", "LineEdit", UI.frame(UI.C_SLOT, UI.LINE))
	t.set_color("font_color", "LineEdit", UI.TEXT)
	t.set_color("font_placeholder_color", "LineEdit", UI.TEXT_DIM)
	t.set_color("caret_color", "LineEdit", UI.ACCENT.lightened(0.3))
	t.set_color("selection_color", "LineEdit", UI.ACCENT.darkened(0.3))
	t.set_font_size("font_size", "LineEdit", UI.fs(UI.F_BODY))

	var line := StyleBoxLine.new()
	line.color = UI.LINE
	line.thickness = 1
	t.set_stylebox("separator", "HSeparator", line)
	var vline := StyleBoxLine.new()
	vline.color = UI.LINE
	vline.vertical = true
	t.set_stylebox("separator", "VSeparator", vline)


# --- barras ----------------------------------------------------------------

static func _bars(t: Theme) -> void:
	t.set_stylebox("background", "ProgressBar", UI.frame(UI.C_INSET, UI.LINE))
	t.set_stylebox("fill", "ProgressBar", UI.bar_fill(UI.ACCENT))
	t.set_color("font_color", "ProgressBar", UI.TEXT)
	t.set_font_size("font_size", "ProgressBar", UI.fs(UI.F_SMALL))


# --- rolagem ---------------------------------------------------------------

static func _scroll(t: Theme) -> void:
	t.set_stylebox("panel", "ScrollContainer", StyleBoxEmpty.new())

	# A BARRA PRECISA SER VISTA (autor, 03/09: "não podemos esperar que o
	# jogador simplesmente adivinhe esse tipo de info"). A anterior era um
	# trilho preto a 35% com um grabber cinza-escuro de 2 px de raio: sobre um
	# painel escuro ela sumia, e quem não soubesse que havia mais conteúdo
	# abaixo nunca ia descobrir. Agora o trilho tem borda própria e o grabber
	# é claro e largo — a barra existe mesmo quando ninguém está tocando nela.
	#
	# MAS O GRABBER DEIXOU DE SER ROXO (revisão 15/09). Ele era ACCENT clareado,
	# a MESMA cor do botão de avançar, e aparecia cheio e berrante em telas onde
	# não havia nada para rolar — competindo com a única coisa da tela que o
	# jogador precisava achar. Rolagem é MATÉRIA, não estado: ela vive nos
	# degraus neutros, e só o hover a acende. A cor saturada deste jogo é
	# reservada para os quatro lugares da direção de arte, e uma barra de
	# rolagem não é nenhum deles.
	for axis in ["VScrollBar", "HScrollBar"]:
		var trough := StyleBoxFlat.new()
		trough.bg_color = UI.MESA
		trough.set_corner_radius_all(0)
		trough.set_border_width_all(1)
		trough.border_color = UI.LAJOTA_HI
		var grab := StyleBoxFlat.new()
		grab.bg_color = UI.ARESTA
		grab.set_corner_radius_all(0)
		var grab_hi := StyleBoxFlat.new()
		grab_hi.bg_color = UI.ARESTA.lightened(0.35)
		grab_hi.set_corner_radius_all(0)
		t.set_stylebox("scroll", axis, trough)
		t.set_stylebox("grabber", axis, grab)
		t.set_stylebox("grabber_highlight", axis, grab_hi)
		t.set_stylebox("grabber_pressed", axis, grab_hi)
	# A ESPESSURA VEM DO ESTILO, nao de uma constante: `ScrollBar` no Godot 4
	# nao tem "scroll_width" — quem define a largura da barra e o tamanho
	# minimo do StyleBox do trilho. Foi por isso que a primeira tentativa de
	# engrossar a barra nao mudou nada na tela.
	var vt: StyleBoxFlat = t.get_stylebox("scroll", "VScrollBar")
	vt.content_margin_left = SCROLL_W * 0.5
	vt.content_margin_right = SCROLL_W * 0.5
	var ht: StyleBoxFlat = t.get_stylebox("scroll", "HScrollBar")
	ht.content_margin_top = SCROLL_W * 0.5
	ht.content_margin_bottom = SCROLL_W * 0.5


# --- tooltip ---------------------------------------------------------------
#
# O tooltip é criado pela própria engine a partir de `Control.tooltip_text`.
# Sem estes dois tipos ele sai com o painel branco padrão do Godot -- e é
# justamente onde a interface esconde o detalhe que saiu da tela.

static func _tooltip(t: Theme) -> void:
	var sb := UI.frame(UI.C_PANEL_HI, UI.ACCENT)
	sb.content_margin_left = 14
	sb.content_margin_right = 14
	sb.content_margin_top = 10
	sb.content_margin_bottom = 10
	t.set_stylebox("panel", "TooltipPanel", sb)
	t.set_color("font_color", "TooltipLabel", UI.TEXT)
	t.set_color("font_shadow_color", "TooltipLabel", Color(0, 0, 0, 0.8))
	t.set_font_size("font_size", "TooltipLabel", UI.fs(UI.F_SMALL))
	t.set_constant("shadow_offset_x", "TooltipLabel", 1)
	t.set_constant("shadow_offset_y", "TooltipLabel", 1)


# --- espaçamentos ----------------------------------------------------------

static func _containers(t: Theme) -> void:
	t.set_constant("separation", "HBoxContainer", 8)
	t.set_constant("separation", "VBoxContainer", 6)
	t.set_constant("h_separation", "GridContainer", 8)
	t.set_constant("v_separation", "GridContainer", 6)
