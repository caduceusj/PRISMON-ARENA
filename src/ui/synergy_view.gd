class_name SynergyView
extends Control
## O painel de Sinergias — aberto SOB DEMANDA, por botão (revisão 31/08).
##
## Ele nasceu fixo na tela de preparação e ficou denso demais: oito cartões de
## texto competindo com a decisão de entrar no combate. O autor tinha razão —
## isto é material de CONSULTA, não de leitura constante. Na preparação ficou
## só a tira de ícones (SynergyStrip); quem quiser o porquê abre aqui.
##
## Três blocos, três perguntas:
##   MATRIZ       — o mapa: toda dupla possível, o que sai e o que falta
##   ATIVAS       — o que esta equipe produz agora, com o efeito escrito
##   A UM PASSO   — o que destrava com UM elemento a mais, e qual

signal closed

const CELL := 26.0
const CARD_MIN_H := 132.0

## Folga interna da célula da matriz, igual nos quatro lados.
const CELL_PAD := 5.0

## A SALA DAS SINERGIAS, de `data/paleta.json` (salas.sinergias).
static var SALA: Color:
	get: return UI.cor_da_sala("sinergias")

var _filter := ""
var _body: VBoxContainer
var _chips: HFlowContainer


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var veil := ColorRect.new()
	veil.color = Color(0, 0, 0, 0.74)
	veil.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	veil.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(veil)

	# A SALA DAS SINERGIAS (17/09). Esta é uma das duas telas que o autor citou
	# pelo nome, e era a mais roxa do jogo: todos os dez cartões usavam a mesma
	# lajota, e a cor só aparecia em losangos de 12 px e nas letras do nome.
	# O véu já escurece o que está atrás; a luz entra por cima dele, senão ela
	# seria apagada pelo próprio véu.
	add_child(UI.luz_de_sala(SALA))

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for m in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + m, 44)
	add_child(margin)

	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel",
		UI.panel(UI.materia_da_sala(UI.LAJOTA, SALA), 0, UI.ACCENT))
	margin.add_child(panel)
	var col: BoxContainer = UI.box(true, 10)
	panel.add_child(col)

	var bar: BoxContainer = UI.box(false, 12)
	col.add_child(bar)
	bar.add_child(UI.label("SINERGIAS DESTA EQUIPE", UI.F_H2, UI.GOLD))
	bar.add_child(UI.spacer())
	# FECHAR é RECUAR: pelo contrato do kit, quem recua é `button_secundario`.
	# Era `UI.button` sem cor, que desde 15/09 devolve o botão neutro — e o
	# único botão de um painel modal não pode ser o mais apagado da tela.
	var close: Button = UI.button_secundario("  FECHAR  ", UI.F_BODY)
	close.custom_minimum_size = Vector2(150, 0)
	close.pressed.connect(func(): closed.emit())
	bar.add_child(close)

	var head := HFlowContainer.new()
	head.add_theme_constant_override("h_separation", 8)
	head.add_theme_constant_override("v_separation", 5)
	col.add_child(head)
	var lbl: Label = UI.label("ENERGIAS EM CAMPO", 11, UI.TEXT_DIM)
	lbl.tooltip_text = "Clique numa energia para filtrar as sinergias."
	head.add_child(lbl)
	_chips = head

	_body = UI.box(true, 10)
	_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(_body)
	rebuild()


func counts() -> Dictionary:
	var c: Dictionary = {}
	for u in Run.team:
		var e: String = u.element()
		c[e] = int(c.get(e, 0)) + 1
	return c


func rebuild() -> void:
	var counts := counts()

	# o primeiro filho é o rótulo; só os chips são refeitos
	for i in range(_chips.get_child_count() - 1, 0, -1):
		var x := _chips.get_child(i)
		_chips.remove_child(x)
		x.queue_free()
	for e in Db.slice_elements:
		var el: String = String(e)
		if not counts.has(el):
			continue
		_chips.add_child(_energy_chip(el, int(counts[el])))

	for x in _body.get_children():
		_body.remove_child(x)
		x.queue_free()

	var top: BoxContainer = UI.box(false, 10)
	top.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_body.add_child(top)
	top.add_child(matrix_card(counts))
	top.add_child(_active_card(counts))
	# "A UM PASSO" SAIU (03/09). Depois que a matriz virou lista de reacoes,
	# ela passou a dizer "falta Gelo" em cada linha apagada — e o bloco de
	# baixo repetia exatamente isso como "+1 Gelo". Era a mesma informacao
	# duas vezes na mesma tela, e como ele crescia com o numero de reacoes
	# trancadas, era tambem o que estourava a altura do painel: com equipe de
	# dois elementos sao sete linhas, e as ultimas caiam fora da tela.


## Chip clicável: filtra os cartões para as reações que envolvem este elemento.
## Chip clicável: filtra os cartões para as reações que envolvem este elemento.
## Usa CardButton pelo mesmo motivo da Cozinha — conteúdo ancorado no retângulo
## de um Button não empurra a largura, e os chips colapsavam uns sobre os outros.
func _energy_chip(el: String, n: int) -> Control:
	var on: bool = _filter == el
	var c := Db.el_color(el)
	# a lajota do chip carrega a ENERGIA dele: o chip de Fogo é uma lajota
	# quente, o de Gelo uma lajota fria. Eram cinco lajotas roxas idênticas com
	# um losango colorido de 14 px cada.
	var card := CardButton.make(UI.materia_da_sala(UI.PANEL_HI, c), c)
	card.set_selected(on)
	card.clicked.connect(func():
		_filter = "" if _filter == el else el
		rebuild())
	var row: BoxContainer = UI.box(false, 6)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.body.add_child(row)
	row.add_child(_gem(el, 14.0))
	row.add_child(UI.label(Db.el_name(el).to_upper(), 11, c.lightened(0.3)))
	row.add_child(UI.label("×%d" % n, 11, UI.TEXT_DIM))

	# pips de Ressonância: quantas unidades faltam para Eco (2) e Coro (4).
	# Absorvidos do bloco RESSONÂNCIA, que dizia o mesmo número noutra coluna.
	var th: Dictionary = Db.resonance_thresholds
	var coro: int = int(th.get("coro", 4))
	var pips: BoxContainer = UI.box(false, 2)
	row.add_child(pips)
	for i in range(coro):
		var r := ColorRect.new()
		r.color = c if i < n else UI.LINE
		r.custom_minimum_size = Vector2(7, 7)
		r.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		pips.add_child(r)
	card.tooltip_text = _resonance_tip(el, n)
	return card


## O que esta contagem já destravou, e o que vem a seguir.
func _resonance_tip(el: String, n: int) -> String:
	var th: Dictionary = Db.resonance_thresholds
	var lines: Array = ["%s — %d na equipe" % [Db.el_name(el), n]]
	for r in Db.resonances:
		if String(r.get("element", "")) != el:
			continue
		var need: int = int(th.get(String(r.get("tier", "eco")), 2))
		# EM PALAVRAS, não em ✔/○: os dois vêm da fonte que o sistema empresta
		# (ver Icons.GLIFOS) e, pior, um círculo vazio ao lado de um número não
		# diz QUANTO falta — que é a única coisa que o jogador quer saber aqui.
		var estado: String = "ativa" if n >= need else "faltam %d" % (need - n)
		lines.append("%s (%d, %s) — %s" % [String(r.get("name", "")), need,
			estado, String(r.get("text", ""))])
	return "
".join(lines)


## Losango do elemento. Delega ao Gem: o desenho pixel a pixel vive num lugar
## so, usado tambem pela tira da preparacao — antes eram duas copias com
## constantes ligeiramente diferentes (1.4 e 1.45 de folga), e por isso o mesmo
## losango tinha tamanhos diferentes em telas diferentes.
func _gem(el: String, px: float) -> Control:
	return Gem.make(Db.el_color(el), int(px) / 2)


# --- todas as reações --------------------------------------------------------

## TODAS AS REAÇÕES, como lista de PARES — não como tabela cruzada.
##
## Era uma matriz 5×5: elemento da aura na linha, elemento do golpe na coluna,
## e o jogador tinha de cruzar duas bordas para descobrir o que sai. O autor
## reprovou (03/09): "está muito não legível, menos matemático".
##
## Ele tem razão, e o número explica por quê: são 25 células para representar
## **8 reações**. A tabela cobra o custo de ler um eixo duplo e devolve, na
## maior parte das células, "nada acontece aqui". A informação real é uma lista
## curta de pares — e é assim que o jogador pensa nela ("Fogo com Água dá
## Vaporizar"), não como coordenada.
##
## O que se perdeu: a matriz distinguia a ORDEM (Fogo sobre aura de Água não é
## o mesmo que Água sobre aura de Fogo). Essa diferença vira multiplicador e
## vive no cartão da reação, que é onde ela cabe — no mapa geral ela só
## dobrava o número de células sem mudar QUAIS reações existem.
func matrix_card(counts: Dictionary) -> Control:
	var card: PanelContainer = UI.card(UI.materia_da_sala(UI.LAJOTA_HI, SALA), UI.LINE)
	card.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	card.custom_minimum_size = Vector2(300, 0)
	var v: BoxContainer = UI.box(true, 6)
	card.add_child(v)
	v.add_child(UI.label("TODAS AS REAÇÕES", 12, UI.TEXT))
	v.add_child(UI.label("Acesa é a que sua equipe faz.", 11, UI.TEXT_DIM))
	v.add_child(UI.spacer(4, false))

	for r in _todas_as_reacoes():
		v.add_child(_linha_reacao(r, counts))
	return card


## Cada reação UMA vez, com o par de elementos que a produz. A matriz listava
## o mesmo par duas vezes (ida e volta); aqui a ida basta.
func _todas_as_reacoes() -> Array:
	var out: Array = []
	var visto: Dictionary = {}
	for a in Db.slice_elements:
		var ea := String(a)
		var aura_id := String(Db.el(ea).get("aura_id", ""))
		if aura_id == "":
			continue
		for b in Db.slice_elements:
			var eb := String(b)
			if ea == eb:
				continue
			var hit := Db.lookup_reaction(aura_id, eb)
			if hit.is_empty():
				continue
			var rid := String(hit["rule"]["id"])
			if visto.has(rid):
				continue
			visto[rid] = true
			out.append({"rule": hit["rule"], "a": ea, "b": eb})
	return out


## `losango + losango  NOME` — e nada mais. Acesa quando a equipe tem os dois
## elementos; apagada, mostra qual falta.
func _linha_reacao(r: Dictionary, counts: Dictionary) -> Control:
	var ea := String(r["a"])
	var eb := String(r["b"])
	var tem_a: bool = int(counts.get(ea, 0)) > 0
	var tem_b: bool = int(counts.get(eb, 0)) > 0
	var viva: bool = tem_a and tem_b
	var col := Color(String(r["rule"].get("color", "#ffffff")))

	var p := PanelContainer.new()
	# ACESA = LAJOTA DA PRÓPRIA REAÇÃO; apagada = matéria neutra. Era o feixe
	# colorido e o miolo roxo nos dois casos, então "acesa" e "apagada" só se
	# distinguiam por 1 px de aresta e por 50% de opacidade. Agora a lista é uma
	# escada de oito matizes onde a equipe chega, e cinza onde ela não chega.
	p.add_theme_stylebox_override("panel", UI.frame(
		UI.C_PANEL, col if viva else UI.LINE, 10, 7,
		UI.materia_da_sala(UI.LAJOTA, col) if viva else UI.LAJOTA))
	p.tooltip_text = "%s — %s × %s
%s
%s" % [String(r["rule"]["name"]),
		Db.el_name(ea), Db.el_name(eb), String(r["rule"].get("text", "")),
		efeito_lido(r["rule"])]
	p.modulate = Color(1, 1, 1, 1.0 if viva else 0.5)

	var row: BoxContainer = UI.box(false, 8)
	p.add_child(row)
	var gems: BoxContainer = UI.box(false, 3)
	gems.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	gems.custom_minimum_size = Vector2(38, 0)
	row.add_child(gems)
	gems.add_child(Gem.make(Db.el_color(ea), 6, 1.0 if tem_a else 0.45))
	gems.add_child(Gem.make(Db.el_color(eb), 6, 1.0 if tem_b else 0.45))

	var nm: Label = UI.label(String(r["rule"]["name"]), UI.F_SMALL,
		col.lightened(0.25) if viva else UI.TEXT_DIM)
	nm.clip_text = true
	nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nm.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(nm)

	# apagada diz O QUE FALTA, em ÍCONE. Escrito ("falta Gelo + Natureza") o
	# texto comia a coluna do nome e "Geada Mortal" saía cortada em "Geada M".
	# O ícone do elemento diz a mesma coisa em 16 px, e é a mesma imagem que o
	# jogador vê no recruta e no chip de energia.
	if not viva:
		var falta := UI.box(false, 3)
		falta.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(falta)
		var f: Label = UI.label("falta", 11, UI.TEXT_DIM)
		f.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		falta.add_child(f)
		var nomes: Array = []
		for e in ([ea] if not tem_a else []) + ([eb] if not tem_b else []):
			falta.add_child(Icons.element(String(e), 16.0))
			nomes.append(Db.el_name(String(e)))
		p.tooltip_text += "
Falta: " + " + ".join(nomes)
	return p


# --- ativas -----------------------------------------------------------------

## O que ESTA equipe produz agora, com o efeito escrito por extenso. É o bloco
## que responde "por que essa composição é boa".
func _active_card(counts: Dictionary) -> Control:
	var card: PanelContainer = UI.card(UI.materia_da_sala(UI.LAJOTA_HI, SALA), UI.LINE)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var v: BoxContainer = UI.box(true, 7)
	card.add_child(v)

	var pairs := _pairs(counts, 0)
	var head: BoxContainer = UI.box(false, 8)
	v.add_child(head)
	head.add_child(UI.label("SINERGIAS ATIVAS", 12, UI.TEXT))
	head.add_child(UI.label("%d em efeito agora" % pairs.size(), 11, UI.TEXT_DIM))

	if pairs.is_empty():
		v.add_child(UI.wrap("Esta equipe não produz nenhuma reação. Todos os Prismons "
			+ "compartilham elemento, ou os elementos que ela tem não se conversam.",
			UI.F_SMALL, UI.BAD))
		return card

	# rolagem: com equipe cheia dá 8 sinergias, e elas não cabem na altura da
	# tela sem espremer o texto até virar ilegível
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	# A BARRA VOLTA A SER "QUANDO PRECISAR" — mas a LARGURA dela fica reservada
	# do mesmo jeito (revisão 15/09: "a barra de rolagem roxa aparece cheia e
	# berrante onde não há nada para rolar").
	#
	# O motivo de 03/09 continua valendo e não foi desfeito: a barra existia
	# para o corte no cartão de baixo ter causa visível, e para a largura não
	# mudar quando a equipe muda de tamanho. SHOW_ALWAYS resolvia os dois de uma
	# vez, e cobrava por isso uma barra desenhada em cima de nada — com equipe
	# de dois elementos são duas sinergias, que cabem folgadas, e mesmo assim a
	# barra aparecia cheia de ponta a ponta, que é a leitura oposta ("isto tudo
	# é o conteúdo") da verdadeira.
	#
	# AUTO devolve a barra ao seu trabalho, e a calha reservada abaixo (uma
	# margem direita da largura da barra) segura a largura: o conteúdo não anda
	# um pixel quando ela aparece. O corte continua tendo causa visível, porque
	# quando há o que rolar a barra está lá.
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	v.add_child(scroll)
	var calha := MarginContainer.new()
	calha.add_theme_constant_override("margin_right", PrismaTheme.SCROLL_W)
	calha.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(calha)
	# GRADE DE 2 COLUNAS, não HFlowContainer. O HFlow decide o número de
	# colunas pela largura que recebe, e essa largura só é conhecida depois do
	# layout: ele fixava 3 colunas no primeiro quadro e o terceiro cartão saía
	# cortado pela borda quando o painel encolhia. Com a grade, o número de
	# colunas é uma decisão minha e os cartões dividem a largura em partes
	# iguais — previsível em qualquer resolução.
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	calha.add_child(grid)
	for p in pairs:
		grid.add_child(_synergy_card(p, true))
	return card


## Reações que a equipe produz (falta = 0) ou que faltam `falta` elementos.
func _pairs(counts: Dictionary, falta: int) -> Array:
	var out: Array = []
	var seen: Dictionary = {}
	for a in Db.slice_elements:
		var ea := String(a)
		var aura_id := String(Db.el(ea).get("aura_id", ""))
		if aura_id == "":
			continue
		for b in Db.slice_elements:
			var eb := String(b)
			if ea == eb:
				continue
			var hit := Db.lookup_reaction(aura_id, eb)
			if hit.is_empty():
				continue
			var rid := String(hit["rule"]["id"])
			# a mesma reação sai de duas ordens; mostra uma vez só
			var key := "%s|%s" % [rid, ea if ea < eb else eb]
			if seen.has(key):
				continue
			var have_a: bool = int(counts.get(ea, 0)) > 0
			var have_b: bool = int(counts.get(eb, 0)) > 0
			var missing: int = (0 if have_a else 1) + (0 if have_b else 1)
			if missing != falta:
				continue
			if _filter != "" and _filter != ea and _filter != eb:
				continue
			seen[key] = true
			out.append({"rule": hit["rule"], "a": ea, "b": eb,
				"falta": ea if not have_a else (eb if not have_b else "")})
	return out


func _synergy_card(p: Dictionary, big: bool) -> Control:
	var rule: Dictionary = p["rule"]
	var col := Color(String(rule.get("color", "#ffffff")))
	# CADA SINERGIA TEM A COR DOS ELEMENTOS QUE A PRODUZEM (17/09, pedido do
	# autor: "cores diferentes nas visualizações de sinergias").
	#
	# `rule.color` vem de `data/reactions.json` e é a cor do par — laranja para
	# Derretimento (Fogo×Gelo), ciano para Congelar (Gelo×Água), verde para
	# Catalisação (Raio×Natureza). Ela já pintava a aresta e o nome; o CORPO do
	# cartão, que é 268x132 px contra os ~120 px² do nome, continuava sendo a
	# mesma lajota roxa em todos os oito. Era esse o "falta cor" desta tela.
	#
	# Por que a cor da regra e não a mistura das duas gemas: misturar Fogo com
	# Gelo dá cinza, e a grade inteira voltaria ao neutro justamente nos pares
	# mais interessantes. As duas gemas continuam no cabeçalho dizendo QUAIS
	# elementos são; a lajota diz O QUE SAI deles.
	var card: PanelContainer = UI.card(UI.materia_da_sala(UI.LAJOTA, col), col)
	# altura mínima igual para todos: numa grade a linha toma a altura do
	# cartão mais alto, e cartões de alturas diferentes deixavam buracos
	# debaixo dos curtos. Com um piso comum as linhas ficam parelhas.
	card.custom_minimum_size = Vector2(268, CARD_MIN_H)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var v: BoxContainer = UI.box(true, 5)
	card.add_child(v)
	var head: BoxContainer = UI.box(false, 7)
	v.add_child(head)
	# o par de losangos é UMA coisa (o par de energias), então anda junto e
	# separado do nome; antes o "+" vinha em corpo de leitura e abria um vão
	# entre as duas gemas maior que o vão entre a gema e o nome.
	# SHRINK_CENTER centrava o par contra o bloco de DUAS linhas (nome +
	# "Fogo x Gelo"), e os losangos caiam justamente no vao entre elas.
	# `icon_head` da ao par uma caixa da altura de UMA linha do nome.
	var gems: BoxContainer = UI.box(false, 3)
	gems.add_child(_gem(String(p["a"]), 15.0))
	gems.add_child(UI.label("+", 11, UI.TEXT_DIM))
	gems.add_child(_gem(String(p["b"]), 15.0))
	head.add_child(UI.icon_head(gems, UI.F_BODY))
	var nm: BoxContainer = UI.box(true, 0)
	nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(nm)
	var title: Label = UI.label(String(rule["name"]).to_upper(), UI.F_BODY, col.lightened(0.25))
	title.clip_text = true
	nm.add_child(title)
	nm.add_child(UI.label("%s × %s" % [Db.el_name(String(p["a"])), Db.el_name(String(p["b"]))],
		11, UI.TEXT_DIM))

	# corpo 18 (rótulo), não 26 (leitura). Isto é material de CONSULTA atrás de
	# um botão: em 26 os cartões não cabiam na altura do painel e o último
	# aparecia cortado no meio de uma frase — o print do autor.
	var body: Label = UI.wrap(String(rule.get("text", "")), 11, UI.TEXT)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(body)

	var efeito := efeito_lido(rule)
	if efeito != "":
		var ef: Label = UI.wrap(efeito, 11, col.lightened(0.15))
		v.add_child(ef)

	var foot: BoxContainer = UI.box(false, 8)
	v.add_child(foot)
	foot.add_child(_tag_pill(_kind_label(rule), col))
	foot.add_child(UI.spacer())
	foot.add_child(UI.label(_requirement(rule), 11, UI.TEXT_DIM))
	card.tooltip_text = "%s — %s × %s
%s
%s
%s · %s" % [String(rule["name"]),
		Db.el_name(String(p["a"])), Db.el_name(String(p["b"])),
		String(rule.get("text", "")), efeito, _kind_label(rule),
		_consume_long(rule)]
	return card


# --- o que a regra FAZ, lido da própria regra --------------------------------
#
# O TEXTO DA VAPORIZAR MENTE (revisão 15/09, achado confirmado).
#
# `data/reactions.json` diz da Vaporizar: "Amplia o golpe e afina a DEF do
# alvo". Ela não afina DEF nenhuma — o `on_react` dela é um `debuff` de
# `ult_gain` ×0,8 por 3 s em quem estiver a 130 px do alvo, e tem até nome
# próprio nos dados ("Névoa"). Quem afina DEF é a Supercondução. O jogador que
# montar Fogo + Água contando com o que o cartão prometeu não recebe nada disso.
#
# A prosa dos oito cartões é a melhor redação do projeto e não se toca — ela é
# de `data/`, e a correção da frase da Vaporizar está pedida ao dono do arquivo.
# O que se conserta AQUI é a causa de a mentira ter durado: o `on_react` estava
# escrito nos dados e não era lido por tela nenhuma. Esta função o lê. É o
# mesmo defeito que a revisão batizou de Raiz 1 ("declarado nos dados, nunca
# lido pelo código"), na versão de interface: enquanto ninguém desenhar o que a
# regra faz, a prosa pode dizer qualquer coisa e nada contradiz.
#
# Por construção esta linha não pode mentir: ela não tem texto próprio, só
# traduz os números que a simulação vai usar.
static func efeito_lido(rule: Dictionary) -> String:
	var partes: Array = []
	for op in rule.get("on_react", []):
		var t := _op_em_palavras(op)
		if t != "":
			partes.append(t)
	return " · ".join(partes)


static func _op_em_palavras(op: Dictionary) -> String:
	var rotulo := String(op.get("label", ""))
	var pre: String = "%s: " % rotulo if rotulo != "" else ""
	match String(op.get("op", "")):
		"debuff":
			var s := "%s%s ×%.2f por %.0f s" % [pre, _stat_nome(String(op.get("stat", ""))),
				float(op.get("mult", 1.0)), float(op.get("duration", 0.0))]
			if float(op.get("radius", 0.0)) > 0.0:
				s += " em quem estiver perto do alvo"
			return s
		"control":
			return "%strava o alvo por %.1f s" % [pre, float(op.get("duration", 0.0))]
		"delay_action":
			return "%satrasa o próximo golpe do alvo em %d%%" % [pre,
				int(round(float(op.get("fraction", 0.0)) * 100.0))]
		"chain":
			return "%sressalta em até %d alvos" % [pre, int(op.get("count", 0))]
		"energy":
			return "%sdevolve %d de Energia ao Domador" % [pre, int(op.get("amount", 0))]
		"maxhp_damage":
			return "%sarranca %d%% do HP máximo" % [pre,
				int(round(float(op.get("pct", 0.0)) * 100.0))]
	return ""


## Os nomes que o jogador lê, para as chaves de estatística da simulação.
static func _stat_nome(stat: String) -> String:
	match stat:
		"def": return "DEF"
		"atk": return "ATK"
		"vel": return "velocidade"
		"ult_gain": return "carga de ultimate"
	return stat


static func _consume_long(rule: Dictionary) -> String:
	match String(rule.get("consume", "")):
		"none": return "não consome a aura — encadeia enquanto ela durar"
		"all":  return "consome a aura inteira"
	return "consome %d UA da aura" % int(Db.combat("transform_consume_ua", 2.0))


## O que a reação É, em uma palavra, mais o número que importa dela.
static func _kind_label(rule: Dictionary) -> String:
	match String(rule.get("kind", "")):
		"amplify":
			return "AMPLIFICA ×%.1f" % float(rule.get("mult_forward", 1.0))
		"catalytic":
			return "CONTROLE"
	return "TRANSFORMA ×%.1f" % float(rule.get("damage_mult", 1.0))


## Curto de propósito. Uma Label sem autowrap reporta o texto INTEIRO como
## largura mínima, e esse número sobe pela árvore: "consome a aura inteira" em
## dois cartões lado a lado prendia 1049 px de largura mínima no painel e
## espremia a coluna de referência contra a borda da tela.
static func _requirement(rule: Dictionary) -> String:
	if String(rule.get("consume", "")) == "none":
		return "encadeia"
	if String(rule.get("consume", "")) == "all":
		return "aura toda"
	return "%d UA" % int(Db.combat("transform_consume_ua", 2.0))


func _tag_pill(text: String, c: Color) -> Control:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", UI.panel(UI.LAJOTA_HI, 3, c))
	p.add_child(UI.label(text, 10, c.lightened(0.3)))
	return p
