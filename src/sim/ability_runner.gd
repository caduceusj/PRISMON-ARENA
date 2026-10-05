class_name AbilityRunner
extends RefCounted
## Interpretador das listas de operacoes que descrevem ultimates, ativos e
## efeitos de reacao. GDD 22.1: os numeros vivem no JSON, nao aqui.
##
## Vocabulario de ops:
##   strike, heal, shield, buff, debuff, taunt, control, repeat, cleanse,
##   consume_aura, discharge, chain, delay_action, rewrite_affinity
##
## Alvos: self, current_target, reaction_target, aim_single, aim_area,
##        enemy_all, enemy_near_self, enemy_lowest_hp, enemy_most_ua,
##        enemy_random_distinct, enemies_near_target,
##        ally_all, ally_most_hurt


static func run(sim: CombatSim, source: SimUnit, ops: Array, aim: Vector2 = Vector2.ZERO,
		react_target: SimUnit = null, element_pick: String = "") -> void:
	for op in ops:
		_exec(sim, source, op, aim, react_target, element_pick)


static func _exec(sim: CombatSim, src: SimUnit, op: Dictionary, aim: Vector2,
		react_target: SimUnit, element_pick: String) -> void:
	var kind := String(op.get("op", ""))
	match kind:
		"repeat":
			var times := int(op.get("times", 1))
			var interval := float(op.get("interval", 1.0))
			var inner: Array = op.get("ops", [])
			run(sim, src, inner, aim, react_target, element_pick)
			for i in range(1, times):
				sim.schedule(sim.now + interval * float(i), src, inner, aim, react_target, element_pick)
			return

		"strike":
			var targets := _targets(sim, src, op, aim, react_target)
			for t in targets:
				sim.strike(src, t, {
					"element": String(op.get("element", src.element if src else "")),
					"ua": float(op.get("ua", 0.0)),
					"mult": float(op.get("mult", 0.0)),
					"elem_mult": float(op.get("elem_mult", 0.0)),
					"flat": float(op.get("flat", 0.0)),
					"lifesteal": float(op.get("lifesteal", 0.0)),
					"bonus_if_aura": String(op.get("bonus_if_aura", "")),
					"bonus_mult": float(op.get("bonus_mult", 1.0)),
					"bonus_if_control": String(op.get("bonus_if_control", "")),
					"control_mult": float(op.get("control_mult", 1.0)),
				})
			# Supernova: se algum alvo ja tinha a aura pedida, a reacao vira global.
			var gr := String(op.get("global_reaction_if", ""))
			if gr != "":
				for t in _side_units(sim, src, false):
					if t.aura.has_aura(gr):
						sim.strike(src, t, {"element": String(op.get("element", "")), "ua": 0.0})

		"heal":
			for t in _targets(sim, src, op, aim, react_target):
				var amount: float = float(op.get("flat", 0.0)) + float(t.hp_max) * float(op.get("pct_max", 0.0))
				if src != null:
					amount *= 1.0 + src.eff_pe() / Db.combat("heal_pe_divisor", 150.0)
				sim.heal(src, t, amount)

		"shield":
			# GDD 17.3 -- ESCUDO = ValorBase + 0.4 * PE
			for t in _targets(sim, src, op, aim, react_target):
				var pe: float = src.eff_pe() if src != null else 0.0
				sim.give_shield(t, float(op.get("base", 0.0)) + Db.combat("shield_pe_scale", 0.4) * pe)

		"buff", "debuff":
			for t in _targets(sim, src, op, aim, react_target):
				t.add_buff(String(op.get("stat", "")), float(op.get("mult", 1.0)),
					float(op.get("value", 0.0)), float(op.get("duration", 1.0)), sim.now,
					String(op.get("label", "")), String(op.get("element", "")),
					int(op.get("max_stacks", 0)))

		"taunt":
			if src == null:
				return
			for t in _side_units(sim, src, false):
				t.taunted_by = src.id
				t.taunt_until = sim.now + float(op.get("duration", 3.0))

		"control":
			for t in _targets(sim, src, op, aim, react_target):
				sim.apply_control(t, String(op.get("control", "stun")),
					float(op.get("duration", 1.0)),
					float(op.get("immunity", Db.combat("control_immunity", 5.0))))

		"cleanse":
			var n := int(op.get("count", 99))
			for t in _targets(sim, src, op, aim, react_target):
				var removed := 0
				for b in t.buffs.duplicate():
					if removed >= n:
						break
					if float(b.get("mult", 1.0)) < 1.0 or String(b.get("label", "")) == "Ferida":
						t.buffs.erase(b)
						removed += 1

		"consume_aura":
			# Devorador de Cinzas: toda a UA da aura vira dano verdadeiro.
			for t in _targets(sim, src, op, aim, react_target):
				var aura_id: String = String(op.get("aura", ""))
				var ua: float = t.aura.consume_all(aura_id)
				if ua > 0.0:
					sim.deal_true(src, t, ua * float(op.get("damage_per_ua", 0.0)))

		"discharge":
			# Circuito Aberto: descarrega e reaplica a aura.
			for t in _targets(sim, src, op, aim, react_target):
				var aura_id2: String = String(op.get("aura", ""))
				var a = t.aura.get_aura(aura_id2)
				if a == null:
					continue
				var amount: float = a.ua
				t.aura.consume_all(aura_id2)
				sim.strike(src, t, {"element": String(op.get("element", "")),
					"ua": amount if bool(op.get("reapply", false)) else 0.0,
					"elem_mult": float(op.get("elem_mult", 1.0))})

		"chain":
			# Eletrocussao: encadeia para inimigos que tambem tenham a aura pedida.
			var need := String(op.get("require_aura", ""))
			var count := int(op.get("count", 2))
			var pool: Array = []
			for t in _side_units(sim, src, false):
				if react_target != null and t.id == react_target.id:
					continue
				if need == "" or t.aura.has_aura(need):
					pool.append(t)
			for i in range(mini(count, pool.size())):
				sim.strike(src, pool[i], {"element": String(op.get("element", "RAIO")),
					"ua": 0.0, "elem_mult": float(op.get("damage_mult", 1.0))})

		"delay_action":
			# Detonacao: empurra o alvo 1 posicao para tras na fila de acao.
			for t in _targets(sim, src, op, aim, react_target):
				t.attack_cd += t.attack_interval(0.0) * float(op.get("fraction", 0.5))

		"rewrite_affinity":
			for t in _targets(sim, src, op, aim, react_target):
				sim.rewrite_affinity(t, element_pick, float(op.get("duration", 12.0)))

		"basic_attack":
			# fim do windup: o golpe basico conecta (ver CombatSim._basic_attack)
			if src != null:
				sim._basic_attack(src, react_target)

		"energy":
			# Catalisacao (GDD 6.4): devolve Energia do Domador — so o lado do
			# jogador. `src == null` E o Domador: `cast_active` roda sem fonte, e o
			# portao antigo (`src != null`) fazia a Catalisacao disparada por um
			# Ativo devolver ZERO — apesar de o texto dela em reactions.json a
			# chamar de "o motor dos Ativos".
			if src == null or src.side == 0:
				sim.gain_energy(float(op.get("amount", 8.0)))

		"maxhp_damage":
			# Geada Mortal (GDD 6.4): o unico dano percentual do jogo
			for t in _targets(sim, src, op, aim, react_target):
				sim.deal_true(src, t, t.hp_max * float(op.get("pct", 0.04)))

		"restore_affinity":
			if src != null:
				sim.restore_affinity(src)

		_:
			push_warning("PRISMON: op desconhecida '%s' (ignorada)" % kind)


# --- resolucao de alvos ----------------------------------------------------

## Unidades de um lado. `friendly=true` => aliados de `src`; se `src` for null
## (Ativo do jogador), aliado = lado 0 e inimigo = lado 1.
static func _side_units(sim: CombatSim, src: SimUnit, friendly: bool) -> Array:
	var my_side: int = src.side if src != null else 0
	var side: int = my_side if friendly else 1 - my_side
	return sim.alive_units(side)


static func _targets(sim: CombatSim, src: SimUnit, op: Dictionary, aim: Vector2,
		react_target: SimUnit) -> Array:
	var t := String(op.get("target", "current_target"))
	# BUG (corrigido em 31/08): o Meteoro declara "radius" no ATIVO, não no op,
	# e o runner só lia o do op — raio 0, nenhum alvo, o Ativo mais caro do
	# jogo não fazia absolutamente nada. Agora o op herda o raio do ativo.
	var radius := float(op.get("radius", op.get("_owner_radius", 0.0)))
	match t:
		"self":
			return [src] if src != null else []
		"reaction_target":
			return [react_target] if react_target != null else []
		"aim_single":
			return [react_target] if react_target != null else []
		"current_target":
			if src == null:
				return []
			var ct := sim.pick_target(src)
			return [ct] if ct != null else []
		"enemy_all":
			return _side_units(sim, src, false)
		"ally_all":
			return _side_units(sim, src, true)
		"aim_area":
			var out: Array = []
			for u in _side_units(sim, src, false):
				if u.pos.distance_to(aim) <= radius:
					out.append(u)
			return out
		"aim_area_ally":
			# cura de ÁREA: pega os aliados dentro do raio, não a equipe toda.
			# Posicionamento passa a valer para o suporte também.
			var outa: Array = []
			for u in _side_units(sim, src, true):
				if u.pos.distance_to(aim) <= radius:
					outa.append(u)
			return outa
		"enemy_near_self":
			if src == null:
				return []
			var out2: Array = []
			for u in _side_units(sim, src, false):
				if u.pos.distance_to(src.pos) <= radius:
					out2.append(u)
			return out2
		"enemies_near_target":
			if react_target == null:
				return []
			var out3: Array = []
			for u in sim.alive_units(react_target.side):
				if u.pos.distance_to(react_target.pos) <= radius:
					out3.append(u)
			return out3
		"enemy_lowest_hp":
			var foes := _side_units(sim, src, false)
			if foes.is_empty():
				return []
			var best: SimUnit = foes[0]
			for f in foes:
				if f.hp_pct() < best.hp_pct():
					best = f
			return [best]
		"enemy_most_ua":
			var foes2 := _side_units(sim, src, false)
			if foes2.is_empty():
				return []
			var best2: SimUnit = foes2[0]
			for f in foes2:
				if f.aura.total_ua() > best2.aura.total_ua():
					best2 = f
			return [best2]
		"enemy_random_distinct":
			var pool := _side_units(sim, src, false)
			var n := mini(int(op.get("count", 1)), pool.size())
			if n <= 0:
				return []
			# deterministico: embaralha com o RNG semeado da simulacao
			var idx: Array = range(pool.size())
			for i in range(idx.size() - 1, 0, -1):
				var j: int = sim.rng.randi_range(0, i)
				var tmp: int = idx[i]
				idx[i] = idx[j]
				idx[j] = tmp
			var out4: Array = []
			for i in range(n):
				out4.append(pool[idx[i]])
			return out4
		"ally_most_hurt":
			var mates := _side_units(sim, src, true)
			if mates.is_empty():
				return []
			var hurt: SimUnit = mates[0]
			for m in mates:
				if m.hp_pct() < hurt.hp_pct():
					hurt = m
			return [hurt]
		_:
			push_warning("PRISMON: alvo desconhecido '%s'" % t)
			return []
