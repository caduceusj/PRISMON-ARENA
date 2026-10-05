class_name AuraState
extends RefCounted
## GDD 4.2 -- as auras de UMA unidade. Puro: sem cena, sem sinais, sem Node.
##
## Regras implementadas:
##   1. Maximo 2 auras simultaneas; a terceira substitui a mais antiga.
##   2. Teto de 8 UA por aura (ajustavel por item/ressonancia).
##   3. Encharcado amplifica UA recebida de OUTRAS fontes em +25%.
##   4. Cada aura decai a uma taxa propria (UA/s).

class Aura extends RefCounted:
	var aura_id: String       # COMBUSTAO / GELIDO / ENCHARCADO / CARGA
	var element: String       # FOGO / GELO / AGUA / RAIO
	var ua: float
	var decay: float
	var source_id: int
	var age: float            # segundos desde a aplicacao (define "a mais antiga")
	var charge_paid: float    # so para CARGA: quanta UA ja pagou dano de acumulo

	func _init(p_aura: String, p_el: String, p_ua: float, p_decay: float, p_src: int) -> void:
		aura_id = p_aura
		element = p_el
		ua = p_ua
		decay = p_decay
		source_id = p_src
		age = 0.0
		charge_paid = 0.0

var auras: Array = []          # Array[Aura], no maximo max_auras
var max_auras: int = 2
var cap_ua: float = 8.0
var cap_overrides: Dictionary = {}   # aura_id -> teto especifico (Coro de Fogo, Totem do Excesso)
var decay_mult: Dictionary = {}      # aura_id -> multiplicador de decaimento (Eco de Agua, Totem)
var decay_frozen: bool = false       # Cinzeiro Eterno


func has_aura(aura_id: String) -> bool:
	for a in auras:
		if a.aura_id == aura_id:
			return true
	return false


func get_aura(aura_id: String) -> Aura:
	for a in auras:
		if a.aura_id == aura_id:
			return a
	return null


func total_ua() -> float:
	var t := 0.0
	for a in auras:
		t += a.ua
	return t


func cap_for(aura_id: String) -> float:
	return float(cap_overrides.get(aura_id, cap_ua))


## GDD 4.2.4 -- Encharcado e o unico estado que amplifica outros.
func incoming_multiplier(aura_id: String) -> float:
	var wet := get_aura("ENCHARCADO")
	if wet == null or aura_id == "ENCHARCADO":
		return 1.0
	var el: Dictionary = Db.el("AGUA")
	return 1.0 + float(el.get("passive_value", 0.25))


## Aplica UA de uma aura. Retorna a UA efetivamente adicionada.
## NAO resolve reacao -- quem chama (CombatSim) resolve antes de aplicar.
## `cap_extra` e o teto que QUEM APLICA impoe (Totem do Excesso: 12 em vez de 8).
## Ele so pode SUBIR o teto — um aplicador sem item nunca reduz o que ja esta la.
func apply(aura_id: String, element: String, ua: float, decay: float, source_id: int,
		cap_extra: float = 0.0) -> float:
	if ua <= 0.0:
		return 0.0
	ua *= incoming_multiplier(aura_id)
	var existing := get_aura(aura_id)
	var cap := maxf(cap_for(aura_id), cap_extra)
	if existing != null:
		var before := existing.ua
		# nunca REDUZIR: uma aura levada a 12 pelo Totem nao volta a 8 porque o
		# proximo golpe veio de um aliado sem o item
		existing.ua = minf(existing.ua + ua, maxf(cap, existing.ua))
		existing.age = 0.0
		existing.source_id = source_id
		# o decaimento e de quem aplicou POR ULTIMO, como o source_id
		existing.decay = decay * float(decay_mult.get(aura_id, 1.0))
		return existing.ua - before

	# GDD 4.2.1 -- a terceira aplicacao substitui a MAIS ANTIGA.
	if auras.size() >= max_auras:
		var oldest: Aura = auras[0]
		for a in auras:
			if a.age > oldest.age:
				oldest = a
		auras.erase(oldest)

	var mult: float = float(decay_mult.get(aura_id, 1.0))
	var fresh := Aura.new(aura_id, element, minf(ua, cap), decay * mult, source_id)
	auras.append(fresh)
	return fresh.ua


## Remove UA de uma aura especifica. Retorna quanto foi realmente consumido.
func consume(aura_id: String, ua: float) -> float:
	var a := get_aura(aura_id)
	if a == null:
		return 0.0
	var taken: float = minf(a.ua, ua) if ua >= 0.0 else a.ua
	a.ua -= taken
	if a.ua <= 0.001:
		auras.erase(a)
	return taken


func consume_all(aura_id: String) -> float:
	return consume(aura_id, -1.0)


func clear() -> void:
	auras.clear()


## Avanca o decaimento. Retorna a lista de auras que expiraram neste tick.
func tick(delta: float) -> Array:
	var expired: Array = []
	for a in auras.duplicate():
		a.age += delta
		if decay_frozen:
			continue
		a.ua -= a.decay * delta
		if a.ua <= 0.001:
			auras.erase(a)
			expired.append(a.aura_id)
	return expired


func snapshot() -> Array:
	var out: Array = []
	for a in auras:
		out.append({ "aura": a.aura_id, "element": a.element, "ua": a.ua, "cap": cap_for(a.aura_id) })
	return out
