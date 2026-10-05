extends Node
## Mede o travamento por colisao no CENARIO RUIM: muitos corpos de corpo a
## corpo disputando os mesmos alvos, que e quando a separacao mais briga com o
## alcance. Roda com e sem a mascara e compara.

func _mk(sim: CombatSim, sp_id: String, side: int) -> SimUnit:
	var s := Db.sp(sp_id)
	var u := SimUnit.new()
	u.side = side
	u.species_id = sp_id
	u.display_name = String(s.get("name", sp_id))
	u.element = String(s.get("element", "FOGO"))
	u.base_element = u.element
	u.role = String(s.get("role", "Guardiao"))
	u.stance = String(s.get("stance", "Vanguarda"))
	u.hp_max = float(s.get("hp", 400)) * 3.0     # combate longo: mais tempo de clinch
	u.atk = float(s.get("atk", 30))
	u.def = float(s.get("def", 10))
	u.vel = float(s.get("vel", 1.0))
	u.pe = float(s.get("pe", 50))
	u.vontade = float(s.get("vontade", 40))
	u.ua_per_hit = float(s.get("ua_per_hit", 2.0))
	u.ult = {}
	return sim.add_unit(u)


func _measure() -> Dictionary:
	var stuck_ticks := 0
	var total_ticks := 0
	var hits := 0
	var idle_units := 0
	var dur := 0.0
	var in_range := 0
	for seed_v in range(10):
		var sim := CombatSim.new(900 + seed_v)
		sim.node_index = 7
		sim.max_duration = 90.0
		# so corpo a corpo dos dois lados: o pior caso de aglomeracao
		for i in range(4):
			_mk(sim, "sheep" if i % 2 == 0 else "apollo", 0)
			_mk(sim, "sheep" if i % 2 == 1 else "apollo", 1)
		sim.begin()
		var hist: Dictionary = {}
		var swings: Dictionary = {}
		for i in range(900):
			if sim.finished:
				break
			sim.step()
			for e in sim.drain_events():
				if String(e["kind"]) == "damage":
					hits += 1
					swings[int(e.get("src", -1))] = true
			for u in sim.units:
				if not u.alive or u.is_controlled(sim.now) or u.windup_until > sim.now:
					continue
				var t: SimUnit = sim.by_id.get(u.target_id)
				if t == null or not t.alive:
					continue
				total_ticks += 1
				if u.pos.distance_to(t.pos) <= u.attack_range:
					in_range += 1
				var old: Variant = hist.get(u.id)
				if i % 10 == 0:
					hist[u.id] = u.pos
				if old == null or sim.now < 2.0:
					continue
				if u.pos.distance_to(t.pos) > u.attack_range * 1.15 	 					and u.pos.distance_to(old) < 6.0:
					stuck_ticks += 1
		dur += sim.now
		for u2 in sim.units:
			if not swings.has(u2.id):
				idle_units += 1
	return {"stuck": float(stuck_ticks) * 100.0 / maxf(float(total_ticks), 1.0),
		"hits": hits, "idle": idle_units, "dur": dur / 10.0,
		"ready": float(in_range) * 100.0 / maxf(float(total_ticks), 1.0),
		"rate": float(hits) * 1000.0 / maxf(float(total_ticks), 1.0)}


func _ready() -> void:
	var mv: Dictionary = Db.tuning["movement"]
	var leash: float = float(mv.get("leash_reach", 0.9))
	var clinch: float = float(mv.get("separation_clinch_scale", 0.3))

	mv["leash_reach"] = 99.0      # mascara inativa
	mv["separation_clinch_scale"] = 1.0
	var off := _measure()

	mv["leash_reach"] = leash     # mascara ativa
	mv["separation_clinch_scale"] = clinch
	var on := _measure()

	print("cenario: 4v4 so corpo a corpo, 10 combates longos")
	print("                travado%   no alcance%   golpes/1k ticks   duracao   nunca bateu")
	print("  SEM mascara:   %5.1f       %5.1f          %6.1f        %5.1fs      %d"
		% [off["stuck"], off["ready"], off["rate"], off["dur"], off["idle"]])
	print("  COM mascara:   %5.1f       %5.1f          %6.1f        %5.1fs      %d"
		% [on["stuck"], on["ready"], on["rate"], on["dur"], on["idle"]])
	get_tree().quit(0)
