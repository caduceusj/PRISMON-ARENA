class_name ReactionResolver
extends RefCounted
## GDD 22.2 -- resolvedor de reacoes. PURO: static, sem estado, sem acesso a cena.
## Isso e o que o torna testavel isoladamente e simulavel em lote (GDD 22.3/22.4).

enum Kind { NONE, AMPLIFY, TRANSFORM, CATALYTIC }

class Result extends RefCounted:
	var kind: int = Kind.NONE
	var rule: Dictionary = {}
	var direction: String = ""
	var trigger_aura: String = ""     # aura que estava no alvo
	var hit_element: String = ""      # elemento do golpe recebido
	var damage_mult: float = 1.0      # AMPLIFY: multiplica o dano do golpe
	var reaction_damage: float = 0.0  # TRANSFORM: dano independente
	var damage_element: String = ""   # elemento do dano de reacao (para Resistencia)
	var consume_ua: float = 0.0       # quanto tirar da aura gatilho (-1 = tudo)
	var ops: Array = []               # efeitos colaterais (on_react)

	func happened() -> bool:
		return kind != Kind.NONE

	func name() -> String:
		return String(rule.get("name", ""))

	func id() -> String:
		return String(rule.get("id", ""))


## Contexto de uma resolucao. Tudo que vem de fora da matriz.
class Ctx extends RefCounted:
	var node_index: int = 1          # N em DanoBase(N) = 30 + 14N
	var attacker_pe: float = 0.0
	var reaction_bonus: float = 0.0  # soma de Eco de Fogo, Totem do Fole, reliquias...
	var target_resist: float = 0.0   # 0..0.75
	var reverse_full_mult: bool = false   # Reliquia: Pedra da Ordem
	var amplify_keeps_aura: bool = false  # Reliquia: Cadinho
	var target_control_immune: bool = false
	var pe_soft_cap: float = 120.0
	var base_a: float = 30.0
	var base_b: float = 14.0
	var resist_cap: float = 0.75


static func base_damage(ctx: Ctx) -> float:
	return ctx.base_a + ctx.base_b * float(ctx.node_index)


## GDD 6.1 -- DanoReacao = DanoBase(N) * (1 + PE/(PE+120)) * (1 + Bonus) * (1 - Resist)
static func transform_damage(mult: float, ctx: Ctx) -> float:
	var pe_curve: float = ctx.attacker_pe / (ctx.attacker_pe + ctx.pe_soft_cap)
	var resist: float = clampf(ctx.target_resist, 0.0, ctx.resist_cap)
	return base_damage(ctx) * mult * (1.0 + pe_curve) * (1.0 + ctx.reaction_bonus) * (1.0 - resist)


## Resolve o golpe `hit_element` contra as auras presentes em `state`.
## NAO altera o estado -- devolve o que deve acontecer. Quem aplica e o CombatSim.
static func resolve(state: AuraState, hit_element: String, ctx: Ctx) -> Result:
	var res := Result.new()
	res.hit_element = hit_element
	if state == null or state.auras.is_empty():
		return res

	# Auras sao testadas na ordem de aplicacao: a mais recente reage primeiro.
	var ordered: Array = state.auras.duplicate()
	ordered.sort_custom(func(a, b): return a.age < b.age)

	for aura in ordered:
		var hit: Dictionary = Db.lookup_reaction(aura.aura_id, hit_element)
		if hit.is_empty():
			continue
		var rule: Dictionary = hit["rule"]
		res.rule = rule
		res.direction = String(hit["direction"])
		res.trigger_aura = aura.aura_id
		res.ops = rule.get("on_react", [])

		match String(rule.get("kind", "")):
			"amplify":
				res.kind = Kind.AMPLIFY
				var fwd := float(rule.get("mult_forward", 1.0))
				var rev := float(rule.get("mult_reverse", fwd))
				var m: float = fwd if (res.direction == "forward" or ctx.reverse_full_mult) else rev
				res.damage_mult = m * (1.0 + ctx.reaction_bonus)
				res.damage_element = hit_element
				res.consume_ua = 0.0 if ctx.amplify_keeps_aura else -1.0
			"transform":
				res.kind = Kind.TRANSFORM
				res.damage_element = String(rule.get("damage_element", hit_element))
				res.reaction_damage = transform_damage(float(rule.get("damage_mult", 1.0)), ctx)
				res.consume_ua = _consume_amount(rule, ctx)
			"catalytic":
				# Uma reacao catalitica de Controle contra um alvo IMUNE nao acontece.
				# Sem isso, Congelar queimaria 2 UA por nada a cada golpe durante os
				# 5 s de imunidade (GDD 7.4) -- um imposto invisivel sobre builds de Gelo.
				if ctx.target_control_immune and _is_control(rule):
					continue
				res.kind = Kind.CATALYTIC
				res.damage_element = ""
				res.consume_ua = _consume_amount(rule, ctx)
			_:
				continue
		return res

	return res


static func _is_control(rule: Dictionary) -> bool:
	for op in rule.get("on_react", []):
		if String(op.get("op", "")) == "control":
			return true
	return false


static func _consume_amount(rule: Dictionary, ctx: Ctx) -> float:
	match String(rule.get("consume", "transform")):
		"all":
			return -1.0
		"none":
			return 0.0
		_:
			return float(Db.combat("transform_consume_ua", 2.0))


## Usado pela Lente Fratal: qualquer outra reacao valida contra este alvo.
static func alternative_reactions(state: AuraState, hit_element: String, exclude_aura: String) -> Array:
	var out: Array = []
	for aura in state.auras:
		if aura.aura_id == exclude_aura:
			continue
		if not Db.lookup_reaction(aura.aura_id, hit_element).is_empty():
			out.append(aura.aura_id)
	return out
