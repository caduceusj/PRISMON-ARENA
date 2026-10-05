class_name ScreenCombat
extends Control
## GDD 3.2 / 8 -- o loop micro. A simulacao roda headless; esta tela apenas
## a observa e injeta a unica agencia do jogador: os Ativos da Mao do Domador.

signal combat_over(result: Dictionary)

const SPEEDS := [1.0, 2.0, 4.0]

var _node: Dictionary = {}
var sim: CombatSim = null
var field: FieldView
var panel: CombatPanel
var dock: ItemDock
var _energy_label: Label
var _speed_idx := 0   # sobrescrito no _ready pela opcao do jogador

## Mesma largura fixa do HUD: as barras não acompanham a janela.
const BAR_W := 1180.0

## LARGURA RESERVADA DE CADA LADO DA ARENA, e a mesma dos dois lados.
##
## Medido pela revisão: o HBox dava 364 px à esquerda (MarginContainer 18+10
## mais os 336 do CombatPanel) e 102 à direita (10+18 mais os 74 da doca), então
## o centro da elipse nascia em x = 966 contra os 800 do centro da tela — o
## centróide da ação ficava a 310 px do centro do quadro. A câmera do FieldView
## recupera ±37 px antes de a borda da elipse sair do quadro; os outros ~166 px
## eram layout, e nenhum código dentro do FieldView podia corrigi-los.
##
## Com os dois lados reservando a MESMA largura, o meio é o meio por construção
## — é a mesma solução das duas células de 140 px da barra do topo do Main.
const LADO := 364.0

## O RESPIRO VERTICAL das duas colunas laterais. Mesmo valor dos dois lados
## pelo mesmo motivo da largura: o que e simetrico por construcao nao volta
## torto depois de um ajuste.
const MARGEM_V := 14

var _paused := false
var _accum := 0.0
var _hitstop := 0.0
var _aiming := ""
var _prisma_target: SimUnit = null
var _ending := 0.0

## A DICA DE INTERVENÇÃO é dada UMA VEZ POR RUN, e não uma vez por combate:
## ela ensina que o botão existe, e ensinar a mesma coisa nove vezes é ruído.
## `Main` a zera ao começar (ou continuar) uma run.
static var _dica_dada := false
var _dica_t := 0.0

const DICA_S := 7.0

var _time_bar: PrismaBar
var _active_buttons: Array = []
var _speed_btn: Button
var _hint: Label
var _picker: Control = null


func setup(node: Dictionary) -> void:
	_node = node


func _ready() -> void:
	sim = CombatBuilder.build(_node, Run.seed_value * 31 + Run.node_index)
	# velocidade PADRAO das Configuracoes; TAB continua trocando no meio
	_speed_idx = clampi(int(ScreenOptions.get_opt("velocidade")), 0, SPEEDS.size() - 1)

	# A SALA DO COMBATE é a arena. Aqui ela não pinta quase nada — o FieldView
	# cobre o miolo com a arte da arena e as duas barras são opacas —, mas
	# `luz_de_sala` registra `UI.sala`, e é de lá que a sombra dura dos títulos
	# de 36 e 54 px tira a cor. Sem a chamada, os anúncios grandes do campo
	# usariam sombra preta em toda arena.
	add_child(UI.luz_de_sala(_cor_da_sala(), 0.04))

	var col := UI.box(true, 0)
	col.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(col)
	col.add_child(_top_bar())

	# Revisão 31/08: a arena deixa de ocupar a largura inteira. À ESQUERDA a
	# leitura da equipe (vida, ultimate, auras, o que cada um está fazendo);
	# à DIREITA a doca de itens e relíquias. O miolo continua sendo a briga.
	var mid := UI.box(false, 0)
	mid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(mid)

	# O painel fica CENTRADO na vertical, não colado no topo: com duas ou três
	# unidades ele virava um bloco preso no canto superior esquerdo.
	# Centrado na vertical, com respiro à esquerda: colado na borda a ficha
	# parecia cortada pela moldura da janela.
	var left := MarginContainer.new()
	left.add_theme_constant_override("margin_left", 18)
	left.add_theme_constant_override("margin_right", 10)
	# RESPIRO EM CIMA E EMBAIXO (autor, 16/09: "o painel da equipe cresceu para
	# quatro fichas e encosta no topo... a primeira ficha esta CORTADA pela
	# borda de cima").
	#
	# A coluna nao tinha margem vertical nenhuma, entao o CenterContainer podia
	# centrar o painel encostado nas duas barras — e um painel mais alto que a
	# coluna transborda para os DOIS lados de uma vez, que e como a ficha de
	# cima sai cortada. Com a margem, existe folga declarada antes de a conta
	# apertar; e a ficha emagreceu (ver CombatPanel) para que cinco fichas —
	# o teto de Vinculo — caibam com sobra dentro dela.
	left.add_theme_constant_override("margin_top", MARGEM_V)
	left.add_theme_constant_override("margin_bottom", MARGEM_V)
	left.custom_minimum_size = Vector2(LADO, 0)
	left.size_flags_vertical = Control.SIZE_EXPAND_FILL
	mid.add_child(left)
	var left_c := CenterContainer.new()
	left.add_child(left_c)
	panel = CombatPanel.new()
	panel.sim = sim
	left_c.add_child(panel)

	field = FieldView.new()
	field.sim = sim
	field.clicked.connect(_on_field_clicked)
	field.size_flags_vertical = Control.SIZE_EXPAND_FILL
	field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mid.add_child(field)

	# A doca continua ENCOSTADA na borda direita — o que muda é que a coluna
	# dela reserva a mesma largura da coluna da esquerda, e a folga fica entre
	# a arena e a doca em vez de sair do outro lado do quadro.
	var right := MarginContainer.new()
	right.add_theme_constant_override("margin_left", int(LADO - ItemDock.W - 18.0))
	right.add_theme_constant_override("margin_right", 18)
	right.add_theme_constant_override("margin_top", MARGEM_V)
	right.add_theme_constant_override("margin_bottom", MARGEM_V)
	right.custom_minimum_size = Vector2(LADO, 0)
	right.size_flags_vertical = Control.SIZE_EXPAND_FILL
	mid.add_child(right)
	var right_c := CenterContainer.new()
	right.add_child(right_c)
	dock = ItemDock.new()
	right_c.add_child(dock)

	col.add_child(_bottom_bar())
	set_process(true)
	set_process_unhandled_key_input(true)


func _top_bar() -> Control:
	var p := PanelContainer.new()
	var sb := UI.panel(Color("#15121f"), 0, UI.LINE)
	sb.content_margin_top = 10
	sb.content_margin_bottom = 10
	p.add_theme_stylebox_override("panel", sb)
	var center := CenterContainer.new()
	p.add_child(center)
	var v := UI.box(true, 4)
	v.custom_minimum_size = Vector2(BAR_W, 0)
	center.add_child(v)
	var row := UI.box(false, 14)
	v.add_child(row)
	row.add_child(UI.label(String(_node.get("title", "Rinha")), UI.F_H2))
	row.add_child(UI.label(String(_node.get("payload", {}).get("arena", "")), UI.F_SMALL, UI.TEXT_DIM))
	row.add_child(UI.spacer())
	_hint = UI.label("", UI.F_BODY, UI.WARN)
	row.add_child(_hint)

	# O tempo deixou de ser uma barra de ponta a ponta: virou um marcador curto
	# ao lado dos controles. Ele só importa perto do fim.
	# 18 px e a altura NATIVA da textura: 10 achatava o desenho da barra
	_time_bar = UI.bar("red", 18)
	_time_bar.custom_minimum_size = Vector2(190, 18)
	_time_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_time_bar)

	_speed_btn = _sem_foco(UI.button("1×", UI.F_BODY))
	_speed_btn.custom_minimum_size = Vector2(56, 0)
	_speed_btn.pressed.connect(_cycle_speed)
	row.add_child(_speed_btn)
	var pause := _sem_foco(UI.button("⏸", UI.F_BODY))
	pause.custom_minimum_size = Vector2(46, 0)
	pause.pressed.connect(_toggle_pause)
	row.add_child(pause)
	return p


## CLICAR UM BOTÃO COM O MOUSE DESLIGAVA ESPAÇO E TAB.
##
## O foco ia para o botão clicado e ficava lá. A partir daí ESPAÇO virava
## `ui_accept` DENTRO do botão (ele reapertava o próprio botão) e TAB virava
## navegação de foco do viewport — as duas teclas eram consumidas antes de
## chegarem a `_unhandled_key_input`, que é onde pausa e velocidade moram. O
## jogador clicava uma vez em "⏸" e perdia os dois atalhos pelo resto da briga.
##
## FOCUS_NONE é o conserto certo AQUI e não no kit: o combate é a única tela
## cujos atalhos de teclado competem com o foco, e tirar o foco de todo botão do
## jogo mataria a navegação por teclado que as listas ainda vão precisar.
func _sem_foco(b: Button) -> Button:
	b.focus_mode = Control.FOCUS_NONE
	return b


func _bottom_bar() -> Control:
	var p := PanelContainer.new()
	var sb := UI.panel(Color("#15121f"), 0, UI.LINE)
	sb.content_margin_top = 12
	sb.content_margin_bottom = 12
	p.add_theme_stylebox_override("panel", sb)
	# Mesma regra do topo: conteúdo com largura própria, centrado. A barra de
	# Energia atravessando 2544 px de tela não ficava mais legível — só maior.
	var center := CenterContainer.new()
	p.add_child(center)
	var v := UI.box(true, 5)
	v.custom_minimum_size = Vector2(BAR_W, 0)
	center.add_child(v)

	# A barra de Energia atravessando a tela foi RESUMIDA. Ela dizia uma coisa
	# só — "quanto falta para eu poder lançar algo" — e gastava a largura
	# inteira para isso. Agora são duas peças menores e mais úteis: um chip com
	# o número, e uma barrinha DENTRO de cada Ativo mostrando o quanto falta
	# para AQUELE custo. A informação passa a morar onde a decisão acontece.
	var row := UI.box(false, 12)
	v.add_child(row)

	var chip := UI.card(Color("#1b2740"), Color("#3a7fe0").darkened(0.3))
	chip.custom_minimum_size = Vector2(150, 0)
	var crow := UI.box(false, 7)
	crow.alignment = BoxContainer.ALIGNMENT_CENTER
	chip.add_child(crow)
	crow.add_child(Icons.node("g_flask", UI.icon_px(UI.F_H2), Color("#7fb8ff")))
	_energy_label = UI.label("0", UI.F_H2, Color("#9fd0ff"))
	crow.add_child(_energy_label)
	row.add_child(chip)
	_active_buttons.clear()
	for i in range(Run.actives.size()):
		var aid: String = Run.actives[i]
		var a: Dictionary = Db.actives[aid]
		var b := _sem_foco(UI.button("[%d] %s  %d⚡" % [i + 1, String(a["name"]), int(a["cost"])],
			UI.F_BODY, Color(String(a["color"]))))
		# 58, o padrão da casa, e não os 42 de antes. Era a terceira altura de
		# botão do jogo, no controle mais apertado da tela: o único que o jogador
		# aperta no meio de uma briga é o que estava mais baixo que todos.
		b.custom_minimum_size = Vector2(0, UI.BTN_H)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.tooltip_text = String(a["text"])
		b.icon = Icons.tex("act_" + aid)
		b.expand_icon = false
		b.add_theme_constant_override("h_separation", 8)
		b.pressed.connect(_arm.bind(aid))
		# barrinha de progresso colada no rodapé interno do botão: enche até o
		# custo daquele Ativo e some quando ele fica disponível
		var fill := ColorRect.new()
		fill.color = Color(String(a["color"]))
		fill.color.a = 0.5
		fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
		fill.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
		# a largura vem da ANCORA direita, animada em _process conforme a
		# Energia sobe; os offsets ficam todos em zero de proposito
		fill.anchor_right = 0.0
		fill.offset_left = 0.0
		fill.offset_right = 0.0
		fill.offset_top = -4.0
		fill.offset_bottom = 0.0
		b.add_child(fill)
		row.add_child(b)
		# `pronto` nasce TRUE porque `Button.disabled` nasce false: os dois têm de
		# começar de acordo, senão a primeira comparação não dispara a escrita e
		# um Ativo sem Energia apareceria clicável até a Energia mudar.
		_active_buttons.append({"btn": b, "id": aid, "fill": fill,
			"cost": float(a["cost"]), "pronto": true})
	return p


# --- loop ------------------------------------------------------------------

func _process(delta: float) -> void:
	if sim == null:
		return
	if sim.finished:
		field.feed(sim.drain_events())
		_ending += delta
		if _ending > 1.4:
			set_process(false)
			_resolve()
		return

	if _hitstop > 0.0:
		_hitstop -= delta
	elif not _paused:
		_accum += delta * SPEEDS[_speed_idx]
		var guard := 0
		while _accum >= CombatSim.TICK and not sim.finished and guard < 60:
			sim.step()
			_accum -= CombatSim.TICK
			guard += 1

	var evs := sim.drain_events()
	for e in evs:
		var hs := float(e.get("hitstop", 0.0))
		if hs > 0.0:
			# GDD 21.2 -- reacoes amplificadoras param a camera por ~60 ms
			_hitstop = maxf(_hitstop, hs)
	field.feed(evs)

	_time_bar.set_value(sim.now, sim.max_duration)
	_refresh_actives()
	if panel != null:
		panel.refresh()
	_dica_de_intervencao(delta)


## O SUBSTITUTO DA AUTO-PAUSA.
##
## O GDD 21.2 pedia pausar sozinho no primeiro Ativo disponível, para ensinar
## que o jogador PODE intervir. Na prática o jogo parava no meio da briga e
## exigia ESPAÇO para voltar — interrompia justamente o momento em que se quer
## olhar. Foi removido a pedido do autor (31/08), e o corpo desta função virou
## um `pass` que o README continuou anunciando como o onboarding do jogo.
##
## O que entrou no lugar NÃO INTERROMPE NADA: na primeira vez em toda a run em
## que um Ativo fica lançável, a linha de dica que já existe no topo escreve
## "Meteoro pronto — aperte 1" e o botão daquele Ativo pulsa uma vez. O ensino
## acontece no mesmo quadro em que o fato acontece, e a briga continua correndo.
##
## Por que uma vez POR RUN e não por combate: o jogador aprende isto uma vez.
## Repetir em nove combates seguidos transforma a dica em ruído — e ruído numa
## linha que também carrega "Mire no campo — ESC cancela" custa a instrução útil.
func _dica_de_intervencao(delta: float) -> void:
	if _dica_t > 0.0:
		_dica_t -= delta
		if _dica_t <= 0.0 and _aiming == "":
			_hint.text = ""
	if _dica_dada or _aiming != "" or _active_buttons.is_empty():
		return
	for i in range(_active_buttons.size()):
		var a: Dictionary = _active_buttons[i]
		if not sim.can_cast(String(a["id"])):
			continue
		_dica_dada = true
		_dica_t = DICA_S
		var nome := String(Db.actives[String(a["id"])].get("name", "Ativo"))
		_hint.text = "%s pronto — aperte %d" % [nome, i + 1]
		Juice.pulse(a["btn"], 1.12)
		Juice.pulse(_hint, 1.10)
		return


## Zerada por `Main` no começo de cada run.
static func esquecer_dica() -> void:
	_dica_dada = false


## O ESTADO DO BOTÃO SÓ É ESCRITO QUANDO ELE MUDA.
##
## A linha `a["btn"].modulate = ...` rodava 60 vezes por segundo e sobrescrevia
## o tween de hover que vive em `UI.button`/`Juice.make_reactive` — o único
## botão do combate era o único do jogo que não respondia ao mouse. Com a lajota
## nova isso ficaria mais visível ainda, porque o hover deixou de ser só brilho
## e virou a lajota subindo. `disabled` já tem estilo próprio no kit (moldura
## apagada e rótulo em TEXT_DIM escurecido), então o modulate não fazia falta:
## ele fazia estrago.
func _refresh_actives() -> void:
	if _energy_label != null:
		_energy_label.text = str(roundi(sim.energy))
	for a in _active_buttons:
		var can: bool = sim.can_cast(String(a["id"]))
		if bool(a["pronto"]) != can:
			a["pronto"] = can
			a["btn"].disabled = not can
		if a.has("fill"):
			var f: ColorRect = a["fill"]
			var pct: float = clampf(sim.energy / maxf(float(a["cost"]), 1.0), 0.0, 1.0)
			f.anchor_right = 0.0 if can else pct


func _cycle_speed() -> void:
	_speed_idx = (_speed_idx + 1) % SPEEDS.size()
	_speed_btn.text = "%d×" % int(SPEEDS[_speed_idx])


func _toggle_pause() -> void:
	set_pausado(not _paused)


## Ponto único de pausa, para o menu de ESC do `Main` parar a briga sem duplicar
## o estado: quem pausa de fora chama isto.
func set_pausado(v: bool) -> void:
	_paused = v
	if not _paused and _dica_t <= 0.0:
		_hint.text = ""


# --- Ativos ----------------------------------------------------------------

func _arm(active_id: String) -> void:
	if not sim.can_cast(active_id):
		return
	var a: Dictionary = Db.actives[active_id]
	var mode := String(a.get("aim", ""))
	_clear_picker()
	# Decide pela FORMA do modo, não por uma lista de nomes. A lista antiga
	# tratava "enemy_area" e esquecia "ally_area": o Orvalho ficava armado para
	# sempre porque o clique não casava com nenhum caso, e a magia nunca saía.
	# Qualquer modo novo que termine em _area ou comece com all_ passa a
	# funcionar sem tocar aqui.
	if mode.begins_with("all_") or mode == "":
		_cast(active_id, Vector2.ZERO, null, "")
		return
	_aiming = active_id
	field.aim_mode = mode
	field.aim_radius = float(a.get("radius", 0.0))
	field.aim_color = Color(String(a.get("color", "#ffffff")))
	_hint.text = "Mire no campo — ESC cancela"


func _on_field_clicked(local: Vector2) -> void:
	if _aiming == "":
		return
	if aim_at(local):
		accept_event()


## Resolve a mira, seja qual for o modo. É o único ponto do jogo que decide o
## que um clique no campo faz — usado tanto pelo input do jogador quanto pelo
## teste automatizado, então o teste exercita o MESMO caminho que a pessoa.
func aim_at(local: Vector2) -> bool:
	if _aiming == "":
		return false
	var a: Dictionary = Db.actives.get(_aiming, {})
	var mode := String(a.get("aim", ""))
	if mode.ends_with("_area"):
		return _cast(_aiming, field.to_field(local), null, "")
	if mode.ends_with("_pick_element"):
		var u := field.unit_at(local)
		if u == null:
			return false
		_prisma_target = u
		_show_element_picker(local)
		return true
	# modo de alvo único sem escolha extra
	var t := field.unit_at(local)
	if t == null:
		return false
	return _cast(_aiming, t.pos, t, "")


func _cancel_aim() -> void:
	_aiming = ""
	_prisma_target = null
	field.aim_mode = ""
	field.aim_radius = 0.0
	_clear_picker()
	_hint.text = ""


func _cast(active_id: String, aim: Vector2, target: SimUnit, element_pick: String) -> bool:
	if not sim.cast_active(active_id, aim, target, element_pick):
		return false
	_cancel_aim()
	if _paused:
		_toggle_pause()
	return true


func _unhandled_input(event: InputEvent) -> void:
	if sim == null or sim.finished:
		return
	if event is InputEventMouseButton and event.pressed \
			and event.button_index == MOUSE_BUTTON_LEFT and _aiming != "":
		var local: Vector2 = field.get_local_mouse_position()
		if not Rect2(Vector2.ZERO, field.size).has_point(local):
			return
		aim_at(local)
		get_viewport().set_input_as_handled()


func _unhandled_key_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	match event.keycode:
		KEY_SPACE:
			_toggle_pause()
		KEY_TAB:
			_cycle_speed()
		KEY_ESCAPE:
			# ESC SÓ É CONSUMIDO QUANDO HÁ MIRA ARMADA. Fora disso ele segue
			# para o `Main`, que abre o menu de pausa — sem esta guarda o
			# combate era a única tela da run de onde não se podia sair nem
			# alcançar as Configurações.
			if _aiming == "":
				return
			_cancel_aim()
		KEY_1, KEY_2, KEY_3:
			var i: int = event.keycode - KEY_1
			if i < _active_buttons.size():
				_arm(String(_active_buttons[i]["id"]))
		_:
			return  # nao consome: F11 e o resto seguem para o Main
	get_viewport().set_input_as_handled()


## GDD 8.2 -- Prisma de Reescrita: o jogador escolhe o elemento de destino.
func _show_element_picker(at: Vector2) -> void:
	_clear_picker()
	var p := UI.card(UI.PANEL, UI.ACCENT)
	p.position = field.global_position + at + Vector2(-90, 14)
	var v := UI.box(true, 4)
	p.add_child(v)
	v.add_child(UI.label("Reescrever para:", 11, UI.TEXT_DIM))
	var row := UI.box(false, 4)
	v.add_child(row)
	for el in Db.slice_elements:
		var b := _sem_foco(UI.button(Db.el_name(el), UI.F_SMALL, Db.el_color(el)))
		b.pressed.connect(func():
			_cast(_aiming, Vector2.ZERO, _prisma_target, el))
		row.add_child(b)
	_picker = p
	add_child(p)


func _clear_picker() -> void:
	if _picker != null and is_instance_valid(_picker):
		_picker.queue_free()
	_picker = null


# --- fim do combate --------------------------------------------------------

func _cor_da_sala() -> Color:
	var arena: Dictionary = Db.arenas.get(String(_node.get("payload", {}).get("arena", "")), {})
	if arena.is_empty():
		return Color("#7a6a9e")
	return Color(String(arena.get("tint", "#7a6a9e")))


## O LADO DO INIMIGO, medido aqui e não na simulação.
##
## `CombatSim.combat_log()` só monta `units` para o lado 0 — é por isso que o
## log de derrota só tinha o SEU lado, que é exatamente a pergunta de quem
## perdeu. A simulação pertence a outra frente, então a segunda metade da tabela
## é montada onde o `sim` ainda está vivo e inteiro: aqui, uma linha antes de o
## resultado sair da tela. Os campos são os MESMOS nomes do lado do jogador,
## para `ScreenResult` desenhar as duas colunas com uma função só.
func _enemy_units() -> Array:
	var out: Array = []
	if sim == null:
		return out
	for u in sim.units:
		if u.side != 1:
			continue
		out.append({
			"name": u.display_name, "element": u.element, "alive": u.alive,
			"damage": u.dmg_dealt, "taken": u.dmg_taken, "healing": u.healing_done,
			"reactions": u.reactions_caused, "kills": u.kills,
		})
	out.sort_custom(func(a, b): return float(a["damage"]) > float(b["damage"]))
	return out


func _resolve() -> void:
	CombatBuilder.writeback(sim)
	var won: bool = sim.winner == CombatSim.Winner.PLAYER
	var log := sim.combat_log()
	log["enemy_units"] = _enemy_units()
	var gained := {"ether": 0}
	if won:
		var rw: Dictionary = _node.get("rewards", {})
		gained["ether"] = int(rw.get("ether", 0))
		Run.add_ether(int(gained["ether"]))
	else:
		Run.defeated = true
	log["gained"] = gained
	log["won"] = won
	combat_over.emit(log)
