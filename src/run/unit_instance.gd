class_name UnitInstance
extends RefCounted
## Uma criatura da SUA equipe, persistente ao longo da run.
## GDD 5.1 / 10.1 / 11 / 12.3 -- forma, peso, vinculo, itens e Estomago.

var uid: int = 0
var species_id: String = ""      # forma ATUAL (base ou evoluida)
var items: Array = []            # Array[String] de item_id
var dishes: Array = []           # Array[String] de dish_id -- Nutricao, permanente
var copies: int = 1              # copias acumuladas da linha base
var hp_ratio: float = 1.0        # HP carregado entre nos
var forced_element: String = ""  # Guisado Cromatico (Transmutacao)
var muda_discount: int = 0       # Prato da Muda
var spent_ether: int = 0                 # para o reembolso do Doce do Esquecimento

static var _next_uid := 1


static func create(sp_id: String) -> UnitInstance:
	var u := UnitInstance.new()
	u.uid = _next_uid
	_next_uid += 1
	u.species_id = sp_id
	return u


func data() -> Dictionary:
	return Db.sp(species_id)

func display_name() -> String:
	return String(data().get("name", species_id))

func is_evolved() -> bool:
	return bool(data().get("evolved", false))

func base_id() -> String:
	return Db.sp_base_id(species_id)

func base_data() -> Dictionary:
	return Db.sp(base_id())

func role() -> String:
	return String(data().get("role", base_data().get("role", "Guardiao")))

func stance() -> String:
	return String(data().get("stance", base_data().get("stance", "Vanguarda")))

func rarity() -> String:
	return String(base_data().get("rarity", "Comum"))


## GDD 11 / 12.4 -- Nucleos e o Guisado Cromatico reescrevem a Afinidade.
func element() -> String:
	for it in items:
		var m: Dictionary = Db.items.get(it, {}).get("mods", {})
		if m.has("set_element"):
			return String(m["set_element"])
	if forced_element != "":
		return forced_element
	return String(base_data().get("element", "FOGO"))


func native_element() -> String:
	return String(base_data().get("element", "FOGO"))


## GDD 5.1 -- Peso Elemental: base 1, evoluida 2. E o que a Ressonancia conta.
func weight() -> int:
	var ev: Dictionary = Db.tuning.get("evolution", {})
	return int(ev.get("weight_evolved", 2)) if is_evolved() else int(ev.get("weight_base", 1))


## GDD 10.5 -- custo em Vinculo: o unico limite de tamanho de equipe.
func bond_cost() -> int:
	var ev: Dictionary = Db.tuning.get("evolution", {})
	return int(ev.get("bond_cost_evolved", 2)) if is_evolved() else int(ev.get("bond_cost_base", 1))


func item_slots() -> int:
	var ev: Dictionary = Db.tuning.get("evolution", {})
	var n: int = int(ev.get("item_slots_evolved", 2)) if is_evolved() else int(ev.get("item_slots_base", 1))
	# Banquete do Diluvio: +1 slot, ignorando o limite da forma (GDD 12.3)
	for d in dishes:
		n += int(Db.dishes.get(d, {}).get("mods", {}).get("item_slot", 0))
	return n


## GDD 12.3 -- Estomago: quantos pratos de Nutricao esta unidade ainda aceita.
func estomago() -> int:
	var f: Dictionary = Db.tuning.get("food", {})
	var n: int = int(f.get("estomago_evolved", 4)) if is_evolved() else int(f.get("estomago_base", 3))
	return n + int(Run.mods().get("estomago_add", 0.0))


func dishes_eaten() -> int:
	var n := 0
	for d in dishes:
		if String(Db.dishes.get(d, {}).get("kind", "")) == "nutricao":
			n += 1
	return n


func stomach_free() -> int:
	return maxi(estomago() - dishes_eaten(), 0)


func ult() -> Dictionary:
	return data().get("ult", {})


## Estatisticas finais: base -> evolucao (x2.2) -> itens -> pratos.
func stats() -> Dictionary:
	var b := base_data()
	var ev: Dictionary = Db.tuning.get("evolution", {})
	var mult: float = float(ev.get("stat_mult", 2.2)) if is_evolved() else 1.0
	var s := {
		"hp": float(b.get("hp", 100)) * mult,
		"atk": float(b.get("atk", 10)) * mult,
		"def": float(b.get("def", 0)) * mult,
		"vel": float(b.get("vel", 1.0)),
		"pe": float(b.get("pe", 0)) * mult,
		"vontade": float(b.get("vontade", 0)),
		"ua_per_hit": float(b.get("ua_per_hit", 2.0)),
	}
	var keys := ["hp", "atk", "def", "vel", "pe", "vontade", "ua_per_hit"]
	for it in items:
		var m: Dictionary = Db.items.get(it, {}).get("mods", {})
		for k in keys:
			if m.has(k):
				s[k] = maxf(float(s[k]) + float(m[k]), 0.0)
	# GDD 12.3 -- Nutricao: os pratos sao bonus PERMANENTES, somados como itens
	for d in dishes:
		var dm: Dictionary = Db.dishes.get(d, {}).get("mods", {})
		for k in keys:
			if dm.has(k):
				s[k] = maxf(float(s[k]) + float(dm[k]), 0.0)
	return s


## Modificadores que os itens desta unidade injetam na simulacao.
func item_mods() -> Dictionary:
	var out := {"reaction_bonus": 0.0, "double_reaction": 0.0, "share_damage": 0.0,
		"aura_cap": 0.0, "aura_decay_mult": 1.0,
		# Revisão 31/08: regeneração de Poder, bônus por reação e atordoamento
		# com recarga — as três famílias de item que o autor pediu.
		"ult_gain": 1.0, "ua_add": 0.0, "healing_out": 1.0,
		# Diapasão Vivo: o item mora numa unidade e o efeito é de EQUIPE.
		# CombatBuilder agrega isto em team_mods[0].
		"team_ult_gain": 1.0,
		"rx_dmg_add": {}, "rx_stun": {}}
	for it in items:
		var m: Dictionary = Db.items.get(it, {}).get("mods", {})
		out["ult_gain"] = float(out["ult_gain"]) * float(m.get("unit_ult_gain", 1.0))
		out["team_ult_gain"] = float(out["team_ult_gain"]) * float(m.get("team_ult_gain", 1.0))
		out["ua_add"] = float(out["ua_add"]) + float(m.get("unit_ua_add", 0.0))
		out["healing_out"] = float(out["healing_out"]) * float(m.get("healing_out", 1.0))
		for rid in m.get("rx_dmg_add", {}).keys():
			out["rx_dmg_add"][rid] = float(out["rx_dmg_add"].get(rid, 0.0)) 				+ float(m["rx_dmg_add"][rid])
		for rid2 in m.get("rx_stun", {}).keys():
			out["rx_stun"][rid2] = m["rx_stun"][rid2]
		out["reaction_bonus"] = float(out["reaction_bonus"]) + float(m.get("unit_reaction_dmg_add", 0.0))
		out["double_reaction"] = float(out["double_reaction"]) + float(m.get("unit_double_reaction", 0.0))
		out["share_damage"] = float(out["share_damage"]) + float(m.get("share_damage", 0.0))
		if m.has("unit_aura_cap"):
			out["aura_cap"] = maxf(float(out["aura_cap"]), float(m["unit_aura_cap"]))
		if m.has("unit_aura_decay_mult"):
			out["aura_decay_mult"] = float(out["aura_decay_mult"]) * float(m["unit_aura_decay_mult"])
	return out


func can_equip() -> bool:
	return items.size() < item_slots()


## Esta unidade já carrega um Núcleo (ou qualquer item que reescreva a Afinidade)?
##
## `element()` devolve o PRIMEIRO item com `set_element`, então um segundo Núcleo
## na mesma criatura era silenciosamente inerte: o jogador pagava, a tela prometia
## a troca de Afinidade, e nada acontecia. Um slot é o preço de uma Afinidade.
func has_core() -> bool:
	for it in items:
		if Dictionary(Db.items.get(it, {}).get("mods", {})).has("set_element"):
			return true
	return false


## Este item reescreve a Afinidade de quem o equipa?
static func item_sets_element(item_id: String) -> bool:
	return Dictionary(Db.items.get(item_id, {}).get("mods", {})).has("set_element")


## Itens de ASSINATURA (campo "for") só servem ao Prismon dono. Um item pode
## aparecer na loja sem que você tenha o dono — e aí não dá para comprar.
func accepts_item(item_id: String) -> bool:
	if not can_equip():
		return false
	# um Núcleo por criatura: o segundo nunca teria efeito (ver has_core)
	if item_sets_element(item_id) and has_core():
		return false
	var owner := String(Db.items.get(item_id, {}).get("for", ""))
	return owner == "" or owner == base_id()


## GDD 10.1 -- A Muda: 2 copias da mesma especie base viram a forma seguinte.
func copies_needed() -> int:
	var base: int = int(Db.tuning.get("evolution", {}).get("copies_needed", 2))
	return maxi(base - Run.evolve_discount() - muda_discount, 1)


func try_evolve() -> bool:
	if is_evolved():
		return false
	if copies < copies_needed():
		return false
	var nxt := String(base_data().get("evolves_to", ""))
	if nxt == "":
		return false
	species_id = nxt
	copies = 0
	muda_discount = 0
	return true
