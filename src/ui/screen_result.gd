class_name ScreenResult
extends Control
## GDD 21.3 -- o log de combate. "A principal ferramenta de aprendizado do
## jogador": o aviso aponta a unidade que nao contribuiu e transforma derrota
## em licao.
##
## ------------------------------------------------------------------------
## REVISÃO DE 15/09 — três defeitos medidos, três consertos.
##
## 1. O LOG DE DERROTA SÓ TINHA O SEU LADO. `CombatSim.combat_log()` monta
##    `units` apenas para o lado 0, então quem perdeu não conseguia descobrir o
##    que o inimigo fez — que é literalmente a pergunta dele. O lado inimigo
##    chega em `enemy_units`, montado por `ScreenCombat` enquanto o `sim` ainda
##    está vivo (a simulação é de outra frente).
##
## 2. JARGÃO DE ENGINE NA TELA DO JOGADOR. "limite de ticks" e "aniquilacao
##    mutua" saem de `combat_sim.gd` e eram impressos crus. `_motivo()` traduz
##    aqui, na tela, e não na simulação: o texto cru continua sendo o que as
##    ferramentas de lote leem.
##
## 3. A TELA PULAVA 144 PX PARA O LADO e deixava 451 das 900 linhas vazias. O
##    salto era o trilho do elenco, escondido só nesta tela e visível na
##    seguinte (corrigido em `main.gd`); as linhas vazias eram uma coluna de 820
##    px no meio de um quadro de 1600.
##
## ------------------------------------------------------------------------
## REVISÃO DE 16/09 — o vazamento, e o excesso que o escondia.
##
## O autor mandou um print em que o painel "O BANDO INIMIGO" saía pela direita
## da tela: as colunas Dano e Cura ficavam cortadas pela borda do monitor.
##
## A CAUSA MEDIDA. As duas tabelas eram irmãs de um HBox e cada célula de número
## pedia 84 px FIXOS de largura mínima (`CELL_W`). Com as cinco colunas abertas
## — o que acontece assim que a equipe tem um curandeiro e a coluna "Cura" deixa
## de ser zero —, cada cartão nascia com 654 px de largura MÍNIMA. Na tela do
## log durante a run, o trilho do elenco come 288 px e sobram 623 px por cartão:
## **1322 px pedidos contra 1260 disponíveis**. Um BoxContainer nunca entrega
## menos que o mínimo do filho, então ele não encolhia nada — ele transbordava,
## e o que passava da borda direita da tela era simplesmente cortado. Reproduzido
## forçando `_cols = COLS` e capturando `12_run_log.png`.
##
## O CONSERTO É DE MÃO DUPLA, e nenhuma das duas metades é o sintoma:
##
## (a) **A célula deixa de somar e passa a caber.** `CELL_W_MIN` é um piso baixo
##     e toda célula ganha `SIZE_EXPAND_FILL`: a largura da coluna vem do que
##     SOBRA no cartão, não do que as colunas somam. Com as cinco colunas a
##     grade pede 518 px em vez de 630 — cabe com folga em qualquer das duas
##     larguras que esta tela tem (com e sem o trilho), e continuaria cabendo se
##     um dia entrasse uma sexta coluna.
##
## (b) **O placar sai de dentro das tabelas.** Os totais eram um rodapé DENTRO de
##     cada cartão, então "causou 2107" e "causou 184" — os dois números que
##     explicam a briga — ficavam a 700 px um do outro, em linhas diferentes.
##     Agora são duas linhas da MESMA tabela, uma em cima da outra, com a barra
##     proporcional medindo um lado contra o outro. É o cartão que responde a
##     pergunta da tela, e ele responde em três linhas.
##
## E O DETALHE POR CRIATURA FICA ATRÁS DE UMA CONSULTA (pedido do autor, 16/09:
## "simplifique mais como essas informacoes sao mostradas"). Os dois painéis
## tinham ~400 px de altura para duas linhas de conteúdo cada: eram quase todo
## vazio, e o vazio dentro de uma moldura lê como defeito. Agora eles nascem
## fechados atrás de um botão e a tela abre com o que se lê em dois segundos —
## quem quiser saber qual criatura não contribuiu abre a gaveta.

signal continue_pressed

var _node: Dictionary = {}
var _log: Dictionary = {}

## A SALA. Vitória e derrota são o mesmo lugar em dois estados, então é o mesmo
## matiz em dois pontos da escada — e não duas cores diferentes.
const SALA_VITORIA := Color("#3f8f6a")
const SALA_DERROTA := Color("#8f3f4e")

## A gaveta do detalhe por criatura e o botão que a abre.
var _detalhe: Control = null
var _bt_detalhe: Button = null
## A rolagem que SEGURA a gaveta dentro da folga, e o vazio que ela ocupa.
var _rolagem: ScrollContainer = null
var _vazio: Control = null

const ABRIR := "  VER DETALHE POR CRIATURA  "
const FECHAR := "  OCULTAR O DETALHE  "


func setup(node: Dictionary, result: Dictionary) -> void:
	_node = node
	_log = result


func _ready() -> void:
	var won: bool = bool(_log.get("won", false))
	add_child(UI.luz_de_sala(SALA_VITORIA if won else SALA_DERROTA))
	# Vitória e derrota são o mesmo arpejo com o acorde trocado (maior/menor),
	# feitos para serem reconhecidos como par. `UI.som` é no-op silencioso se o
	# autoload `Som` não estiver registrado, e mudo em headless.
	UI.som("vitoria" if won else "derrota")

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for s in ["left", "right"]:
		margin.add_theme_constant_override("margin_" + s, 26)
	margin.add_theme_constant_override("margin_top", 26)
	margin.add_theme_constant_override("margin_bottom", 22)
	add_child(margin)

	var col := UI.box(true, 12)
	margin.add_child(col)

	var head := UI.box(false, 12)
	col.add_child(head)
	head.add_child(UI.label("VITÓRIA" if won else "DERROTA", 36, UI.GOOD if won else UI.BAD))
	head.add_child(UI.spacer())
	var motivo := UI.label("%.1f s  ·  %s" % [float(_log.get("duration", 0.0)),
		_motivo(String(_log.get("reason", "")))], UI.F_BODY, UI.TEXT_DIM)
	motivo.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	head.add_child(motivo)

	# O PLACAR PRIMEIRO: quem ficou de pé e quanto cada lado causou. É a
	# resposta da tela, e agora ela cabe em três linhas de uma tabela só.
	col.add_child(_placar_card())
	col.add_child(_resumo_card())

	var warn := String(_log.get("warning", ""))
	if warn != "":
		var wc := UI.card(UI.PANEL, UI.WARN.darkened(0.45))
		wc.add_child(UI.label(warn, UI.F_BODY, UI.WARN))
		col.add_child(wc)

	if won:
		col.add_child(_reward_card())
	else:
		var c := UI.card(UI.PANEL, UI.BAD.darkened(0.4))
		c.add_child(UI.label(
			"A run termina aqui. Na derrota, a coluna que costuma explicar é a de "
			+ "Reações: ela está no detalhe por criatura.",
			UI.F_BODY, UI.TEXT_DIM))
		col.add_child(c)

	# A GAVETA. Fechada de nascença, e ela abre PARA DENTRO do vazio que sobra
	# entre o conteúdo e o rodapé — ver `_gaveta`.
	col.add_child(_gaveta())

	# O VAZIO TEM DONO. Com a gaveta fechada ele empurra o rodapé para baixo;
	# com ela aberta ele SAI, e a folga inteira vira gaveta. Se os dois
	# expandissem juntos, a gaveta ficaria com metade do que há.
	_vazio = UI.spacer()
	col.add_child(_vazio)

	var foot := UI.box(false, 14)
	foot.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_child(foot)
	# CONTINUAR entra PRIMEIRO na árvore de propósito: `Main._focar_primeiro`
	# anda em ordem de desenho, e é ele que o ENTER tem de acionar.
	var b := UI.button_confirmar("  CONTINUAR  ", UI.F_H2)
	b.custom_minimum_size = Vector2(420, 0)
	b.pressed.connect(func(): continue_pressed.emit())
	foot.add_child(b)
	foot.add_child(_bt_detalhe)


## TRADUÇÃO DO MOTIVO DO FIM.
##
## O texto cru vem de `combat_sim.gd` e serve às ferramentas de lote — é ele que
## aparece no CSV do autoplay. Aqui ele vira português de jogador. "Limite de
## ticks" não é uma coisa que acontece no mundo do PRISMON; é uma coisa que
## acontece dentro do laço `run_to_end`.
func _motivo(cru: String) -> String:
	if cru.begins_with("tempo esgotado"):
		var entre := cru.substr(cru.find("(")) if cru.contains("(") else ""
		return "o tempo acabou — venceu quem tinha mais vida %s" % entre
	match cru:
		"limite de ticks":
			return "a briga travou: ninguém conseguiu derrubar ninguém"
		"aniquilacao mutua":
			return "os dois lados caíram no mesmo instante"
		"inimigos eliminados":
			return "o bando inteiro caiu"
		"equipe eliminada":
			return "a sua equipe inteira caiu"
		_:
			return cru


## O resumo de uma linha: o que a briga produziu, antes do detalhe.
func _resumo_card() -> Control:
	var card := UI.card()
	var v := UI.box(true, 6)
	card.add_child(v)

	# reacoes causadas
	var rrow := UI.box(false, 12)
	v.add_child(rrow)
	rrow.add_child(_tag("REAÇÕES CAUSADAS"))
	var rx: Array = _log.get("reactions", [])
	if rx.is_empty():
		rrow.add_child(UI.label("nenhuma — sua equipe só bateu", UI.F_BODY, UI.BAD))
	for r in rx:
		var chip := UI.box(false, 4)
		chip.add_child(UI.label(String(r["name"]), UI.F_BODY, Color(String(r["color"]))))
		chip.add_child(UI.label("×%d" % int(r["count"]), UI.F_BODY, UI.TEXT))
		rrow.add_child(chip)

	# maior golpe
	var big: Dictionary = _log.get("biggest_hit", {})
	if not big.is_empty():
		var brow := UI.box(false, 12)
		v.add_child(brow)
		brow.add_child(_tag("MAIOR GOLPE"))
		brow.add_child(UI.label("%s → %d  em %s  (%s)" % [String(big.get("src", "?")),
			roundi(float(big.get("amount", 0.0))), String(big.get("dst", "?")),
			UI.damage_name(String(big.get("type", "")))], UI.F_BODY, UI.GOLD))

	# ativos usados — SO quando houve algum. "ATIVOS USADOS: nenhum" gastava
	# uma linha da tela para informar que nao ha o que informar.
	var acts: Array = _log.get("actives", [])
	if not acts.is_empty():
		var arow := UI.box(false, 12)
		v.add_child(arow)
		arow.add_child(_tag("ATIVOS USADOS"))
		arow.add_child(UI.label("  ·  ".join(acts), UI.F_BODY,
			UI.ACCENT.lightened(0.2)))
	return card


# --- o placar ---------------------------------------------------------------

## As colunas do PLACAR. São três porque a pergunta é de três partes: quem
## reagiu, quem bateu, quem apanhou. Nocautes e Cura não comparam lados — são
## perguntas sobre criatura, e moram na gaveta.
const PLACAR_COLS := [
	{"key": "reactions", "head": "Reações"},
	{"key": "damage",    "head": "Dano"},
	{"key": "taken",     "head": "Sofrido"},
]


## OS DOIS LADOS NA MESMA TABELA, uma linha cada.
##
## Era um rodapé DENTRO de cada um dos dois cartões (`_totais`), e comparar
## "causou 2107" com "causou 184" obrigava o olho a atravessar 700 px de tela na
## horizontal. Empilhados na mesma coluna, os dois números viram uma frase só —
## e a barra proporcional de `_cell` mede um lado contra o outro de graça,
## porque o `best` agora é o máximo DOS DOIS lados.
func _placar_card() -> Control:
	var minha: Array = _log.get("units", [])
	var dele: Array = _log.get("enemy_units", [])
	var lados: Array = [
		{"nome": "A SUA EQUIPE", "cor": UI.GOOD, "soma": _somar(minha), "n": minha.size()},
		{"nome": "O BANDO INIMIGO", "cor": UI.BAD, "soma": _somar(dele), "n": dele.size()},
	]

	var best: Dictionary = {}
	for l in lados:
		var s: Dictionary = l["soma"]
		for c in PLACAR_COLS:
			var k := String(c["key"])
			best[k] = maxf(float(best.get(k, 0.0)), float(s.get(k, 0.0)))

	var card := UI.card()
	var g := GridContainer.new()
	g.columns = 2 + PLACAR_COLS.size()
	g.add_theme_constant_override("h_separation", 12)
	g.add_theme_constant_override("v_separation", 4)
	card.add_child(g)

	var vazio := Control.new()
	vazio.custom_minimum_size = Vector2(NOME_W_MIN, 0)
	vazio.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	g.add_child(vazio)
	g.add_child(_cabecalho("De pé"))
	for c in PLACAR_COLS:
		g.add_child(_cabecalho(String(c["head"])))

	for l in lados:
		var cor: Color = l["cor"]
		var s: Dictionary = l["soma"]
		var corpos: int = int(l["n"])
		var nome := UI.label(String(l["nome"]), UI.F_BODY, cor.lightened(0.15))
		nome.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		g.add_child(nome)
		if corpos == 0:
			# `combat_log()` só monta o lado 0; quem monta o lado 1 é
			# ScreenCombat. Sem ele a linha existe e não mente.
			g.add_child(_texto_cell("—", UI.TEXT_DIM))
			for _c in PLACAR_COLS:
				g.add_child(_texto_cell("—", UI.LINE.lightened(0.2)))
			continue
		var vivos: int = int(s["vivos"])
		g.add_child(_texto_cell("%d de %d" % [vivos, corpos],
			cor if vivos > 0 else UI.TEXT_DIM))
		for c in PLACAR_COLS:
			var k := String(c["key"])
			g.add_child(_cell(float(s.get(k, 0.0)), float(best.get(k, 0.0)), k))
	return card


## Os totais de um lado, sem agregar por nome: aqui a pergunta é do LADO.
func _somar(fonte: Array) -> Dictionary:
	var s: Dictionary = {"vivos": 0, "kills": 0.0, "reactions": 0.0,
		"damage": 0.0, "healing": 0.0, "taken": 0.0}
	for u in fonte:
		if bool(u.get("alive", false)):
			s["vivos"] = int(s["vivos"]) + 1
		for campo in ["kills", "reactions", "damage", "healing", "taken"]:
			s[campo] = float(s[campo]) + float(u.get(campo, 0))
	return s


# --- a gaveta do detalhe por criatura ---------------------------------------

## O DETALHE FICA ATRÁS DE UMA CONSULTA.
##
## As duas tabelas por criatura são a ferramenta de aprendizado do §21.3 e
## continuam inteiras — mas elas respondem a segunda pergunta, não a primeira. A
## primeira ("ganhei? por quanto?") já está respondida acima em três linhas, e
## manter as tabelas abertas custava ~400 px de moldura para duas linhas de
## conteúdo: o vazio DENTRO de um painel lê como defeito, não como espaço.
##
## AS DUAS TABELAS EMPILHADAS, e não lado a lado. Lado a lado era o que obrigava
## cada uma a caber em meia tela — a origem aritmética do vazamento. Empilhadas,
## cada tabela tem a largura inteira (1236 px com o trilho à vista contra os 670
## que cinco colunas pedem), a coluna do nome come toda a folga e as colunas de
## número das duas caem no MESMO x: comparar "1811" com "184" continua sendo
## olhar para cima e para baixo, que é o gesto que as duas tabelas existiam para
## permitir. E a comparação de lado contra lado já foi respondida no placar.
##
## O botão vive no RODAPÉ, ao lado do CONTINUAR, e a gaveta abre no vazio que há
## entre o conteúdo e ele. Duas razões: o vazio passa a ter função em vez de ser
## sobra, e `Main._focar_primeiro` continua entregando o foco ao CONTINUAR, que
## é o que o ENTER tem de fazer nesta tela.
func _gaveta() -> Control:
	_cols = _colunas([_log.get("units", []), _log.get("enemy_units", [])])
	_detalhe = UI.box(true, 10)
	_detalhe.visible = false
	_detalhe.add_child(_tabela_card("A SUA EQUIPE", _log.get("units", []), UI.GOOD))
	_detalhe.add_child(_tabela_card("O BANDO INIMIGO", _log.get("enemy_units", []), UI.BAD))

	_bt_detalhe = UI.button_secundario(ABRIR, UI.F_BODY)
	_bt_detalhe.custom_minimum_size = Vector2(400, 0)
	_bt_detalhe.pressed.connect(_alternar_detalhe)

	# A ROLAGEM É O QUE FAZ A FRASE ACIMA VIRAR LAYOUT (16/09). Sem ela a
	# intenção morava só no comentário: um BoxContainer nunca entrega menos
	# que o mínimo do filho, então a gaveta aberta empurrava o rodapé para
	# fora da janela — CONTINUAR terminava em y=963 de 900, medido em
	# tools/gaveta_probe.tscn. Com rolagem vertical AUTO, o mínimo do
	# ScrollContainer NÃO inclui a altura do filho: ele aceita a folga que
	# há, e o que não couber ROLA. O rodapé não se mexe mais.
	_rolagem = ScrollContainer.new()
	_rolagem.visible = false
	_rolagem.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_rolagem.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_rolagem.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	# calha reservada: a largura do conteúdo não muda quando a barra aparece
	var calha := MarginContainer.new()
	calha.add_theme_constant_override("margin_right", PrismaTheme.SCROLL_W)
	calha.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rolagem.add_child(calha)
	_detalhe.visible = true
	calha.add_child(_detalhe)
	return _rolagem


func _alternar_detalhe() -> void:
	var aberto: bool = not _rolagem.visible
	_rolagem.visible = aberto
	if _vazio != null:
		_vazio.visible = not aberto
	_bt_detalhe.text = FECHAR if aberto else ABRIR
	# a gaveta abre no topo, sempre: reabrir no meio da tabela lê como
	# defeito de desenho
	if aberto:
		_rolagem.scroll_vertical = 0


# --- a tabela por criatura --------------------------------------------------

## Placar por unidade em TABELA, como o "Pontuações por Cara" do How Many
## Dudes: uma linha por Cara, uma coluna por métrica. A barra sozinha dizia
## quem bateu mais; a tabela diz também quem curou, quem morreu e quem apanhou
## — que e o que explica uma derrota.

## A LARGURA DA CÉLULA DE NÚMERO, fixa — e é a COLUNA DO NOME que estica.
##
## Fixa está certo: é o que faz "1811" e "184" caírem no mesmo x em tabelas
## diferentes. O que estava errado era somar cinco delas dentro de meia tela. Com
## as tabelas empilhadas (ver `_gaveta`), cinco colunas pedem 670 px contra os
## 1236 que a mais estreita das duas larguras desta tela oferece — e a folga toda
## cai na coluna do nome, que é a única com texto de largura imprevisível.
##
## Esticar a CÉLULA em vez do nome foi a primeira tentativa e ficou pior: numa
## tabela de três colunas a barra proporcional virava uma laje de 380 px atrás de
## um número de dois dígitos.
const CELL_W := 84
const CELL_PAD := 7

## O piso da coluna do NOME. O rótulo não tem `clip_text`, então ele empurra a
## coluna sozinho quando precisa ("Hipocampo ×2" mede ~156 px + 22 do ícone); o
## piso só existe para que um elenco de nomes curtos não encolha a coluna a
## ponto de desalinhar uma tabela da outra.
const NOME_W_MIN := 190

## Uma palavra por coluna. Eram tres delas em duas linhas ("Dano" em cima de
## "Causado"), o que dava um cabecalho de tres alturas diferentes para cinco
## colunas — e "Cura Concedida" nao diz mais do que "Cura".
const COLS := [
	{"key": "kills",     "head": "Nocautes"},
	{"key": "reactions", "head": "Reações"},
	{"key": "damage",    "head": "Dano"},
	{"key": "healing",   "head": "Cura"},
	{"key": "taken",     "head": "Sofrido"},
]

## As colunas que ESTA tela vai desenhar, decididas uma vez em `_gaveta` e usadas
## pelas duas tabelas. Ver `_colunas`.
var _cols: Array = []


## COLUNA ZERADA NAO APARECE — MAS O ZERO TEM DE SER DOS DOIS LADOS.
##
## A regra nasceu para uma tabela so: numa briga sem curandeiro a coluna "Cura"
## era uma pilha de zeros cinzentos ocupando espaco para dizer que nada aconteceu.
## Quando a tela ganhou a segunda tabela, aplicar a regra POR TABELA quebrou a
## unica coisa que faz duas tabelas lado a lado valerem a pena: ler a mesma
## coluna na mesma posicao nas duas.
##
## Medido no print 06_log_de_combate.png: o jogador saia com 4 colunas e o bando
## com 3. A que sumia era "Reacoes", porque o bando causou ZERO — e o rodape
## desta mesma tela diz, na derrota, "a coluna que explica costuma ser a de
## Reacoes". Um zero ali nao e ausencia de informacao, e A informacao.
##
## Agora a coluna entra se QUALQUER um dos lados produziu alguma coisa nela.
func _colunas(fontes: Array) -> Array:
	var best: Dictionary = {}
	for fonte in fontes:
		for u in _agregar(fonte):
			for c in COLS:
				var k := String(c["key"])
				best[k] = maxf(float(best.get(k, 0.0)), float(u.get(k, 0)))
	var cols: Array = COLS.filter(func(c): return float(best.get(String(c["key"]), 0.0)) > 0.0)
	# Dano fica sempre: uma tabela sem nenhuma coluna nao e uma tabela.
	return cols if not cols.is_empty() else [COLS[2]]


## SOMA os Prismons de mesmo nome (pedido do autor, 03/09).
##
## Duas Coallas na equipe viravam duas linhas "Coalla" na tabela, com numeros
## diferentes e nada dizendo que eram bichos distintos — parecia erro. O que o
## jogador quer saber e quanto a ESPECIE rendeu, entao as linhas somam e o
## rotulo ganha "×2". Uma linha morre so quando todas as copias morreram.
##
## Vale para os DOIS lados desde 15/09: um bando de "4 Pinto-Raios" é
## exatamente o caso que a soma foi escrita para resolver.
##
## `_por_nome()` continua existindo sem argumento e continua significando "o SEU
## lado": é a assinatura que `tools/smoke_test.gd` exercita, e o teste é de
## outro dono. Quem agrega é `_agregar`, e as duas tabelas o chamam.
func _por_nome() -> Array:
	return _agregar(_log.get("units", []))


func _agregar(fonte: Array) -> Array:
	var acc: Dictionary = {}
	var ordem: Array = []
	for u in fonte:
		var k := String(u.get("name", ""))
		if not acc.has(k):
			acc[k] = {"name": k, "element": u.get("element", "FOGO"),
				"alive": false, "count": 0,
				"kills": 0, "reactions": 0, "damage": 0.0,
				"healing": 0.0, "taken": 0.0}
			ordem.append(k)
		var a: Dictionary = acc[k]
		a["count"] = int(a["count"]) + 1
		a["alive"] = bool(a["alive"]) or bool(u.get("alive", false))
		for campo in ["kills", "reactions"]:
			a[campo] = int(a[campo]) + int(u.get(campo, 0))
		for campo in ["damage", "healing", "taken"]:
			a[campo] = float(a[campo]) + float(u.get(campo, 0.0))
		acc[k] = a
	var out: Array = []
	for k in ordem:
		out.append(acc[k])
	out.sort_custom(func(a, b): return float(a["damage"]) > float(b["damage"]))
	return out


## Um cartão da gaveta: só a tabela por criatura. O rodapé de totais que morava
## aqui virou o placar lá de cima — ver `_placar_card`.
func _tabela_card(titulo: String, fonte: Array, cor: Color) -> Control:
	var card := UI.card(UI.PANEL, cor.darkened(0.45))
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var v := UI.box(true, 6)
	card.add_child(v)
	v.add_child(UI.label(titulo, 12, cor.lightened(0.15)))
	v.add_child(UI.hsep())
	if fonte.is_empty():
		v.add_child(UI.label("sem dados deste lado", UI.F_BODY, UI.TEXT_DIM))
		return card
	v.add_child(_scoreboard(fonte))
	return card


func _scoreboard(fonte: Array) -> Control:
	var linhas := _agregar(fonte)

	# o melhor de cada coluna vira referência para a barrinha de fundo
	var best: Dictionary = {}
	for u in linhas:
		for c in COLS:
			var k := String(c["key"])
			best[k] = maxf(float(best.get(k, 0.0)), float(u.get(k, 0)))

	# A ESCOLHA DAS COLUNAS NAO E FEITA AQUI: ela olha os DOIS lados e foi feita
	# uma vez em `_gaveta` (ver `_colunas`). Refaze-la por tabela e o que deixava
	# os dois placares com contagens diferentes.
	# O plano B usa o `best` local: se alguem montar o placar sem passar pelo
	# `_ready` desta tela, uma tabela so continua se comportando como antes.
	var cols: Array = _cols
	if cols.is_empty():
		cols = COLS.filter(func(c): return float(best.get(String(c["key"]), 0.0)) > 0.0)
		if cols.is_empty():
			cols = [COLS[2]]

	var g := GridContainer.new()
	g.columns = cols.size() + 1
	g.add_theme_constant_override("h_separation", 12)
	g.add_theme_constant_override("v_separation", 3)

	# A COLUNA DO NOME ESTICA. Ela é a que tem texto de largura imprevisível, e
	# é nela que a folga do cartão deve cair primeiro.
	var vazio := Control.new()
	vazio.custom_minimum_size = Vector2(NOME_W_MIN, 0)
	vazio.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	g.add_child(vazio)
	for c in cols:
		g.add_child(_cabecalho(String(c["head"])))

	for u in linhas:
		var nm := UI.box(false, 6)
		nm.add_child(Icons.element(String(u.get("element", "FOGO")), 16.0))
		var alive: bool = bool(u.get("alive", true))
		var rotulo := String(u["name"])
		if int(u.get("count", 1)) > 1:
			rotulo += " ×%d" % int(u["count"])
		var unm := UI.label(rotulo, UI.F_BODY, UI.TEXT if alive else UI.TEXT_DIM)
		unm.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		nm.add_child(unm)
		if not alive:
			nm.add_child(UI.label("✝", UI.F_SMALL, UI.BAD))
		g.add_child(nm)
		for c in cols:
			g.add_child(_cell(float(u.get(String(c["key"]), 0)),
				float(best.get(String(c["key"]), 0.0)), String(c["key"])))
	return g


## Cabeçalho de coluna de número. Alinhado pela BASE: se um dia voltar um
## cabeçalho de duas linhas, o nome da coluna continua encostando na mesma linha
## dos vizinhos. A margem repete o `content_margin` da célula — sem ela o
## cabeçalho encosta na borda da coluna e os números ficam 7 px à esquerda dele.
func _cabecalho(texto: String) -> Control:
	var h := UI.label(texto, 11, UI.TEXT_DIM, HORIZONTAL_ALIGNMENT_RIGHT)
	h.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	h.size_flags_vertical = Control.SIZE_EXPAND_FILL
	h.custom_minimum_size = Vector2(CELL_W - CELL_PAD, 0)
	var hm := MarginContainer.new()
	hm.add_theme_constant_override("margin_right", CELL_PAD)
	hm.add_child(h)
	return hm


## Célula de TEXTO alinhada com as de número ("2 de 2", "—"): mesma largura,
## mesmo respiro à direita. Sem ela a coluna "De pé" ficaria 7 px fora do
## alinhamento do próprio cabeçalho.
func _texto_cell(texto: String, cor: Color) -> Control:
	var l := UI.label(texto, UI.F_BODY, cor, HORIZONTAL_ALIGNMENT_RIGHT)
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.custom_minimum_size = Vector2(CELL_W - CELL_PAD, 0)
	var m := MarginContainer.new()
	m.add_theme_constant_override("margin_right", CELL_PAD)
	m.add_child(l)
	return m


## Célula: o número, com uma barra de fundo proporcional ao melhor da coluna —
## a comparação fica visível sem ler os dígitos.
##
## A largura é `CELL_W` e não estica: quem estica é a coluna do nome. Ver a nota
## de `CELL_W` — é lá que mora a aritmética do vazamento de 16/09.
func _cell(value: float, best: float, key: String) -> Control:
	var col := UI.TEXT
	if value <= 0.0:
		col = UI.LINE.lightened(0.2)
	elif key == "healing":
		col = UI.GOOD
	elif key == "taken":
		col = UI.BAD.lightened(0.15)
	elif key == "damage":
		col = UI.GOLD

	# StyleBoxFlat, nao a moldura 9-patch do UI.panel: a moldura desenha o
	# quadro mesmo com fundo transparente, e a tabela virava uma grade de
	# caixinhas vazias nas celulas zeradas.
	var p := PanelContainer.new()
	p.custom_minimum_size = Vector2(CELL_W, 0)
	var frac: float = 0.0 if best <= 0.0 else clampf(value / best, 0.0, 1.0)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(col.r, col.g, col.b, 0.20 * frac)
	sb.corner_radius_top_left = 3
	sb.corner_radius_top_right = 3
	sb.corner_radius_bottom_left = 3
	sb.corner_radius_bottom_right = 3
	sb.content_margin_left = CELL_PAD
	sb.content_margin_right = CELL_PAD
	sb.content_margin_top = 2
	sb.content_margin_bottom = 2
	p.add_theme_stylebox_override("panel", sb)
	p.add_child(UI.label("%d" % roundi(value), UI.F_BODY, col,
		HORIZONTAL_ALIGNMENT_RIGHT))
	return p


func _tag(text: String) -> Control:
	var l := UI.label(text, 11, UI.TEXT_DIM)
	l.custom_minimum_size = Vector2(150, 0)
	return l


func _reward_card() -> Control:
	var g: Dictionary = _log.get("gained", {})
	var card := UI.card_gold()
	var v := UI.box(true, 4)
	card.add_child(v)
	v.add_child(UI.label("RECOMPENSA", 11, UI.TEXT_DIM))
	var row := UI.box(false, 18)
	v.add_child(row)
	row.add_child(Icons.counter("ether", "+%d Éter" % int(g.get("ether", 0)), UI.GOLD, 32.0))
	return card
