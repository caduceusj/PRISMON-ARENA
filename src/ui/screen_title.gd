class_name ScreenTitle
extends Control
## MENU PRINCIPAL (revisão 04/09, pedido do autor).
##
## Antes esta tela era uma folha de rosto: título, elenco, um cartão com os
## números do protótipo e o botão de começar espremido no meio disso. Virou um
## menu de verdade — logotipo, três botões, e o resto atrás deles.
##
## O logotipo entra PIXELIZADO (ver `LogoView`): a arte é vetorial de traço
## limpo e a interface é pixel art, e sem tratamento os dois não pertencem à
## mesma tela. Se o PNG ainda não estiver no projeto, cai no nome escrito e o
## menu continua funcionando.

signal start_requested(seed_value: int)
signal continue_requested
signal options_requested

var _seed_field: LineEdit

## Quem sabe se ha run guardada e o roteador, e ele DIZ a esta tela em vez de
## ela perguntar. E de proposito: `Main` ja instancia `ScreenTitle`, e a tela
## chamando `Main` de volta fecharia um ciclo entre os dois scripts.
var _tem_save := false
var _save_passo := 0


func setup(tem_save: bool, passo: int) -> void:
	_tem_save = tem_save
	_save_passo = passo

## A SALA DO MENU. Roxo-vidro: nao e o roxo de nenhum elemento, e e o unico
## lugar do jogo onde a cor do lugar nao vem de uma arena nem de um perigo.
## Vem de `data/paleta.json` (salas.titulo) desde 17/09.
static var SALA: Color:
	get: return UI.cor_da_sala("titulo")

## Largura unica da coluna do menu. Os quatro botoes, a semente e a linha de
## atalhos nascem todos dela — era 320 para os botoes e 720 para o resto, e a
## coluna inteira do menu nao tinha borda comum nenhuma.
const MENU_W := 360.0


func _ready() -> void:
	# A LUZ DA SALA entra ANTES de tudo (primeiro filho): ela e aditiva e tem de
	# ficar por baixo do logotipo, nao por cima dele.
	# SEM FORÇA ESCRITA AQUI (17/09). Eram dez telas passando a própria força
	# (0,04 a 0,075) e, com isso, dez lugares para editar quando a atmosfera do
	# jogo tivesse de mudar — o oposto do "fácil de customizar" que o autor
	# pediu. Quem manda na intensidade agora é `sala_forca` em data/paleta.json.
	add_child(UI.luz_de_sala(SALA))

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var col := UI.box(true, 8)
	col.custom_minimum_size = Vector2(720, 0)
	center.add_child(col)

	# A TIRA DE 9 CORES SAIU (15/09).
	#
	# Ela era residuo de mockup, e media 720 x 14 px de nove retangulos chapados
	# logo ACIMA do logotipo — a unica peca do jogo feita a mao, e justamente
	# ela com um segundo espectro, mais pobre e mais chapado, empilhado em cima.
	# Quatro das nove cores ainda saiam escurecidas em 62% porque os elementos
	# nao estao no slice: uma legenda de uma legenda que a tela nao explica.
	#
	# No lugar dela nao entrou outra peca: entrou AR. O logotipo e holografico e
	# ja carrega o espectro inteiro; a cor do lugar agora vem da luz da sala,
	# que e o mesmo recurso que todas as outras telas passaram a usar.
	col.add_child(UI.spacer(26, false))

	# O LOGOTIPO, ou o nome escrito se o PNG ainda não estiver no projeto.
	var logo := LogoView.make(660.0)
	if logo != null:
		col.add_child(logo)
	else:
		col.add_child(UI.label("P R I S M O N", 58, UI.TEXT,
			HORIZONTAL_ALIGNMENT_CENTER))

	col.add_child(UI.label("Você comanda o campo elemental em que eles lutam.",
		UI.F_SMALL, UI.TEXT_DIM, HORIZONTAL_ALIGNMENT_CENTER))
	col.add_child(UI.spacer(14, false))

	# --- os botões: é isto que um menu principal é --------------------------
	var menu := UI.box(true, 8)
	menu.custom_minimum_size = Vector2(MENU_W, 0)
	menu.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	col.add_child(menu)

	# CONTINUAR so aparece quando ha run guardada, e diz ONDE ela parou: um
	# botao de continuar que nao informa o que sera continuado obriga o jogador
	# a apertar para descobrir.
	if _tem_save:
		var seguir := UI.button_confirmar("  CONTINUAR — PASSO %d  " % _save_passo, UI.F_H2)
		seguir.custom_minimum_size = Vector2(MENU_W, 0)
		seguir.pressed.connect(func(): continue_requested.emit())
		menu.add_child(seguir)
		var novo := UI.button("  NOVA RUN  ", UI.F_H2)
		novo.custom_minimum_size = Vector2(MENU_W, 0)
		novo.tooltip_text = "Apaga a run guardada."
		novo.pressed.connect(_start)
		menu.add_child(novo)
	else:
		var jogar := UI.button_confirmar("  JOGAR  ", UI.F_H1)
		jogar.custom_minimum_size = Vector2(MENU_W, 60)
		jogar.pressed.connect(_start)
		menu.add_child(jogar)

	var opcoes := UI.button("  CONFIGURAÇÕES  ", UI.F_H2)
	opcoes.custom_minimum_size = Vector2(MENU_W, 0)
	opcoes.pressed.connect(func(): options_requested.emit())
	menu.add_child(opcoes)

	# SAIR deixou de ser VERMELHO. `UI.BAD` e a cor de "voce esta perdendo vida"
	# no combate inteiro; gasta-la no botao mais inofensivo do jogo — fechar a
	# janela — era o mesmo erro que o relatorio mediu no confirmar.
	var sair := UI.button("  SAIR  ", UI.F_H2)
	sair.custom_minimum_size = Vector2(MENU_W, 0)
	sair.pressed.connect(func(): get_tree().quit())
	menu.add_child(sair)

	col.add_child(UI.spacer(12, false))

	# A SEMENTE fica embaixo e discreta: é ferramenta de teste, não decisão de
	# quem só quer jogar. Vazia = aleatória.
	var row := UI.box(false, 10)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_child(row)
	var sl := UI.label("Semente", UI.F_SMALL, UI.TEXT_DIM)
	sl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(sl)
	_seed_field = LineEdit.new()
	_seed_field.placeholder_text = "aleatória"
	_seed_field.custom_minimum_size = Vector2(150, 0)
	var lajota := UI.materia_da_sala(UI.PANEL_HI, SALA)
	_seed_field.add_theme_stylebox_override("normal", UI.panel(lajota, 6, UI.LINE))
	_seed_field.add_theme_stylebox_override("focus", UI.panel(lajota, 6, UI.ACCENT))
	_seed_field.add_theme_color_override("font_color", UI.TEXT)
	row.add_child(_seed_field)

	col.add_child(UI.label(
		"Durante o combate: 1–3 lançam Ativos · ESPAÇO pausa · TAB muda a velocidade",
		11, UI.TEXT_DIM, HORIZONTAL_ALIGNMENT_CENTER))


func _start() -> void:
	var txt := _seed_field.text.strip_edges()
	start_requested.emit(int(txt) if txt.is_valid_int() else 0)
