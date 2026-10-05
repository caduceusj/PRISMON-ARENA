class_name PickPanel
extends Control
## Escolher UMA coisa entre poucas: lista à esquerda, PREVIEW à direita.
##
## Desenho pedido pelo autor (03/09), a partir da loja do *How Many Dudes*: a
## lista diz só nome e tipo, e o item selecionado abre num painel ao lado com o
## ícone grande e a descrição embaixo. É melhor do que a lista antiga por dois
## motivos concretos:
##
##   * a linha da lista para de carregar descrição, então todas as linhas têm
##     a MESMA altura e a coluna fica regular;
##   * a descrição ganha espaço de verdade em vez de quebrar em três linhas
##     dentro de um cartão apertado.
##
## A peça é compartilhada de propósito: a Feira e o momento de Poder usam a
## mesma tela, então o jogador aprende a ler uma vez só. Quem usa só fornece as
## ofertas e decide o que acontece no botão de confirmar.
##
## == O QUE MUDOU EM 15/09: COMPARTILHADA NÃO É IDÊNTICA ==
##
## A revisão mediu a caixa de conteúdo das quatro telas que passam por aqui:
## loja 954x604 em (323,148) e cozinha 954x604 em (323,148) — IDÊNTICO ao
## pixel. "A PANELA ESTÁ NO FOGO" e "FEIRA DE PASSAGEM" liam como a mesma tela
## com as palavras trocadas, e o diagnóstico foi "não há cenografia, não há
## fogo, não há banca, não há mercador".
##
## A gramática compartilhada era a coisa certa e continua; o que faltava era um
## lugar onde cada momento pudesse ser ELE MESMO. São três agora:
##
##   `sala`           a cor do lugar — luz aditiva, tinta da faixa, fissura
##   `header_builder` a CENOGRAFIA: a bolsa da Feira, o fogo da Cozinha, a Mão
##                    do Domador no Poder, o que o Mercador vê da sua equipe.
##                    É ela que faz a caixa de conteúdo ter tamanhos diferentes.
##   `list_title`     o que a coluna da esquerda É naquele lugar
##
## Medido depois: as caixas de conteúdo passaram a 1180 px de largura (a mesma
## de `UI.BANNER_W`, então a faixa deixou de ter seis larguras) e alturas de
## 644 / 674 / 700 / 688 px — nenhum par idêntico.

signal chosen(offer: Dictionary)
signal dismissed
signal rerolled

## A LUZ DE CADA SALA: uma cor por momento, nenhuma repetida.
##
## Elas continuam MORANDO NUM LUGAR SÓ, porque a regra é sobre o CONJUNTO
## ("nenhuma repetida") — mas desde 17/09 esse lugar é `data/paleta.json`, no
## bloco `salas`, e não seis `const Color("#...")` aqui. Trocar a cara do jogo
## deixou de exigir editar GDScript. O nome da sala é o nome do MOMENTO, e é o
## mesmo nome nos dois lados.
##
## Por que continuam existindo como nome AQUI: sete telas escrevem
## `PickPanel.SALA_FEIRA`, e o erro que se quer impedir é alguém escrever
## `UI.cor_da_sala("feira")` (a chave é "loja") e receber uma tela sem cor.
## Com o apelido, o nome errado não compila em vez de desbotar em silêncio.
##
## `static var` com getter, e não `const`: `const` não pode ler `static var`, e
## a paleta só existe depois de `Db.load_all()`. O getter resolve na hora do uso
## — que é sempre dentro de um `_ready()`, ou seja, depois dos autoloads.
static var SALA_FEIRA: Color:
	get: return UI.cor_da_sala("loja")        # âmbar de lamparina sobre a banca
static var SALA_COZINHA: Color:
	get: return UI.cor_da_sala("cozinha")     # laranja de brasa
static var SALA_PODER: Color:
	get: return UI.cor_da_sala("poder")       # ciano de descarga
static var SALA_TROCA: Color:
	get: return UI.cor_da_sala("troca")       # verde de lona de carroça
static var SALA_ACASO: Color:
	get: return UI.cor_da_sala("acaso")       # violeta frio de estrada à noite
static var SALA_RECRUTA: Color:
	get: return UI.cor_da_sala("recruta")     # azul de crepúsculo


## O QUE FAZ A SALA APARECER, e por que não foi só subir o halo.
##
## O sistema de sala existia desde 15/09 e ninguém o via. A causa não era o
## nome nem a chamada: era que a MATÉRIA é a mesma em toda tela. Um halo de 6%
## por cima de uma lajota idêntica em dez telas continua sendo dez vezes a
## mesma lajota. E subir só o halo não resolve — ele é aditivo e chapado, e em
## 20% lava a tela inteira de leitoso sem que a lajota mude de lugar.
##
## O que muda de lugar é o DEGRAU. Toda tela desta leva passa os seus degraus
## por `UI.materia_da_sala(degrau, cor_da_sala)`, que gira matiz e saturação do
## degrau para a cor do lugar e preserva o V — uma tela azul passa a ser FEITA
## de lajota azul. O QUANTO mora em `sala_na_materia`, em data/paleta.json:
## nenhuma tela escreve esse número, elas dizem só QUAL lugar. Com a paleta
## "vidro" (0,0) a função é a identidade e o jogo volta ao neutro de 16/09 sem
## tocar em uma linha de GDScript — que é o pedido de customização do autor.

## Uma oferta é um Dictionary com, no mínimo:
##   id · name · text · kind_label (a palavra sob o nome: "Relíquia", "Poder"…)
## e opcionalmente:
##   price (int) · icon (nome no Icons) · color (String) · owner (species_id)
##   blocked (String — o motivo, quando não dá para levar)
var offers: Array = []

## Rótulo do botão que confirma. "COMPRAR" na Feira, "APRENDER" no Poder.
var confirm_label := "COMPRAR"

## Rótulo do botão de sair. "DISPENSAR" na Feira, "SAIR DA COZINHA" na Cozinha —
## a saída também é parte do lugar.
var dismiss_label := "DISPENSAR"

## O que a coluna da esquerda É neste momento: a banca, o cardápio, os poderes.
var list_title := ""

## Gancho opcional para desenhar o preview à mão: `Callable(oferta, VBox)`.
## Existe para o Mercador de Trocas, onde o preview não é "o que é isto" e sim
## "o que você dá CONTRA o que você recebe" — uma comparação lado a lado. Sem
## o gancho, o preview padrão (nome, ícone grande, descrição) continua valendo.
var preview_builder: Callable = Callable()

## A CENOGRAFIA da sala: `Callable(col: VBoxContainer)`, montada entre a faixa
## de título e o corpo. É o que impede as quatro telas de serem o mesmo
## retângulo — ver a nota no topo do arquivo.
var header_builder: Callable = Callable()

## A cor do lugar. Use uma das constantes SALA_* acima.
var sala: Color = SALA_FEIRA

var title_text := ""
var subtitle_text := ""
var reroll_label := ""          # vazio esconde o botão de renovar
var reroll_enabled := true

## A LARGURA DE CASA. A soma das duas colunas mais o respiro é exatamente
## `UI.BANNER_W` (1180) — a mesma largura útil que o combate já usa na barra de
## tempo. A revisão mediu SEIS larguras de faixa no jogo (688 a 1412 px) para o
## único elemento que aparece em todas as telas; as quatro que passam por aqui
## convergem de uma vez, e a coluna do preview ganha 176 px, que é onde a prosa
## do item finalmente cabe em duas linhas em vez de quatro.
const LIST_W := 520.0
const PREVIEW_W := 646.0
const GAP := 14                 # respiro entre painéis e em volta dos botões

## A LINHA E O SEU ESPACO SAO A MEDIDA DA LISTA (revisão 04/09).
##
## `ROW_H` era 66 e servia só de piso — o conteúdo real (ícone, nome, tipo)
## pedia 89 px, e ninguém sabia disso. A caixa de rolagem então ficava com
## 322 px, que dá 3,45 linhas: a quarta aparecia cortada ao meio e a lista
## lia como QUEBRADA em vez de rolável.
##
## Agora a linha manda: 90 px de altura fixa, e a caixa recebe um número
## INTEIRO delas. `tools/lista_probe` confere as duas coisas — se o conteúdo
## de uma linha crescer além de ROW_H, o probe acusa antes de virar print.
const ROW_H := 90.0
const ROW_SEP := 6
const LINHAS_VISIVEIS := 4


## Altura da caixa de rolagem: sempre um número inteiro de linhas.
static func altura_da_lista() -> float:
	return float(LINHAS_VISIVEIS) * (ROW_H + float(ROW_SEP)) - float(ROW_SEP)

## Altura RESERVADA para o miolo. Sem ela o CenterContainer encolhe tudo até o
## mínimo do conteúdo: com quatro ofertas a lista aparecia com duas linhas e
## meia e uma barra de rolagem, num painel perdido no meio da tela. Aqui a
## caixa tem tamanho fixo e a lista só rola quando o estoque passa dela.
const BODY_H := 470.0

var _sel := 0
var _rows: Array = []

## A DICA DE CADA LINHA, guardada fora do controle.
##
## A linha SELECIONADA fica sem `tooltip_text` (ver `_dicas_da_selecao`), então
## o texto precisa de um lugar de onde voltar quando a seleção mudar. Guardar no
## próprio nó não serve: apagar e repor no mesmo campo é o que se quer evitar
## quando o valor certo tem de sobreviver a uma troca de seleção.
var _tips: Array = []
var _preview: VBoxContainer
var _confirm: Button
var _list: VBoxContainer


func _ready() -> void:
	# A LUZ ENTRA PRIMEIRO: é o filho zero, então desenha atrás de tudo. Ela
	# também registra `UI.sala`, e é de lá que a sombra dura dos títulos de 36 e
	# 54 px tira a cor — por isso tem de existir ANTES do primeiro rótulo.
	add_child(UI.luz_de_sala(sala))

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var col := UI.box(true, GAP)
	center.add_child(col)

	if title_text != "":
		col.add_child(UI.banner(title_text, sala))
	if subtitle_text != "":
		col.add_child(UI.label(subtitle_text, UI.F_SMALL, UI.TEXT_DIM,
			HORIZONTAL_ALIGNMENT_CENTER))

	# A CENOGRAFIA da sala, entre a faixa e o corpo.
	if header_builder.is_valid():
		header_builder.call(col)

	var row := UI.box(false, GAP)
	row.custom_minimum_size = Vector2(0, BODY_H)
	col.add_child(row)
	row.add_child(_left_column())
	row.add_child(_right_column())
	_select(0)


# --- coluna da lista --------------------------------------------------------

func _left_column() -> Control:
	# A LAJOTA DESTE LUGAR. Era `UI.card()` — o painel neutro, igual ao das
	# outras nove telas. Agora a banca é âmbar, a panela é brasa e a bancada de
	# Poder é ciano, porque a matéria muda, não só o halo.
	var card := UI.card(UI.materia_da_sala(UI.PANEL, sala))
	card.custom_minimum_size = Vector2(LIST_W, 0)
	var v := UI.box(true, 8)
	card.add_child(v)

	# O QUE ESTA COLUNA É. Uma palavra, e as quatro telas param de ter a mesma
	# coluna esquerda sem legenda nenhuma.
	if list_title != "":
		v.add_child(UI.label(list_title, UI.F_SMALL, UI.tint_of(sala, true),
			HORIZONTAL_ALIGNMENT_CENTER))

	if reroll_label != "":
		var rr := UI.button_secundario(reroll_label, UI.F_SMALL)
		rr.disabled = not reroll_enabled
		rr.pressed.connect(func(): rerolled.emit())
		v.add_child(rr)

	# a lista rola: com renovar, o estoque pode passar da altura da tela
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	# AUTO, escrito: a barra de rolagem roxa aparecendo cheia onde não há nada
	# para rolar é um achado da revisão, e o modo é a diferença entre "some
	# quando não precisa" e "fica lá". Com 4 ofertas e 4 linhas visíveis, o caso
	# comum desta peça é justamente o que NÃO rola.
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	# O MINIMO VAI NA CAIXA, e não no painel inteiro: o painel tem chrome
	# diferente em cada tela (a loja tem botão de renovar, a cozinha não), e
	# uma altura fixa lá em cima sobra em uma e falta na outra. Aqui a conta é
	# sempre a mesma — tantas linhas inteiras, ponto.
	scroll.custom_minimum_size = Vector2(0, altura_da_lista())
	v.add_child(scroll)
	_list = UI.box(true, ROW_SEP)
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# RESPIRO À DIREITA (autor, 03/09: "adicione um leve espaçamento onde usa
	# scroll pois está muito apertado"): sem isto a linha encosta na barra de
	# rolagem e a barra parece parte do cartão.
	var pad := MarginContainer.new()
	pad.add_theme_constant_override("margin_right", GAP)
	pad.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pad.add_child(_list)
	scroll.add_child(pad)

	_rows.clear()
	_tips.clear()
	for i in range(offers.size()):
		var r := _row(i)
		_rows.append(r)
		_tips.append(String(r.tooltip_text))
		_list.add_child(r)
		# a lista se monta de cima para baixo: o olho segue a ordem em que
		# deve ler, em vez de receber as quatro linhas de uma vez
		Juice.enter_item(r, i)
	if offers.is_empty():
		_list.add_child(UI.label("Nada por aqui.", UI.F_BODY, UI.TEXT_DIM,
			HORIZONTAL_ALIGNMENT_CENTER))

	# SAIR É RECUAR, e recuar é roxo. Antes era um `UI.button` cru de 46 px de
	# altura — uma das três alturas de botão que a revisão mediu convivendo, e
	# quebrada justo na peça mais reusada do jogo. Agora a altura vem de
	# `UI.BTN_H` (58), como em todo botão.
	var out := UI.button_secundario(dismiss_label)
	out.pressed.connect(func(): dismissed.emit())
	v.add_child(out)
	return card


## Uma linha: ícone, nome, tipo, e o preço à direita. SEM descrição — é ela que
## fazia as linhas terem alturas diferentes e a coluna ficar irregular.
func _row(i: int) -> CardButton:
	var o: Dictionary = offers[i]
	var col := _color_of(o)
	var card := CardButton.make(UI.PANEL, col).as_list_row()
	card.custom_minimum_size = Vector2(0, ROW_H)
	card.clicked.connect(_select.bind(i))

	var row := UI.box(false, 10)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.body.add_child(row)
	row.add_child(_icon_of(o, 32.0))

	var v := UI.box(true, 1)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(v)
	var nm := UI.label(String(o.get("name", "")), UI.F_BODY, col.lightened(0.3))
	nm.clip_text = true
	v.add_child(nm)
	v.add_child(UI.label(String(o.get("kind_label", "")), UI.F_SMALL, UI.TEXT_DIM))

	# retrato do dono, quando o item é de uma criatura específica. 40 px e
	# não 30: em 30 o sprite dentro do aro saía escuro demais para
	# reconhecer de relance, que é a única coisa que ele precisa fazer.
	var owner := String(o.get("owner", ""))
	if owner != "":
		row.add_child(_dono(owner, 40.0))
		# A DICA MORTA (achado da revisão): o medalhão tinha `tooltip_text` e
		# `mouse_filter = IGNORE`, e ainda por cima o botão invisível do
		# CardButton cobre a linha inteira — ela nunca apareceu uma vez. O
		# Godot sobe pelos pais quando o controle sob o mouse não tem dica
		# própria, então a dica da LINHA é a que de fato aparece.
		card.tooltip_text = "Só o %s pode usar" % Db.sp_name(owner)

	if o.has("price"):
		var pr := UI.box(false, 4)
		pr.alignment = BoxContainer.ALIGNMENT_END
		pr.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		pr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var ok: bool = Run.ether >= int(o["price"])
		# A MOEDA EM TAMANHO DE MOEDA. Saía em 16 px aqui e 32 no HUD — metade
		# do tamanho justamente na tela onde se gasta dinheiro (medido na
		# revisão como 10 px de tinta contra 23). O HUD usa
		# `UI.icon_px(UI.F_H2)`; a loja passa a usar o mesmo.
		pr.add_child(Icons.node("ether", UI.icon_px(UI.F_H2),
			UI.GOLD if ok else UI.TEXT_DIM))
		var pl := UI.label(str(int(o["price"])), UI.F_H2, UI.GOLD if ok else UI.BAD)
		pl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		pr.add_child(pl)
		row.add_child(pr)

	# O QUE NÃO DÁ PARA LEVAR se apaga um pouco — mas continua clicável, porque
	# o motivo mora no preview e o jogador precisa poder ir lê-lo.
	var why := _motivo(o)
	if why != "":
		card.modulate = Color(1, 1, 1, 0.72)
		card.tooltip_text = why
	return card


# --- coluna do preview ------------------------------------------------------

func _right_column() -> Control:
	# a lajota ERGUIDA do mesmo lugar: um degrau acima da lista, mesmo matiz
	var card := UI.card(UI.materia_da_sala(UI.PANEL_HI, sala), UI.LINE)
	card.custom_minimum_size = Vector2(PREVIEW_W, 0)
	_preview = UI.box(true, GAP)
	card.add_child(_preview)
	return card


func _select(i: int) -> void:
	if offers.is_empty():
		_paint_preview({})
		return
	_sel = clampi(i, 0, offers.size() - 1)
	for k in range(_rows.size()):
		_rows[k].set_selected(k == _sel)
	_dicas_da_selecao()
	_paint_preview(offers[_sel])


## A LINHA SELECIONADA NÃO TEM DICA (autor, 16/09).
##
## O print dele mostra a caixa escura da dica aberta POR CIMA da lista, dizendo
## "…+45% de…" — enquanto o painel do lado, a 14 px de distância, já mostrava a
## mesma frase em corpo maior e sem cursor nenhum: *"não precisa dessas caixas
## de texto se o overlay de atributo já mostra"*.
##
## Não é uma coincidência de conteúdo, é estrutural: o preview desta tela É o
## espelho da linha selecionada. Nome, ícone grande, texto, dono e motivo de
## bloqueio — tudo que a dica da linha diria já está aberto ao lado. Então a
## regra que vale aqui, e que vale para qualquer par lista/preview do jogo:
##
##   se a informação já está visível num painel da tela, a dica não abre.
##
## As linhas NÃO selecionadas continuam com dica: delas o preview não mostra
## nada, e é justamente a pergunta "e esta aqui, o que é?" que o cursor faz
## antes de clicar.
func _dicas_da_selecao() -> void:
	for k in range(_rows.size()):
		if k >= _tips.size():
			continue
		_rows[k].tooltip_text = "" if k == _sel else String(_tips[k])


## POR QUE NÃO DÁ PARA LEVAR — sempre uma frase, nunca um botão apagado sem
## explicação.
##
## Era a diferença medida entre as duas telas gêmeas: "na Feira o COMPRAR morre
## em silêncio quando falta Éter; na Cozinha a mesma situação é escrita na cara
## do jogador". O motivo estava certo na Cozinha porque `ScreenKitchen._blocker`
## escrevia `blocked = "Éter insuficiente"`; a Feira nunca escreveu, e o preço
## simplesmente desabilitava o botão.
##
## A conta de Éter vive AQUI e não nas telas de propósito: é a mesma regra para
## todo mundo que tem `price`, e a economia apertou em 15/09 (sobra mediana de
## 119 para 30 de Éter, 406 itens recusados em 1000 runs) — a partir de agora
## isto acontece de verdade, e em toda tela com preço.
func _motivo(o: Dictionary) -> String:
	var why := String(o.get("blocked", ""))
	if why != "":
		return why
	if o.has("price"):
		var falta: int = int(o["price"]) - Run.ether
		if falta > 0:
			return "falta %d de Éter — você tem %d" % [falta, Run.ether]
	return ""


func _paint_preview(o: Dictionary) -> void:
	for c in _preview.get_children():
		_preview.remove_child(c)
		c.queue_free()
	if o.is_empty():
		_preview.add_child(UI.label("—", UI.F_BODY, UI.TEXT_DIM,
			HORIZONTAL_ALIGNMENT_CENTER))
		return
	var col := _color_of(o)
	var why := _motivo(o)

	# o preview PULSA ao trocar de seleção: sem isso, clicar numa linha da
	# lista muda o painel ao lado em silêncio e o olho não acompanha
	Juice.pulse(_preview, 1.015)
	if preview_builder.is_valid():
		# SEM espaçador: quem desenha o preview à mão decide como preencher a
		# coluna. Com um espaçador expansível aqui, ele disputava a folga com o
		# comparativo do Mercador (que também expande) e os dois ficavam com
		# metade — o comparativo encolhia e sobrava um buraco embaixo dele.
		preview_builder.call(o, _preview)
		_fechar_preview(o, why)
		return

	_preview.add_child(UI.label(String(o.get("name", "")), UI.F_H1,
		col.lightened(0.3), HORIZONTAL_ALIGNMENT_CENTER))

	# palco do ícone: fundo próprio e o ícone GRANDE, como na referência
	var stage := PanelContainer.new()
	stage.add_theme_stylebox_override("panel",
		UI.frame(UI.C_INSET, UI.tint_of(col.darkened(0.3)), 18, 18))
	stage.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_preview.add_child(stage)
	var mid := CenterContainer.new()
	stage.add_child(mid)
	mid.add_child(_icon_of(o, 96.0))

	# DE QUEM É. O preview é onde o jogador olha o detalhe, e era a única
	# das duas colunas que não dizia nada sobre o dono do item — ele
	# aparecia só como um medalhão pequeno na linha da lista.
	var dono := String(o.get("owner", ""))
	if dono != "":
		var linha_dono := UI.box(false, 8)
		linha_dono.alignment = BoxContainer.ALIGNMENT_CENTER
		_preview.add_child(linha_dono)
		linha_dono.add_child(_dono(dono, 48.0))
		var quem := UI.label("Só o %s pode usar" % Db.sp_name(dono),
			UI.F_SMALL, Db.el_color(String(Db.sp(dono).get("element", "FOGO"))).lightened(0.3))
		quem.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		linha_dono.add_child(quem)

	var txt := UI.wrap(String(o.get("text", "")), UI.F_SMALL, UI.TEXT)
	txt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_preview.add_child(txt)

	# SEM espaçador no fim: o `stage` já expande, e dois filhos expansíveis na
	# mesma coluna dividem a folga — o palco do ícone encolhia para a metade e a
	# outra metade virava um buraco entre a descrição e o preço. Com um só, a
	# folga toda vai para o palco e o pé continua colado embaixo.
	_fechar_preview(o, why)


## O pé do preview: o preço, o motivo de não dar, e o botão que comete.
##
## O PREÇO EM TAMANHO DE PREÇO: é o número que decide a compra e ele aparecia
## só na lista, em 16 px, ao lado de uma moeda de 16. Aqui ele fica ao lado do
## que você TEM — comprar é uma subtração, e uma subtração precisa dos dois
## números à vista.
func _fechar_preview(o: Dictionary, why: String) -> void:
	if o.has("price"):
		var preco := int(o["price"])
		var da: bool = Run.ether >= preco
		var linha := UI.box(false, 8)
		linha.alignment = BoxContainer.ALIGNMENT_CENTER
		_preview.add_child(linha)
		linha.add_child(Icons.node("ether", UI.icon_px(UI.F_H2),
			UI.GOLD if da else UI.BAD))
		var pl := UI.label(str(preco), UI.F_H1, UI.GOLD if da else UI.BAD)
		pl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		linha.add_child(pl)
		var tem := UI.label("de %d na bolsa" % Run.ether, UI.F_SMALL, UI.TEXT_DIM)
		tem.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		linha.add_child(tem)

	if why != "":
		_preview.add_child(UI.label(why, UI.F_SMALL, UI.BAD,
			HORIZONTAL_ALIGNMENT_CENTER))

	# CONFIRMAR É VERDE, SEMPRE. Recebia `col` — a cor da oferta SELECIONADA —
	# então o mesmo botão mudava de cor a cada clique na lista, e nenhuma das
	# cores era a que `docs/pecas/botoes.png` define como "confirmar". A forma
	# também mudou: `button_confirmar` tem um SEGUNDO canto cortado, que lê como
	# commit até em escala de cinza.
	_confirm = UI.button_confirmar("  %s  " % confirm_label, UI.F_H2)
	_confirm.disabled = why != ""
	_confirm.pressed.connect(func(): chosen.emit(o))
	_preview.add_child(_confirm)


# --- comuns -----------------------------------------------------------------

## Retrato de quem pode usar. Medalhão de lado fixo com o aro na cor do
## elemento — a mesma peça da doca e do painel de combate, para a criatura ser
## reconhecida pela MESMA imagem em toda a interface.
func _dono(species_id: String, px: float) -> Control:
	var el := String(Db.sp(species_id).get("element", "FOGO"))
	var med := MonsterPortrait.medallion(species_id, el, px)
	# SEM DICA, nos dois lugares em que este medalhão aparece — e pelo mesmo
	# motivo de `_dicas_da_selecao`, aplicado a mais um caso:
	#
	#   no PREVIEW a frase "Só o Apollo pode usar" está escrita ao lado do
	#   medalhão, a 8 px dele. Uma dica que repete a legenda encostada no
	#   desenho é a definição do ruído que o autor apontou;
	#   na LINHA da lista o botão invisível do CardButton cobre tudo, então a
	#   dica do medalhão nunca chegou a aparecer uma vez (achado da revisão de
	#   15/09) — lá a frase mora no `tooltip_text` da linha, ver `_row`.
	#
	# IGNORE e não STOP: sem dica própria, parar o mouse aqui deve continuar
	# valendo como parar o mouse no painel que está por baixo.
	med.mouse_filter = Control.MOUSE_FILTER_IGNORE
	med.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return med


func _color_of(o: Dictionary) -> Color:
	if o.has("color"):
		return Color(String(o["color"]))
	var owner := String(o.get("owner", ""))
	if owner != "":
		return Db.el_color(String(Db.sp(owner).get("element", "FOGO")))
	return UI.GOLD


func _icon_of(o: Dictionary, px: float) -> Control:
	var ic := Icons.node(String(o.get("icon", "")), px)
	ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return ic
