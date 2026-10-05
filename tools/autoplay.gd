extends Node
## GDD 22.3 / 22.4 -- simulador em lote. "Um autobattler com reacoes elementais
## NAO PODE ser balanceado a mao -- precisa de um simulador em lote desde o
## primeiro dia." Nao negociavel.
##
## Roda runs inteiras sem render, dirigindo o MODELO (RunState/NodeGen/CombatSim)
## sem tocar em nenhuma tela. Exporta CSV e confere os alvos do GDD 17.4.
##
##   godot --headless res://tools/autoplay.tscn -- --runs=200 --csv=user://runs.csv

var runs := 60
var momento_visto: Dictionary = {}   # kind -> quantas runs chegaram a ve-lo
var momento_passo: Dictionary = {}   # passo -> quantas runs chegaram nele
var csv_path := ""
var verbose := false

var rows: Array = []
var combats: Array = []


func _ready() -> void:
	_parse_args()
	print("=== PRISMA :: autoplay (%d runs) ===" % runs)
	var t0 := Time.get_ticks_msec()
	for i in range(runs):
		rows.append(_play_run(1000 + i * 17))
	var dt := Time.get_ticks_msec() - t0
	_report(dt)
	if csv_path != "":
		_write_csv()
	get_tree().quit(0)


func _parse_args() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--runs="):
			runs = maxi(int(a.split("=")[1]), 1)
		elif a.begins_with("--csv="):
			csv_path = a.split("=")[1]
		elif a == "--verbose":
			verbose = true
		elif a.begins_with("--momentos="):
			# TROCA A SEQUENCIA DE MOMENTOS SO NESTA RODADA, para comparar
			# arranjos sem editar os dados a cada tentativa. Escolher onde a
			# loja entra e uma decisao de alcance, e alcance se mede.
			var seq: Array = []
			for k in a.split("=")[1].split(","):
				seq.append(String(k))
			Db.tuning["momentos"]["evento_apos_combate"] = seq
			print("momentos: %s" % ", ".join(seq))


# --- o bot -----------------------------------------------------------------

const DUOS := [
	["sheep", "hipocampo"], ["sheep", "pinto_raio"], ["sheep", "apollo"],
	["sheep", "coalla"], ["hipocampo", "pinto_raio"], ["hipocampo", "apollo"],
	["hipocampo", "coalla"], ["pinto_raio", "apollo"], ["pinto_raio", "coalla"],
	["apollo", "coalla"],
]

func _play_run(seed_value: int) -> Dictionary:
	Run.start_run(seed_value)
	var duo: Array = DUOS[seed_value % DUOS.size()]
	Run.set_starting_team(duo)
	var node_reached := 0
	var combats_won := 0

	while true:
		Run.node_index += 1
		if Run.node_index > Run.total_nodes():
			break
		node_reached = Run.node_index
		var pair := NodeGen.generate_pair(Run.node_index)
		var node: Dictionary = _choose(pair)
		Run.history.append({"index": Run.node_index, "type": String(node.get("type", ""))})

		var res := _fight(node)
		if not bool(res["won"]):
			break
		combats_won += 1
		if Run.node_index < Run.total_nodes():
			# ALCANCE DO MOMENTO: quantas runs chegam a ver cada evento.
			# Um evento no passo 8 e visto por pouco mais de um terco das
			# runs — a metrica existe para isso nao passar despercebido.
			var kind_m := EventGen.kind_after(Run.node_index)
			if kind_m != "":
				momento_visto[kind_m] = int(momento_visto.get(kind_m, 0)) + 1
				momento_passo[Run.node_index] = int(momento_passo.get(Run.node_index, 0)) + 1
			_do_moment(Run.node_index)
		Run.heal_between_nodes()
		if Run.team.is_empty():
			break

	var won: bool = node_reached >= Run.total_nodes() and not Run.defeated
	var els: Array = []
	for u in Run.team:
		if not els.has(u.element()):
			els.append(u.element())
	# ORDENAR E O QUE TORNA A COMPOSICAO COMPARAVEL (revisao 15/09). Sem isto os
	# elementos entravam na ordem do time, e "AGUA/FOGO" e "FOGO/AGUA" viravam
	# duas linhas do relatorio — a build dominante ficava picada em ate 6
	# permutacoes e nenhuma delas aparecia no topo.
	els.sort()
	var res_names: Array = []
	for r in Run.active_resonances():
		res_names.append(String(r["name"]))
	var cooked := 0
	for u in Run.team:
		cooked += u.dishes.size()
	return {
		"seed": seed_value, "won": won, "node": node_reached, "combats": combats_won,
		"duo": "%s+%s" % [duo[0], duo[1]],
		"team": Run.team.size(), "bond": Run.bond_used(),
		"elements": "/".join(els), "resonances": "+".join(res_names),
		"relics": Run.relics.size(), "ether": Run.ether,
		"dishes": cooked,
	}


## O bot joga o momento de evento como um jogador razoavel: recruta o que
## abre reacoes novas, compra o que cabe no bolso, e so entra em evento de
## acaso com a equipe saudavel.
func _do_moment(index: int) -> void:
	match EventGen.kind_after(index):
		"recruta":
			var offer := EventGen.recruit_offer(index)
			if offer.is_empty():
				return
			var mine: Array = []
			for u in Run.team:
				if not mine.has(u.element()):
					mine.append(u.element())
			var best := String(offer[0])
			var best_new := -1
			for id in offer:
				var after: Array = mine.duplicate()
				if not after.has(String(Db.sp(String(id)).get("element", ""))):
					after.append(String(Db.sp(String(id)).get("element", "")))
				var n: int = Db.reactions_between(after).size()
				if n > best_new:
					best_new = n
					best = String(id)
			Run.recruit(best)
		"poder":
			# O bot aprende o poder MAIS BARATO que ainda nao tem. Sem este
			# ramo ele atravessava a run inteira com o unico Ativo inicial:
			# a taxa de vitoria medida caiu de 43% para 9% e "Ativos por
			# combate" para 1.11 — era o MEDIDOR quebrado, nao o jogo.
			#
			# ESCOLHAS SEGUIDAS (15/09): o momento passou a dar
			# `momentos.poder.escolhas` ofertas em sequencia, porque o Acaso
			# tomou o lugar do segundo momento de Poder e 1 inicial + 1
			# aprendido parava em 2 Ativos — o teto de 3 ficava inalcancavel.
			# Um bot que aprende UM por momento sub-mede o jogo inteiro: e a
			# mao do jogador que encolhe, nao o desenho.
			for k in range(EventGen.power_escolhas()):
				if Run.active_slots_free() <= 0:
					break
				var oferta := EventGen.power_offer(index, k)
				if oferta.is_empty():
					break
				oferta.sort_custom(func(a, b): return int(a["cost"]) < int(b["cost"]))
				Run.learn_active(String(oferta[0]["id"]))
		"troca":
			# o bot troca quando a oferta traz MAIS elementos novos para a
			# equipe; se nao traz, recusa — trocar por trocar so embaralha
			var ofertas := EventGen.trade_offer(index)
			var meus: Array = []
			for u3 in Run.team:
				if not meus.has(u3.element()):
					meus.append(u3.element())
			for of in ofertas:
				var alvo := Run.find_by_uid(int(of["uid"]))
				if alvo == null:
					continue
				var novo_el := String(Db.sp(String(of["species"])).get("element", ""))
				if meus.has(novo_el):
					continue
				var depois: Array = meus.duplicate()
				depois.erase(alvo.element())
				depois.append(novo_el)
				if Db.reactions_between(depois).size() > Db.reactions_between(meus).size():
					Run.trade(alvo, String(of["species"]), of["items"], of["dishes"])
					break
		"cozinha":
			for o in EventGen.kitchen_offer(index):
				var did := String(o["id"])
				if not Run.can_afford_dish(did):
					continue
				var eat: Array = Run.team.filter(func(u): return Run.unit_accepts(u, did))
				if eat.is_empty():
					continue
				eat.sort_custom(func(a, b): return a.dishes_eaten() < b.dishes_eaten())
				Run.cook(did, eat[0])
		"loja":
			for o in EventGen.shop_offer(index):
				match String(o["kind"]):
					"item":
						var iid := String(o["id"])
						var h: Array = Run.team.filter(func(u): return u.accepts_item(iid))
						if not h.is_empty() and Run.spend_ether(int(o["price"])):
							h.sort_custom(func(a, b): return a.items.size() < b.items.size())
							h[0].items.append(iid)
							Run.team_changed.emit()
					"relic":
						if Run.spend_ether(int(o["price"])):
							Run.add_relic(String(o["id"]))
		"acaso":
			var ev := EventGen.chance_offer(index)
			if ev.is_empty():
				return
			var hp2 := 0.0
			for u3 in Run.team:
				hp2 += u3.hp_ratio
			hp2 /= maxf(float(Run.team.size()), 1.0)
			if hp2 > 0.55:
				EventGen.resolve_chance(ev, index)


## Heuristica do bot: aceita risco quando a equipe esta inteira.
func _choose(pair: Array) -> Dictionary:
	if pair.size() == 1:
		return pair[0]
	var hp := 0.0
	for u in Run.team:
		hp += u.hp_ratio
	hp /= maxf(float(Run.team.size()), 1.0)
	var best: Dictionary = pair[0]
	var best_score := -INF
	for n in pair:
		var s2: float = float(int(n.get("rewards", {}).get("ether", 0)))
		s2 -= float(int(n.get("danger", 0))) * (2.5 if hp < 0.7 else 0.9)
		if s2 > best_score:
			best_score = s2
			best = n
	return best


func _fight(node: Dictionary) -> Dictionary:
	var sim := CombatBuilder.build(node, Run.seed_value * 31 + Run.node_index)
	var casts := 0
	while not sim.finished:
		sim.step()
		# o bot lanca o Ativo mais caro que couber -- "usar e melhor que guardar"
		for aid in _by_cost_desc():
			if sim.can_cast(aid):
				sim.cast_active(aid, _best_aim(sim, aid), _best_target(sim), "GELO")
				casts += 1
				break
		sim.drain_events()
	CombatBuilder.writeback(sim)
	var log := sim.combat_log()
	var alive_p := sim.alive_units(0).size()
	var alive_e := sim.alive_units(1).size()
	var roles_p: Array = []
	for u in sim.alive_units(0):
		roles_p.append(u.role)
	var roles_e: Array = []
	for u in sim.alive_units(1):
		roles_e.append(u.role)
	combats.append({"node": Run.node_index, "duration": sim.now,
		"reactions": int(log["total_reactions"]), "actives": casts,
		"won": sim.winner == CombatSim.Winner.PLAYER,
		"timeout": String(log["reason"]).begins_with("tempo"),
		# O CHEFE TEM TETO DE TEMPO PROPRIO (combat.boss_duration), entao juntar
		# a briga dele com as de passagem numa media so escondia uma
		# distribuicao bimodal: o relatorio dizia "5,6% no relogio" sem dizer
		# que quase todo o excedente era chefe.
		"chefe": String(node.get("type", "")) == "chefe",
		# AS DUAS FAIXAS DO GDD 17.4. "Reacoes por combate" tem alvo 25–45 para a
		# build de REACAO e 5–12 para a de RESSONANCIA — e ate 15/09 o medidor
		# juntava tudo numa faixa de 5 a 45, larga demais para poder falhar.
		#
		# O corte e o PESO ELEMENTAL MAXIMO, nao "tem alguma ressonancia acesa":
		# um Eco custa 2 de peso, que qualquer time de quatro corpos acende por
		# acidente sem deixar de ser um time espalhado. Medido com o criterio
		# frouxo, a "build de ressonancia" dava 49 reacoes por combate contra um
		# alvo de 5–12 — porque nao era build de ressonancia nenhuma. O que o
		# GDD chama de build de ressonancia e a CONCENTRACAO, e concentracao se
		# le no peso; o limiar sai de resonances.json (thresholds.coro).
		"peso_max": _peso_maximo(),
		"alive_p": alive_p, "alive_e": alive_e,
		"roles_p": "/".join(roles_p), "roles_e": "/".join(roles_e)})
	var won: bool = sim.winner == CombatSim.Winner.PLAYER
	if won:
		var rw: Dictionary = node.get("rewards", {})
		Run.add_ether(int(rw.get("ether", 0)))
	else:
		Run.defeated = true
	return {"won": won}


## Maior Peso Elemental da equipe agora — o eixo de CONCENTRACAO do GDD 5.
func _peso_maximo() -> int:
	var maior := 0
	for v in Run.elemental_weight().values():
		maior = maxi(maior, int(v))
	return maior


func _by_cost_desc() -> Array:
	var a := Run.actives.duplicate()
	a.sort_custom(func(x, y): return int(Db.actives[x]["cost"]) > int(Db.actives[y]["cost"]))
	return a


func _best_target(sim: CombatSim) -> SimUnit:
	var foes := sim.alive_units(1)
	if foes.is_empty():
		return null
	var best: SimUnit = foes[0]
	for f in foes:
		if f.aura.total_ua() > best.aura.total_ua():
			best = f
	return best


## Mira no lado CERTO. O bot mirava sempre no centroide inimigo, o que jogava
## a cura de area (Orvalho, Circulo de Seiva) em cima dos inimigos — o Ativo
## saia, a metrica contava, e ninguem era curado.
func _best_aim(sim: CombatSim, active_id: String = "") -> Vector2:
	var mode := String(Db.actives.get(active_id, {}).get("aim", ""))
	var side: int = 0 if mode.begins_with("ally") else 1
	var pool := sim.alive_units(side)
	if pool.is_empty():
		return Vector2.ZERO
	# centroide de quem mais interessa: os aliados MAIS FERIDOS quando e cura
	if side == 0:
		pool.sort_custom(func(a, b): return a.hp_pct() < b.hp_pct())
		pool = pool.slice(0, mini(3, pool.size()))
	var c := Vector2.ZERO
	for f in pool:
		c += f.pos
	return c / float(pool.size())







# --- relatorio -------------------------------------------------------------

## O PROTOCOLO DE MEDICAO (revisao 15/09). A faixa de vitoria que o GDD 17.4
## julga tem 10 pontos de largura. Com n runs, a margem de 95% de uma proporcao
## e 1.96*sqrt(p(1-p)/n): 200 runs dao +-6,7 pontos e 1000 dao +-3,0. Abaixo de
## 1000 o instrumento nao separa "no alvo" de "fora do alvo", e qualquer decisao
## de balanceamento tirada dali e tomada em cima de ruido.
const MIN_RUNS := 1000

## Tolerancia de LEITURA da mediana. Era o ultimo numero de julgamento que
## sobrava num .gd; desde 16/09 vem de data/tuning.json
## (targets.median_combat_duration_tol), como todo o resto do bloco. O padrao
## de 0.21 fica aqui so como rede se a chave sumir dos dados.
const TOL_MEDIANA_PADRAO := 0.21


func _alvo(chave: String, padrao: float) -> float:
	return float(Db.tuning.get("targets", {}).get(chave, padrao))


func _faixa(chave: String, lo: float, hi: float) -> Array:
	var f: Array = Db.tuning.get("targets", {}).get(chave, [])
	return [float(f[0]), float(f[1])] if f.size() == 2 else [lo, hi]


func _media(lista: Array, campo: String) -> float:
	if lista.is_empty():
		return 0.0
	var s := 0.0
	for c in lista:
		s += float(c[campo])
	return s / float(lista.size())


## Metodo nomeado em vez de lambda: o parser do GDScript 4.7 nao aceita lambda
## multilinha como argumento, e a comparacao de duas divisoes numa linha so
## passava de 120 colunas.
func _taxa_maior(a: Variant, b: Variant, tab: Dictionary) -> bool:
	var ta: float = float(tab[a][0]) / maxf(float(tab[a][1]), 1.0)
	var tb: float = float(tab[b][0]) / maxf(float(tab[b][1]), 1.0)
	return ta > tb


func _fracao(lista: Array, campo: String) -> float:
	if lista.is_empty():
		return 0.0
	var k := 0
	for c in lista:
		if bool(c[campo]):
			k += 1
	return float(k) / float(lista.size())


func _report(dt: int) -> void:
	var wins := 0
	var nodes := 0.0
	for r in rows:
		if bool(r["won"]):
			wins += 1
		nodes += float(r["node"])
	var durations: Array = []
	for c in combats:
		durations.append(float(c["duration"]))
	durations.sort()
	var median: float = durations[durations.size() / 2] if not durations.is_empty() else 0.0
	var normais: Array = combats.filter(func(c): return not bool(c["chefe"]))
	var chefes: Array = combats.filter(func(c): return bool(c["chefe"]))
	var coro: int = int(Db.resonance_thresholds.get("coro", 4))
	var por_reacao: Array = normais.filter(func(c): return int(c["peso_max"]) < coro)
	var por_resson: Array = normais.filter(func(c): return int(c["peso_max"]) >= coro)

	print("")
	print("runs: %d em %d ms  (%.1f ms/run)" % [rows.size(), dt, float(dt) / float(maxi(rows.size(), 1))])
	print("combates simulados: %d  (%d normais, %d de chefe)"
		% [combats.size(), normais.size(), chefes.size()])
	print("")
	# OS ALVOS SAO DADO (principio 22.1). Ate 15/09 os limiares estavam escritos
	# a mao nesta funcao — 0.35/0.45, 22/34, 0.06, 1.5/2.5, 5/45 — enquanto o
	# bloco `targets` de data/tuning.json era DECORATIVO: oito constantes que
	# nenhum .gd lia, num projeto cujo primeiro principio e que numero de
	# balanceamento nao mora em codigo. Agora mexer no alvo e mexer no dado.
	var win: float = float(wins) / float(maxi(rows.size(), 1))
	var f_win := [_alvo("winrate_experienced_min", 0.35),
		_alvo("winrate_experienced_max", 0.45)]
	var alvo_dur := _alvo("median_combat_duration", 28.0)
	var tol_dur := _alvo("median_combat_duration_tol", TOL_MEDIANA_PADRAO)
	var to_max := _alvo("timeout_rate_max", 0.06)
	var a_lo := _alvo("actives_per_combat_min", 1.5)
	var a_hi := _alvo("actives_per_combat_max", 2.5)
	var f_rx := _faixa("reactions_per_combat_reaction_build", 25.0, 45.0)
	var f_rs := _faixa("reactions_per_combat_resonance_build", 5.0, 12.0)

	print("%-42s %-14s %s" % ["MÉTRICA (GDD §17.4)", "ALVO", "MEDIDO"])
	print("-".repeat(78))
	_line("Taxa de vitória da run", "%.0f–%.0f%%" % [f_win[0] * 100.0, f_win[1] * 100.0],
		"%.0f%%" % (win * 100.0), win, f_win[0], f_win[1])
	_line("Duração de combate (mediana)", "%.0f s ±%.0f%%" % [alvo_dur, tol_dur * 100.0],
		"%.1f s" % median, median,
		alvo_dur * (1.0 - tol_dur), alvo_dur * (1.0 + tol_dur))
	# DUAS LINHAS, e nao uma media. O chefe tem teto proprio desde 04/09
	# (combat.boss_duration = 90 s contra 45 s), entao juntar os dois grupos
	# esconde uma distribuicao bimodal: a media so fica dentro do alvo porque as
	# lutas de passagem sao muitas.
	_line("Relógio · lutas normais", "< %.0f%%" % (to_max * 100.0),
		"%.1f%%" % (_fracao(normais, "timeout") * 100.0),
		_fracao(normais, "timeout"), 0.0, to_max)
	_info("Relógio · chefe", "(teto próprio)",
		"%.1f%%" % (_fracao(chefes, "timeout") * 100.0))
	_line("Ativos por combate · lutas normais", "%.1f–%.1f" % [a_lo, a_hi],
		"%.2f" % _media(normais, "actives"), _media(normais, "actives"), a_lo, a_hi)
	_info("Ativos por combate · chefe", "(sem alvo)", "%.2f" % _media(chefes, "actives"))
	_line("Reações · build de reação (n=%d)" % por_reacao.size(),
		"%.0f–%.0f" % [f_rx[0], f_rx[1]], "%.1f" % _media(por_reacao, "reactions"),
		_media(por_reacao, "reactions"), f_rx[0], f_rx[1])
	if por_resson.is_empty():
		_info("Reações · build de ressonância", "%.0f–%.0f" % [f_rs[0], f_rs[1]],
			"— nenhum combate com Peso %d+ (o bot recruta por diversidade)" % coro)
	else:
		_line("Reações · build de ressonância (n=%d)" % por_resson.size(),
			"%.0f–%.0f" % [f_rs[0], f_rs[1]], "%.1f" % _media(por_resson, "reactions"),
			_media(por_resson, "reactions"), f_rs[0], f_rs[1])
	# GDD 23.1 -- "a comida importa?". Com Nutricao no lugar da Manutencao, a
	# pergunta vira: o sistema e usado, ou da para ignorar a cozinha inteira?
	var dishes := 0.0
	var cooked_runs := 0
	for r2 in rows:
		dishes += float(r2.get("dishes", 0))
		if int(r2.get("dishes", 0)) > 0:
			cooked_runs += 1
	var cooked_ratio: float = float(cooked_runs) / float(maxi(rows.size(), 1))
	_line("Runs que cozinharam ao menos 1 prato", "> 70%", "%.0f%%" % (cooked_ratio * 100.0),
		cooked_ratio, 0.70, 1.01)
	print("%-42s %-14s %.1f" % ["Pratos por run (média)", "—",
		dishes / float(maxi(rows.size(), 1))])
	print("-".repeat(78))
	print("nó médio alcançado: %.1f / %d" % [nodes / float(maxi(rows.size(), 1)), Run.total_nodes()])

	# A MARGEM DA MEDICAO, impressa junto do numero que ela qualifica.
	var margem: float = 1.96 * sqrt(maxf(win * (1.0 - win), 0.0001)
		/ float(maxi(rows.size(), 1)))
	print("margem da taxa de vitória (95%%): ±%.1f pontos  ·  faixa julgada: %.0f pontos"
		% [margem * 100.0, (f_win[1] - f_win[0]) * 100.0])
	if rows.size() < MIN_RUNS:
		print("AVISO: com %d runs a margem NAO resolve a faixa. Use --runs=%d antes de decidir."
			% [rows.size(), MIN_RUNS])

	# GDD 23.1 -- "existe uma build dominante?" / "algum elemento e lixo?"
	var comp: Dictionary = {}
	for r in rows:
		if bool(r["won"]):
			comp[r["elements"]] = int(comp.get(r["elements"], 0)) + 1
	if not comp.is_empty():
		print("")
		print("composições vencedoras (elementos em ordem — ver els.sort()):")
		var keys := comp.keys()
		keys.sort_custom(func(a, b): return int(comp[a]) > int(comp[b]))
		for k in keys:
			print("   %-26s %d  (%.0f%% das vitórias)" % [k, int(comp[k]),
				float(comp[k]) / float(maxi(wins, 1)) * 100.0])

	# VITORIA POR ESPECIE INICIAL — o A/B que a composicao vencedora nao sabe
	# fazer. `DUOS[seed % 10]` com seed = 1000 + i*17: 17 e 10 sao coprimos,
	# entao os dez pares recebem o mesmo numero de runs e cada especie entra em
	# quatro deles. Medir presenca em composicao VENCEDORA mede o que sobrou no
	# fim; isto mede o que foi ATRIBUIDO no comeco, e foi o que derrubou a
	# alegacao de que "apollo decide a run" (ele estava abaixo da media).
	# O `n` vai impresso ao lado porque a conclusao depende dele.
	var by_sp: Dictionary = {}
	for r5 in rows:
		for sp in String(r5["duo"]).split("+"):
			if not by_sp.has(sp):
				by_sp[sp] = [0, 0]
			by_sp[sp][1] += 1
			if bool(r5["won"]):
				by_sp[sp][0] += 1
	if not by_sp.is_empty():
		print("")
		print("vitória por espécie inicial (base: %.0f%%):" % (win * 100.0))
		var sp_keys: Array = by_sp.keys()
		sp_keys.sort_custom(_taxa_maior.bind(by_sp))
		for s in sp_keys:
			var g: int = int(by_sp[s][0])
			var t: int = int(by_sp[s][1])
			print("   %-14s %5.1f%%  (%d/%d)" % [s, 100.0 * float(g) / maxf(float(t), 1.0), g, t])

	print("")
	# Recruta e Poder aparecem MAIS DE UMA VEZ por run, entao o numero deles e
	# "ocorrencias por 100 runs" e passa de 100%. Os que aparecem uma vez so
	# (loja, cozinha, troca) sao alcance de verdade — e sao esses que importam
	# para saber se um momento esta escondido num passo que ninguem alcanca.
	print("alcance dos momentos (ocorrencias por 100 runs):")
	for k in ["recruta", "poder", "loja", "cozinha", "troca", "acaso"]:
		if not momento_visto.has(k):
			continue
		var n_m: int = int(momento_visto[k])
		print("   %-9s %3d de %d runs  (%d%%)" % [k, n_m, runs,
			roundi(100.0 * float(n_m) / maxf(float(runs), 1.0))])

	# ALCANCE POR PASSO. O alcance por TIPO nao basta para decidir onde por um
	# momento novo: "loja 38%" nao diz se o problema e a loja ou o passo 8.
	print("")
	print("alcance por passo (quantas runs chegam a cada momento):")
	var passos: Array = momento_passo.keys()
	passos.sort()
	for pa in passos:
		var n_p: int = int(momento_passo[pa])
		print("   passo %d  %-9s %3d de %d  (%d%%)" % [int(pa),
			EventGen.kind_after(int(pa)), n_p, runs,
			roundi(100.0 * float(n_p) / maxf(float(runs), 1.0))])

	# GDD 23.1 — "onde as runs morrem?": histograma de mortes por no
	var deaths: Dictionary = {}
	for r3 in rows:
		if not bool(r3["won"]):
			deaths[int(r3["node"])] = int(deaths.get(int(r3["node"]), 0)) + 1
	print("
onde as runs morrem (no -> mortes):")
	var dk: Array = deaths.keys()
	dk.sort()
	for k in dk:
		var bar := "#".repeat(int(deaths[k]) * 40 / maxi(rows.size(), 1))
		print("   no %d  %3d  %s" % [int(k), int(deaths[k]), bar])

	var n1_total := 0
	var n1_win := 0
	for c2 in combats:
		if int(c2["node"]) == 1:
			n1_total += 1
			if bool(c2["won"]):
				n1_win += 1
	if n1_total > 0:
		print("vitoria no PRIMEIRO combate: %d%%  (%d/%d)"
			% [n1_win * 100 / n1_total, n1_win, n1_total])

	print("
vitoria por dupla inicial:")
	var by_duo: Dictionary = {}
	for r4 in rows:
		var d2: String = String(r4["duo"])
		if not by_duo.has(d2):
			by_duo[d2] = [0, 0]
		by_duo[d2][1] += 1
		if bool(r4["won"]):
			by_duo[d2][0] += 1
	var duo_keys: Array = by_duo.keys()
	duo_keys.sort_custom(func(a, b):
		return float(by_duo[a][0]) / maxf(float(by_duo[a][1]), 1.0) 			> float(by_duo[b][0]) / maxf(float(by_duo[b][1]), 1.0))
	for d3 in duo_keys:
		print("   %-24s %3d%%  (%d/%d)" % [d3,
			int(by_duo[d3][0]) * 100 / maxi(int(by_duo[d3][1]), 1),
			int(by_duo[d3][0]), int(by_duo[d3][1])])

	# diagnostico dos impasses: quem sobra vivo quando o relogio estoura?
	var to_list: Array = combats.filter(func(c): return bool(c["timeout"]))
	if not to_list.is_empty():
		var ap := 0.0
		var ae := 0.0
		var stall: Dictionary = {}
		for c in to_list:
			ap += float(c["alive_p"])
			ae += float(c["alive_e"])
			var key: String = "%s  x  %s" % [String(c["roles_p"]), String(c["roles_e"])]
			stall[key] = int(stall.get(key, 0)) + 1
		print("
impasses (%d): media de %.1f vivos seus x %.1f inimigos"
			% [to_list.size(), ap / float(to_list.size()), ae / float(to_list.size())])
		var keys2: Array = stall.keys()
		keys2.sort_custom(func(a, b): return int(stall[a]) > int(stall[b]))
		for i in range(mini(5, keys2.size())):
			print("   %-46s %d" % [String(keys2[i]), int(stall[keys2[i]])])
	print("")


func _line(name: String, target: String, got: String, value: float, lo: float, hi: float) -> void:
	var mark := "  ok" if (value >= lo and value <= hi) else "  <-- FORA DO ALVO"
	print("%-42s %-14s %s%s" % [name, target, got, mark])


## Linha sem julgamento: o numero existe, mas o GDD 17.4 nao tem alvo para ele
## (o chefe tem teto de tempo proprio, entao a media dele nao cabe na mesma
## faixa das lutas de passagem).
func _info(name: String, target: String, got: String) -> void:
	print("%-42s %-14s %s" % [name, target, got])


# O CSV SAI DE UMA LISTA SO (revisao 15/09).
#
# Ate aqui o cabecalho era uma string e a linha era um "%d,%s,..." escrito a
# mao — 12 especificadores para 11 argumentos. O `%` do GDScript, com aridade
# errada, NAO falha: ele devolve o proprio formato. As 400 linhas do arquivo
# saiam literalmente "%d,%s,%d,..." e o unico export de dados da run nunca
# produziu um numero, enquanto o README:32 o anunciava como a ferramenta de
# balanceamento. Com a lista unica a aridade deixa de existir como conceito.
## `duo` entrou junto: a dupla inicial e atribuida por sorteio balanceado
## (DUOS[seed % 10]) e foi a coluna que derrubou a alegacao de que "apollo decide
## a run". Sem ela o CSV nao permite refazer fora do Godot a unica analise do
## relatorio que mudou uma conclusao.
const CSV_COLUNAS := ["seed", "duo", "won", "node", "combats", "team", "bond",
	"elements", "resonances", "relics", "ether", "dishes"]


func _write_csv() -> void:
	var f := FileAccess.open(csv_path, FileAccess.WRITE)
	if f == null:
		printerr("nao consegui escrever ", csv_path)
		return
	f.store_line(",".join(CSV_COLUNAS))
	for r in rows:
		var campos: Array = []
		for c in CSV_COLUNAS:
			var v: Variant = r.get(c, "")
			campos.append(("1" if bool(v) else "0") if typeof(v) == TYPE_BOOL else str(v))
		f.store_line(",".join(campos))
	f.close()
	print("CSV: ", ProjectSettings.globalize_path(csv_path))
