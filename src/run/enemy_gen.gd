class_name EnemyGen
extends RefCounted
## GDD 16.1 -- faccao Selvagens: espelham o bestiario do jogador.
## A composicao e deterministica por semente, para que o card do no (GDD 14.2)
## mostre exatamente o time que vai aparecer -- sem nevoa de guerra.


## Lista de species_id que compoem o time. Mesma semente => mesma lista.
static func compose(theme: Dictionary, count: int, seed_value: int, power: float) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var els: Array = theme.get("elements", ["FOGO"])
	var pool: Array = Db.base_species.filter(func(s): return els.has(String(Db.sp(s).get("element", ""))))
	if pool.is_empty():
		pool = Db.base_species.duplicate()
	pool.sort()

	var out: Array = []
	# garante um Guardiao na Vanguarda e um Arcano no Meio: times legiveis
	var guard: Array = pool.filter(func(s): return String(Db.sp(s).get("role", "")) == "Guardiao")
	var arc: Array = pool.filter(func(s): return String(Db.sp(s).get("role", "")) == "Arcano")
	if not guard.is_empty():
		out.append(guard[rng.randi_range(0, guard.size() - 1)])
	if not arc.is_empty() and out.size() < count:
		out.append(arc[rng.randi_range(0, arc.size() - 1)])
	# Teto de unidades SEM DANO (Guardiao + Curandeiro). Tanque nao mata tanque
	# em 45 s, e curandeiro alonga qualquer impasse: um time pequeno com dois
	# nao-dano e um timeout garantido. O teto escala com o tamanho do time.
	var passive_cap: int = 1 if count <= 3 else 2
	var passives := 0
	for chosen in out:
		if String(Db.sp(chosen).get("role", "")) in ["Guardiao", "Curandeiro"]:
			passives += 1
	var attempts := 0
	while out.size() < count and attempts < 60:
		attempts += 1
		var pick: String = pool[rng.randi_range(0, pool.size() - 1)]
		if String(Db.sp(pick).get("role", "")) in ["Guardiao", "Curandeiro"]:
			if passives >= passive_cap:
				continue
			passives += 1
		out.append(pick)
	while out.size() < count:
		out.append(arc[rng.randi_range(0, arc.size() - 1)] if not arc.is_empty() 			else pool[rng.randi_range(0, pool.size() - 1)])

	# a partir de certo indice de poder, parte do time ja vem evoluida
	var evolved_slots: int = 0
	if power >= 1.20:
		evolved_slots = 1
	if power >= 1.40:
		evolved_slots = 2
	for i in range(mini(evolved_slots, out.size())):
		var nxt := String(Db.sp(out[i]).get("evolves_to", ""))
		if nxt != "":
			out[i] = nxt
	return out


## Texto do card do no: "2x Faulha  1x Brasilho" (GDD 14.2).
static func preview(theme: Dictionary, count: int, seed_value: int) -> String:
	var power: float = NodeGen.power_for(Run.node_index + 1)
	var ids := compose(theme, count, seed_value, power)
	var tally: Dictionary = {}
	for id in ids:
		tally[id] = int(tally.get(id, 0)) + 1
	var parts: Array = []
	for id in tally.keys():
		parts.append("%d× %s" % [int(tally[id]), Db.sp_name(String(id))])
	return "  ".join(parts)


## Monta as SimUnit inimigas dentro do sim.
static func build(sim: CombatSim, theme: Dictionary, count: int, seed_value: int,
		power: float) -> void:
	for id in compose(theme, count, seed_value, power):
		sim.add_unit(_unit_from(id, power))


static func _unit_from(species_id: String, power: float) -> SimUnit:
	var s := Db.sp(species_id)
	var base := Db.sp(Db.sp_base_id(species_id))
	var evolved := bool(s.get("evolved", false))
	var mult: float = float(Db.tuning.get("evolution", {}).get("stat_mult", 2.2)) if evolved else 1.0

	var u := SimUnit.new()
	u.side = 1
	u.species_id = species_id
	u.display_name = String(s.get("name", species_id))
	u.element = String(base.get("element", "FOGO"))
	u.base_element = u.element
	u.role = String(base.get("role", "Guardiao"))
	u.stance = String(base.get("stance", "Vanguarda"))
	u.evolved = evolved
	u.hp_max = float(base.get("hp", 300)) * mult * power * Db.combat("hp_scale", 1.0)
	u.atk = float(base.get("atk", 20)) * mult * power
	u.def = float(base.get("def", 10)) * mult * power
	u.vel = float(base.get("vel", 1.0))
	u.pe = float(base.get("pe", 0)) * mult * power
	u.vontade = float(base.get("vontade", 0))
	u.ua_per_hit = float(base.get("ua_per_hit", 2.0))
	u.ult = s.get("ult", {})
	# a Afinidade resiste ao proprio elemento, dos dois lados (ver CombatBuilder)
	u.resist = SimUnit.resist_for(u.element)
	return u


## GDD 16.2 -- CHEFE I: O Devorador (testa economia).
static func build_boss(sim: CombatSim) -> SimUnit:
	var b: Dictionary = Db.boss
	var u := SimUnit.new()
	u.side = 1
	u.is_boss = true
	u.species_id = String(b.get("id", "devorador"))
	u.display_name = String(b.get("name", "Chefe"))
	u.element = String(b.get("element", "FOGO"))
	u.base_element = u.element
	u.role = String(b.get("role", "Guardiao"))
	u.stance = String(b.get("stance", "Vanguarda"))
	# O CHEFE ESCALA COMO TODO MUNDO (revisão 04/09).
	#
	# Ele não escalava por nada: `build_boss` lia a ficha de enemies.json e
	# pronto, enquanto `difficulty.boss_power` só era consultado por
	# `NodeGen.power_for` — que o nó do chefe nem usa. Resultado medido: mexer
	# em boss_power de 2.1 para 3.2 não alterava UM dígito do autoplay, e o
	# Devorador matava 1 run em 500. Havia três botões e nenhum ligado.
	#
	# Agora o multiplicador chega, com a MESMA fórmula de `_unit_from`: a ficha
	# em enemies.json é a identidade dele, `boss_power` é a dificuldade.
	# COMO O MULTIPLICADOR SE REPARTE. Medido: jogar `power` inteiro no HP faz
	# TODA briga de chefe bater no teto de 45 s — os estouros pularam de 5% para
	# 11% e a vitória mal se mexeu. Um chefe com HP demais não é difícil, é
	# comprido. O perigo tem de vir do GOLPE: ATK sobe cheio, HP acompanha pela
	# raiz, e a defesa (já 52 contra os 10-20 de uma criatura comum) não sobe.
	var power: float = float(Db.tuning.get("difficulty", {}).get("boss_power", 2.1))
	u.hp_max = float(b.get("hp", 4500)) * sqrt(maxf(power, 0.01)) * Db.combat("hp_scale", 1.0)
	u.atk = float(b.get("atk", 46)) * power
	u.def = float(b.get("def", 50))
	u.vel = float(b.get("vel", 0.7))
	u.pe = float(b.get("pe", 55)) * power
	u.vontade = float(b.get("vontade", 70))
	u.ua_per_hit = float(b.get("ua_per_hit", 2.0))
	u.ult = b.get("ult", {})
	# O Devorador continua SEM resistencia elemental, de proposito: a ficha dele
	# em enemies.json diz "Nao tem resistencias: qualquer build vence". Ele e o
	# unico do jogo que nao recebe SimUnit.resist_for.
	u.resist = {}
	sim.add_unit(u)

	var esc: Dictionary = b.get("escort", {})
	if not esc.is_empty():
		for t in Db.themes:
			if String(t.get("id", "")) == String(esc.get("theme", "")):
				build(sim, t, int(esc.get("count", 2)), 1337, float(esc.get("power", 1.2)))
				break
	return u
