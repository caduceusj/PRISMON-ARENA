class_name CombatSim
extends RefCounted
## GDD 22.3 -- simulacao HEADLESS e DETERMINISTICA do combate.
##
## Nao toca em nenhum no de cena. A camada visual (CombatView) e um OBSERVADOR
## que consome os eventos emitidos aqui. Isso permite:
##   * rodar 10.000 combates em segundos, sem render (tools/batch_sim.gd)
##   * replays por semente, com poucos bytes
##   * fast-forward confiavel em 4x

const TICK := 0.1

enum Winner { NONE, PLAYER, ENEMY, DRAW }

var units: Array = []                 # Array[SimUnit], ordem estavel
var by_id: Dictionary = {}
var now: float = 0.0
var finished := false
var winner: int = Winner.NONE
var end_reason: String = ""

var rng := RandomNumberGenerator.new()
var node_index: int = 1
var max_duration: float = 45.0

var energy: float = 0.0               # Energia do Domador (so o lado do jogador)
var energy_max: float = 100.0

var events: Array = []                # fila consumida pela view
var team_mods: Array = [{}, {}]       # mods agregados por lado

# telemetria do combate (GDD 21.3 / 23.1)
var stat_reactions: Dictionary = {}   # reaction_id -> contagem
var stat_actives: Array = []
var stat_biggest_hit: Dictionary = {}
var stat_total_damage: Array = [0.0, 0.0]

var scheduled: Array = []              # ops agendadas: [{at, src, ops, aim, ...}]
var player_ether: int = 0              # copia da bolsa, para o chefe consumir
var ether_eaten: int = 0
var _boss_timer: float = 0.0
var _next_id := 1
var _amplify_cd: Dictionary = {}      # unit_id -> tempo do proximo Cadinho

# --- arena e modificadores do bando (autor, 03/09) --------------------------
#
# Ate aqui a arena era DECORACAO: o campo "text" de data/enemies.json prometia
# "2 UA de Encharcado a cada 3 s" e o simulador nao fazia nada. Agora ela tem
# efeito, e o bando inimigo pode vir com modificadores que a tela de escolha
# mostra ANTES de o jogador entrar.
var arena_effect: Dictionary = {}     # {op, ...} — ver data/enemies.json
## A ARENA INTEIRA, e nao so o efeito dela. O evento `begin` mandava
## `arena_effect` sob a chave "arena", e a camada visual procurava `tint` ali
## dentro — mas o tint mora no nivel de cima, junto de `id` e `name`. Resultado:
## a tintura de piso pedida em 03/09 nunca chegou a acontecer; toda arena
## desenhava com o cinza padrao. Quem desenha precisa da ficha completa.
var arena: Dictionary = {}            # {id, name, tint, effect, ...}
var enemy_mods: Array = []            # Array[Dictionary] dos modificadores
var _arena_timer: float = 0.0
var _cycle_timer: float = 0.0
var _estimulo_stacks: int = 0

## PROFUNDIDADE DA CADEIA DE REACOES. A Eletrocussao nao consome a aura, e o op
## "chain" chama strike() de volta — ou seja, reacao -> golpe -> reacao e um
## ciclo de verdade. Ele terminava por ACIDENTE: as auras acabavam antes.
## Quando as arenas passaram a encharcar o campo inteiro de forma continua, a
## recursao deixou de ter fim e o autoplay estourou a pilha (1023 quadros).
## Este contador fecha o ciclo por construcao.
var _react_depth: int = 0


## A semente FICA GUARDADA. Ela so existia como parametro do _init, e quem
## precisasse dela depois — a decoracao de piso, por exemplo — nao tinha de onde
## tirar. Guardar custa um int e da determinismo a qualquer coisa que se monte
## por combate.
var semente: int = 0


func _init(seed_value: int = 0) -> void:
	semente = seed_value
	rng.seed = seed_value


# --- construcao ------------------------------------------------------------

func add_unit(u: SimUnit) -> SimUnit:
	u.id = _next_id
	_next_id += 1
	u.hp = u.hp_max
	units.append(u)
	by_id[u.id] = u
	return u


## Chamado depois de adicionar todas as unidades e definir team_mods.
func begin() -> void:
	max_duration = float(team_mods[0].get("combat_duration", Db.combat("max_duration", 45.0)))
	energy_max = Db.combat("energy_max", 100.0)
	# O DOMADOR NAO ENTRA DE MAOS VAZIAS (revisao 15/09, decisao do autor).
	# Medido em 1000 runs: 15% dos combates nao ofereciam UM Ativo sequer (52% no
	# passo 2) e a mediana do primeiro Ativo disponivel era 5,8 s numa briga de
	# 12,6 s — a unica agencia do jogador chegava depois de metade da luta.
	# `energy_start` fecha essa janela sem tocar em hp_scale, que e o botao que
	# move a vitoria em 23 pontos percentuais.
	energy = minf(Db.combat("energy_start", 0.0), energy_max)
	_layout()
	for u in units:
		var m: Dictionary = team_mods[u.side]
		# O teto de UA vem dos dados. O teto que um ITEM impoe (Totem do Excesso)
		# NAO mora aqui: ele vale sobre os ALVOS de quem carrega o item e viaja em
		# `u.unit_aura_cap`. Ate 15/09 o CombatBuilder o escrevia nesta mesma
		# propriedade, e esta linha o apagava antes do primeiro tique.
		u.aura.cap_ua = Db.combat("aura_cap_ua", 8.0)
		u.aura.max_auras = int(Db.combat("max_auras", 2))
		# ESTES DOIS VIAJAM NO APLICADOR, nao no receptor — ver a nota em
		# SimUnit.aplica_cap_override. Escrito em `u.aura`, o Coro de Fogo
		# fazia a Combustao INIMIGA empilhar ate 16 em cima de voce.
		var cf: float = float(m.get("combustao_cap_mult", 1.0))
		if cf != 1.0:
			u.aplica_cap_override["COMBUSTAO"] = u.aura.cap_ua * cf
		var ed: float = float(m.get("encharcado_decay_mult", 1.0))
		if ed != 1.0:
			u.aplica_decay_mult["ENCHARCADO"] = ed
	_marcar_repetidos()
	_aplicar_modificadores()
	_apply_role_movement()
	_emit({"kind": "begin", "duration": max_duration,
		"arena": arena, "efeito": arena_effect, "mods": enemy_mods})


## As unidades se DESLOCAM. O Papel decide como: Guardiao e Lamina fecham
## distancia, Arcano e Curandeiro mantem a sua. A Postura continua decidindo
## QUEM elas atacam (GDD 7.2) -- o Papel decide so o corpo a corpo.
## Os modificadores do bando viram BUFFS permanentes no lado inimigo — a mesma
## maquinaria dos itens e das relíquias, entao nada de caminho paralelo.
func _aplicar_modificadores() -> void:
	for m in enemy_mods:
		var ef: Dictionary = m.get("effect", {})
		if String(ef.get("op", "")) != "team_mod":
			continue
		var stat := String(ef.get("stat", ""))
		var val := float(ef.get("value", 1.0))
		# "10% mais resistentes" e menos dano RECEBIDO; "10% mais dano" e mais
		# ATK. Sao os dois eixos que o resto do jogo ja usa.
		var alvo := "dmg_taken" if stat == "dmg_taken" else "atk"
		for u in units:
			if u.side == 1:
				u.add_buff(alvo, val, 0.0, 9999.0, 0.0, String(m.get("name", "")))


## O que a ARENA faz a cada tique. Tres formas, todas sem dano direto:
##
##   mare_elemental — banha o campo inteiro de uma aura. É lenha para reação:
##       não machuca, mas faz o próximo golpe de outro elemento estourar.
##   estimulo       — todos ficam mais rápidos ou mais fortes, de tempos em
##       tempos. Pressiona quem demora, sem punir com dano.
##   assombrada     — tratada no _kill, não aqui.
func _tick_arena() -> void:
	var op := String(arena_effect.get("op", ""))
	if op == "" or op == "assombrada":
		return
	var cada := float(arena_effect.get("every", 4.0))
	_arena_timer += TICK
	if _arena_timer < cada:
		return
	_arena_timer = 0.0

	if op == "mare_elemental":
		var el := String(arena_effect.get("element", "FOGO"))
		var ua := float(arena_effect.get("ua", 2.0))
		for u in units:
			if u.alive:
				put_aura(null, u, el, ua)
		_emit({"kind": "arena_pulse", "element": el, "op": op})
		return

	if op == "estimulo":
		var teto := int(arena_effect.get("max", 4))
		if _estimulo_stacks >= teto:
			return
		_estimulo_stacks += 1
		var atk := float(arena_effect.get("atk", 0.0))
		var vel := float(arena_effect.get("atk_speed", 0.0))
		for u in units:
			if not u.alive:
				continue
			if atk > 0.0:
				u.add_buff("atk", 1.0 + atk, 0.0, 9999.0, now, "Estímulo")
			if vel > 0.0:
				u.add_buff("atk_speed", 1.0 + vel, 0.0, 9999.0, now, "Estímulo")
		_emit({"kind": "arena_pulse", "op": op, "stacks": _estimulo_stacks})


## Afinidade Instável: o bando troca de elemento de tempos em tempos. É o
## modificador que mais muda a leitura da briga — a reação que funcionava há
## cinco segundos pode não funcionar agora.
func _tick_ciclo_elemento() -> void:
	var cada := 0.0
	for m in enemy_mods:
		var ef: Dictionary = m.get("effect", {})
		if String(ef.get("op", "")) == "element_cycle":
			cada = float(ef.get("every", 5.0))
	if cada <= 0.0:
		return
	_cycle_timer += TICK
	if _cycle_timer < cada:
		return
	_cycle_timer = 0.0
	var els: Array = Db.slice_elements
	for u in units:
		if u.side != 1 or not u.alive:
			continue
		var novo := String(els[rng.randi_range(0, els.size() - 1)])
		if novo == u.element:
			continue
		u.element = novo
		u.resist = SimUnit.resist_for(novo)
		_emit({"kind": "rewrite", "dst": u.id, "element": novo,
			"duration": 0.0, "pos": u.pos})


func _apply_role_movement() -> void:
	var mv: Dictionary = Db.tuning.get("movement", {})
	var roles: Dictionary = mv.get("roles", {})
	for u in units:
		var r: Dictionary = roles.get(u.role, {})
		u.attack_range = float(r.get("range", 60.0))
		u.speed_px = float(r.get("move_speed", 90.0))
		u.kite = float(r.get("kite", 0.0))
		if u.is_boss:
			u.attack_range *= float(mv.get("boss_scale", 1.35))
		u.home = u.pos
		u.facing = 1.0 if u.side == 0 else -1.0


## GDD 7.2 -- posicionamento AUTOMATICO e PREVISIVEL.
## Tres faixas por Postura; dentro da faixa, VEL decrescente; empate pelo id da especie.
## Numera as copias de uma mesma especie DENTRO de cada lado. Uma criatura
## sozinha nao ganha marca — "Apollo II" sem um "Apollo I" na tela seria ruido.
##
## Determinismo: percorre na ordem de `units`, que `_layout` ja deixou estavel
## por id. Sem isso, dois combates com a mesma semente sairiam com as marcas
## trocadas entre si, e o print de regressao acusaria uma diferenca que nao e uma.
## O primeiro TAMBEM leva marca. Deixar o "I" implicito produzia um
## "Pinto-Raio" solto no meio de um "III" e um "IV", que le como falha de
## rotulo e nao como convencao — a marca so aparece quando ha copias, entao
## quem a ve ja sabe que ha mais de um.
const ROMANOS := ["I", "II", "III", "IV", "V", "VI", "VII", "VIII"]


func _marcar_repetidos() -> void:
	for lado in [0, 1]:
		var quantos: Dictionary = {}
		for u in units:
			if u.side == lado:
				quantos[u.species_id] = int(quantos.get(u.species_id, 0)) + 1
		var visto: Dictionary = {}
		for u in units:
			if u.side != lado or int(quantos.get(u.species_id, 0)) < 2:
				continue
			var n: int = int(visto.get(u.species_id, 0))
			visto[u.species_id] = n + 1
			u.marca = ROMANOS[n] if n < ROMANOS.size() else str(n + 1)


func _layout() -> void:
	var gap: float = Db.combat("lane_gap", 150.0)
	var ugap: float = Db.combat("unit_gap", 92.0)
	for side in [0, 1]:
		var mine: Array = units.filter(func(u): return u.side == side)
		for u in mine:
			u.lane = stance_lane(u.stance)
		for lane in [0, 1, 2]:
			var in_lane: Array = mine.filter(func(u): return u.lane == lane)
			in_lane.sort_custom(func(a, b):
				if not is_equal_approx(a.vel, b.vel):
					return a.vel > b.vel
				return a.species_id < b.species_id)
			var n := in_lane.size()
			for i in range(n):
				var u: SimUnit = in_lane[i]
				u.slot = i
				var dir := -1.0 if side == 0 else 1.0
				var x: float = dir * (Db.combat("lane_base", 205.0) + float(lane) * gap)
				var y: float = (float(i) - float(n - 1) * 0.5) * ugap
				u.pos = Vector2(x, y)
	# ordem de iteracao estavel para todo o resto da simulacao
	units.sort_custom(func(a, b):
		if a.side != b.side:
			return a.side < b.side
		if a.lane != b.lane:
			return a.lane < b.lane
		return a.slot < b.slot)


static func stance_lane(stance: String) -> int:
	match stance:
		"Vanguarda": return SimUnit.LANE_VANGUARDA
		"Meio":      return SimUnit.LANE_MEIO
		_:           return SimUnit.LANE_FUNDO


# --- loop principal --------------------------------------------------------

## Avanca exatamente 1 tick. Nunca toca em nos de cena.
func step() -> void:
	if finished:
		return
	now += TICK

	_tick_auras()
	_tick_energy()
	_tick_pending()
	_tick_boss()
	_tick_arena()
	_tick_ciclo_elemento()

	for u in units:
		if not u.alive:
			continue
		if u.control_until > 0.0 and u.control_until <= now:
			u.control_until = 0.0
			u.control_kind = ""
		u.expire_buffs(now)
		u.retarget_cd -= TICK
		if u.taunt_until <= now:
			u.taunted_by = -1

	_tick_movement()

	for u in units:
		if not u.alive or not u.can_act(now):
			continue
		u.attack_cd -= TICK
		# fora de alcance a unidade nao ataca -- ela ANDA. O cooldown fica
		# guardado, entao ela golpeia no instante em que chega.
		if u.attack_cd <= 0.0 and _can_act_now(u):
			_unit_act(u)

	_check_end()


func run_to_end(max_ticks: int = 2000) -> int:
	var t := 0
	while not finished and t < max_ticks:
		step()
		t += 1
	if not finished:
		_finish(Winner.DRAW, "limite de ticks")
	return winner


func alive_units(side: int) -> Array:
	# FANTASMA nao conta: ele age, mas nao segura o combate de pe nem serve de
	# alvo. Sem esta excecao a Arena Assombrada travaria toda briga em empate.
	return units.filter(func(u): return u.alive and not u.ghost and u.side == side)


func _check_end() -> void:
	var p := alive_units(0).size()
	var e := alive_units(1).size()
	if p == 0 and e == 0:
		_finish(Winner.ENEMY, "aniquilacao mutua")
	elif e == 0:
		_finish(Winner.PLAYER, "inimigos eliminados")
	elif p == 0:
		_finish(Winner.ENEMY, "equipe eliminada")
	elif now >= max_duration:
		# GDD 7.3 -- estouro: vence quem tem maior % de HP total. Empate exato = derrota.
		var hp_p := _team_hp_pct(0)
		var hp_e := _team_hp_pct(1)
		if hp_p > hp_e:
			_finish(Winner.PLAYER, "tempo esgotado (%d%% x %d%%)" % [roundi(hp_p * 100), roundi(hp_e * 100)])
		else:
			_finish(Winner.ENEMY, "tempo esgotado (%d%% x %d%%)" % [roundi(hp_p * 100), roundi(hp_e * 100)])


func _team_hp_pct(side: int) -> float:
	var cur := 0.0
	var total := 0.0
	for u in units:
		if u.side != side:
			continue
		total += u.hp_max
		cur += maxf(u.hp, 0.0)
	return cur / maxf(total, 1.0)


func _finish(w: int, reason: String) -> void:
	finished = true
	winner = w
	end_reason = reason
	_emit({"kind": "end", "winner": w, "reason": reason})


func _emit(ev: Dictionary) -> void:
	ev["t"] = now
	events.append(ev)


# --- auras, passivas e energia --------------------------------------------

func _tick_auras() -> void:
	for u in units:
		if not u.alive:
			continue
		for a in u.aura.auras.duplicate():
			match a.aura_id:
				"COMBUSTAO":
					# GDD 4.1 -- Combustao: 4 dano/s
					_deal(null, u, float(Db.el("FOGO").get("passive_value", 4.0)) * TICK,
						"elemental", "FOGO", false, true)
				"ESPORO":
					# GDD 4.1 -- Esporo comeca fraco e dobra; o dobro vem mais
					# rapido com Eco de Natureza DE QUEM APLICOU a aura.
					var base_dps: float = float(Db.el("NATUREZA").get("passive_value", 2.0))
					var dt: float = float(team_mods[1 - u.side].get("esporo_double_time", 3.0))
					var mult: float = minf(pow(2.0, floorf(a.age / maxf(dt, 0.5))), 5.0)
					_deal(null, u, base_dps * mult * TICK, "elemental", "NATUREZA", false, true)
				"CARGA":
					# GDD 4.1 -- Carga: a cada 4 stacks, 15 de dano
					var step_ua: float = float(Db.el("RAIO").get("passive_step", 4.0))
					while a.ua - a.charge_paid >= step_ua:
						a.charge_paid += step_ua
						_deal(null, u, float(Db.el("RAIO").get("passive_value", 15.0)),
							"elemental", "RAIO", false, true)
		u.aura.tick(TICK)
		for a in u.aura.auras:
			if a.aura_id == "CARGA":
				a.charge_paid = minf(a.charge_paid, a.ua)


func _tick_energy() -> void:
	var mult: float = float(team_mods[0].get("energy_mult", 1.0))
	energy = minf(energy + Db.combat("energy_per_second", 2.0) * mult * TICK, energy_max)


func _tick_pending() -> void:
	if scheduled.is_empty():
		return
	for p in scheduled.duplicate():
		if p["at"] > now:
			continue
		scheduled.erase(p)
		var src: SimUnit = p.get("src")
		if src != null and not src.alive:
			continue
		AbilityRunner.run(self, src, p["ops"], p.get("aim", Vector2.ZERO),
			p.get("react_target"), String(p.get("element_pick", "")))


## Agenda ops para um instante futuro (usado por op "repeat" e por efeitos temporarios).
func schedule(at: float, src: SimUnit, ops: Array, aim: Vector2 = Vector2.ZERO,
		react_target: SimUnit = null, element_pick: String = "") -> void:
	scheduled.append({"at": at, "src": src, "ops": ops, "aim": aim,
		"react_target": react_target, "element_pick": element_pick})


## Dano verdadeiro: ignora DEF, Resistencia Elemental e escudo elemental.
func deal_true(src: SimUnit, dst: SimUnit, amount: float) -> void:
	_deal(src, dst, amount, "true", "", false, false)


func gain_energy(amount: float) -> void:
	var mult: float = float(team_mods[0].get("energy_mult", 1.0))
	energy = minf(energy + amount * mult, energy_max)


# --- acao da unidade -------------------------------------------------------

func _unit_act(u: SimUnit) -> void:
	var gelido: float = _gelido_slow(u.side)
	u.attack_cd = u.attack_interval(gelido)

	# GDD 7.3 -- ao encher a Energia, a ultimate dispara na proxima acao.
	if u.ult_energy >= Db.combat("ultimate_max", 100.0) and not u.ult.is_empty():
		u.ult_energy = 0.0
		_emit({"kind": "ult", "src": u.id, "name": String(u.ult.get("name", "")),
			"pos": u.pos, "element": u.element})
		AbilityRunner.run(self, u, u.ult.get("ops", []), Vector2.ZERO)
		return

	# GDD 7.2 -- Suporte nao escolhe alvo inimigo: age sobre aliados.
	# Decisao de prototipo: se ninguem precisa de cura, ele ataca (registrado em NOTAS.md).
	if u.stance == "Suporte":
		var hurt := _most_hurt_ally(u.side)
		if hurt != null and hurt.hp_pct() < float(Db.tune("combat", "support_heal_threshold", 0.9)):
			# A cura de Suporte escala com ATK, e o HP escala com hp_scale — ver
			# combat._support_heal_doc. `support_heal_scale` fecha essa distancia.
			var amount: float = u.eff_atk() * (1.0 + u.eff_pe() / Db.combat("heal_pe_divisor", 150.0)) \
				* Db.combat("support_heal_scale", 1.0)
			heal(u, hurt, amount)
			return

	var target := pick_target(u)
	if target == null:
		return
	# O golpe tem WINDUP: a animacao de ataque toca esticada sobre o intervalo
	# inteiro, e o dano conecta exatamente quando o QUADRO DE DANO do sprite
	# aparece (quadro 13 do Apollo, 11 do Coalla... — data/anims.json). A
	# simulacao continua deterministica: o windup e agendado na fila.
	var interval: float = u.attack_interval(gelido)
	var frac: float = _hit_fraction(u)
	if frac <= 0.0:
		_basic_attack(u, target)
		return
	u.windup_until = now + interval * frac
	_emit({"kind": "attack", "src": u.id, "dst": target.id, "interval": interval,
		"windup": interval * frac, "pos": u.pos})
	schedule(u.windup_until, u, [{"op": "basic_attack"}], Vector2.ZERO, target)


## Fracao do intervalo em que o golpe conecta, vinda do sheet da especie.
func _hit_fraction(u: SimUnit) -> float:
	var c: Dictionary = Db.anims.get("creatures", {}).get(u.species_id, {})
	if c.is_empty() and u.is_boss:
		c = Db.anims.get("creatures", {}).get(String(Db.boss.get("sprite", "")), {})
	return float(c.get("hit_fraction", 0.0))


## O golpe basico de fato — chamado no instante do quadro de dano.
func _basic_attack(u: SimUnit, target: SimUnit) -> void:
	if not u.alive or u.is_controlled(now):
		return
	u.windup_until = -1.0
	# o alvo pode ter morrido durante o windup: redireciona se houver alguem
	# ao alcance; senao o golpe corta o ar
	if target == null or not target.alive:
		target = pick_target(u)
		if target == null:
			return
	if u.pos.distance_to(target.pos) > u.attack_range * 1.6:
		return
	_emit({"kind": "swing", "src": u.id, "dst": target.id, "from": u.pos,
		"to": target.pos, "ranged": u.kite > 0.0, "element": u.element})
	strike(u, target, {
		"element": u.element,
		"ua": u.applied_ua(float(team_mods[u.side].get("team_ua_add", 0.0))),
		"mult": 1.0,
	})
	u.ult_energy = minf(u.ult_energy + Db.combat("ultimate_per_attack", 10.0)
		* u.stat_mult("ult_gain") * u.unit_ult_gain * _team_ult_gain(u.side),
		Db.combat("ultimate_max", 100.0))

	# Correnteza: aliados aplicam uma aura extra alem da propria.
	var extra: float = u.stat_sum("extra_aura")
	if extra > 0.0:
		var extra_el := ""
		for b in u.buffs:
			if b["stat"] == "extra_aura":
				extra_el = String(b.get("element", ""))
				break
		if extra_el != "" and extra_el != u.element and target.alive:
			apply_element(u, target, extra_el, extra, 0.0)


## Alvo ATUAL. E pegajoso: reavaliar a cada tick faria as unidades trocarem de
## alvo no meio do passo e o combate viraria um formigueiro ilegivel.
func pick_target(u: SimUnit) -> SimUnit:
	var cur: SimUnit = by_id.get(u.target_id)
	if cur != null and cur.alive and cur.side != u.side and u.retarget_cd > 0.0:
		return cur
	var fresh := choose_target(u)
	if fresh != null:
		u.target_id = fresh.id
		u.retarget_cd = float(Db.tuning.get("movement", {}).get("retarget_interval", 0.5))
	return fresh


## GDD 7.2 -- comportamento de alvo por Postura. Deterministico, sem RNG.
func choose_target(u: SimUnit) -> SimUnit:
	var foes := alive_units(1 - u.side)
	if foes.is_empty():
		return null
	if u.taunted_by >= 0 and u.taunt_until > now:
		var t: SimUnit = by_id.get(u.taunted_by)
		if t != null and t.alive:
			return t
	match u.stance:
		"Vanguarda":
			# ataca o inimigo mais proximo
			var best: SimUnit = foes[0]
			var bd: float = u.pos.distance_squared_to(best.pos)
			for f in foes:
				var d: float = u.pos.distance_squared_to(f.pos)
				if d < bd or (is_equal_approx(d, bd) and f.id < best.id):
					best = f
					bd = d
			return best
		"Meio":
			# ataca o inimigo com mais UA acumulada (prioriza gatilhar reacoes)
			var best2: SimUnit = foes[0]
			for f in foes:
				var a: float = f.aura.total_ua()
				var b: float = best2.aura.total_ua()
				if a > b or (is_equal_approx(a, b) and f.id < best2.id):
					best2 = f
			return best2
		_:
			# Retaguarda / Suporte em modo ofensivo: finaliza o de menor HP %
			var best3: SimUnit = foes[0]
			for f in foes:
				if f.hp_pct() < best3.hp_pct() or (is_equal_approx(f.hp_pct(), best3.hp_pct()) and f.id < best3.id):
					best3 = f
			return best3


func _most_hurt_ally(side: int) -> SimUnit:
	var best: SimUnit = null
	for u in alive_units(side):
		if best == null or u.hp_pct() < best.hp_pct():
			best = u
	return best


## DIAPASAO VIVO: "+10% de carga de ultimate para o RESTO da equipe". O item mora
## numa unidade, mas o efeito e de equipe — CombatBuilder agrega os `team_ult_gain`
## dos itens dentro de team_mods[0], junto de reliquias e ressonancias. Ate 15/09
## a chave existia no JSON e ninguem a lia.
func _team_ult_gain(side: int) -> float:
	return float(team_mods[side].get("team_ult_gain", 1.0))


func _gelido_slow(side: int) -> float:
	# a lentidao vem da RESSONANCIA DE GELO DE QUEM APLICOU; no prototipo usamos
	# o mod do lado oposto ao portador (quem aplicou a aura).
	var base: float = float(Db.el("GELO").get("passive_value", 0.20))
	return base + float(team_mods[1 - side].get("gelido_slow_add", 0.0))


# --- golpe, reacao e dano --------------------------------------------------

## Todo dano com elemento passa por aqui. E o unico lugar onde uma reacao nasce.
func strike(src: SimUnit, dst: SimUnit, p: Dictionary) -> void:
	if dst == null or not dst.alive:
		return
	var element: String = String(p.get("element", ""))
	# A MAO DO DOMADOR TEM LADO (revisao 15/09). `cast_active` roda com
	# `source = null`, e todo o combate descobria o time do golpe por `src.side`:
	# com src nulo o Ativo do jogador era a unica coisa do jogo que nao recebia
	# reliquia, ressonancia nem PE. O Domador joga pelo lado 0.
	var mods: Dictionary = team_mods[src.side if src != null else 0]

	# 1) dano bruto do golpe
	var dmg := 0.0
	var dmg_type := "elemental"
	if src != null:
		var m: float = float(p.get("mult", 0.0))
		if m > 0.0:
			# GDD 17.3 -- DANO FISICO = ATK * (1 - DEF/(DEF+100))
			dmg += src.eff_atk() * m * (1.0 - dst.eff_def() / (dst.eff_def() + 100.0))
			dmg_type = "physical"
		var em: float = float(p.get("elem_mult", 0.0))
		if em > 0.0:
			# GDD 17.3 -- DANO ELEMENTAL = ATK * 0.6 * (1 - ResistElem)
			dmg += src.eff_atk() * Db.combat("elemental_damage_scale", 0.6) * em \
				* (1.0 - dst.resist_to(element))
	dmg += float(p.get("flat", 0.0)) * (1.0 - dst.resist_to(element))

	# 2) bonus condicionais declarados no dado da ultimate
	var ba: String = String(p.get("bonus_if_aura", ""))
	if ba != "" and dst.aura.has_aura(ba):
		dmg *= float(p.get("bonus_mult", 1.0))
	var bc: String = String(p.get("bonus_if_control", ""))
	if bc != "" and dst.control_kind == bc and dst.control_until > now:
		dmg *= float(p.get("control_mult", 1.0))

	# 3) critico e os Coros (Gelo e Natureza)
	var crit := false
	var crit_chance: float = Db.combat("crit_base", 0.0) + float(mods.get("crit_add", 0.0))
	if crit_chance > 0.0 and rng.randf() < crit_chance:
		crit = true
		dmg *= Db.combat("crit_multiplier", 1.5)
	# medido ANTES da reacao, que e quando a aura gatilho ainda esta no alvo
	var vs_aura: float = _dmg_vs_auras(mods, dst)
	dmg *= vs_aura

	# 4) reacao (GDD 6) -- decide ANTES de aplicar a aura do golpe
	var ua: float = float(p.get("ua", 0.0))
	if element == "RAIO":
		ua *= float(mods.get("carga_ua_mult", 1.0))
	var res := _resolve_reaction(src, dst, element)

	if res.happened() and res.kind == ReactionResolver.Kind.AMPLIFY:
		dmg *= res.damage_mult

	# 5) dano principal
	if dmg > 0.0:
		_deal(src, dst, dmg, dmg_type, element, crit, false)
		var ls: float = float(p.get("lifesteal", 0.0))
		if ls > 0.0 and src != null:
			heal(src, src, dmg * ls)

	# 6) consequencias da reacao, ou aplicacao da aura
	if res.happened():
		_apply_reaction(src, dst, res, p, vs_aura)
	elif ua > 0.0 and element != "":
		put_aura(src, dst, element, ua)


func apply_element(src: SimUnit, dst: SimUnit, element: String, ua: float, dmg: float) -> void:
	strike(src, dst, {"element": element, "ua": ua, "flat": dmg})


## CORO DE GELO / CORO DE NATUREZA -- "inimigos com <aura> recebem +15% de dano".
##
## A chave e montada por concatenacao (`dmg_vs_gelido`, `dmg_vs_esporo`), o que
## explica por que um grep pelo nome inteiro devolvia zero ocorrencia e os dois
## Coros pareciam mortos. Eles estavam MEIO vivos: o bonus entrava so no dano do
## GOLPE, e o golpe e a menor parte do dano de uma equipe de reacao — 36,1
## reacoes por combate medidas. Agora ele multiplica tambem o dano
## TRANSFORMATIVO da reacao, que e onde o topo do eixo de build prometia estar.
##
## De proposito NAO entra em `ctx.reaction_bonus`: a reacao AMPLIFICADORA
## multiplica o proprio dano do golpe, que ja recebeu este fator aqui — somar
## nos dois lugares cobraria o Coro duas vezes no mesmo numero.
func _dmg_vs_auras(mods: Dictionary, dst: SimUnit) -> float:
	var m := 1.0
	for held in dst.aura.auras:
		m *= 1.0 + float(mods.get("dmg_vs_" + String(held.aura_id).to_lower(), 0.0))
	return m


## PE DE REFERENCIA DA MAO DO DOMADOR (revisao 15/09).
##
## A curva de PE do GDD 6.1 vale ate 2x no dano de reacao, e com `src == null` o
## Ativo do jogador entrava com PE 0 — a unica fonte de reacao do jogo que nao
## escalava com a propria equipe. O Domador nao tem ficha, entao ele toma
## emprestada a da equipe VIVA. A formula e dado, nao codigo: `active_pe_mode`
## escolhe media ou soma e `active_pe_mult` calibra.
func _pe_de_referencia() -> float:
	var vivos := alive_units(0)
	if vivos.is_empty():
		return 0.0
	var soma := 0.0
	for u in vivos:
		soma += u.eff_pe()
	var modo := String(Db.tune("combat", "active_pe_mode", "media"))
	var base: float = soma if modo == "soma" else soma / float(vivos.size())
	return base * Db.combat("active_pe_mult", 1.0)


func _resolve_reaction(src: SimUnit, dst: SimUnit, element: String) -> ReactionResolver.Result:
	if element == "" or dst.aura.auras.is_empty():
		return ReactionResolver.Result.new()
	var mods: Dictionary = team_mods[src.side if src != null else 0]
	var ctx := ReactionResolver.Ctx.new()
	ctx.node_index = node_index
	ctx.attacker_pe = src.eff_pe() if src != null else _pe_de_referencia()
	ctx.reaction_bonus = float(mods.get("reaction_dmg_add", 0.0)) \
		+ (src.unit_reaction_bonus if src != null else 0.0)
	ctx.target_resist = dst.resist_to(element)
	ctx.reverse_full_mult = bool(mods.get("reverse_full_mult", false))
	ctx.pe_soft_cap = Db.combat("pe_soft_cap", 120.0)
	ctx.base_a = Db.combat("reaction_base_a", 30.0)
	ctx.base_b = Db.combat("reaction_base_b", 14.0)
	ctx.resist_cap = Db.combat("resist_cap", 0.75)
	ctx.target_control_immune = dst.control_immune_until > now or dst.control_until > now
	# Reliquia Cadinho: amplificadoras nao consomem a aura (com recarga por alvo)
	var cd: float = float(mods.get("amplify_keeps_aura_cd", 0.0))
	if cd > 0.0 and float(_amplify_cd.get(dst.id, -999.0)) <= now:
		ctx.amplify_keeps_aura = true
	var res := ReactionResolver.resolve(dst.aura, element, ctx)
	# SINERGIA DE ITEM, NO FUNIL UNICO (16/09). O bonus era aplicado la em
	# `_apply_reaction`, que roda DEPOIS de `dmg *= res.damage_mult` em
	# strike — e so mexia em `reaction_damage`, que e zero numa AMPLIFY.
	# Resultado: Lente de Forja (Derretimento) e Chave de Vapor (Vaporizar),
	# os dois itens do jogo que nomeiam uma reacao amplificadora, nao
	# mudavam numero nenhum — foi o que o bloco [cobertura de dados] do
	# smoke_test acusou. Aqui alcanca os dois campos e roda uma vez so.
	if src != null and res.happened() and not src.rx_dmg_add.is_empty():
		var b: float = float(src.rx_dmg_add.get(res.id(), 0.0))
		if b > 0.0:
			res.damage_mult *= 1.0 + b
			res.reaction_damage *= 1.0 + b
	return res


func _apply_reaction(src: SimUnit, dst: SimUnit, res: ReactionResolver.Result, p: Dictionary,
		vs_aura: float = 1.0) -> void:
	var rule := res.rule
	var mods: Dictionary = team_mods[src.side if src != null else 0]

	if res.kind == ReactionResolver.Kind.AMPLIFY and res.consume_ua == 0.0:
		_amplify_cd[dst.id] = now + float(mods.get("amplify_keeps_aura_cd", 0.0))
	if res.consume_ua < 0.0:
		dst.aura.consume_all(res.trigger_aura)
	elif res.consume_ua > 0.0:
		dst.aura.consume(res.trigger_aura, res.consume_ua)

	# ATORDOAMENTO DE ITEM (revisão 31/08). Vale só para UMA reação nomeada —
	# é o que faz o item valer muito numa build e nada em outra. Tem recarga
	# própria por unidade e por reação, então não vira controle permanente
	# numa equipe que reage o tempo todo. O BÔNUS DE DANO irmão dele mudou de
	# lugar em 16/09: foi para `_resolve_reaction`, porque aqui ele já chegava
	# depois de o multiplicador da AMPLIFY ter sido consumido.
	if src != null and src.rx_stun.has(res.id()) and not dst.control_immune_until > now:
		var cfg: Dictionary = src.rx_stun[res.id()]
		var ready: float = float(src.rx_stun_ready.get(res.id(), -999.0))
		if ready <= now and dst.control_until <= now:
			src.rx_stun_ready[res.id()] = now + float(cfg.get("cooldown", 6.0))
			apply_control(dst, "stun", float(cfg.get("duration", 1.0)),
				Db.combat("control_immunity", 5.0))

	stat_reactions[res.id()] = int(stat_reactions.get(res.id(), 0)) + 1
	if src != null:
		src.reactions_caused += 1
	# PORTAO DE ENERGIA POR REACAO. Exigia `src != null`, entao a reacao causada
	# por um Ativo nao devolvia nada — apesar de a Catalisacao se chamar, no
	# proprio texto de reactions.json, "o motor dos Ativos". Um Ativo e do lado 0
	# por construcao: Chuva Torrencial (35) passa a pagar parte do Meteoro (40).
	if src == null or src.side == 0:
		gain_energy(Db.combat("energy_per_reaction", 1.0))

	# `radius` vai no evento porque a simulacao JA usa esse raio para causar dano
	# em area logo abaixo — quem desenha a faixa de reacao precisa do mesmo numero
	# para nao inventar um circulo de outro tamanho.
	_emit({"kind": "reaction", "id": res.id(), "name": res.name(),
		"color": String(rule.get("color", "#ffffff")), "src": src.id if src else 0,
		"dst": dst.id, "pos": dst.pos, "flash": float(rule.get("screen_flash", 0.3)),
		"hitstop": float(rule.get("hitstop", 0.0)), "damage": res.reaction_damage,
		"radius": float(rule.get("radius", 0.0)),
		"class": res.kind, "direction": res.direction})

	# dano transformativo (independente do golpe), com area opcional
	if res.kind == ReactionResolver.Kind.TRANSFORM and res.reaction_damage > 0.0:
		var radius: float = float(rule.get("radius", 0.0))
		var dano: float = res.reaction_damage * vs_aura
		_deal(src, dst, dano, "reaction", res.damage_element, false, false)
		if radius > 0.0:
			for other in alive_units(dst.side):
				if other.id != dst.id and other.pos.distance_to(dst.pos) <= radius:
					_deal(src, other, dano, "reaction", res.damage_element, false, false)

	# efeitos declarados em on_react (controle, debuff, cadeia, empurrao).
	# O TETO fecha a recursao: sem ele, uma cadeia num campo encharcado nao
	# tem fim (ver _react_depth).
	if not res.ops.is_empty():
		var teto: int = int(Db.combat("max_reaction_chain", 3))
		if _react_depth < teto:
			_react_depth += 1
			AbilityRunner.run(self, src, res.ops, dst.pos, dst)
			_react_depth -= 1

	# Lente Fratal / Totem do Ricochete: chance de uma SEGUNDA reacao valida
	var chance: float = float(mods.get("second_reaction_chance", 0.0))
	if src != null:
		chance += src.unit_double_reaction
	if chance > 0.0 and rng.randf() < chance:
		var second := _resolve_reaction(src, dst, res.hit_element)
		if second.happened() and second.trigger_aura != res.trigger_aura:
			# o fator dos Coros e recalculado: a primeira reacao ja pode ter
			# consumido a aura que o dava
			_apply_reaction(src, dst, second, p, _dmg_vs_auras(mods, dst))


func put_aura(src: SimUnit, dst: SimUnit, element: String, ua: float) -> void:
	var e := Db.el(element)
	var aura_id: String = String(e.get("aura_id", ""))
	if aura_id == "" or ua <= 0.0:
		return
	# O SINAL ESTAVA INVERTIDO (revisao 15/09). "Auras aplicadas por esta unidade
	# decaem 50% mais devagar" (Totem da Persistencia; 60% no Sifao das Mares) era
	# escrito em `aura.decay_mult` DO PORTADOR — ou seja, os dois itens faziam as
	# auras do INIMIGO durarem mais em cima de quem os equipava. O multiplicador
	# pertence a QUEM APLICA, e por isso viaja em `src`.
	var decay: float = float(e.get("decay", 1.0))
	var teto_extra := 0.0
	if src != null:
		decay *= src.unit_aura_decay_mult
		# ressonancia por aura (Eco de Agua em ENCHARCADO)
		decay *= float(src.aplica_decay_mult.get(aura_id, 1.0))
		# Totem do Excesso: "teto de UA sobe de 8 para 12 NOS ALVOS desta
		# unidade". O teto e de quem aplica, nao de quem recebe.
		teto_extra = maxf(src.unit_aura_cap,
			# ressonancia por aura (Coro de Fogo em COMBUSTAO)
			float(src.aplica_cap_override.get(aura_id, 0.0)))
	var added := dst.aura.apply(aura_id, element, ua, decay, src.id if src else 0, teto_extra)
	if added > 0.0:
		var cur := dst.aura.get_aura(aura_id)
		_emit({"kind": "aura", "dst": dst.id, "aura": aura_id, "element": element,
			"ua": added, "total": cur.ua if cur else 0.0, "pos": dst.pos})

	# CORACAO INSTAVEL, o lado ruim: "suas unidades tambem recebem auras dos
	# inimigos". A reliquia dava +30% de dano de reacao e cobrava nada. Agora a
	# aura que a sua unidade joga no inimigo respinga nela — o que arma reacao
	# para o outro lado tambem. A chamada de volta usa `src = null`, e e isso que
	# fecha a recursao.
	if src != null and dst.side != src.side:
		var back: float = float(team_mods[src.side].get("enemy_aura_backlash", 0.0))
		if back > 0.0:
			put_aura(null, src, element, ua * back)


## Ponto unico de aplicacao de dano. `ambient` = dano de aura/ambiente (nao reflete).
func _deal(src: SimUnit, dst: SimUnit, amount: float, dtype: String,
		element: String, crit: bool, ambient: bool) -> void:
	if dst == null or not dst.alive or dst.ghost or amount <= 0.0:
		return
	# FANTASMA aplica aura mas NÃO machuca: é o que o autor pediu — "ainda
	# podem ajudar inserindo sinergias, porém sem dar dano nos ataques".
	if src != null and src.ghost:
		return
	amount *= dst.stat_mult("dmg_taken")

	# COLEIRA COMPARTILHADA pelo PONTO UNICO DE DANO (revisao 15/09).
	#
	# Era `m.hp -= each` cru: nao matava, nao passava por escudo, nao emitia
	# evento, nao entrava na telemetria — e deixava aliado com HP NEGATIVO ainda
	# vivo, o que envenenava `enemy_lowest_hp` e `_most_hurt_ally` (um alvo com
	# hp_pct() negativo vence qualquer comparacao de "mais ferido" para sempre).
	# `dtype == "shared"` fecha a recursao entre duas Coleiras na mesma equipe.
	if dst.share_damage > 0.0 and dtype != "shared":
		var shared: float = amount * dst.share_damage
		amount -= shared
		var mates := alive_units(dst.side).filter(func(u): return u.id != dst.id)
		if mates.is_empty():
			# ULTIMO VIVO: sem para quem dividir, o dano VOLTA. Descartar aqui
			# transformava a Coleira em reducao pura de dano exatamente na hora
			# mais critica da briga.
			amount += shared
		else:
			var each: float = shared / float(mates.size())
			for m in mates:
				_deal(dst, m, each, "shared", "", false, true)

	if dst.shield > 0.0:
		var absorbed: float = minf(dst.shield, amount)
		dst.shield -= absorbed
		amount -= absorbed
	dst.hp -= amount
	dst.dmg_taken += amount
	stat_total_damage[1 - dst.side] += amount
	if src != null:
		src.dmg_dealt += amount
		if amount > float(stat_biggest_hit.get("amount", 0.0)):
			stat_biggest_hit = {"amount": amount, "src": src.display_name,
				"dst": dst.display_name, "type": dtype}

	if not ambient:
		# GDD 7.3 -- +5 de Energia de ultimate por golpe recebido
		dst.ult_energy = minf(dst.ult_energy + Db.combat("ultimate_per_hit_taken", 5.0)
			* dst.stat_mult("ult_gain") * dst.unit_ult_gain * _team_ult_gain(dst.side),
			Db.combat("ultimate_max", 100.0))
		var refl: float = dst.stat_sum("reflect")
		if refl > 0.0 and src != null and src.alive:
			var back: float = amount * refl
			_deal(dst, src, back, "elemental", "RAIO", false, true)
			var rua: float = dst.stat_sum("reflect_ua")
			if rua > 0.0:
				put_aura(dst, src, "RAIO", rua)
			var chain: int = int(dst.stat_sum("reflect_chain"))
			if chain > 0:
				var others := alive_units(src.side).filter(func(u): return u.id != src.id)
				for i in range(mini(chain, others.size())):
					_deal(dst, others[i], back * 0.5, "elemental", "RAIO", false, true)

	_emit({"kind": "damage", "src": src.id if src else 0, "dst": dst.id,
		"amount": amount, "type": dtype, "element": element, "crit": crit, "pos": dst.pos})

	if dst.hp <= 0.0:
		_kill(dst, src)


func _kill(u: SimUnit, killer: SimUnit) -> void:
	if not u.alive or u.ghost:
		return
	# ARENA ASSOMBRADA: quem cai vira FANTASMA. Continua em campo aplicando
	# aura — ou seja, ainda arma reação para os vivos — mas não causa dano e
	# não conta como vivo (ver alive_units). Uma equipe derrubada não vence
	# sozinha; ela continua ajudando quem sobrou.
	if String(arena_effect.get("op", "")) == "assombrada":
		u.ghost = true
		u.hp = 1.0
		u.shield = 0.0
		u.aura.clear()
		_emit({"kind": "ghost", "id": u.id, "pos": u.pos, "name": u.display_name})
		if u.side == 0:
			gain_energy(Db.combat("energy_per_ally_death", 5.0))
		_check_end()
		return
	u.alive = false
	u.hp = 0.0
	u.aura.clear()
	_emit({"kind": "death", "id": u.id, "pos": u.pos, "name": u.display_name})
	if u.side == 0:
		# GDD 8.1 -- "mecanica de consolo": derrotas alimentam intervencao
		gain_energy(Db.combat("energy_per_ally_death", 5.0))
	if killer != null and killer.alive:
		killer.kills += 1
		# Passo do Trovao: cada abate reseta a ultimate
		if killer.has_buff("reset_ult_on_kill"):
			killer.ult_energy = Db.combat("ultimate_max", 100.0)
			for b in killer.buffs:
				if b["stat"] == "reset_ult_on_kill":
					b["value"] = float(b["value"]) - 1.0
					if b["value"] <= 0.0:
						killer.buffs.erase(b)
					break


## FADIGA DE CURA (revisão 04/09). A cura perde força conforme a briga se
## arrasta.
##
## Sem ela o impasse tinha uma forma só: `Arcano/Curandeiro × Curandeiro` era o
## empate mais comum do jogo — um curandeiro que cura mais do que apanha nunca
## morre, e o combate acaba no relógio. Nenhum ajuste de dano resolve isso; o
## que resolve é a cura deixar de acompanhar.
##
## Só morde DEPOIS de `heal_falloff_from`: a cura no começo da briga continua
## valendo tudo, que é quando ela é decisão e não teimosia.
func _fadiga_de_cura() -> float:
	var t0: float = Db.combat("heal_falloff_from", 18.0)
	if now <= t0:
		return 1.0
	var taxa: float = Db.combat("heal_falloff_rate", 0.045)
	return maxf(1.0 - (now - t0) * taxa, Db.combat("heal_falloff_floor", 0.15))


func heal(src: SimUnit, dst: SimUnit, amount: float) -> void:
	if dst == null or not dst.alive or amount <= 0.0:
		return
	amount *= dst.stat_mult("healing")
	if src != null:
		amount *= src.unit_healing_out
	amount *= _fadiga_de_cura()
	if amount <= 0.0:
		return
	var before := dst.hp
	dst.hp = minf(dst.hp + amount, dst.hp_max)
	var real := dst.hp - before
	if src != null:
		src.healing_done += real
	if real > 0.0:
		_emit({"kind": "heal", "dst": dst.id, "amount": real, "pos": dst.pos})


func give_shield(dst: SimUnit, amount: float) -> void:
	if dst == null or not dst.alive or amount <= 0.0:
		return
	dst.shield += amount
	_emit({"kind": "shield", "dst": dst.id, "amount": amount, "pos": dst.pos})


## GDD 7.4 -- Vontade reduz a duracao do Controle e concede imunidade depois.
func apply_control(dst: SimUnit, kind: String, duration: float, immunity: float) -> void:
	if dst == null or not dst.alive:
		return
	if dst.control_immune_until > now:
		_emit({"kind": "control_immune", "dst": dst.id, "pos": dst.pos})
		return
	var real: float = duration * (1.0 - dst.vontade / Db.combat("will_control_divisor", 150.0))
	if real <= 0.0:
		return
	dst.control_kind = kind
	dst.control_until = now + real
	dst.control_immune_until = now + real + immunity
	# TODO CONTROLE DURAVA O DOBRO (corrigido em 15/09). `attack_cd` so anda
	# dentro do laco guardado por `can_act`, e `can_act` e `alive and not
	# is_controlled` — ou seja, o cooldown JA fica congelado durante o controle.
	# A linha que havia aqui (`dst.attack_cd = maxf(dst.attack_cd, real)`)
	# empilhava uma segunda espera por cima da primeira: congelar de 1,5 s
	# custava 3,0 s de inacao, e atordoar de 1 s custava 2 s. Nenhum dado dizia
	# isso, e ele contaminava toda medida de Gelo e de item de atordoamento.
	_emit({"kind": "control", "dst": dst.id, "control": kind, "duration": real, "pos": dst.pos})


# --- A Mao do Domador (GDD 8) ---------------------------------------------

func can_cast(active_id: String) -> bool:
	var a: Dictionary = Db.actives.get(active_id, {})
	if a.is_empty() or finished or energy < float(a.get("cost", 0.0)):
		return false
	return true


## Lanca um Ativo. `aim` e a posicao no campo; `target` so para mira de alvo unico.
func cast_active(active_id: String, aim: Vector2, target: SimUnit = null,
		element_pick: String = "") -> bool:
	if not can_cast(active_id):
		return false
	var a: Dictionary = Db.actives[active_id]
	energy -= float(a.get("cost", 0.0))
	stat_actives.append(String(a.get("name", active_id)))
	_emit({"kind": "active", "id": active_id, "name": String(a.get("name", "")),
		"pos": aim, "color": String(a.get("color", "#ffffff")),
		"radius": float(a.get("radius", 0.0))})
	AbilityRunner.run(self, null, a.get("ops", []), aim, target, element_pick)
	return true


## GDD 8.2 -- Prisma de Reescrita. Funciona em inimigos E em aliados.
func rewrite_affinity(u: SimUnit, element_id: String, duration: float) -> void:
	if u == null or not u.alive or element_id == "":
		return
	u.element = element_id
	# "Tambem muda sua Resistencia Elemental" (texto do Prisma em actives.json).
	# Ate 15/09 a linha escrevia 0.0 e a frase era falsa em qualquer direcao.
	u.resist = SimUnit.resist_for(element_id)
	schedule(now + duration, u, [{"op": "restore_affinity"}])
	_emit({"kind": "rewrite", "dst": u.id, "element": element_id,
		"duration": duration, "pos": u.pos})


func restore_affinity(u: SimUnit) -> void:
	if u == null:
		return
	u.element = u.base_element
	_emit({"kind": "rewrite", "dst": u.id, "element": u.base_element,
		"duration": 0.0, "pos": u.pos})


# --- log pos-combate (GDD 21.3) -------------------------------------------

func combat_log() -> Dictionary:
	var per_unit: Array = []
	for u in units:
		if u.side != 0:
			continue
		per_unit.append({
			"name": u.display_name, "element": u.element, "alive": u.alive,
			"damage": u.dmg_dealt, "taken": u.dmg_taken, "healing": u.healing_done,
			"reactions": u.reactions_caused, "kills": u.kills,
		})
	per_unit.sort_custom(func(a, b): return a["damage"] > b["damage"])

	# "Aviso": a unidade que menos contribuiu -- transforma derrota em licao.
	var warn := ""
	var total: float = maxf(stat_total_damage[0], 1.0)
	if per_unit.size() >= 2:
		var worst: Dictionary = per_unit[per_unit.size() - 1]
		var share: float = float(worst["damage"]) / total
		if share < 0.08 and float(worst["healing"]) < total * 0.05:
			warn = "! %s causou %d%% do dano total" % [worst["name"], roundi(share * 100.0)]

	var rx: Array = []
	for k in stat_reactions.keys():
		rx.append({"id": k, "name": String(Db.reactions.get(k, {}).get("name", k)),
			"count": int(stat_reactions[k]),
			"color": String(Db.reactions.get(k, {}).get("color", "#ffffff"))})
	rx.sort_custom(func(a, b): return a["count"] > b["count"])

	return {
		"winner": winner, "reason": end_reason, "duration": now,
		"reactions": rx, "total_reactions": _sum_reactions(),
		"biggest_hit": stat_biggest_hit, "actives": stat_actives,
		"units": per_unit, "warning": warn,
		"damage_dealt": stat_total_damage[0], "damage_taken": stat_total_damage[1],
	}


func _sum_reactions() -> int:
	var t := 0
	for k in stat_reactions.keys():
		t += int(stat_reactions[k])
	return t


func drain_events() -> Array:
	var e := events
	events = []
	return e


## GDD 16.2 -- CHEFE I "Fome Insaciavel": come Ingredientes; se zerar, ganha ATK.
## Fica dentro da simulacao (e nao na UI) para o lote de balanceamento ver o efeito.
func _tick_boss() -> void:
	var boss: SimUnit = null
	for u in units:
		if u.is_boss and u.alive:
			boss = u
			break
	if boss == null:
		return
	var traits: Array = Db.boss.get("traits", [])
	if traits.is_empty():
		return
	var t: Dictionary = traits[0]
	_boss_timer += TICK
	if _boss_timer < float(t.get("interval", 8.0)):
		return
	_boss_timer = 0.0
	var want: int = int(t.get("ether", 12))
	var got: int = mini(want, player_ether - ether_eaten)
	ether_eaten += maxi(got, 0)
	var left: int = player_ether - ether_eaten
	_emit({"kind": "boss_hunger", "eaten": maxi(got, 0), "left": left,
		"name": String(t.get("name", "Fome")), "pos": boss.pos})
	if left <= 0 and not boss.has_buff("boss_rage"):
		boss.add_buff("atk", 1.0 + float(t.get("atk_bonus_when_empty", 0.5)), 0.0,
			9999.0, now, "Faminto")
		boss.add_buff("boss_rage", 1.0, 1.0, 9999.0, now, "")
		_emit({"kind": "boss_rage", "dst": boss.id, "pos": boss.pos})


# --- deslocamento na arena ------------------------------------------------
#
# GDD 7.1/7.2 -- o jogador continua SEM posicionar ninguem: a formacao inicial
# e automatica (tres faixas por Postura) e o deslocamento e automatico tambem.
# O que o movimento acrescenta e legibilidade e consequencia: Laminas mergulham
# na retaguarda, Guardioes se encontram no meio, Arcanos mantem distancia --
# e area (Meteoro, Detonacao) passa a depender de como o campo se aglomerou.

## Pode agir agora? Ultimates e cura de Suporte acontecem onde a unidade estiver;
## um golpe normal exige o alvo dentro do alcance.
func _can_act_now(u: SimUnit) -> bool:
	if u.ult_energy >= Db.combat("ultimate_max", 100.0) and not u.ult.is_empty():
		return true
	if u.stance == "Suporte":
		var hurt := _most_hurt_ally(u.side)
		if hurt != null and hurt.hp_pct() < float(Db.tune("combat", "support_heal_threshold", 0.9)):
			return true
	var t := pick_target(u)
	# 10% de folga: sem ela, a separacao de corpos pode segurar a unidade a
	# 1-2px alem do alcance para sempre (deadlock separacao x alcance)
	return t != null and u.pos.distance_to(t.pos) <= u.attack_range * 1.1


func _move_slow(side: int) -> float:
	var mv: Dictionary = Db.tuning.get("movement", {})
	return float(mv.get("gelido_move_slow", 0.0)) \
		+ float(team_mods[1 - side].get("gelido_move_slow", 0.0))


func _tick_movement() -> void:
	var mv: Dictionary = Db.tuning.get("movement", {})
	var slack: float = float(mv.get("arrive_slack", 10.0))
	for u in units:
		if not u.alive or u.is_controlled(now):
			continue
		if u.windup_until > now:
			continue    # plantada: armando o golpe
		var desired: Vector2 = _desired_position(u)
		var to: Vector2 = desired - u.pos
		var d: float = to.length()
		if d > slack:
			var step_len: float = u.eff_speed(_move_slow(u.side)) * TICK
			u.pos += to / d * minf(step_len, d)
		var t: SimUnit = by_id.get(u.target_id)
		if t != null and t.alive and not is_equal_approx(t.pos.x, u.pos.x):
			u.facing = signf(t.pos.x - u.pos.x)
	_separate(mv)
	_leash_to_target(mv)
	_clamp_arena(mv)


func _desired_position(u: SimUnit) -> Vector2:
	# Suporte fica perto de quem precisa de cura, e longe da briga.
	if u.stance == "Suporte":
		var ally := _most_hurt_ally(u.side)
		var anchor: Vector2 = ally.pos if ally != null else u.home
		var foe := _nearest_enemy(u)
		if foe == null:
			return anchor
		var away: Vector2 = anchor - foe.pos
		if away.length() < 1.0:
			away = Vector2(-1.0 if u.side == 0 else 1.0, 0.0)
		return foe.pos + away.normalized() * maxf(u.kite, 1.0)

	var t := pick_target(u)
	if t == null:
		return u.home
	# A direcao de aproximacao vem da CASA da unidade, nao da posicao atual.
	# Sem isso, todo mundo que mira o mesmo alvo converge no mesmo vetor e o
	# campo vira uma bola. Com isso, cada uma chega pelo seu lado -- o leque
	# se abre sozinho e a formacao continua legivel durante a briga.
	var approach: Vector2 = u.home - t.pos
	if approach.length() < 1.0:
		approach = Vector2(-1.0 if u.side == 0 else 1.0, 0.0)
	var melee_hold: float = float(Db.tuning.get("movement", {}).get("melee_hold", 0.9))
	var hold: float = u.kite if u.kite > 0.0 else u.attack_range * melee_hold
	return t.pos + approach.normalized() * hold


func _nearest_enemy(u: SimUnit) -> SimUnit:
	var best: SimUnit = null
	var bd := INF
	for f in alive_units(1 - u.side):
		var d: float = u.pos.distance_squared_to(f.pos)
		if d < bd:
			bd = d
			best = f
	return best


## Empurrao suave para ninguem se sobrepor. O(n^2) com n <= 16: irrelevante.
func _separate(mv: Dictionary) -> void:
	var radius: float = float(mv.get("separation_radius", 46.0))
	var push: float = float(mv.get("separation_push", 150.0)) * TICK
	var clinch: float = float(mv.get("separation_clinch_scale", 0.3))
	# ZONA MORTA NO CLINCH (revisão 04/09). Medido: 83% do tempo em que uma
	# criatura de corpo a corpo JA estava dentro do alcance, ela continuava se
	# mexendo — 32% dela a mais de metade da velocidade. Com só 2 trocas de alvo
	# por combate não era perseguição: a separação afastava, a coleira puxava de
	# volta, e nenhuma das duas terminava. A escala de clinch (0.3) diminuía o
	# empurrão sem nunca zerá-lo, então a oscilação seguia, mais devagar.
	#
	# `separation_settle` é a fração do raio ACIMA da qual duas criaturas que já
	# podem bater param de se empurrar. 1.0 = nunca para (como era antes).
	var settle: float = float(mv.get("separation_settle", 1.0))
	var live: Array = units.filter(func(x): return x.alive)
	for i in range(live.size()):
		for j in range(i + 1, live.size()):
			var a: SimUnit = live[i]
			var b: SimUnit = live[j]
			var delta: Vector2 = b.pos - a.pos
			var d: float = delta.length()
			if d >= radius or d < 0.001:
				# empatados no mesmo pixel: desempata pelo id, sem RNG
				if d < 0.001:
					var bias := Vector2(0.0, 1.0 if b.id > a.id else -1.0)
					a.pos -= bias * push
					b.pos += bias * push
				continue
			# os dois ja podem bater e nao estao encavalados: nada a corrigir
			if d >= radius * settle and _in_reach(a) and _in_reach(b):
				continue
			var n: Vector2 = delta / d
			var overlap: float = (radius - d) * 0.5
			var amount: float = minf(overlap, push)
			# Quem ja esta encaixado no alvo leva um empurrao menor: o clinch
			# para de tremer e o golpe sai.
			if not a.is_controlled(now):
				a.pos -= n * amount * (clinch if _in_reach(a) else 1.0)
			if not b.is_controlled(now):
				b.pos += n * amount * (clinch if _in_reach(b) else 1.0)


func _in_reach(u: SimUnit) -> bool:
	var t: SimUnit = by_id.get(u.target_id)
	if t == null or not t.alive:
		return false
	return u.pos.distance_to(t.pos) <= u.attack_range


## A MASCARA entre os corpos (revisao 31/08, bug reportado pelo autor: "os
## bichos se barram e nunca chegam no alcance"). Os corpos continuam se
## afastando para nao virar sopa, mas nenhum empurrao pode tirar uma unidade
## do alcance do seu alvo: depois de separar, quem passou do ponto e puxado de
## volta para a borda de dentro do proprio alcance. Determinístico, sem RNG.
func _leash_to_target(mv: Dictionary) -> void:
	var reach_pct: float = float(mv.get("leash_reach", 0.9))
	for u in units:
		if not u.alive or u.is_controlled(now):
			continue
		var t: SimUnit = by_id.get(u.target_id)
		if t == null or not t.alive:
			continue
		# Arcano mantem distancia de proposito: a trava so o segura no alcance,
		# nunca o puxa para dentro do kite.
		var reach: float = u.attack_range * reach_pct
		if u.kite > 0.0:
			reach = maxf(reach, minf(u.kite, u.attack_range * 0.98))
		var delta: Vector2 = u.pos - t.pos
		var d: float = delta.length()
		if d <= reach:
			continue
		if d < 0.001:
			continue
		u.pos = t.pos + delta / d * reach


## A arena e uma ELIPSE (revisao 31/08, pedido do autor: "troque a arena para
## ser algo mais circular"). Prender num retangulo deixava quatro cantos que a
## briga nunca usava e que o desenho tinha de fingir que existiam; a elipse
## empurra a briga para o meio, que e onde a camera olha.
func _clamp_arena(mv: Dictionary) -> void:
	var hw: float = float(mv.get("arena_half_width", 620.0))
	var hh: float = float(mv.get("arena_half_height", 285.0))
	for u in units:
		var nx: float = u.pos.x / hw
		var ny: float = u.pos.y / hh
		var d: float = sqrt(nx * nx + ny * ny)
		if d > 1.0:
			u.pos = Vector2(nx / d * hw, ny / d * hh)
