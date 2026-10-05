class_name Main
extends Control
## Roteador de telas + HUD persistente de recursos.
## GDD 3.1 -- loop macro: ESCOLHA DE NO -> PREPARACAO -> COMBATE -> RECOMPENSA -> UPKEEP.
##
## Desde 15/09 ele tambem e o dono de tres coisas que nao cabiam em nenhuma
## tela: o SAVE DA RUN (user://run_save.cfg), o MENU DE PAUSA (ESC) e a
## sincronia do F11 com a opcao "Tela cheia".

var hud: PanelContainer
var rail: RosterRail
var ribbon: RunRibbon
var chrome_on := false
var _pausa: Control = null

## Largura fixa do conteúdo das barras: nada aqui acompanha o tamanho da janela.
## Largura das duas celulas laterais da barra do topo. Iguais de proposito:
## e o que garante que a fita caia no centro exato da tela.
const LADO_W := 140.0

const BAR_W := 1180.0
var hud_labels: Dictionary = {}
var content: Control
var screen: Control = null

var pair: Array = []
var current_node: Dictionary = {}
var last_result: Dictionary = {}


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# um Theme na raiz alcança tooltip, barra de rolagem, LineEdit e
	# ProgressBar — que os overrides por nó nunca tocavam
	theme = PrismaTheme.get_theme()
	# as configuracoes valem desde o primeiro quadro: tela cheia aplicada
	# antes de qualquer tela aparecer evita o pisca de janela -> tela cheia
	ScreenOptions.carregar()
	# a camada de dicas vive por cima de TUDO e ignora o mouse; nenhuma tela
	# precisa saber que ela existe — `tooltip_text` continua sendo o unico
	# lugar onde se escreve uma dica
	call_deferred("add_child", TooltipLayer.new())
	var bg := ColorRect.new()
	bg.color = UI.BG
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	var root := UI.box(true, 0)
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(root)

	hud = _build_hud()
	root.add_child(hud)

	# Layout do How Many Dudes: o elenco mora num trilho fixo à ESQUERDA e a
	# fita da run no ALTO; o miolo fica livre para a arena e para as decisões.
	var body := UI.box(false, 0)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(body)

	rail = RosterRail.new()
	rail.visible = false
	body.add_child(rail)

	content = Control.new()
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(content)

	Run.resources_changed.connect(_refresh_hud)
	Run.team_changed.connect(_refresh_hud)
	go_title()


# --- HUD -------------------------------------------------------------------

func _build_hud() -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", _pele_do_hud(UI.PANEL))

	# A barra deixa de esticar de ponta a ponta. Em 2544 px de largura os
	# espaçadores jogavam o logo num canto e os recursos no outro, e o
	# conteúdo "escalava" com a janela. Agora o conteúdo tem largura própria e
	# fica CENTRADO: em qualquer resolução ele ocupa o mesmo lugar.
	var center := CenterContainer.new()
	p.add_child(center)
	var row := UI.box(false, 22)
	row.custom_minimum_size = Vector2(BAR_W, 0)
	center.add_child(row)

	# O NOME DO JOGO saiu da barra (pedido do autor, 03/09). Quem esta jogando
	# ja sabe que jogo e; o rotulo so gastava largura ao lado da fita.
	# LIMPEZA (31/08): a barra tinha NÓ, ÉTER, DESPENSA (com cinco contagens
	# escritas "7 F 2 G 4 Á…"), VÍNCULO, RELÍQUIAS e SEMENTE — seis blocos que
	# estouravam a largura e que ninguem lia no meio da decisao. Sobraram DOIS
	# numeros: o que se gasta e o que se cozinha. O resto ja tem casa propria:
	# a fita mostra o nó, o trilho mostra o Vínculo, a doca mostra as relíquias.
	# A FITA FICA NO CENTRO DA TELA (pedido do autor, 03/09). Ela e a coisa
	# que se olha para saber o que vem pela frente, e estava encostada a
	# esquerda com o Eter logo ao lado e meia barra vazia a direita.
	#
	# Nao basta centrar a fita dentro da linha: o Eter ocupa espaco so de um
	# lado e empurraria o centro. Por isso a linha e simetrica — uma celula
	# vazia a ESQUERDA com a mesma largura da celula do Eter a direita. Com
	# os dois lados iguais, o meio e o meio de verdade.
	var esq := Control.new()
	esq.custom_minimum_size = Vector2(LADO_W, 0)
	row.add_child(esq)

	var meio := CenterContainer.new()
	meio.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(meio)
	ribbon = RunRibbon.new()
	meio.add_child(ribbon)

	# UMA moeda so (03/09). Antes eram ÉTER e DESPENSA lado a lado, e o autor
	# nao sabia dizer o que "DESPENSA" media — sinal de que a segunda moeda
	# custava mais atencao do que valia.
	var dir := UI.box(false, 0)
	dir.custom_minimum_size = Vector2(LADO_W, 0)
	dir.alignment = BoxContainer.ALIGNMENT_END
	row.add_child(dir)
	dir.add_child(_hud_field("ether", "ÉTER", "0", UI.GOLD, "ether"))
	return p


## Ícone + número, UMA linha. Era rótulo em cima e número embaixo — duas
## linhas de altura para dizer a mesma coisa duas vezes, já que a moeda
## desenhada não precisa da palavra "ÉTER" por cima dela. O nome vive no
## tooltip, para quem passar o mouse na primeira vez.
func _hud_field(key: String, title: String, value: String, color: Color = UI.TEXT,
		icon: String = "") -> Control:
	var row := UI.box(false, 7)
	row.tooltip_text = title
	if icon != "":
		row.add_child(Icons.node(icon, UI.icon_px(UI.F_H2)))
	var l := UI.label(value, UI.F_H2, color)
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(l)
	hud_labels[key] = l
	return row


## A PELE DA BARRA DO TOPO, com o miolo que lhe mandarem.
##
## Era `Color("#15121f")` escrito aqui — um dos hex soltos que sobravam fora de
## `data/paleta.json` depois que o kit virou dado.
func _pele_do_hud(miolo: Color) -> StyleBoxTexture:
	var sb := UI.panel(miolo, 0, UI.LINE)
	sb.content_margin_left = 14
	sb.content_margin_right = 14
	sb.content_margin_top = 9
	sb.content_margin_bottom = 9
	return sb


## A BARRA DO TOPO MUDA DE SALA JUNTO COM A TELA (17/09).
##
## Ela é a maior superfície contínua do jogo fora do combate e aparece em TODAS
## as telas de fora da briga — ou seja, era também a maior peça que não mudava
## nunca. Um recruta azul com uma barra roxa em cima continua sendo meio roxo.
##
## Roda depois de `content.add_child(s)`: `add_child` dispara o `_ready()` da
## tela na hora, e é lá que `UI.luz_de_sala()` registra `UI.sala`. Quando a tela
## não declara sala (o combate, que esconde a barra), `UI.sala` é o fundo e a
## conta devolve o degrau neutro — o caso seguro.
func _hud_da_sala() -> void:
	if hud == null or not is_instance_valid(hud):
		return
	hud.add_theme_stylebox_override("panel",
		_pele_do_hud(UI.materia_da_sala(UI.PANEL, UI.sala)))


func _refresh_hud() -> void:
	if hud_labels.is_empty():
		return
	_contar(hud_labels["ether"], Run.ether)


## O número CONTA até o valor novo em vez de saltar (04/09).
##
## Ganhar 22 de Éter trocando "10" por "32" num quadro é uma informação que
## passa despercebida — o olho não registra um dígito que muda sozinho. Subindo
## em ~0.35 s ele vira um evento, e o pulso no fim diz que a recompensa é sua.
func _contar(l: Label, alvo: int) -> void:
	var de := int(l.text) if l.text.is_valid_int() else alvo
	if de == alvo:
		l.text = str(alvo)
		return
	if not Juice.enabled:
		l.text = str(alvo)
		return
	var t := l.create_tween()
	t.tween_method(func(v: float): l.text = str(roundi(v)),
		float(de), float(alvo), 0.35).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	t.tween_callback(func(): Juice.pulse(l, 1.14))


func _set_chrome(on: bool) -> void:
	chrome_on = on
	hud.visible = on
	rail.visible = on
	if on:
		rail.rebuild()
		ribbon.rebuild()


## Telas em que a largura vale mais que o elenco à vista: a arena precisa do
## espaço, e o log já lista as unidades na própria tabela.
## O FOCO INICIAL DA TELA NOVA, num lugar so.
##
## Sem isto a navegacao por teclado existe e nao comeca: o jogador aperta a seta
## e nada acontece, porque nenhum controle tem o foco para ceder ao vizinho.
##
## O COMBATE FICA DE FORA de proposito. La as teclas sao do JOGO — 1/2/3 lancam
## Ativos, ESPACO pausa, TAB muda a velocidade — e um botao focado come ESPACO e
## TAB antes do jogo ver. Foi exatamente o defeito relatado ("clicar qualquer
## botao com o mouse desliga ESPACO e TAB"); dar foco na entrada o reintroduziria
## sem nem precisar de clique.
func _focar_primeiro(s: Control) -> void:
	if s is ScreenCombat:
		return
	var alvo := _primeiro_focavel(s)
	if alvo != null:
		alvo.grab_focus()


## Primeiro Control da arvore, em ordem de desenho, que aceita foco e esta
## visivel. LineEdit fica para depois de qualquer botao: numa tela com campo de
## texto (o de Semente, no titulo) comecar dentro do campo faria a primeira seta
## do jogador andar o cursor em vez de trocar de opcao.
func _primeiro_focavel(n: Node) -> Control:
	var texto: Control = null
	var pilha: Array = [n]
	while not pilha.is_empty():
		var atual: Node = pilha.pop_front()
		if atual is Control:
			var c := atual as Control
			if c.focus_mode != Control.FOCUS_NONE and c.is_visible_in_tree():
				if c is LineEdit:
					if texto == null:
						texto = c
				else:
					return c
		for f in atual.get_children():
			pilha.append(f)
	return texto


func _swap(s: Control) -> void:
	if screen != null and is_instance_valid(screen):
		screen.queue_free()
	screen = s
	s.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	content.add_child(s)
	# JUICE: a tela nova entra subindo e aparecendo. Vive AQUI, no único ponto
	# por onde toda troca de tela passa — nenhuma tela precisa saber disso.
	Juice.enter_screen(s)
	_focar_primeiro(s)
	_hud_da_sala()
	_refresh_hud()
	if chrome_on:
		# No combate o topo inteiro some: o caminho da run nao ajuda a assistir
		# uma briga, e a fita competia com a arena pelo olho.
		var fighting: bool = s is ScreenCombat
		hud.visible = not fighting
		# O LOG VOLTOU A TER O TRILHO (15/09). Ele era escondido aqui, e como a
		# tela seguinte o mostra, o conteudo do log nascia 144 px a esquerda do
		# conteudo do evento — dois retangulos diferentes para duas telas
		# consecutivas. E o trilho tem o que dizer no log: quem sobrou vivo.
		rail.visible = not (fighting or s is ScreenEnd)
		if rail.visible:
			rail.rebuild()
		ribbon.rebuild()


func go_title() -> void:
	_set_chrome(false)
	_fechar_pausa()
	var s := ScreenTitle.new()
	s.setup(tem_save(), save_passo())
	s.start_requested.connect(func(seed_value: int):
		Run.start_run(seed_value)
		ScreenCombat.esquecer_dica()
		apagar_save()
		go_starter())
	s.continue_requested.connect(_continuar_run)
	s.options_requested.connect(go_options)
	_swap(s)


## Configurações. Voltam para o menu, e não para o jogo: a tela existe para ser
## ajustada antes de começar, e sair dela pelo meio de uma run confundiria.
func go_options() -> void:
	_set_chrome(false)
	var o := ScreenOptions.new()
	o.closed.connect(go_title)
	_swap(o)


## Revisão 31/08: o jogador escolhe a dupla inicial (antes era sorteada).
func go_starter() -> void:
	var s := ScreenStarter.new()
	s.confirmed.connect(func(ids: Array):
		Run.set_starting_team(ids)
		_set_chrome(true)
		next_node())
	_swap(s)


func next_node() -> void:
	Run.node_index += 1
	if Run.node_index > Run.total_nodes():
		go_end(true)
		return
	pair = NodeGen.generate_pair(Run.node_index)
	var s := ScreenMap.new()
	s.setup(pair)
	s.chosen.connect(_on_node_chosen)
	_swap(s)


func _on_node_chosen(node: Dictionary) -> void:
	current_node = node
	Run.history.append({"index": Run.node_index, "type": String(node.get("type", ""))})
	go_prep()


func go_prep() -> void:
	var s := ScreenPrep.new()
	s.setup(current_node)
	s.fight.connect(go_combat)
	_swap(s)


func go_combat() -> void:
	var s := ScreenCombat.new()
	s.setup(current_node)
	s.combat_over.connect(_on_combat_over)
	_swap(s)


## O nó que acabou de ser jogado guarda os NÚMEROS do combate, e não só o tipo.
## É o que faz "A RUN EM NÚMEROS" da tela de fim ter números de combate: até
## 15/09 o cartão com esse título mostrava peso elemental, relíquias e pratos —
## nenhum deles produzido por uma briga. `Run.history` já era escrito aqui; só
## faltava escrever o que importa nele.
func _on_combat_over(result: Dictionary) -> void:
	last_result = result
	if not Run.history.is_empty():
		var h: Dictionary = Run.history[Run.history.size() - 1]
		h["won"] = bool(result.get("won", false))
		h["duration"] = float(result.get("duration", 0.0))
		h["reactions"] = int(result.get("total_reactions", 0))
		h["damage"] = float(result.get("damage_dealt", 0.0))
		h["taken"] = float(result.get("damage_taken", 0.0))
		h["actives"] = int((result.get("actives", []) as Array).size())
		var big: Dictionary = result.get("biggest_hit", {})
		h["biggest"] = float(big.get("amount", 0.0))
		h["biggest_src"] = String(big.get("src", ""))
		Run.history[Run.history.size() - 1] = h
	var s := ScreenResult.new()
	s.setup(current_node, result)
	s.continue_pressed.connect(_after_combat)
	_swap(s)


## Vitória fora do chefe → o MOMENTO DE EVENTO daquele nó. O jogador não
## escolhe qual evento aparece (o esquema está em tuning → momentos), mas
## dentro dele sempre há uma escolha (revisão 31/08).
func _after_combat() -> void:
	# A recuperação acontece AQUI — depois do combate e ANTES do evento. Se
	# viesse depois, o dano que um evento de acaso cobra seria apagado junto e
	# "a fenda desmorona, equipe perde 22% do HP" viraria texto decorativo.
	Run.heal_between_nodes()
	if Run.defeated or Run.node_index >= Run.total_nodes():
		_after_node()
		return
	match EventGen.kind_after(Run.node_index):
		"recruta":
			var r := ScreenRecruit.new()
			r.setup(EventGen.recruit_offer(Run.node_index))
			r.finished.connect(_after_node)
			_swap(r)
		"loja":
			var l := ScreenShop.new()
			l.setup(EventGen.shop_offer(Run.node_index), Run.node_index)
			l.finished.connect(_after_node)
			_swap(l)
		"poder":
			var pw := ScreenPower.new()
			pw.setup(EventGen.power_offer(Run.node_index), Run.node_index)
			pw.finished.connect(_after_node)
			_swap(pw)
		"troca":
			var tr := ScreenTrade.new()
			tr.setup(EventGen.trade_offer(Run.node_index), Run.node_index)
			tr.finished.connect(_after_node)
			_swap(tr)
		"cozinha":
			var k := ScreenKitchen.new()
			k.setup(EventGen.kitchen_offer(Run.node_index), Run.node_index)
			k.finished.connect(_after_node)
			_swap(k)
		"acaso":
			var ev := EventGen.chance_offer(Run.node_index)
			if ev.is_empty():
				_after_node()
				return
			var a := ScreenChance.new()
			a.setup(ev, Run.node_index)
			a.finished.connect(_after_node)
			_swap(a)
		_:
			_after_node()


func _after_node() -> void:
	if Run.defeated:
		go_end(false)
		return
	if Run.team.is_empty():
		go_end(false)
		return
	if Run.node_index >= Run.total_nodes():
		go_end(true)
		return
	# O SAVE ACONTECE AQUI, no fim do no, e em lugar nenhum mais. E o unico
	# instante em que a run esta em repouso: o combate acabou, o evento acabou,
	# e o proximo par de nos ainda nao foi sorteado. Salvar no meio de uma tela
	# obrigaria a gravar o estado DELA tambem.
	salvar_run()
	next_node()


func go_end(won: bool) -> void:
	Run.victory = won
	# a run acabou: o save deixa de valer. Sem isso a tela de titulo ofereceria
	# "continuar" para uma run morta.
	apagar_save()
	var s := ScreenEnd.new()
	s.setup(won)
	s.restart.connect(go_title)
	_swap(s)


# --- save da run -----------------------------------------------------------
#
# `Run` e um autoload de estado SIMPLES: numeros, ids e uma lista de
# UnitInstance cujos campos tambem sao numeros e ids. Nenhum no, nenhuma cena,
# nenhuma referencia viva. Por isso o save cabe num ConfigFile e o load nao
# precisa de nenhuma ordem especial de reconstrucao.
#
# O que NAO e salvo: o par de nos oferecido (`pair`) e o no escolhido
# (`current_node`). Os dois sao derivados de `seed_value + node_index` por
# `NodeGen.generate_pair`, entao voltam identicos sozinhos. Salvar um dicionario
# gerado seria guardar um cache que pode divergir dos dados na proxima versao.

const SAVE_ARQ := "user://run_save.cfg"
const SAVE_VERSAO := 1


static func tem_save() -> bool:
	if not FileAccess.file_exists(SAVE_ARQ):
		return false
	var f := ConfigFile.new()
	if f.load(SAVE_ARQ) != OK:
		return false
	return int(f.get_value("run", "versao", 0)) == SAVE_VERSAO


## Em que passo a run guardada parou — a tela de titulo mostra isso no botao.
static func save_passo() -> int:
	var f := ConfigFile.new()
	if f.load(SAVE_ARQ) != OK:
		return 0
	return int(f.get_value("run", "node", 0))


static func apagar_save() -> void:
	if FileAccess.file_exists(SAVE_ARQ):
		DirAccess.remove_absolute(SAVE_ARQ)


func salvar_run() -> void:
	var f := ConfigFile.new()
	f.set_value("run", "versao", SAVE_VERSAO)
	f.set_value("run", "seed", Run.seed_value)
	f.set_value("run", "node", Run.node_index)
	f.set_value("run", "ether", Run.ether)
	f.set_value("run", "relics", Run.relics.duplicate())
	f.set_value("run", "actives", Run.actives.duplicate())
	f.set_value("run", "history", Run.history.duplicate(true))
	f.set_value("run", "incubator", Run.incubator_uses)
	f.set_value("run", "reroll", Run.reroll_count)
	var bichos: Array = []
	for u in Run.team:
		bichos.append({
			"sp": u.species_id, "items": u.items.duplicate(),
			"dishes": u.dishes.duplicate(), "copies": u.copies,
			"hp": u.hp_ratio, "el": u.forced_element,
			"muda": u.muda_discount, "gasto": u.spent_ether,
		})
	f.set_value("run", "team", bichos)
	f.save(SAVE_ARQ)


func _continuar_run() -> void:
	if not carregar_run():
		return
	ScreenCombat.esquecer_dica()
	_set_chrome(true)
	next_node()


## Reconstroi `Run` a partir do arquivo. Comeca por `start_run(seed)` de
## proposito: e ele que zera tudo o que NAO esta no save (defeated, victory, os
## contadores) e deixa o RNG na mesma semente. Depois disso a equipe sorteada
## por ele e jogada fora e substituida pela equipe gravada.
func carregar_run() -> bool:
	if not tem_save():
		return false
	var f := ConfigFile.new()
	if f.load(SAVE_ARQ) != OK:
		return false
	Run.start_run(int(f.get_value("run", "seed", 0)))
	Run.team.clear()
	for d in f.get_value("run", "team", []):
		var e: Dictionary = d
		var u := UnitInstance.create(String(e.get("sp", "")))
		u.items = (e.get("items", []) as Array).duplicate()
		u.dishes = (e.get("dishes", []) as Array).duplicate()
		u.copies = int(e.get("copies", 1))
		u.hp_ratio = float(e.get("hp", 1.0))
		u.forced_element = String(e.get("el", ""))
		u.muda_discount = int(e.get("muda", 0))
		u.spent_ether = int(e.get("gasto", 0))
		Run.team.append(u)
	Run.node_index = int(f.get_value("run", "node", 0))
	Run.ether = int(f.get_value("run", "ether", 0))
	Run.relics = (f.get_value("run", "relics", []) as Array).duplicate()
	Run.actives = (f.get_value("run", "actives", []) as Array).duplicate()
	Run.history = (f.get_value("run", "history", []) as Array).duplicate(true)
	Run.incubator_uses = int(f.get_value("run", "incubator", 0))
	Run.reroll_count = int(f.get_value("run", "reroll", 0))
	Run.team_changed.emit()
	Run.resources_changed.emit()
	return true


# --- menu de pausa ---------------------------------------------------------
#
# Ate 15/09 as Configuracoes ficavam TRANCADAS fora da run: o unico caminho
# para elas era a tela de titulo, e dali nao se volta. Quem quisesse baixar o
# volume no meio do ato tinha de perder a run. E nao havia como sair de uma run
# a nao ser morrendo ou fechando o jogo.

func _abrir_pausa() -> void:
	if _pausa != null and is_instance_valid(_pausa):
		return
	_pausar_combate(true)
	var raiz := Control.new()
	raiz.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# STOP e nao IGNORE: o veu existe tambem para o clique nao passar para a
	# tela de baixo. Um menu de pausa que deixa apertar LUTAR atras dele nao e
	# um menu de pausa.
	raiz.mouse_filter = Control.MOUSE_FILTER_STOP
	# 0,94 e nao 0,82: medido no print, com 0,82 a tela de baixo continuava
	# legivel — dois botoes "ESCOLHER" e dois cartoes de combate atras do menu,
	# competindo com ele. Um veu de pausa que deixa ler o que esta atras nao
	# suspende nada; sobram 6% so para a tela nao virar um retangulo preto.
	var veu := ColorRect.new()
	veu.color = Color(UI.BG.r, UI.BG.g, UI.BG.b, 0.94)
	veu.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	raiz.add_child(veu)
	# a força do halo vem da paleta (`sala_forca`), como em toda tela desde
	# 17/09 — não havia por que a pausa ter uma atmosfera com número próprio
	raiz.add_child(UI.luz_de_sala(UI.ACCENT))

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	raiz.add_child(center)
	var col := UI.box(true, 10)
	col.custom_minimum_size = Vector2(420, 0)
	center.add_child(col)
	col.add_child(UI.banner("PAUSA", UI.ACCENT))
	col.add_child(UI.label("Passo %d de %d · semente %d"
		% [Run.node_index, Run.total_nodes(), Run.seed_value],
		UI.F_SMALL, UI.TEXT_DIM, HORIZONTAL_ALIGNMENT_CENTER))
	col.add_child(UI.spacer(8, false))

	var voltar := UI.button_confirmar("  VOLTAR AO JOGO  ", UI.F_H2)
	voltar.pressed.connect(_fechar_pausa)
	col.add_child(voltar)

	var opc := UI.button("  CONFIGURAÇÕES  ", UI.F_H2)
	opc.pressed.connect(_pausa_opcoes)
	col.add_child(opc)

	var sair := UI.button_secundario("  SALVAR E SAIR DA RUN  ", UI.F_H2)
	sair.pressed.connect(_sair_da_run)
	col.add_child(sair)

	_pausa = raiz
	add_child(raiz)


## As Configuracoes vivem DENTRO do veu de pausa, e nao no lugar da tela: sair
## delas devolve o jogador exatamente onde ele estava, que e a diferenca entre
## "abrir as opcoes" e "abandonar a run".
func _pausa_opcoes() -> void:
	if _pausa == null or not is_instance_valid(_pausa):
		return
	for c in _pausa.get_children():
		if c is CenterContainer:
			c.visible = false
	var o := ScreenOptions.new()
	o.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	o.closed.connect(func():
		o.queue_free()
		if _pausa != null and is_instance_valid(_pausa):
			for c in _pausa.get_children():
				if c is CenterContainer:
					c.visible = true)
	_pausa.add_child(o)


func _fechar_pausa() -> void:
	if _pausa != null and is_instance_valid(_pausa):
		_pausa.queue_free()
	_pausa = null
	_pausar_combate(false)


func _sair_da_run() -> void:
	salvar_run()
	_fechar_pausa()
	go_title()


## O combate e a unica tela que anda sozinha; as outras ja estao paradas.
func _pausar_combate(on: bool) -> void:
	if screen != null and is_instance_valid(screen) and screen is ScreenCombat:
		(screen as ScreenCombat).set_pausado(on)


func _unhandled_key_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	if event.keycode == KEY_F11:
		var mode := DisplayServer.window_get_mode()
		var cheia: bool = (mode == DisplayServer.WINDOW_MODE_FULLSCREEN
			or mode == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN)
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED if cheia
			else DisplayServer.WINDOW_MODE_FULLSCREEN)
		# A OUTRA METADE DA SINCRONIA. A tela de Configuracoes ja relia o modo
		# real ao montar, entao deixou de mentir; faltava o F11 escrever o
		# estado de volta. Sem esta linha, fechar o jogo em tela cheia ligada
		# por F11 reabria em janela.
		ScreenOptions.cfg["tela_cheia"] = not cheia
		ScreenOptions.salvar()
		get_viewport().set_input_as_handled()
		return
	if event.keycode == KEY_ESCAPE and chrome_on:
		if _pausa != null and is_instance_valid(_pausa):
			_fechar_pausa()
		else:
			_abrir_pausa()
		get_viewport().set_input_as_handled()
