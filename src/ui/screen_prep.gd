class_name ScreenPrep
extends Control
## GDD 21.1 — a tela de preparação responde CINCO perguntas: Ressonâncias
## ativas, reações possíveis, formação prevista, cozinha e Vínculo.
##
## ------------------------------------------------------------------------
## RECOMPOSIÇÃO DE 16/09 — "os bonecos estão amontoados em meio a muita
## informação que pode ser consultada via subsecções ao invés de mostrados
## assim" (autor, com print).
##
## A leva de 15/09 tinha resolvido o VAZIO desta tela e criado o problema
## oposto. O print mostra o elenco espremido no meio de TRÊS blocos abertos ao
## mesmo tempo: "CONTRA ESTE BANDO" à esquerda (430 px), "O QUE ESTA EQUIPE
## PRODUZ" por cima das criaturas, e a coluna FORMAÇÃO / MÃO / ITENS à direita
## (340 px). Sobravam 766 px de largura para cinco corpos, e neles os nomes se
## encavalavam (ver o conserto em `ranch_view.gd`).
##
## A tela agora tem DUAS zonas, e não três colunas:
##
##   PALCO       a equipe em pé, ocupando a largura que sobra, e o LUTAR logo
##               abaixo dela — o botão fecha o bloco em vez de flutuar numa
##               faixa própria a 200 px de distância
##   CONSULTA    UM painel de 430 px com TRÊS SUBSEÇÕES em abas:
##                 BANDO    quem está do outro lado e o que ele acende em você
##                 EQUIPE   formação prevista, o que a equipe produz, e a porta
##                          para o painel completo de Sinergias
##                 MOCHILA  a Mão do Domador, relíquias e itens equipados
##
## NADA FOI CORTADO — tudo o que a tela mostrava continua alcançável, a um
## clique de distância. O que mudou é quantas dessas coisas gritam ao mesmo
## tempo: eram três blocos e uma coluna, hoje é um painel com uma aba aberta.
##
## QUAIS DAS CINCO PERGUNTAS FICARAM SEM CLIQUE (NOTAS 3.10, critério 21.1):
##   · Vínculo             VISÍVEL — chip do cabeçalho
##   · quem vai lutar      VISÍVEL — o palco, que é a resposta mais direta e a
##                         única que exige espaço em vez de texto
##   · formação prevista   VISÍVEL EM PARTE — o rancho já ordena por Postura no
##                         chão; o detalhe por faixa vive na aba EQUIPE
##   · reações possíveis   CONSULTA (aba EQUIPE) — eram OITO pastilhas coloridas
##                         em cima das criaturas, o bloco mais denso da tela
##   · Ressonâncias        CONSULTA (ANALISAR SINERGIAS, onde já moravam os pips)
##   · cozinha             fora desta tela: o Estômago está no trilho do elenco,
##                         visível durante a run inteira
##
## A GRAMÁTICA DO BANDO continua a mesma da tela anterior (`screen_map.gd`):
## texto agrupado, "4 Apollos", nunca quatro medalhões repetidos.
##
## E A COLUNA DEIXOU DE CORTAR O ÚLTIMO ITEM. A causa não era a altura — era
## que a rolagem não tinha FUNDO: a doca de itens terminava no nada, sem uma
## aresta que dissesse "acabou aqui, role para ver o resto". Agora a rolagem
## vive DENTRO do painel de consulta, e é a aresta do painel que a fecha.

signal fight


var _node: Dictionary = {}

## Largura da coluna de consulta. É a LINHA DE LISTA da folha de peças (430 px)
## — a mesma medida que a coluna do bando usava, agora com as três subseções
## dentro dela em vez de duas colunas disputando a tela.
const COL_CONSULTA := 430.0

const ABAS := ["BANDO", "EQUIPE", "MOCHILA"]

var _aba := 0
var _botoes: Array = []
var _corpo: BoxContainer


func setup(node: Dictionary) -> void:
	_node = node


func _ready() -> void:
	# A SALA É A ARENA. Cada rinha acontece num lugar, e o lugar tem cor
	# própria em data/enemies.json — é o único dado de ambiente que já existe.
	# Sem esta chamada todo título de 36 e 54 px usaria sombra preta, porque a
	# sombra dura dos títulos tira a cor de `UI.sala`, que `luz_de_sala` registra.
	add_child(UI.luz_de_sala(_cor_da_sala()))

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for s in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + s, 18)
	add_child(margin)

	var col := UI.box(true, 12)
	margin.add_child(col)
	col.add_child(_header())

	var row := UI.box(false, 16)
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(row)
	# O elenco NÃO mora aqui como lista: ele mora no trilho fixo da esquerda
	# (RosterRail), visível em toda a run. O que mora aqui é o palco — os
	# mesmos bichos, de corpo inteiro, que é a leitura que o trilho não dá.
	row.add_child(_palco())
	row.add_child(_consulta())
	_abrir(0)


func _cor_da_sala() -> Color:
	var arena: Dictionary = Db.arenas.get(String(_node.get("payload", {}).get("arena", "")), {})
	if arena.is_empty():
		return Color("#7a6a9e")
	return Color(String(arena.get("tint", "#7a6a9e")))


# --- faixa 1: cabeçalho ----------------------------------------------------

## Faixa de título em LARGURA FIXA + uma linha de chips.
##
## A faixa tinha seis larguras diferentes no jogo (688 a 1412 px, medidas) para
## o único elemento presente em todas as telas; aqui ela era `EXPAND_FILL` e
## ficava com a largura da tela inteira. UI.BANNER_W = 1180 é a mesma BAR_W que
## o combate usa, então a faixa da preparação e a barra de tempo do combate se
## alinham — duas telas consecutivas com a mesma borda.
##
## E o texto virou CAIXA ALTA: esta era a única faixa em caixa mista do jogo, na
## tela mais visitada da run.
func _header() -> Control:
	var v := UI.box(true, 8)
	var bn := UI.banner(String(_node.get("title", "Rinha")).to_upper(), _cor_da_sala())
	bn.custom_minimum_size.x = UI.BANNER_W
	bn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	v.add_child(bn)

	var chips := UI.box(false, 8)
	chips.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_child(chips)

	var danger := int(_node.get("danger", 0))
	var dcor: Color = UI.GOLD if danger <= 2 else (UI.WARN if danger <= 4 else UI.BAD)
	chips.add_child(_chip("PERIGO", UI.stars(danger), dcor))

	var corpos := 0
	for l in _bando():
		corpos += int(l["n"])
	chips.add_child(_chip("BANDO", "%d corpos" % corpos, UI.TEXT_DIM))
	chips.add_child(_chip("VÍNCULO", "%d/%d" % [Run.bond_used(), Run.bond_total()],
		UI.ACCENT.lightened(0.2)))

	# as mesmas regras da tela de escolha, repetidas aqui de propósito: é a
	# última tela antes de LUTAR, e é onde o jogador ainda pode montar a
	# equipe sabendo o que o espera.
	chips.add_child(UI.rules_strip(_node.get("payload", {}), UI.F_SMALL))
	return v


## Pastilha rotulada. É a diferença entre "★★★★☆" solto num canto e um dado com
## nome: a revisão mediu cinco estrelas sem rótulo e sem dica na versão antiga.
func _chip(rotulo: String, valor: String, cor: Color) -> Control:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", UI.frame(UI.C_PANEL_HI, cor, 10, 6))
	var row := UI.box(false, 7)
	var r := UI.label(rotulo, UI.F_SMALL, UI.TEXT_DIM)
	r.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(r)
	var val := UI.label(valor, UI.F_SMALL, cor)
	val.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(val)
	p.add_child(row)
	p.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return p


# --- zona 1: o palco -------------------------------------------------------

## A equipe em pé, e o botão que a manda lutar — nesta ordem, colados.
##
## O RODAPÉ DEIXOU DE SER UMA FAIXA DA TELA INTEIRA (era assim desde 15/09, e a
## razão registrada então era impedir que a coluna de consulta corresse até a
## borda de baixo e fatiasse o último cartão). A razão continua válida e o
## conserto dela mudou de lugar: hoje quem fecha a consulta é a ARESTA DO
## PAINEL dela, não um rodapé vazio atravessado embaixo. Em troca, o LUTAR
## parou de flutuar a 200 px do elenco — o print do autor mostrava "um vazio
## grande embaixo das criaturas", e metade dele era esta faixa.
func _palco() -> Control:
	var col := UI.box(true, 14)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var ranch := RanchView.new()
	ranch.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(ranch)

	var foot := UI.box(false, 12)
	foot.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_child(foot)
	# VERDE, e com o segundo canto cortado. Era vermelho — a cor que o combate
	# inteiro usa para "você está perdendo vida" — em cima do botão que começa a
	# briga. Ver `docs/pecas/botoes.png`, gerada do próprio código.
	var b := UI.button_confirmar("  LUTAR  ", UI.F_H1)
	b.custom_minimum_size = Vector2(420, 0)
	b.pressed.connect(func(): fight.emit())
	foot.add_child(b)
	return col


# --- zona 2: a consulta, em três subseções ----------------------------------

## UM painel, TRÊS abas, uma aberta por vez.
##
## As abas são `CardButton.as_list_row()` — a peça do kit para "linha de lista
## sem caixa": feixe de 3 px na aresta em repouso, 6 sob o mouse, e a célula
## C_FOCUS (o feixe descendo a aresta inteira) quando é a escolhida. É a mesma
## gramática de seleção do resto do jogo, então não há nada novo para aprender.
func _consulta() -> Control:
	var painel := PanelContainer.new()
	painel.custom_minimum_size = Vector2(COL_CONSULTA, 0)
	painel.add_theme_stylebox_override("panel", UI.frame(UI.C_PANEL, UI.LINE, 14, 12))

	var v := UI.box(true, 10)
	painel.add_child(v)

	var tira := UI.box(false, 6)
	v.add_child(tira)
	_botoes.clear()
	for i in range(ABAS.size()):
		tira.add_child(_botao_aba(i))

	# A ROLAGEM VIVE DENTRO DO PAINEL, e é isso que conserta o corte do rodapé:
	# o conteúdo termina numa aresta desenhada, não no ar. A calha reservada
	# segura a largura para o conteúdo não andar quando a barra aparece.
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	v.add_child(scroll)
	var calha := MarginContainer.new()
	calha.add_theme_constant_override("margin_right", PrismaTheme.SCROLL_W)
	calha.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(calha)
	_corpo = UI.box(true, 10)
	calha.add_child(_corpo)
	return painel


func _botao_aba(i: int) -> Control:
	var b := CardButton.make(UI.PANEL, _cor_da_sala()).as_list_row()
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var t := UI.label(String(ABAS[i]), UI.F_SMALL, UI.TEXT, HORIZONTAL_ALIGNMENT_CENTER)
	b.body.add_child(t)
	b.clicked.connect(func(): _abrir(i))
	_botoes.append(b)
	return b


## Troca o conteúdo da subseção. A tela inteira NÃO é remontada: só o miolo do
## painel de consulta muda, então o palco não pisca e o idle das criaturas não
## recomeça a cada clique.
func _abrir(i: int) -> void:
	_aba = i
	for k in range(_botoes.size()):
		_botoes[k].set_selected(k == i)
	if _corpo == null:
		return
	for c in _corpo.get_children():
		_corpo.remove_child(c)
		c.queue_free()
	match i:
		0: _monta_bando(_corpo)
		1: _monta_equipe(_corpo)
		_: _monta_mochila(_corpo)


## LINHA DE LISTA SEM CAIXA — a peça da direção de arte ("O Vidro do Domador").
##
## Dentro de um painel que já é moldura, cada cartão com moldura própria vira o
## terceiro retângulo aninhado da mesma linha. Aqui a identidade da linha é o
## feixe de 3 px na aresta esquerda, na cor de quem ela descreve.
func _linha_lista(cor: Color) -> PanelContainer:
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(UI.LAJOTA.r, UI.LAJOTA.g, UI.LAJOTA.b, 0.55)
	sb.set_corner_radius_all(0)
	sb.border_width_left = 3
	sb.border_color = UI.tint_of(cor, true)
	sb.content_margin_left = 14
	sb.content_margin_right = 10
	sb.content_margin_top = 9
	sb.content_margin_bottom = 9
	p.add_theme_stylebox_override("panel", sb)
	return p


# --- aba BANDO --------------------------------------------------------------

## A pergunta que a preparação não respondia é a única que importa aqui: "o que
## a minha máquina faz NESTE bando?". O dado já estava no projeto inteiro —
## `Db.reactions_between` é a mesma função que a tela de iniciais usa desde
## 31/08 — e nenhuma tela o cruzava com a composição inimiga.
##
## O QUE ESTA ABA NÃO MOSTRA, e por quê.
##
## A primeira versão listava, por espécie, TODAS as reações que a equipe
## dispara. O print mostrou o erro no mesmo instante: esse conjunto não depende
## do inimigo — a aura sai de um Prismon seu e o golpe que a acende sai de
## outro —, então as oito pastilhas eram as MESMAS oito da aba EQUIPE. Uma
## seção nova que repete a vizinha é pior que seção nenhuma: ensina que ali não
## há informação.
##
## Ficou o que MUDA de bando para bando e de espécie para espécie:
##   · O QUE O BANDO DISPARA EM VOCÊ. Reação é aura no alvo + golpe de outro
##     elemento, então quem acende reação na SUA equipe é o bando batendo com
##     dois elementos diferentes — mais a maré da arena, que aplica aura nos dois
##     lados. Um bando de quatro Pinto-Raios num campo sem maré não acende NADA:
##     é a informação mais acionável da tela, e ela não existia em lugar nenhum.
##   · a Afinidade de cada espécie — logo, a que ela RESISTE (`self_resist` 0,20
##     em data/elements.json: todo alvo resiste ao próprio elemento), e quais das
##     SUAS reações dependem justamente de um golpe daquele elemento.
func _monta_bando(v: BoxContainer) -> void:
	var linhas := _bando()
	if linhas.is_empty():
		v.add_child(UI.label("—", UI.F_BODY, UI.TEXT_DIM))
		return

	if _meus_elementos().size() < 2:
		var aviso := UI.card_danger(UI.WARN)
		aviso.add_child(UI.wrap(
			"Sua equipe tem um elemento só: nenhuma reação sai dela sozinha. "
			+ "Reações vêm de elementos DIFERENTES se atingindo.",
			UI.F_SMALL, UI.WARN))
		v.add_child(aviso)

	_contra_voce_bloco(v)
	v.add_child(UI.hsep())
	for l in linhas:
		v.add_child(_linha_inimigo(l))


## O caso comum é "nada — este bando só bate", e ele NÃO ganha caixa: um cartão
## de perigo em volta de uma boa notícia é ruído. A moldura de `card_danger`
## (régua de acento no pé) só aparece quando há de fato o que temer.
func _contra_voce_bloco(v: BoxContainer) -> void:
	var rx := _contra_voce()
	v.add_child(UI.label("O QUE O BANDO DISPARA EM VOCÊ", UI.F_SMALL, UI.TEXT_DIM))
	if rx.is_empty():
		var l := UI.label("nada — este bando só bate", UI.F_BODY, UI.GOOD)
		l.tooltip_text = ("Reação precisa de DOIS elementos: a aura de um e o golpe "
			+ "de outro. Este bando (e a arena) não juntam dois.")
		l.mouse_filter = Control.MOUSE_FILTER_STOP
		v.add_child(l)
		return
	var card := UI.card_danger(UI.BAD)
	var flow := HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", 6)
	flow.add_theme_constant_override("v_separation", 3)
	card.add_child(flow)
	for r in rx:
		flow.add_child(_reacao_chip(r))
	card.tooltip_text = ("O bando junta elementos diferentes (contando a maré da arena): "
		+ "cada golpe pode acender uma destas na sua equipe.")
	v.add_child(card)


## Uma espécie do bando, como linha de lista — medalhão, contagem e o que ela
## segura. Sem `custom_minimum_size`: dentro do painel de consulta a linha
## cresce com o conteúdo, que é o que impede o nome de uma reação de ser cortado.
func _linha_inimigo(l: Dictionary) -> Control:
	var el := String(l["el"])
	var c := Db.el_color(el)
	var card := _linha_lista(c)

	var row := UI.box(false, 10)
	card.add_child(row)
	# `icon_head` ancora o medalhão na PRIMEIRA LINHA do bloco, e não no centro
	# dele: quando a espécie segura três reações a linha cresce, e um medalhão
	# centrado ficava órfão no meio das pastilhas, longe do nome que ele ilustra.
	var med := MonsterPortrait.medallion(String(l["sp"]), el, 48.0)
	med.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(UI.icon_head(med, UI.F_H2))

	var v := UI.box(true, 3)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(v)

	var head := UI.box(false, 7)
	v.add_child(head)
	var nm := UI.label(ScreenMap.rotulo_bando(l), UI.F_H2, c.lightened(0.4))
	nm.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	head.add_child(nm)
	head.add_child(UI.spacer())
	head.add_child(UI.element_chip(el))

	var tip: Array = ["%s — Afinidade %s. Golpes de %s doem 20%% menos nele "
		% [String(l["name"]), Db.el_name(el), Db.el_name(el)]
		+ "(toda Afinidade resiste ao próprio elemento)."]

	# O QUE ELE SEGURA. `self_resist` corta 20% do golpe do próprio elemento — e
	# é o golpe que ACENDE a reação, então as reações cujo gatilho é daquele
	# elemento chegam enfraquecidas nesta espécie. É a única coisa nesta aba que
	# muda de espécie para espécie, e é por isso que ela mora aqui.
	var fracas := _reacoes_gatilho(el)
	if fracas.is_empty():
		v.add_child(UI.label("não segura nenhuma reação sua", UI.F_SMALL, UI.TEXT_DIM))
		tip.append("Nenhuma reação sua depende de um golpe de %s." % Db.el_name(el))
	else:
		v.add_child(_faixa("segura", fracas))
		for r in fracas:
			tip.append("− %s: acende com um golpe de %s, que é justamente o que ele resiste."
				% [String(r["name"]), Db.el_name(el)])

	card.tooltip_text = "\n".join(tip)
	return card


## Rótulo curto + as pastilhas, numa faixa que quebra sozinha.
func _faixa(rotulo: String, reacoes: Array) -> Control:
	var flow := HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", 6)
	flow.add_theme_constant_override("v_separation", 3)
	var r := UI.label(rotulo, UI.F_SMALL, UI.TEXT_DIM)
	r.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	flow.add_child(r)
	for x in reacoes:
		flow.add_child(_reacao_chip(x))
	return flow


func _reacao_chip(r: Dictionary) -> Control:
	var cor: Color = r["color"]
	var resiste: bool = bool(r.get("resiste", false))
	var p := PanelContainer.new()
	# A célula AFUNDADA quando a reação é resistida: o chip lê como encaixe
	# apagado, e não como um estado a menos de cor — que some em escala de cinza.
	p.add_theme_stylebox_override("panel",
		UI.frame(UI.C_INSET if resiste else UI.C_PANEL_HI, cor, 8, 4))
	var row := UI.box(false, 5)
	p.add_child(row)
	var rid := String(r.get("id", ""))
	if rid != "":
		var ic := Icons.node("rx_" + rid, 16.0)
		if ic.texture != null:
			row.add_child(ic)
	var l := UI.label(String(r["name"]), UI.F_SMALL,
		cor.darkened(0.35) if resiste else cor.lightened(0.15))
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(l)
	if resiste:
		row.add_child(UI.label("−", UI.F_SMALL, UI.TEXT_DIM))
	p.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return p


func _meus_elementos() -> Array:
	var els: Array = []
	for u in Run.team:
		# String() explicito: `Run.team` e um Array solto, entao `u` chega como
		# Variant e `:=` nao tem o que inferir de `u.element()`.
		var e := String(u.element())
		if not els.has(e):
			els.append(e)
	return els


## As SUAS reações cujo golpe-gatilho é do elemento `el_alvo`.
##
## `reactions_between` devolve pares {from = quem pôs a aura, to = quem bateu}.
## Quem paga a resistência é o GOLPE (`to`), e `self_resist` = 0,20 diz que toda
## Afinidade resiste ao próprio elemento: contra um bando de Raio, toda reação
## que precisa de um golpe de Raio para acender chega com 20% menos dano.
##
## A dedução tem de ser por ROTA e não por reação: a matriz define quase toda
## reação nos dois sentidos (Eletrocussão acende com Encharcado+Raio e com
## Eletrizado+Água), e a primeira versão desta função marcava a reação inteira e
## depois desmarcava na segunda rota — o resultado era uma lista sempre vazia,
## visível no primeiro print.
func _reacoes_gatilho(el_alvo: String) -> Array:
	var vistos: Dictionary = {}
	var out: Array = []
	for l in Db.reactions_between(_meus_elementos()):
		if String(l["to"]) != el_alvo:
			continue
		var r: Dictionary = l["reaction"]
		var rid := String(r.get("id", ""))
		if vistos.has(rid):
			continue
		vistos[rid] = true
		out.append({"id": rid, "name": String(r.get("name", rid)),
			"color": Color(String(r.get("color", "#ffffff"))), "resiste": true})
	return out


## O QUE O BANDO ACENDE NA SUA EQUIPE.
##
## Reação é aura no alvo + golpe de outro elemento. Na sua equipe a aura é posta
## por um inimigo e o golpe vem de OUTRO inimigo, então o que importa é o
## conjunto de elementos DO BANDO — não o cruzamento com os seus, que é o que
## uma primeira versão desta tela calculava (errado: os seus Prismons não batem
## uns nos outros).
##
## A maré da arena entra no conjunto porque ela aplica aura nos DOIS lados: num
## Campo Magnético todo mundo fica Eletrizado, e aí basta um único inimigo de
## Água para acender Eletrocussão em cima de você.
func _contra_voce() -> Array:
	var els: Array = []
	for l in _bando():
		var e := String(l["el"])
		if not els.has(e):
			els.append(e)
	var mare := _mare_da_arena()
	if mare != "" and not els.has(mare):
		els.append(mare)
	var vistos: Dictionary = {}
	var out: Array = []
	for l in Db.reactions_between(els):
		var r: Dictionary = l["reaction"]
		var rid := String(r.get("id", ""))
		if vistos.has(rid):
			continue
		vistos[rid] = true
		out.append({"id": rid, "name": String(r.get("name", rid)),
			"color": Color(String(r.get("color", "#ffffff"))), "resiste": false})
	return out


## O elemento que a arena despeja no campo, se ela despejar algum.
func _mare_da_arena() -> String:
	var arena: Dictionary = Db.arenas.get(String(_node.get("payload", {}).get("arena", "")), {})
	var ef: Dictionary = arena.get("effect", {})
	if String(ef.get("op", "")) != "mare_elemental":
		return ""
	return String(ef.get("element", ""))


## Agrupado por espécie — a MESMA gramática de `ScreenMap`.
func _bando() -> Array:
	return ScreenMap.enemy_lines(_node)


# --- aba EQUIPE -------------------------------------------------------------

## O que a equipe PRODUZ e em que ordem ela entra em campo.
##
## O painel completo de Sinergias continua atrás de um botão (revisão 31/08,
## pedido do autor: "essa informação deve ser opcional, como um botão"). O que
## mudou em 16/09 é que a tira de ícones também saiu da tela de repouso: eram
## oito pastilhas coloridas pousadas em cima das criaturas, o bloco mais denso
## da preparação, e nada nelas muda entre um combate e o seguinte — é material
## de consulta, exatamente como o painel que elas abrem.
func _monta_equipe(v: BoxContainer) -> void:
	_formacao(v)
	v.add_child(UI.hsep())
	var strip := SynergyStrip.new()
	strip.open_requested.connect(_open_synergies)
	v.add_child(strip)


## GDD 21.1 — silhuetas nas três faixas, na ordem exata em que aparecerão.
## Usa a MESMA regra do CombatSim: sem surpresa no combate.
func _formacao(v: BoxContainer) -> void:
	var tit := UI.label("FORMAÇÃO PREVISTA", 12, UI.TEXT_DIM)
	tit.tooltip_text = "Dentro da faixa a ordem é por VEL decrescente. Quem ataca antes aplica antes."
	tit.mouse_filter = Control.MOUSE_FILTER_STOP
	v.add_child(tit)
	var lanes := [[], [], []]
	for u in Run.team:
		lanes[CombatSim.stance_lane(u.stance())].append(u)
	for l in lanes:
		l.sort_custom(func(a, b):
			var va: float = float(a.stats()["vel"])
			var vb: float = float(b.stats()["vel"])
			if not is_equal_approx(va, vb):
				return va > vb
			return a.base_id() < b.base_id())
	var names := ["FRENTE", "CENTRO", "FUNDO"]
	for i in range(3):
		var row := UI.box(false, 5)
		v.add_child(row)
		var tag := UI.label(names[i], 10, UI.TEXT_DIM)
		tag.custom_minimum_size = Vector2(60, 0)
		tag.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		row.add_child(tag)
		if lanes[i].is_empty():
			row.add_child(UI.label("—", UI.F_SMALL, UI.TEXT_DIM))
		for u in lanes[i]:
			var p := MonsterPortrait.medallion(u.species_id, u.element(), 34.0)
			p.tooltip_text = "%s — VEL %.1f" % [u.display_name(), float(u.stats()["vel"])]
			row.add_child(p)


## O painel denso, sob demanda. Véu, matriz completa, efeito de cada reação e
## o que falta destravar — e um FECHAR.
func _open_synergies() -> void:
	var view := SynergyView.new()
	view.closed.connect(func(): view.queue_free())
	add_child(view)


# --- aba MOCHILA ------------------------------------------------------------

## O que você CARREGA: os Ativos da mão, as relíquias e os itens equipados.
##
## Eram duas peças em lugares diferentes da coluna antiga, com a doca de itens
## rolando até a borda de baixo da tela — o cartão "Presa Rachada / Coalla"
## saía fatiado no meio dos glifos, sem nada dizendo que havia mais coisa
## embaixo. Agora as duas moram na mesma subseção e a rolagem termina na aresta
## do painel.
func _monta_mochila(v: BoxContainer) -> void:
	_mao(v)
	v.add_child(UI.hsep())

	var dock := ItemDock.new()
	dock.detailed = true
	dock.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_child(dock)
	# A DOCA PERDE A PRÓPRIA MOLDURA aqui dentro: ela já está dentro do painel de
	# consulta, e painel dentro de painel é o "retângulo aninhado" que o projeto
	# combateu em 03/09. `_ready` da doca roda DENTRO do `add_child` acima (o nó
	# já está na árvore), então esta sobrescrita vem depois dele — e não antes,
	# que era o jeito errado de escrever isto.
	dock.add_theme_stylebox_override("panel", StyleBoxEmpty.new())


func _mao(v: BoxContainer) -> void:
	v.add_child(UI.label("A MÃO DO DOMADOR", 12, UI.TEXT_DIM))

	# GRADE, não uma pilha de HBox. Cada linha era um HBox independente, então
	# nada garantia que a coluna do ícone de uma linha caísse no mesmo x da
	# outra — e quando um Ativo não tinha arte (Orvalho, Círculo de Seiva) a
	# linha inteira escorregava. Com a grade as quatro colunas são as MESMAS
	# para todas as linhas, por construção.
	var g := GridContainer.new()
	g.columns = 4
	g.add_theme_constant_override("h_separation", 8)
	g.add_theme_constant_override("v_separation", 5)
	g.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_child(g)

	var px := UI.icon_px(UI.F_SMALL)
	for i in range(Run.actives.size()):
		var aid := String(Run.actives[i])
		var a: Dictionary = Db.actives[aid]
		var tip := String(a["text"])

		var idx := UI.label("%d" % (i + 1), UI.F_SMALL, UI.ACCENT, HORIZONTAL_ALIGNMENT_CENTER)
		idx.custom_minimum_size = Vector2(px, 0)
		idx.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		idx.tooltip_text = tip
		g.add_child(idx)

		var ic := Icons.active(aid, px)
		ic.tooltip_text = tip
		ic.mouse_filter = Control.MOUSE_FILTER_STOP
		g.add_child(ic)

		# clip_text trava a largura MÍNIMA em 1 px (medido em fit_probe): sem
		# isso "Prisma de Reescrita" reportaria a largura inteira do texto e
		# empurraria a coluna de referência para fora da tela.
		var nm := UI.label(String(a["name"]), UI.F_SMALL, Color(String(a["color"])))
		nm.clip_text = true
		nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		nm.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		nm.tooltip_text = tip
		g.add_child(nm)

		var cost := UI.box(false, 3)
		cost.alignment = BoxContainer.ALIGNMENT_END
		cost.tooltip_text = tip
		var cl := UI.label(str(int(a["cost"])), UI.F_SMALL, UI.WARN, HORIZONTAL_ALIGNMENT_RIGHT)
		cl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		cost.add_child(cl)
		cost.add_child(Icons.node("g_flask", px * 0.75, UI.WARN))
		g.add_child(cost)

	if Run.actives.is_empty():
		v.add_child(UI.label("nenhum — compre na Feira", UI.F_SMALL, UI.TEXT_DIM))
