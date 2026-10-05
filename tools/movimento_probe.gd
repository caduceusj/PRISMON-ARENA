extends Node
## QUANTO AS CRIATURAS REALMENTE ANDAM?
##
## O clinch_probe ja diz que ninguem TRAVA (0% preso, 99.7% no alcance). Isso
## responde "o movimento esta quebrado?" — nao responde "o movimento existe?".
## Sao perguntas diferentes: um combate em que todos fecham em meio segundo e
## ficam parados ate o fim tambem marca 0% de travamento.
##
## Aqui se mede o outro lado: fracao do tempo andando, distancia percorrida por
## combate, e quanto demora ate o primeiro golpe.

const COMBATES := 40


## Velocidade maxima do papel, em px/s.
func _vel_max(u: SimUnit) -> float:
	var papeis: Dictionary = Db.tuning.get("movement", {}).get("roles", {})
	return float(papeis.get(u.role, {}).get("move_speed", 100.0))


## Quem NAO recua de proposito: os papeis sem `kite`.
func _corpo_a_corpo(u: SimUnit) -> bool:
	var papeis: Dictionary = Db.tuning.get("movement", {}).get("roles", {})
	return float(papeis.get(u.role, {}).get("kite", 0.0)) <= 0.01


func _ready() -> void:
	var tick_total := 0
	var tick_andando := 0
	var dist := 0.0
	var unidades := 0
	var t_primeiro := 0.0
	var com_primeiro := 0
	var dur := 0.0
	var tick_no_alcance_andando := 0
	var tick_no_alcance := 0
	# CORPO A CORPO E DISTANCIA SAO CASOS DIFERENTES. Quem tem `kite` recua de
	# proposito — andar no alcance e o TRABALHO dele. Somar os dois num numero
	# so mede a soma de um defeito com uma funcionalidade, e foi o que a
	# primeira versao deste probe fez.
	var cc_no_alcance := 0
	var cc_no_alcance_andando := 0
	# POR FAIXA DE VELOCIDADE. "Andando" com um limiar de 0.6 px por tick e
	# 6 px/s — 4% da velocidade de uma Lamina. Isso conta como andar qualquer
	# micro-ajuste, inclusive os que ninguem ve. O que importa para o olho e
	# quanto do tempo a criatura se move de forma VISIVEL.
	var faixas := [0.05, 0.25, 0.50]
	var cc_faixa := [0, 0, 0]
	# O PRECO DA ZONA MORTA e sobreposicao: se ninguem se empurra, os corpos
	# encavalam. Medir so a remexida esconderia metade da troca.
	var pares_total := 0
	var pares_encavalados := 0
	var trocas_de_alvo := 0

	for s in range(COMBATES):
		Run.start_run(700 + s)
		Run.set_starting_team(["sheep", "apollo"])
		if s % 2 == 0:
			Run.team.append(UnitInstance.create("hipocampo"))
		Run.node_index = 4 + s % 5
		var par: Array = NodeGen.generate_pair(Run.node_index)
		var sim := CombatBuilder.build(par[0], 500 + s * 13)

		var alvos: Dictionary = {}
		var antes: Dictionary = {}
		for u in sim.units:
			antes[u.id] = u.pos
		var primeiro := -1.0
		for i in range(900):
			if sim.finished:
				break
			sim.step()
			for e in sim.drain_events():
				if String(e["kind"]) == "damage" and primeiro < 0.0:
					primeiro = sim.now
			for u in sim.units:
				if not u.alive:
					continue
				tick_total += 1
				var d: float = u.pos.distance_to(antes[u.id])
				var andando: bool = d > 0.6   # 0.6 px por passo de 0.1 s
				if andando:
					tick_andando += 1
				# ANDAR JA ESTANDO NO ALCANCE nao e deslocamento, e remexida:
				# a criatura ja podia bater dali. E o numero que separa
				# "atravessou a arena" de "ficou se ajeitando".
				var alvo: SimUnit = sim.by_id.get(u.target_id)
				if alvo != null and alvo.alive 						and u.pos.distance_to(alvo.pos) <= u.attack_range:
					tick_no_alcance += 1
					if andando:
						tick_no_alcance_andando += 1
					if _corpo_a_corpo(u):
						cc_no_alcance += 1
						if andando:
							cc_no_alcance_andando += 1
						var vmax: float = _vel_max(u) * 0.1   # px por tick
						for k in faixas.size():
							if d > vmax * float(faixas[k]):
								cc_faixa[k] += 1
				if alvos.get(u.id, -1) != u.target_id:
					if alvos.has(u.id):
						trocas_de_alvo += 1
					alvos[u.id] = u.target_id
				dist += d
				antes[u.id] = u.pos
		for a in sim.units:
			for b in sim.units:
				if a.id >= b.id or not a.alive or not b.alive:
					continue
				pares_total += 1
				if a.pos.distance_to(b.pos) < 34.0:   # meio corpo
					pares_encavalados += 1
		dur += sim.now
		unidades += sim.units.size()
		if primeiro >= 0.0:
			t_primeiro += primeiro
			com_primeiro += 1

	print("=== movimento em combate (%d combates reais) ===" % COMBATES)
	print("  fracao do tempo ANDANDO         %.1f%%"
		% (100.0 * float(tick_andando) / maxf(float(tick_total), 1.0)))
	print("  distancia media por unidade     %.0f px por combate"
		% (dist / maxf(float(unidades), 1.0)))
	print("  ate o PRIMEIRO golpe            %.2f s (media)"
		% (t_primeiro / maxf(float(com_primeiro), 1.0)))
	print("  duracao media do combate        %.1f s" % (dur / float(COMBATES)))
	print("  no alcance e andando, TODOS     %.1f%%"
		% (100.0 * float(tick_no_alcance_andando) / maxf(float(tick_no_alcance), 1.0)))
	print("  no alcance e andando, CORPO A CORPO  %.1f%%   <- so isto e remexida"
		% (100.0 * float(cc_no_alcance_andando) / maxf(float(cc_no_alcance), 1.0)))
	for k in faixas.size():
		print("     ... a mais de %2.0f%% da velocidade    %.1f%% do tempo"
			% [100.0 * float(faixas[k]),
				100.0 * float(cc_faixa[k]) / maxf(float(cc_no_alcance), 1.0)])
	print("  pares encavalados no fim        %.1f%%"
		% (100.0 * float(pares_encavalados) / maxf(float(pares_total), 1.0)))
	print("  trocas de alvo por unidade      %.1f por combate"
		% (float(trocas_de_alvo) / maxf(float(unidades), 1.0)))
	get_tree().quit(0)
