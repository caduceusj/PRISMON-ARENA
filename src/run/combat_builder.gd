class_name CombatBuilder
extends RefCounted
## Achata o estado da run (UnitInstance + Reliquias + Ressonancias) para dentro
## de uma CombatSim headless. E a unica ponte entre a camada de run e a de sim.


static func build(node: Dictionary, seed_value: int) -> CombatSim:
	var sim := CombatSim.new(seed_value)
	sim.node_index = Run.node_index
	sim.player_ether = Run.ether

	var mods := Run.mods()
	sim.team_mods[0] = _player_mods(mods,
		bool(Dictionary(node.get("payload", {})).get("boss", false)))

	# DIAPASAO VIVO: "+10% de carga de ultimate para o resto da equipe". A chave
	# `team_ult_gain` e de ITEM, e `Run.mods()` so junta ressonancia e reliquia —
	# por isso ninguem a lia. Ela e agregada aqui, onde item e equipe se encontram.
	var team_ult := 1.0
	for u in Run.team:
		team_ult *= float(u.item_mods()["team_ult_gain"])
	if not is_equal_approx(team_ult, 1.0):
		sim.team_mods[0]["team_ult_gain"] = team_ult

	for u in Run.team:
		sim.add_unit(_sim_unit_from(u, mods))

	var payload: Dictionary = node.get("payload", {})
	# ARENA E MODIFICADORES (autor, 03/09). Ate aqui a arena so tinha nome:
	# o campo "text" dela prometia efeitos que o simulador nunca executou.
	var ar: Dictionary = Db.arenas.get(String(payload.get("arena", "")), {})
	sim.arena = ar
	sim.arena_effect = ar.get("effect", {})
	for mid in payload.get("mods", []):
		for m in Db.modifiers:
			if String(m["id"]) == String(mid):
				sim.enemy_mods.append(m)
	if bool(payload.get("boss", false)):
		EnemyGen.build_boss(sim)
	else:
		var theme := _theme(String(payload.get("theme", "")))
		EnemyGen.build(sim, theme, int(payload.get("count", 3)),
			int(payload.get("enemy_seed", 1)), float(payload.get("power", 1.0)))

	sim.team_mods[1] = _enemy_mods(sim)
	sim.begin()
	return sim


static func _theme(id: String) -> Dictionary:
	for t in Db.themes:
		if String(t.get("id", "")) == id:
			return t
	return Db.themes[0] if not Db.themes.is_empty() else {}


## O TETO DE TEMPO DO CHEFE E OUTRO (revisão 04/09).
##
## Os 45 s existem para uma briga de passagem não arrastar. O chefe tem várias
## vezes a ficha de uma criatura comum, e com o teto de todo mundo a luta dele
## quase sempre batia no relógio — e estourar não é empate: vence quem está com
## mais % de HP, que com o HP do Devorador é sempre ele. O jogador perdia para
## um cronômetro sem nunca ver o chefe cair.
##
## Medido: com o teto comum, os estouros do jogo inteiro pulavam de 5% para 11%,
## e praticamente todo o excedente eram brigas de chefe.
static func _player_mods(mods: Dictionary, chefe: bool = false) -> Dictionary:
	var out := mods.duplicate()
	# a Ampulheta Quebrada encurta o combate para os DOIS lados
	if not out.has("combat_duration"):
		out["combat_duration"] = Db.combat(
			"boss_duration" if chefe else "max_duration", 45.0)
	return out


## Inimigos tambem tem Ressonancia -- a composicao deles importa (GDD 14.5.4).
static func _enemy_mods(sim: CombatSim) -> Dictionary:
	var weight: Dictionary = {}
	for u in sim.units:
		if u.side != 1:
			continue
		weight[u.element] = int(weight.get(u.element, 0)) + (2 if u.evolved else 1)
	var th: Dictionary = Db.resonance_thresholds
	var out: Dictionary = {}
	for r in Db.resonances:
		var count: int = int(weight.get(String(r["element"]), 0))
		if count >= int(th.get(String(r["tier"]), 99)):
			for k in r.get("mods", {}).keys():
				var v: float = float(r["mods"][k])
				match String(k):
					"encharcado_decay_mult", "carga_ua_mult", "combustao_cap_mult":
						out[k] = float(out.get(k, 1.0)) * v
					_:
						out[k] = float(out.get(k, 0.0)) + v
	return out


static func _sim_unit_from(inst: UnitInstance, mods: Dictionary) -> SimUnit:
	var st := inst.stats()
	var u := SimUnit.new()
	u.side = 0
	u.source_uid = inst.uid
	u.species_id = inst.species_id
	u.display_name = inst.display_name()
	u.element = inst.element()
	u.base_element = u.element
	u.role = inst.role()
	u.stance = inst.stance()
	u.evolved = inst.is_evolved()
	u.hp_max = float(st["hp"]) * float(mods.get("team_hp_mult", 1.0)) * Db.combat("hp_scale", 1.0)
	u.atk = float(st["atk"])
	u.def = float(st["def"])
	u.vel = float(st["vel"])
	u.pe = float(st["pe"])
	u.vontade = float(st["vontade"])
	u.ua_per_hit = float(st["ua_per_hit"])
	u.ult = inst.ult()
	# RESISTENCIA ELEMENTAL (revisao 15/09). A formula do GDD 17.3 existia inteira
	# no simulador e nunca recebia um numero: `u.resist` nascia vazio e so era
	# reescrito com 0.0. Agora a Afinidade ATUAL resiste ao proprio elemento — e e
	# isso que torna verdadeira a ultima frase do Prisma de Reescrita ("Tambem
	# muda sua Resistencia Elemental") e o pilar "elemento e estado, nao tipo".
	u.resist = SimUnit.resist_for(u.element)

	var im := inst.item_mods()
	u.unit_reaction_bonus = float(im["reaction_bonus"])
	u.unit_ult_gain = float(im["ult_gain"])
	u.unit_healing_out = float(im["healing_out"])
	u.rx_dmg_add = im["rx_dmg_add"]
	u.rx_stun = im["rx_stun"]
	u.unit_double_reaction = float(im["double_reaction"])
	u.share_damage = float(im["share_damage"])
	# Os dois campos abaixo valem sobre os ALVOS desta unidade, nao sobre ela.
	# Ate 15/09 eram escritos em `u.aura`, o que (a) era apagado por
	# CombatSim.begin no caso do teto e (b) invertia o sinal no caso do
	# decaimento — os dois Totens faziam a aura do INIMIGO durar mais.
	u.unit_aura_cap = float(im["aura_cap"])
	u.unit_aura_decay_mult = float(im["aura_decay_mult"])
	# BICO PARA-RAIO: "+2 UA por golpe". `unit_ua_add` era somado em
	# UnitInstance.item_mods e nunca chegava aqui — o item de assinatura do
	# Pinto-Raio valia so a metade que o texto promete.
	u.ua_per_hit = maxf(u.ua_per_hit + float(im["ua_add"]), 0.0)

	u.hp_max = maxf(u.hp_max, 1.0)
	# Sem piso de 5%: quem voltou nocauteado entra com 1 de HP mesmo. O piso
	# antigo curava de graça quem tinha caído.
	u.hp = maxf(u.hp_max * clampf(inst.hp_ratio, 0.0, 1.0), 1.0)
	return u


## Depois do combate, devolve o HP restante para a run (persiste entre nos).
static func writeback(sim: CombatSim) -> void:
	for su in sim.units:
		if su.side != 0:
			continue
		var inst := Run.find_by_uid(su.source_uid)
		if inst != null:
			inst.hp_ratio = clampf(su.hp / maxf(su.hp_max, 1.0), 0.0, 1.0)
	# GDD 16.2 -- o que O Devorador comeu sai da BOLSA da run. Era a despensa;
	# com moeda unica ele passa a morder o mesmo Eter que compra item e comida,
	# o que torna a Fome uma ameaca que o jogador de fato sente.
	if sim.ether_eaten > 0:
		Run.spend_ether(sim.ether_eaten)
