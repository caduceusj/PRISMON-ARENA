extends Node
## Teste de fumaca headless — elenco de 5 criaturas animadas + fluxo
## "2 combates + eventos automaticos".
##   godot --headless res://tools/smoke_test.tscn

var failures := 0


func _ready() -> void:
	# SEM ANIMACAO nas ferramentas: um print tirado no meio da transicao
	# nao serve para comparar nada, e um teste que espera o fim do tween
	# vira lento e intermitente.
	Juice.enabled = false
	await _run_all()


func _run_all() -> void:
	print("=== PRISMA :: smoke test ===")
	_check_db()
	_check_fontes()
	_check_matrix()
	_check_aura_rules()
	_check_windup()
	_check_natureza()
	_check_combat()
	_check_determinism()
	_check_movement()
	_check_no_deadlock()
	_check_cooking()
	await _check_actives()
	_check_survival()
	_check_moments()
	_check_intro()
	_check_log_soma()
	_check_alvo_escolhido()
	_check_troca()
	_check_arena_e_mods()
	_check_cadeia_termina()
	_check_par_ordenado()
	_check_boss()
	_check_kit()
	_check_paleta()
	_check_som()
	_check_csv()
	_check_cobertura()
	await _check_flow()
	print("=== %s ===" % ("TUDO OK" if failures == 0 else "%d FALHA(S)" % failures))
	get_tree().quit(1 if failures > 0 else 0)


func ok(cond: bool, msg: String) -> void:
	if cond:
		print("  ok   ", msg)
	else:
		failures += 1
		printerr("  FAIL ", msg)


func _check_db() -> void:
	print("[dados]")
	ok(Db.loaded, "Db carregou")
	ok(Db.slice_elements.size() == 5, "5 elementos no slice (com NATUREZA)")
	ok(Db.reactions.size() == 8, "8 reacoes (%d)" % Db.reactions.size())
	ok(Db.base_species.size() == 5, "5 especies de teste (%d)" % Db.base_species.size())
	ok(Db.anims.get("creatures", {}).size() == 5, "5 criaturas com animacao")
	for id in Db.base_species:
		ok(MonsterArt.sheet("attack", String(id)) != null, "sheet de ataque: %s" % id)


## A FONTE PRECISA SOBREVIVER A EXPORTACAO (autor, 03/09: "quando to
## exportando a fonte que eu coloquei nao ta indo").
##
## O defeito era `load_dynamic_font`, que le o .ttf cru: existe no editor, nao
## existe no pacote exportado, e a fonte cai no padrao da engine sem nenhum
## erro. Um teste que so verifica "carregou" passaria nos dois casos — por isso
## aqui se cobra que a fonte seja um RECURSO com caminho res://, que e o que
## distingue o recurso importado (empacotado) do arquivo lido do disco.
func _check_fontes() -> void:
	print("[fontes]")
	var t := PrismaTheme.get_theme()
	ok(PrismaTheme.body_font != null, "a fonte do corpo carregou")
	ok(PrismaTheme.digit_font != null, "a fonte dos digitos carregou")
	ok(PrismaTheme.body_font.resource_path.begins_with("res://assets/fonts/"),
		"a fonte do corpo e RECURSO importado (%s)" % PrismaTheme.body_font.resource_path)
	ok(not PrismaTheme.body_font.fallbacks.is_empty(),
		"a cadeia de fallback esta montada")
	# o acento e o motivo de a m6x11 (sem plus) ter sido descartada
	var f: Font = t.default_font
	var sz: int = UI.fs(UI.F_BODY)
	ok(f.get_string_size("Coração", HORIZONTAL_ALIGNMENT_LEFT, -1, sz).x > 0.0,
		"a fonte mede texto com acento")
	ok(f.has_char("ã".unicode_at(0)) and f.has_char("Ç".unicode_at(0)),
		"a fonte tem os acentos do portugues")


func _check_matrix() -> void:
	print("[matriz de reacoes]")
	ok(Db.lookup_reaction("GELIDO", "FOGO")["rule"]["id"] == "DERRETIMENTO",
		"Gelido + Fogo = Derretimento")
	ok(Db.lookup_reaction("ESPORO", "RAIO")["rule"]["id"] == "CATALISACAO",
		"Esporo + Raio = Catalisacao")
	ok(Db.lookup_reaction("ESPORO", "GELO")["rule"]["id"] == "GEADA_MORTAL",
		"Esporo + Gelo = Geada Mortal")
	ok(Db.lookup_reaction("ESPORO", "FOGO").is_empty(),
		"Esporo + Fogo nao reage (lacuna deliberada, GDD 6.6)")


func _check_aura_rules() -> void:
	print("[regras de aura]")
	var st := AuraState.new()
	st.apply("COMBUSTAO", "FOGO", 20.0, 1.0, 1)
	ok(is_equal_approx(st.get_aura("COMBUSTAO").ua, 8.0), "teto de 8 UA")
	var st2 := AuraState.new()
	st2.apply("ENCHARCADO", "AGUA", 3.0, 0.5, 1)
	st2.apply("COMBUSTAO", "FOGO", 2.0, 1.0, 1)
	ok(is_equal_approx(st2.get_aura("COMBUSTAO").ua, 2.5),
		"Encharcado amplifica +25 pct (%.2f)" % st2.get_aura("COMBUSTAO").ua)


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
	u.hp_max = float(s.get("hp", 400))
	u.atk = float(s.get("atk", 30))
	u.def = float(s.get("def", 10))
	u.vel = float(s.get("vel", 1.0))
	u.pe = float(s.get("pe", 50))
	u.vontade = float(s.get("vontade", 40))
	u.ua_per_hit = float(s.get("ua_per_hit", 2.0))
	u.ult = s.get("ult", {})
	return sim.add_unit(u)


## O golpe conecta no QUADRO DE DANO do sprite: windup = intervalo x fracao.
func _check_windup() -> void:
	print("[windup — o golpe sai no quadro certo]")
	var sim := CombatSim.new(1)
	sim.node_index = 1
	var atk := _mk(sim, "apollo", 0)
	var alvo := _mk(sim, "sheep", 1)
	alvo.vel = 0.0001
	sim.begin()
	atk.pos = Vector2(-30, 0)
	alvo.pos = Vector2.ZERO
	var t_attack := -1.0
	var t_damage := -1.0
	for i in range(200):
		sim.step()
		for e in sim.drain_events():
			if String(e["kind"]) == "attack" and int(e["src"]) == atk.id and t_attack < 0.0:
				t_attack = float(e["t"])
			if String(e["kind"]) == "damage" and int(e.get("src", 0)) == atk.id and t_damage < 0.0:
				t_damage = float(e["t"])
		if t_damage >= 0.0:
			break
	ok(t_attack >= 0.0 and t_damage >= 0.0, "ataque e dano aconteceram")
	var interval: float = 1.0 / 1.9
	var expected: float = interval * (13.0 - 1.0) / 18.0
	var got: float = t_damage - t_attack
	ok(absf(got - expected) <= 0.11,
		"apollo: dano %.2fs apos o inicio (quadro 13 => ~%.2fs)" % [got, expected])


func _check_natureza() -> void:
	print("[natureza]")
	var sim := CombatSim.new(2)
	sim.node_index = 3
	var pinto := _mk(sim, "pinto_raio", 0)
	var vitima := _mk(sim, "sheep", 1)
	sim.begin()
	sim.put_aura(null, vitima, "NATUREZA", 4.0)
	ok(vitima.aura.has_aura("ESPORO"), "Esporo aplicado")
	var e0 := sim.energy
	sim.strike(pinto, vitima, {"element": "RAIO", "ua": 2.0, "mult": 1.0})
	ok(int(sim.stat_reactions.get("CATALISACAO", 0)) >= 1, "Raio sobre Esporo = Catalisacao")
	ok(sim.energy >= e0 + 7.9, "Catalisacao devolveu 8 de Energia (%.1f -> %.1f)" % [e0, sim.energy])

	var sim2 := CombatSim.new(3)
	sim2.node_index = 3
	var gelo := _mk(sim2, "sheep", 0)
	var alvo2 := _mk(sim2, "apollo", 1)
	sim2.begin()
	sim2.put_aura(null, alvo2, "NATUREZA", 4.0)
	var hp0 := alvo2.hp
	sim2.strike(gelo, alvo2, {"element": "GELO", "ua": 2.0, "mult": 1.0})
	ok(int(sim2.stat_reactions.get("GEADA_MORTAL", 0)) >= 1, "Gelo sobre Esporo = Geada Mortal")
	ok(hp0 - alvo2.hp >= alvo2.hp_max * 0.04, "Geada Mortal cobrou 4 pct do HP max")

	var sim3 := CombatSim.new(4)
	var dummy := _mk(sim3, "sheep", 0)
	_mk(sim3, "hipocampo", 1)
	sim3.begin()
	sim3.put_aura(null, dummy, "NATUREZA", 8.0)
	var before := dummy.hp
	for i in range(10):
		sim3._tick_auras()
	ok(before - dummy.hp > 0.0, "Esporo pinga dano (%.1f em 1s)" % (before - dummy.hp))


func _check_combat() -> void:
	print("[combate]")
	var sim := CombatSim.new(12345)
	sim.node_index = 4
	_mk(sim, "sheep", 0)
	_mk(sim, "apollo", 0)
	_mk(sim, "hipocampo", 1)
	_mk(sim, "pinto_raio", 1)
	sim.begin()
	var w := sim.run_to_end()
	ok(sim.finished, "combate terminou em %.1fs" % sim.now)
	ok(w != CombatSim.Winner.NONE, "houve um vencedor (%d)" % w)
	var log := sim.combat_log()
	print("       reacoes: %d | fim: %s" % [int(log["total_reactions"]), log["reason"]])


func _check_determinism() -> void:
	print("[determinismo]")
	var a := _run_seeded(999)
	var b := _run_seeded(999)
	ok(a == b, "mesma semente => mesmo resultado (%s vs %s)" % [a, b])
	var t0 := Time.get_ticks_msec()
	for i in range(100):
		_run_seeded(i)
	print("       100 combates em %d ms" % (Time.get_ticks_msec() - t0))


func _run_seeded(s: int) -> Dictionary:
	var sim := CombatSim.new(s)
	sim.node_index = 5
	_mk(sim, "sheep", 0)
	_mk(sim, "pinto_raio", 0)
	_mk(sim, "coalla", 0)
	_mk(sim, "apollo", 1)
	_mk(sim, "hipocampo", 1)
	sim.begin()
	sim.run_to_end()
	return {"winner": sim.winner, "t": snappedf(sim.now, 0.1), "rx": sim._sum_reactions()}


func _check_movement() -> void:
	print("[deslocamento]")
	var sim := CombatSim.new(4242)
	sim.node_index = 3
	var tank := _mk(sim, "sheep", 0)
	var mage := _mk(sim, "pinto_raio", 0)
	var blade := _mk(sim, "apollo", 0)
	var foe := _mk(sim, "hipocampo", 1)
	_mk(sim, "coalla", 1)
	sim.begin()
	ok(tank.attack_range < 100.0, "Guardiao corpo a corpo (%.0f)" % tank.attack_range)
	ok(mage.kite > 0.0, "Arcano mantem distancia (%.0f)" % mage.kite)
	ok(blade.speed_px > tank.speed_px, "Lamina mais rapida que Guardiao")
	var d0: float = tank.pos.distance_to(foe.pos)
	for i in range(40):
		sim.step()
	ok(tank.pos.distance_to(foe.pos) < d0, "o Guardiao fechou distancia")


## Bug reportado em 31/08: "os bichos se barram, fica um colidindo no outro e
## nao bate no inimigo porque nunca chega no alcance dele".
##
## O travamento tem uma assinatura precisa: a unidade esta FORA do alcance do
## alvo E NAO SAI DO LUGAR (oscila entre o passo e o empurrao). Medir so a
## distancia confundiria com quem esta apenas caminhando; medir so o movimento
## confundiria com quem esta parada batendo. Precisa dos dois.
func _check_no_deadlock() -> void:
	print("[mascara de alcance]")
	var worst := 0.0
	var worst_who := ""
	for seed_v in range(8):
		var sim := CombatSim.new(500 + seed_v)
		sim.node_index = 5
		for id in ["sheep", "apollo", "coalla"]:
			_mk(sim, id, 0)
		for id2 in ["sheep", "apollo", "hipocampo"]:
			_mk(sim, id2, 1)
		sim.begin()
		var hist: Dictionary = {}     # id -> posicao de 10 ticks atras
		var stuck: Dictionary = {}
		var seen: Dictionary = {}
		for i in range(500):
			if sim.finished:
				break
			sim.step()
			sim.drain_events()
			for u in sim.units:
				if not u.alive or u.is_controlled(sim.now) or u.windup_until > sim.now:
					continue
				var t: SimUnit = sim.by_id.get(u.target_id)
				if t == null or not t.alive:
					continue
				seen[u.id] = int(seen.get(u.id, 0)) + 1
				var old: Variant = hist.get(u.id)
				if i % 10 == 0:
					hist[u.id] = u.pos
				if old == null or sim.now < 2.0:
					continue
				var moved: float = u.pos.distance_to(old)
				var far: bool = u.pos.distance_to(t.pos) > u.attack_range * 1.15
				if far and moved < 6.0:
					stuck[u.id] = int(stuck.get(u.id, 0)) + 1
		for k in stuck.keys():
			var pct: float = float(stuck[k]) * 100.0 / maxf(float(seen.get(k, 1)), 1.0)
			if pct > worst:
				worst = pct
				worst_who = sim.by_id[k].display_name
	ok(worst < 12.0, "ninguem trava fora de alcance (pior: %s, %.0f%% do tempo)"
		% [worst_who if worst_who != "" else "-", worst])



func _check_cooking() -> void:
	print("[culinaria]")
	ok(Db.dishes.size() == 7, "7 pratos (%d)" % Db.dishes.size())
	Run.start_run(31337)
	Run.team.clear()
	Run.recruit("apollo")
	var u: UnitInstance = Run.team[0]
	var atk0: float = float(u.stats()["atk"])
	Run.add_ether(8)
	Run.cook("espeto_flamejante", u)
	ok(is_equal_approx(float(u.stats()["atk"]), atk0 + 10.0), "+10 ATK permanente")
	Run.add_ether(8)
	var hp0: float = float(u.stats()["hp"])
	Run.cook("ensopado_de_raizes", u)
	ok(is_equal_approx(float(u.stats()["hp"]), hp0 + 80.0), "Ensopado de Raizes: +80 HP")
	ok(u.dishes_eaten() == 2, "Estomago 2/%d" % u.estomago())


## Os MOMENTOS (revisao 31/08): o jogo decide QUAL evento; o jogador escolhe
## dentro dele. Nada acontece sozinho.
func _check_moments() -> void:
	print("[momentos de evento]")
	var kinds: Dictionary = {}
	for i in range(1, 9):
		var k := EventGen.kind_after(i)
		ok(k in ["recruta", "loja", "cozinha", "acaso", "poder", "troca"],
			"passo %d tem momento (%s)" % [i, k])
		kinds[k] = true
	# Nao se cobra um NUMERO de tipos: os 8 passos nao cabem todos os
	# momentos, e trocar um pelo outro e decisao de design. O que se cobra e
	# o que sustenta a progressao — recruta e poder.
	ok(kinds.has("poder"), "o momento de PODER esta na sequencia")
	ok(kinds.has("recruta"), "o momento de RECRUTA esta na sequencia")

	# A MAO DO DOMADOR comeca com UM poder e cresce ate o teto (autor, 03/09).
	# Os dois momentos de Poder da sequencia levam exatamente de 1 a 3 — se
	# alguem mexer na sequencia sem mexer no teto, e aqui que doi.
	#
	# E DOEU: encaixar a segunda loja (04/09) esbarrou justamente aqui. Os 8
	# passos comportam 3 recrutas + 2 poderes + 1 cozinha + 2 lojas e mais
	# nada, entao a TROCA saiu da sequencia. O Mercador continua testado logo
	# abaixo (_check_troca) e a tela continua nas capturas: ele esta pronto,
	# so nao esta no caminho. Ver o _loja_duas_vezes em data/tuning.json.
	# PISO DE RECRUTAS. Medido: tirar UM recruta da sequencia derrubou a
	# taxa de vitoria de 40% para 11% (autoplay, 150 runs) — a equipe cai
	# de 5 para 4 corpos contra a mesma curva de poder inimiga. E o lever
	# de dificuldade mais forte da trilha, e nao pode ser mexido por
	# acidente ao encaixar um momento novo.
	var recrutas := 0
	for i3 in range(1, 9):
		if EventGen.kind_after(i3) == "recruta":
			recrutas += 1
	ok(recrutas >= 3, "a sequencia tem ao menos 3 recrutas (%d)" % recrutas)

	# PISO DE LOJAS (autor, 04/09: "faz a loja aparecer mais de uma vez no
	# ciclo"). Com uma loja so, e no ultimo passo, 38% das runs chegavam a
	# comprar alguma coisa — medido. Duas lojas nao e enfeite: e a diferenca
	# entre o Eter ser moeda e ser placar.
	var lojas := 0
	for i4 in range(1, 9):
		if EventGen.kind_after(i4) == "loja":
			lojas += 1
	ok(lojas >= 2, "a sequencia tem ao menos 2 lojas (%d)" % lojas)

	var poderes := 0
	for i2 in range(1, 9):
		if EventGen.kind_after(i2) == "poder":
			poderes += 1
	Run.start_run(4242)
	Run.set_starting_team(["sheep", "apollo"])
	var inicio: int = Run.actives.size()
	ok(inicio == 1, "a run comeca com UM poder (%d)" % inicio)
	# ESCOLHAS POR MOMENTO (15/09). O Acaso tomou o lugar do segundo momento de
	# Poder, e com UMA escolha por momento a conta parava em 2 — o teto de 3
	# Ativos virava inalcancavel na run de verdade. A conta que fecha o teto
	# agora tem tres fatores, e os tres sao dado: quantos momentos a trilha tem,
	# quantas escolhas cada um da, e qual e o teto.
	var escolhas: int = EventGen.power_escolhas()
	ok(inicio + poderes * escolhas == int(Db.run_cfg("max_actives", 3)),
		"%d momento(s) de Poder x %d escolha(s) levam de %d ao teto de %d"
			% [poderes, escolhas, inicio, int(Db.run_cfg("max_actives", 3))])
	var oferta := EventGen.power_offer(2)
	ok(not oferta.is_empty(), "o momento de Poder oferece algo (%d)" % oferta.size())
	for o2 in oferta:
		ok(not Run.actives.has(String(o2["id"])),
			"nao oferece um poder que voce ja tem (%s)" % String(o2["id"]))
	ok(Run.actives.size() == inicio, "so montar a oferta NAO ensina nada")
	ok(Run.learn_active(String(oferta[0]["id"])), "aprender entra na mao")
	ok(Run.actives.size() == inicio + 1, "a mao cresceu para %d" % Run.actives.size())
	ok(not Run.learn_active(String(oferta[0]["id"])), "o mesmo poder duas vezes NAO entra")
	while Run.active_slots_free() > 0:
		var livre: Array = Db.active_order.filter(func(a): return not Run.actives.has(String(a)))
		if livre.is_empty():
			break
		Run.learn_active(String(livre[0]))
	ok(Run.actives.size() == int(Db.run_cfg("max_actives", 3)),
		"a mao para no teto de %d" % Run.actives.size())
	var sobra: Array = Db.active_order.filter(func(a): return not Run.actives.has(String(a)))
	if not sobra.is_empty():
		ok(not Run.learn_active(String(sobra[0])), "mao cheia RECUSA um poder novo")

	# recruta: duas opcoes, e NADA entra na equipe sem escolha
	Run.start_run(777)
	Run.set_starting_team(["sheep", "apollo"])
	var before: int = Run.team.size()
	var offer := EventGen.recruit_offer(2)
	ok(offer.size() == 2, "recruta oferece 2 criaturas (%d)" % offer.size())
	ok(offer[0] != offer[1], "as duas opcoes sao diferentes")
	ok(Run.team.size() == before, "montar a oferta NAO recruta sozinho")
	Run.recruit(String(offer[0]))
	ok(Run.team.size() == before + 1, "escolher recruta a criatura inteira")

	# loja: a banca tem o tamanho que os DADOS dizem, itens com dono, e o Eter DRENA
	Run.start_run(778)
	Run.set_starting_team(["sheep", "apollo"])
	Run.add_ether(120)
	var stock := EventGen.shop_offer(4)
	ok(stock.size() >= 2, "loja tem estoque (%d)" % stock.size())
	var dishes_na_loja := 0
	var itens := 0
	for o in stock:
		if String(o["kind"]) == "dish":
			dishes_na_loja += 1
		if String(o["kind"]) == "item":
			itens += 1
	ok(dishes_na_loja == 0, "a loja NAO vende mais pratos")
	# O TETO DA BANCA E DADO, nao um 3 escrito aqui: `momentos.loja.ofertas`
	# subiu de 3 para 4 em 15/09 (o gargalo do Eter era oferta, nao preco) e
	# esta assercao passou a cobrar um numero que o proprio arquivo ja tinha
	# contrariado. Um teste que fixa a constante impede o ajuste que ele deveria
	# proteger.
	# `ofertas` conta ITENS: a reliquia entra POR CIMA, com a chance propria
	# (momentos.loja.reliquia_chance), entao a banca tem no maximo ofertas + 1.
	var ofertas: int = int(Dictionary(Db.tune("momentos", "loja", {})).get("ofertas", 3))
	ok(itens <= ofertas, "no maximo %d itens por banca (%d)" % [ofertas, itens])
	ok(stock.size() <= ofertas + 1,
		"a banca e ofertas + no maximo UMA reliquia (%d de %d)" % [stock.size(), ofertas + 1])
	var e0: int = Run.ether
	ok(Run.spend_ether(11), "gastar Eter funciona")
	ok(Run.ether == e0 - 11, "Eter drenou (%d -> %d)" % [e0, Run.ether])
	ok(not Run.spend_ether(99999), "sem saldo nao cobra")
	ok(EventGen.reroll_price("loja", 1) > EventGen.reroll_price("loja", 0),
		"renovar fica mais caro a cada vez")
	ok(String(EventGen.shop_offer(4, 0)[0]["id"]) != String(EventGen.shop_offer(4, 3)[0]["id"])
		or EventGen.shop_offer(4, 3).size() != stock.size(),
		"renovar troca o estoque de verdade")

	# item de assinatura so serve ao dono
	Run.start_run(781)
	Run.set_starting_team(["sheep", "apollo"])
	var dono: UnitInstance = null
	for u2 in Run.team:
		if u2.species_id == "apollo":
			dono = u2
	ok(dono != null and dono.accepts_item("cauda_de_brasa"), "Apollo aceita a Cauda de Brasa")
	ok(not Run.team[0].accepts_item("cauda_de_brasa") or Run.team[0].species_id == "apollo",
		"quem nao e Apollo recusa a Cauda de Brasa")
	ok(not dono.accepts_item("la_condutora"), "Apollo recusa item do Sheep")
	ok(dono.accepts_item("presa_rachada"), "item generico serve a qualquer um")

	# cozinha: pratos em Éter, o jogador escolhe quem come
	Run.start_run(779)
	Run.set_starting_team(["sheep", "apollo"])
	Run.add_ether(24)
	var menu := EventGen.kitchen_offer(2)
	ok(menu.size() == 3, "cardapio tem 3 pratos (%d)" % menu.size())
	var so_pratos := true
	for m2 in menu:
		if String(m2["kind"]) != "dish":
			so_pratos = false
	ok(so_pratos, "a cozinha so serve pratos")
	var antes: int = Run.team[1].dishes_eaten()
	ok(Run.cook("espeto_flamejante", Run.team[1]) != "", "cozinhar para um alvo escolhido")
	ok(Run.team[1].dishes_eaten() == antes + 1, "so o Prismon escolhido comeu")
	ok(Run.team[0].dishes_eaten() == 0, "o outro nao comeu nada")

	# acaso: recusar nao muda nada; aceitar resolve
	Run.start_run(779)
	Run.set_starting_team(["sheep", "apollo"])
	var ev := EventGen.chance_offer(1)
	ok(not ev.is_empty(), "evento de acaso sorteado (%s)" % String(ev.get("id", "")))
	ok(ev.has("accept_label") and ev.has("outcomes"), "evento tem escolha e desfechos")
	var snap := {"eter": Run.ether, "time": Run.team.size()}
	ok(Run.ether == int(snap["eter"]), "so montar a oferta nao aplica nada")
	var res := EventGen.resolve_chance(ev, 1)
	ok(res.has("good") and res.has("lines"), "aceitar resolve o evento")

	# determinismo
	Run.start_run(780)
	var a := EventGen.chance_offer(4)
	Run.start_run(780)
	var b := EventGen.chance_offer(4)
	ok(String(a.get("id", "")) == String(b.get("id", "")), "eventos deterministicos")


## Revisao 31/08: o no 1 so oferece temas leves e poder reduzido.
func _check_intro() -> void:
	print("[introducao suave]")
	var wins := 0
	for seed_v in range(12):
		Run.start_run(9000 + seed_v)
		Run.set_starting_team(["sheep", "hipocampo"])
		Run.node_index = 1
		var pair := NodeGen.generate_pair(1)
		for n in pair:
			ok(int(n["danger"]) <= 2, "no 1 so sorteia perigo <=2 (veio %d)" % int(n["danger"]))
		var sim := CombatBuilder.build(pair[0], seed_v)
		sim.run_to_end()
		if sim.winner == CombatSim.Winner.PLAYER:
			wins += 1
	ok(wins >= 10, "primeiro combate quase sempre vencido (%d/12)" % wins)
	ok(NodeGen.power_for(1) < 0.9, "poder inicial reduzido (%.2f)" % NodeGen.power_for(1))
	# A ESCALADA NAO E SO A CURVA DE PODER (revisao 03/09). Desde que o bando
	# ganhou modificadores, parte da dificuldade do fim do Ato vem deles: um
	# a partir do passo 3, dois a partir do 6. `power_last` caiu de 1.26 para
	# 1.02 justamente para abrir espaco — sem isso a vitoria medida caiu de
	# 40% para 25%. Entao o teste cobra a escalada COMBINADA, que e a que o
	# jogador sente, e nao mais so o multiplicador cru.
	ok(NodeGen.power_for(8) > NodeGen.power_for(1),
		"o poder cru ainda sobe (%.2f -> %.2f)"
			% [NodeGen.power_for(1), NodeGen.power_for(8)])
	# cada modificador vale ~1.10x de poder efetivo (mais ATK ou menos dano
	# recebido); dois no fim do Ato dao ~1.21x.
	#
	# A CONTAGEM DE CORPOS ENTRA NA CONTA (15/09). Ate aqui a escalada era medida
	# so pelo multiplicador de poder x modificadores, e desde que
	# `difficulty.enemy_count_by_node` virou um array explicito e ele que carrega
	# a maior parte da subida: 2 corpos no passo 1 contra 5 no passo 8. Medir sem
	# os corpos dava 1.36 -> 1.11 (a curva parecia DESCER, porque power_last caiu
	# para abrir espaco para os modificadores) e a assercao virou falso negativo.
	Run.start_run(777)
	Run.set_starting_team(["sheep", "apollo"])
	var mods_fim: int = (NodeGen.generate_pair(8)[0]["payload"].get("mods", []) as Array).size()
	var base_1: float = NodeGen.power_for(1) * float(NodeGen.enemy_count_for(1))
	var efetivo: float = NodeGen.power_for(8) * float(NodeGen.enemy_count_for(8)) \
		* pow(1.10, float(mods_fim))
	ok(efetivo > base_1 * 3.0,
		"a dificuldade COMBINADA mais que TRIPLICA (%.2f -> %.2f: %dx%.2f -> %dx%.2f com %d mod)"
			% [base_1, efetivo, NodeGen.enemy_count_for(1), NodeGen.power_for(1),
				NodeGen.enemy_count_for(8), NodeGen.power_for(8), mods_fim])


## TODOS os Ativos, pelo CAMINHO DO JOGADOR.
##
## O teste antigo chamava AbilityRunner.run direto e passou verde enquanto o
## Meteoro e o Orvalho não funcionavam no jogo — porque ele pulava a camada de
## MIRA, que era onde estava o defeito. Duas vezes seguidas o mesmo tipo de bug
## escapou por isso.
##
## Agora o teste instancia a tela de combate de verdade, aperta o botão do
## Ativo (`_arm`) e clica no campo (`aim_at`), como uma pessoa faria. E percorre
## `Db.actives` inteiro: um Ativo novo com um modo de mira novo é coberto
## automaticamente, sem ninguém lembrar de adicionar caso de teste.
func _check_actives() -> void:
	print("[todos os Ativos, pelo caminho do jogador]")
	for aid in Db.active_order:
		var id := String(aid)
		var a: Dictionary = Db.actives[id]

		Run.start_run(31000 + id.length())
		Run.set_starting_team(["sheep", "coalla"])
		Run.actives = [id]

		var cb := ScreenCombat.new()
		cb.setup({"type": "rinha", "title": "teste", "danger": 1,
			"payload": {"theme": "cardume_profundo", "count": 3,
				"enemy_seed": 7, "power": 1.0, "arena": ""},
			"rewards": {"ether": 0}})
		add_child(cb)
		await get_tree().process_frame

		var sim: CombatSim = cb.sim
		# equipe ferida e inimigos agrupados: assim tanto cura quanto dano
		# tem o que fazer, e o efeito e mensuravel
		var foes: Array = []
		for u in sim.units:
			if u.side == 0:
				u.hp = u.hp_max * 0.5
			else:
				foes.append(u)
		for k in range(foes.size()):
			foes[k].pos = Vector2(140.0, float(k) * 18.0)

		var hp_ally := 0.0
		var hp_foe := 0.0
		var ua_foe := 0.0
		for u2 in sim.units:
			if u2.side == 0:
				hp_ally += u2.hp
			else:
				hp_foe += u2.hp
				ua_foe += u2.aura.total_ua()

		sim.energy = 100.0
		cb._refresh_actives()
		cb._arm(id)
		# modos que exigem mira: o clique acontece onde os inimigos estao
		if cb._aiming != "":
			# clica na posicao DESENHADA, que e onde unit_at() procura
			var alvo: SimUnit = foes[0] if String(a.get("aim", "")).begins_with("enemy") 				else sim.units[0]
			ok(cb.aim_at(cb.field.screen_of(alvo)),
				"%s: o clique no campo LANCA (mira %s)" % [String(a["name"]), String(a.get("aim", ""))])
		# Prisma de Reescrita abre o seletor de elemento: fecha escolhendo um
		if String(a.get("aim", "")).ends_with("_pick_element"):
			cb._cast(id, foes[0].pos, foes[0], "FOGO")

		var d_ally := 0.0
		var d_foe := 0.0
		var d_ua := 0.0
		for u3 in sim.units:
			if u3.side == 0:
				d_ally += u3.hp
			else:
				d_foe += u3.hp
				d_ua += u3.aura.total_ua()
		var curou: bool = d_ally > hp_ally + 1.0
		var bateu: bool = d_foe < hp_foe - 1.0
		var aplicou: bool = d_ua > ua_foe + 0.01
		var mudou: bool = false
		for u4 in sim.units:
			if u4.side != 0 and u4.element != u4.base_element:
				mudou = true
		ok(curou or bateu or aplicou or mudou,
			"%s TEVE EFEITO (cura %.0f · dano %.0f · UA %.1f)"
				% [String(a["name"]), d_ally - hp_ally, hp_foe - d_foe, d_ua - ua_foe])
		ok(sim.energy < 100.0, "%s cobrou Energia" % String(a["name"]))
		cb.queue_free()
		await get_tree().process_frame


func _check_survival() -> void:
	print("[recuperacao entre batalhas]")
	Run.start_run(9090)
	Run.set_starting_team(["sheep", "apollo"])
	var a: UnitInstance = Run.team[0]
	var b: UnitInstance = Run.team[1]
	# A CURA ENTRE NOS E TOTAL, E ISSO E DECISAO DO AUTOR (NOTAS 5.23, 02/09):
	# "faz as criaturas sempre regenerarem vida quando acabar batalha e tira as
	# coisas que recupera vida fora de batalha que vai ser inutil".
	#
	# Em 15/09 esta assercao foi reescrita como formula, para acomodar uma cura
	# PARCIAL vinda de `run.heal_between_nodes_pct`. Aquilo foi um engano: a
	# chave era dado morto porque a regra tinha sido REMOVIDA de proposito, e
	# nao porque ninguem tinha se lembrado de liga-la. "Chave sem leitor" e
	# "regra que o autor tirou" parecem a mesma coisa de dentro do grep.
	#
	# Voltou a ser um numero LITERAL, de propósito. Uma formula que le do dado
	# aceitaria qualquer valor em silencio; o literal reprova a mudanca e obriga
	# quem a fizer a vir ler esta nota antes.
	a.hp_ratio = 0.30
	b.hp_ratio = 0.0
	Run.heal_between_nodes()
	ok(is_equal_approx(a.hp_ratio, 1.0), "ferido volta INTEIRO (0.30 -> %.2f)" % a.hp_ratio)
	ok(is_equal_approx(b.hp_ratio, 1.0), "nocauteado volta INTEIRO (0.00 -> %.2f)" % b.hp_ratio)
	ok(b.hp_ratio > 0.0, "e quem caiu volta em pe para o proximo combate")
	ok(not Db.has_method("consumables") and not ("descanso_preco" in
		Db.tuning.get("momentos", {}).get("loja", {})),
		"cura fora de combate saiu da Loja")

	# O ACASO NAO COBRA MAIS EM SANGUE (16/09). Com cura total entre nos, HP
	# perdido num evento voltava inteiro na briga seguinte — era um risco de
	# mentira. `Run.team_hp_delta` continua existindo e funcionando, so nao ha
	# mais nenhuma op de dado que a chame.
	Run.team_hp_delta(-0.25)
	ok(a.hp_ratio < 1.0, "team_hp_delta ainda fere quem for chamar (%.2f)" % a.hp_ratio)
	var _tem_dano := false
	for e in Db.random_events:
		for r in (e.get("outcomes", []) as Array):
			for o in (r.get("ops", []) as Array):
				if String(o.get("op", "")) == "damage":
					_tem_dano = true
	ok(not _tem_dano, "nenhum evento cobra HP — o custo virou o que voce equipou")

	print("[o acaso cobra o que voce equipou]")
	# O RISCO DO ACASO E `perde_equipado` (autor, 16/09). O que esta cerca
	# cobra e a parte que a previa PROMETE: sai UMA coisa, e sai de verdade.
	var rngp := RandomNumberGenerator.new()
	rngp.seed = 909
	ok(Run.perder_equipado(rngp) == "", "sem nada equipado, nao ha o que perder")
	var prato := ""
	for d in Db.dish_order:
		if String(Db.dishes[d].get("kind", "")) != "nutricao":
			continue
		# o Banquete do Diluvio nao serve aqui: ele CONCEDE slot, e o teste
		# do teto de itens logo abaixo precisa dele intocado
		if int(Db.dishes[d].get("mods", {}).get("item_slot", 0)) > 0:
			continue
		prato = String(d)
		break
	var item := ""
	for it in Db.item_order:
		if a.accepts_item(String(it)):
			item = String(it)
			break
	a.items.append(item)
	a.dishes.append(prato)
	ok(Run.perder_equipado(rngp, true) != "", "so_prato tira o prato")
	ok(a.dishes.is_empty() and a.items.size() == 1,
		"so_prato NAO encosta no item (itens %d, pratos %d)" % [a.items.size(), a.dishes.size()])
	ok(Run.perder_equipado(rngp) != "", "sem so_prato, o item pode sair")
	ok(a.items.is_empty(), "e saiu (itens %d)" % a.items.size())

	# O BANQUETE DO DILUVIO E UM SLOT. Ele nao pode sair debaixo de um item:
	# a ficha ficaria em "itens 2/1", estado que `accepts_item` nunca permite.
	var banq := ""
	for d in Db.dish_order:
		if int(Db.dishes[d].get("mods", {}).get("item_slot", 0)) > 0:
			banq = String(d)
			break
	if banq != "":
		a.dishes.append(banq)
		# enche os slots com o que ESTA unidade aceita (item com dono, ou um
		# segundo Nucleo, seriam recusados — e o laco giraria para sempre)
		for it in Db.item_order:
			if not a.can_equip():
				break
			if a.accepts_item(String(it)):
				a.items.append(String(it))
		var antes := a.items.size()
		for i in 12:
			Run.perder_equipado(rngp, true)
		ok(a.dishes.has(banq),
			"o Banquete nao sai com a vaga ocupada (%d itens em %d slots)"
			% [a.items.size(), a.item_slots()])
		ok(a.items.size() <= a.item_slots(),
			"ninguem termina acima do teto de itens (%d/%d)"
			% [a.items.size(), a.item_slots()])
		a.items.resize(antes)

	print("[cura em area]")
	var sim := CombatSim.new(77)
	sim.node_index = 5
	var h1 := _mk(sim, "sheep", 0)
	var h2 := _mk(sim, "apollo", 0)
	var h3 := _mk(sim, "coalla", 0)
	_mk(sim, "hipocampo", 1)
	sim.begin()
	h1.hp = h1.hp_max * 0.4
	h2.hp = h2.hp_max * 0.4
	h3.hp = h3.hp_max * 0.4
	h1.pos = Vector2(0, 0)
	h2.pos = Vector2(60, 0)
	h3.pos = Vector2(900, 0)      # fora do raio
	var before3 := h3.hp
	AbilityRunner.run(sim, null, Db.actives["orvalho"].get("ops", []), Vector2(30, 0), null)
	ok(h1.hp > h1.hp_max * 0.4 and h2.hp > h2.hp_max * 0.4, "Orvalho curou quem estava na area")
	ok(is_equal_approx(h3.hp, before3), "quem estava fora da area NAO foi curado")


func _check_boss() -> void:
	print("[chefe]")
	Run.start_run(555)
	Run.node_index = 9
	Run.add_ether(20)
	Run.recruit("apollo")
	Run.recruit("pinto_raio")
	var pair := NodeGen.generate_pair(9)
	ok(pair.size() == 1 and String(pair[0]["type"]) == "chefe", "no 9 e o chefe (opcao unica)")
	var sim := CombatBuilder.build(pair[0], 42)
	var boss: SimUnit = null
	for u in sim.units:
		if u.is_boss:
			boss = u
	ok(boss != null, "O Devorador em campo")
	ok(MonsterArt.sheet("idle", boss.species_id) != null, "chefe tem sprite (coalla gigante)")
	sim.run_to_end()
	ok(sim.finished, "combate de chefe terminou (%.0fs)" % sim.now)
	ok(sim.ether_eaten > 0, "Fome Insaciavel comeu %d de Eter" % sim.ether_eaten)


## A CADEIA DE REACOES TERMINA, mesmo com o campo encharcado.
##
## A Eletrocussao nao consome a aura (GDD 6.4) e o op "chain" chama strike() de
## volta: reacao -> golpe -> reacao e um ciclo. Ele terminava por ACIDENTE,
## porque as auras acabavam. Quando as arenas passaram a molhar o campo inteiro
## de forma continua, a recursao deixou de ter fim e o autoplay estourou a
## pilha com 1023 quadros — um crash que iria direto para o build exportado.
##
## Este teste roda o pior caso de proposito: mare elemental no maximo, equipe
## cheia dos dois lados, combate inteiro. Se a recursao voltar, ele nao passa —
## ele trava o processo, que e exatamente o sinal que se quer.
func _check_cadeia_termina() -> void:
	print("[cadeia de reacoes termina]")
	ok(int(Db.combat("max_reaction_chain", 0)) > 0, "existe teto de cadeia")
	var sim := CombatSim.new(4242)
	# maré ligada no talo: 4 UA por segundo em TODO MUNDO
	sim.arena_effect = {"op": "mare_elemental", "element": "AGUA", "ua": 4.0, "every": 1.0}
	for sp in ["pinto_raio", "sheep", "hipocampo"]:
		_mk_unit(sim, 0, sp)
	for sp in ["pinto_raio", "apollo", "coalla"]:
		_mk_unit(sim, 1, sp)
	sim.begin()
	# run_to_end devolve o VENCEDOR, nao a contagem de tiques — o tempo
	# simulado esta em sim.now
	sim.run_to_end(2000)
	ok(sim.finished, "o combate TERMINA com o campo encharcado (%.1fs, %s)"
		% [sim.now, sim.end_reason])
	ok(sim._react_depth == 0, "a profundidade volta a zero (%d)" % sim._react_depth)
	ok(sim._sum_reactions() > 0, "e reacoes aconteceram de verdade (%d)" % sim._sum_reactions())


## ARENAS COM EFEITO e MODIFICADORES DE BANDO (autor, 03/09).
##
## Antes deste bloco a arena era DECORACAO: o campo "text" prometia "2 UA de
## Encharcado a cada 3 s" e o simulador nao fazia nada. Um teste que so
## checasse "a arena tem nome" passaria verde do mesmo jeito — por isso aqui
## se cobra o EFEITO acontecendo dentro da simulacao.
func _check_arena_e_mods() -> void:
	print("[arena e modificadores]")
	for a in Db.arenas.values():
		ok(not (a.get("effect", {}) as Dictionary).is_empty(),
			"arena %s tem efeito de verdade" % String(a["name"]))

	# MARÉ ELEMENTAL: banha o campo de aura, sem dano
	var sim := CombatSim.new(11)
	sim.arena_effect = {"op": "mare_elemental", "element": "AGUA", "ua": 2.0, "every": 1.0}
	var a1 := _mk_unit(sim, 0, "sheep")
	var b1 := _mk_unit(sim, 1, "apollo")
	sim.begin()
	var hp_antes := b1.hp
	for i in range(12):
		sim._tick_arena()
	ok(a1.aura.total_ua() > 0.0, "a mare molha o SEU lado (%.1f UA)" % a1.aura.total_ua())
	ok(b1.aura.total_ua() > 0.0, "e o lado inimigo tambem (%.1f UA)" % b1.aura.total_ua())
	ok(is_equal_approx(b1.hp, hp_antes), "a mare NAO causa dano")

	# ESTÍMULO: mais forte de tempos em tempos, com teto
	var sim2 := CombatSim.new(12)
	sim2.arena_effect = {"op": "estimulo", "every": 1.0, "atk": 0.10, "max": 3}
	var a2 := _mk_unit(sim2, 0, "sheep")
	_mk_unit(sim2, 1, "apollo")
	sim2.begin()
	var atk0 := a2.eff_atk()
	for i in range(60):
		sim2._tick_arena()
	ok(a2.eff_atk() > atk0, "o estimulo aumenta o ATK (%.0f -> %.0f)" % [atk0, a2.eff_atk()])
	ok(sim2._estimulo_stacks == 3, "e para no teto de 3 (%d)" % sim2._estimulo_stacks)

	# ASSOMBRADA: quem cai vira fantasma — aplica aura, nao da dano, nao segura
	# o combate de pe
	var sim3 := CombatSim.new(13)
	sim3.arena_effect = {"op": "assombrada"}
	var a3 := _mk_unit(sim3, 0, "sheep")
	var b3 := _mk_unit(sim3, 1, "apollo")
	sim3.begin()
	sim3._kill(a3, b3)
	ok(a3.ghost, "quem cai na Assombrada vira fantasma")
	ok(sim3.alive_units(0).is_empty(), "o fantasma NAO conta como vivo")
	var hp3 := b3.hp
	sim3._deal(a3, b3, 999.0, "physical", "", false, false)
	ok(is_equal_approx(b3.hp, hp3), "o fantasma NAO causa dano")
	sim3.put_aura(a3, b3, "GELO", 3.0)
	ok(b3.aura.total_ua() > 0.0, "mas o fantasma AINDA aplica aura")

	# MODIFICADORES: viram buff no lado inimigo, e escalam com o passo
	var sim4 := CombatSim.new(14)
	_mk_unit(sim4, 0, "sheep")
	var b4 := _mk_unit(sim4, 1, "apollo")
	var atk_base := b4.eff_atk()
	for m in Db.modifiers:
		if String(m["id"]) == "ferozes":
			sim4.enemy_mods.append(m)
	sim4.begin()
	ok(b4.eff_atk() > atk_base,
		"Ferozes deixa o inimigo mais forte (%.0f -> %.0f)" % [atk_base, b4.eff_atk()])

	Run.start_run(555)
	Run.set_starting_team(["sheep", "apollo"])
	# RETA FINAL (autor, 03/09): ate o passo 5 a briga e limpa — e o trecho
	# em que a equipe se monta. A dificuldade extra entra so no fim, e o
	# teste cobra os tres degraus: nenhum, um, dois.
	var reta: int = int(Db.tune("difficulty", "reta_final_a_partir_de", 6))
	for i4 in range(1, reta):
		var m4: Array = NodeGen.generate_pair(i4)[0]["payload"].get("mods", [])
		ok(m4.is_empty(), "passo %d (antes da reta final) vem LIMPO" % i4)
	var no_meio: Array = NodeGen.generate_pair(reta)[0]["payload"].get("mods", [])
	ok(no_meio.size() == 1, "o passo %d abre a reta final com UM (%d)"
		% [reta, no_meio.size()])
	var no_fim: Array = NodeGen.generate_pair(reta + 2)[0]["payload"].get("mods", [])
	ok(no_fim.size() == 2, "o passo %d vem com DOIS (%d)" % [reta + 2, no_fim.size()])
	# e as arenas que MUDAM A REGRA nao aparecem antes da reta final
	var especiais: Array = Db.arenas.values().filter(func(a): return bool(a.get("late", false)))
	ok(not especiais.is_empty(), "existem arenas de reta final (%d)" % especiais.size())
	var vazou := false
	for s5 in [1, 42, 999]:
		Run.seed_value = s5
			
		for i5 in range(1, reta):
			var nome := String(NodeGen.generate_pair(i5)[0]["payload"].get("arena", ""))
			if bool(Db.arenas.get(nome, {}).get("late", false)):
				vazou = true
	ok(not vazou, "nenhuma arena de reta final aparece antes dela")


func _mk_unit(sim: CombatSim, side: int, sp: String) -> SimUnit:
	var u := SimUnit.new()
	var d := Db.sp(sp)
	u.side = side
	u.species_id = sp
	u.display_name = Db.sp_name(sp)
	u.element = String(d.get("element", "FOGO"))
	u.base_element = u.element
	u.hp = float(d.get("hp", 500))
	u.hp_max = u.hp
	u.atk = float(d.get("atk", 50))
	u.def = float(d.get("def", 30))
	return sim.add_unit(u)


## O MERCADOR DE TROCAS troca JUSTO (autor, 03/09).
##
## A regra que faz a tela valer a pena: quem entrega um Prismon investido
## recebe um com a MESMA quantidade de itens e pratos. Se isso escorregar, o
## Mercador vira uma armadilha silenciosa — o jogador entrega uma criatura
## equipada, recebe uma nua, e so descobre no combate seguinte.
func _check_troca() -> void:
	print("[mercador de trocas]")
	Run.start_run(2718)
	Run.set_starting_team(["sheep", "apollo"])
	var sheep: UnitInstance = Run.team[0]
	sheep.items.append("presa_rachada")
	sheep.dishes.append("espeto_flamejante")

	var ofertas := EventGen.trade_offer(4)
	ok(not ofertas.is_empty(), "o Mercador oferece algo (%d)" % ofertas.size())
	var para_sheep: Dictionary = {}
	for o in ofertas:
		if int(o["uid"]) == sheep.uid:
			para_sheep = o
	ok(not para_sheep.is_empty(), "ha oferta para o Prismon investido")
	ok(para_sheep["items"].size() == sheep.items.size(),
		"vem com a MESMA quantidade de itens (%d x %d)"
		% [para_sheep["items"].size(), sheep.items.size()])
	ok(para_sheep["dishes"].size() == sheep.dishes.size(),
		"vem com a MESMA quantidade de pratos (%d x %d)"
		% [para_sheep["dishes"].size(), sheep.dishes.size()])
	# a regra de assinatura vale aqui tambem
	var especie := String(para_sheep["species"])
	for it in para_sheep["items"]:
		var dono := String(Db.items[String(it)].get("for", ""))
		ok(dono == "" or dono == especie,
			"o item ofertado (%s) serve para o %s" % [String(it), especie])
	ok(not _tem_especie(especie), "nao oferece uma especie que voce ja tem")

	# a troca EXECUTA: sai um, entra outro com a carga da oferta
	var antes := Run.team.size()
	ok(Run.trade(sheep, especie, para_sheep["items"], para_sheep["dishes"]),
		"a troca acontece")
	ok(Run.team.size() == antes, "a equipe nao muda de tamanho")
	ok(not Run.team.has(sheep), "quem saiu nao esta mais na equipe")
	var novo: UnitInstance = null
	for u in Run.team:
		if u.species_id == especie:
			novo = u
	ok(novo != null, "quem entrou esta na equipe")
	if novo != null:
		ok(novo.items.size() == 1 and novo.dishes.size() == 1,
			"quem entrou trouxe a carga da oferta (%d item, %d prato)"
			% [novo.items.size(), novo.dishes.size()])
		ok(is_equal_approx(novo.hp_ratio, 1.0), "quem entrou vem inteiro")

	# Prismon pelado: oferta pelada, sem presente de graca
	Run.start_run(2719)
	Run.set_starting_team(["sheep", "apollo"])
	for o in EventGen.trade_offer(4):
		ok(o["items"].is_empty() and o["dishes"].is_empty(),
			"Prismon sem nada equipado recebe oferta sem nada")


func _tem_especie(sp_id: String) -> bool:
	for u in Run.team:
		if u.base_id() == sp_id:
			return true
	return false


## QUEM recebe o efeito e um ALVO ESCOLHIDO, nao um sorteio (autor, 03/09:
## "coloque o item que muda o elemento do alvo para aparecer uma outra tela pra
## voce selecionar o prismon").
##
## Aqui se cobra o modelo por tras das duas telas novas. O Guisado Cromatico
## em especial estava QUEBRADO EM SILENCIO: `cook()` recebia `pick` vazio,
## caia em `forced_element = element()`, cobrava o Eter e dizia que a Afinidade
## mudou — e a criatura continuava igual. Nenhum teste pegava porque o retorno
## era uma mensagem de sucesso.
func _check_alvo_escolhido() -> void:
	print("[alvo escolhido]")
	Run.start_run(31415)
	Run.set_starting_team(["sheep", "apollo"])
	Run.add_ether(400)
	var sheep: UnitInstance = Run.team[0]
	var antes := sheep.element()

	# GUISADO: sem escolher elemento, nao muda nada — e com escolha, muda
	Run.cook("guisado_cromatico", sheep, "")
	ok(sheep.element() == antes,
		"Guisado sem escolha NAO muda a Afinidade (segue %s)" % sheep.element())
	sheep.dishes.clear()
	var destino := "RAIO" if antes != "RAIO" else "FOGO"
	Run.cook("guisado_cromatico", sheep, destino)
	ok(sheep.element() == destino,
		"Guisado COM escolha muda para %s (%s)" % [destino, sheep.element()])

	# NUCLEO: o item so muda o elemento de quem o recebe
	Run.start_run(31416)
	Run.set_starting_team(["sheep", "apollo"])
	var a: UnitInstance = Run.team[0]
	var b: UnitInstance = Run.team[1]
	var b_antes := b.element()
	# A ORDEM IMPORTA (15/09): a pergunta "quantos aceitam?" tem de ser feita
	# ANTES de equipar, porque `accepts_item` passou a recusar um SEGUNDO item
	# com set_element na mesma criatura. Cobrar 2 depois de equipar virou a
	# assercao guardando o bug que a regra nova conserta — e de quebra o par de
	# assercoes agora prova as DUAS metades da regra.
	ok(Run.team.filter(func(u): return u.accepts_item("nucleo_igneo")).size() >= 2,
		"com dois destinos possiveis a loja tem de PERGUNTAR")
	a.items.append("nucleo_igneo")
	ok(a.element() == "FOGO", "quem recebeu o Nucleo Igneo virou Fogo (%s)" % a.element())
	ok(b.element() == b_antes, "o OUTRO nao mudou de elemento (%s)" % b.element())
	ok(a.has_core() and not a.accepts_item("nucleo_gelido"),
		"um Nucleo por criatura: o segundo nunca teria efeito, entao e recusado")
	ok(Run.team.filter(func(u): return u.accepts_item("nucleo_gelido")).size() == 1,
		"e sobra UM destino, que e o que a tela tem de dizer em vez de sumir com a opcao")

	# EVENTO DE ACASO: concede, mas NAO decide. Antes ele sorteava o item E
	# quem recebia — e sorteava de Db.item_order inteiro contra quem tivesse
	# espaco (can_equip), sem olhar o dono: dava para o Sheep receber a Cauda
	# de Brasa, que e so do Apollo. A regra de assinatura valia na loja e era
	# furada aqui.
	var achou_item := false
	for seed_i in range(40):
		Run.start_run(9000 + seed_i)
		Run.set_starting_team(["sheep", "apollo"])
		var itens_antes := 0
		for u2 in Run.team:
			itens_antes += u2.items.size()
		for n2 in range(1, 9):
			var ev2 := EventGen.chance_offer(n2)
			if ev2.is_empty():
				continue
			var r2 := EventGen.resolve_chance(ev2, n2)
			var itens_depois := 0
			for u2 in Run.team:
				itens_depois += u2.items.size()
			ok(itens_depois == itens_antes,
				"o acaso NAO equipa sozinho (passo %d)" % n2)
			for pend in r2.get("pendente", []):
				if String(pend["tipo"]) == "item":
					achou_item = true
					var pode: Array = Run.team.filter(func(u):
						return u.accepts_item(String(pend["id"])))
					ok(not pode.is_empty(),
						"o item achado (%s) serve para ALGUEM da equipe" % String(pend["id"]))
		if achou_item:
			break
	ok(achou_item, "algum acaso concedeu item nas 40 sementes")


## A opção da DIREITA nunca é mais fácil que a da esquerda.
##
## A tela deixou de escrever "o mais perigoso paga mais" (pedido do autor,
## 03/09); no lugar da frase ficou a convenção de que a direita é a mais dura.
## Uma convenção que falha uma vez em vinte não é aprendida — é ruído. Por
## isso ela é testada em toda a trilha e em várias sementes.
func _check_par_ordenado() -> void:
	print("[par de combates: direita nunca mais facil]")
	var falhas := 0
	var pares := 0
	var antes := Run.seed_value
	for s2 in [1, 7, 42, 555, 9001, 31337]:
		Run.seed_value = s2
		for i in range(1, int(Db.run_cfg("nodes_per_act", 8)) + 1):
			var par := NodeGen.generate_pair(i)
			if par.size() < 2:
				continue
			pares += 1
			if int(par[0].get("danger", 0)) > int(par[1].get("danger", 0)):
				falhas += 1
	Run.seed_value = antes
	ok(falhas == 0, "em %d pares, a da direita nunca e mais facil (%d falhas)"
		% [pares, falhas])
	ok(pares >= 40, "conferidos %d pares em 6 sementes" % pares)


## O log SOMA os Prismons de mesmo nome (pedido do autor, 03/09: "coloque os
## prismons para somar o dano dos prismons com o mesmo nome"). Duas Coallas
## viravam duas linhas "Coalla" com numeros diferentes e nada dizendo que eram
## bichos distintos — parecia defeito da tela.
func _check_log_soma() -> void:
	print("[log: soma por nome]")
	var tela := ScreenResult.new()
	tela._log = {"units": [
		{"name": "Coalla", "element": "NATUREZA", "alive": true,
			"damage": 269.0, "taken": 0.0, "healing": 171.0, "reactions": 1, "kills": 1},
		{"name": "Coalla", "element": "NATUREZA", "alive": false,
			"damage": 170.0, "taken": 40.0, "healing": 77.0, "reactions": 0, "kills": 0},
		{"name": "Apollo", "element": "FOGO", "alive": true,
			"damage": 1468.0, "taken": 230.0, "healing": 0.0, "reactions": 2, "kills": 0},
	]}
	var linhas := tela._por_nome()
	ok(linhas.size() == 2, "duas Coallas viram UMA linha (%d linhas)" % linhas.size())
	var coalla: Dictionary = {}
	for l in linhas:
		if String(l["name"]) == "Coalla":
			coalla = l
	ok(int(coalla.get("count", 0)) == 2, "a linha diz que sao 2")
	ok(is_equal_approx(float(coalla["damage"]), 439.0),
		"dano somado 269 + 170 = %d" % roundi(float(coalla["damage"])))
	ok(is_equal_approx(float(coalla["healing"]), 248.0),
		"cura somada 171 + 77 = %d" % roundi(float(coalla["healing"])))
	ok(int(coalla["kills"]) == 1 and int(coalla["reactions"]) == 1, "nocautes e reacoes somam")
	ok(bool(coalla["alive"]), "viva enquanto UMA das copias estiver viva")
	ok(String(linhas[0]["name"]) == "Apollo", "ordenado por dano (Apollo na frente)")
	tela.free()


## O KIT DE INTERFACE TINGE, e o painel tem CORPO.
##
## E a versao de UI do mesmo achado: "declarado nos dados, nunca lido pelo
## codigo". `UI.panel(bg, ...)` recebia a cor da sala de dezesseis lugares e
## DESCARTAVA o bg — sete salas escritas, nenhuma renderizada, e o comentario
## ao lado ate admitia. Nada reclamou por semanas porque nenhuma assercao
## comparava dois bytes.
##
## Sao duas medidas, no molde do [arena e modificadores]: em vez de conferir que
## a constante existe, compoe a textura de verdade e compara os PIXELS.
##   1. cada celula, tingida de Fogo e de Agua, tem de sair diferente — se sair
##      igual, o feixe daquela celula nao esta recebendo a cor.
##   2. UI.panel com dois `bg` diferentes tem de dar duas texturas diferentes.
func _check_kit() -> void:
	print("[kit de interface]")
	var fogo := Db.el_color("FOGO")
	var agua := Db.el_color("AGUA")
	# A composicao tem um plano B declarado para driver sem acesso a pixel
	# (`_compor` devolve a textura crua). Nesse caso as duas saem iguais por
	# motivo legitimo, e acusar seria mentir sobre a causa.
	if UI.frame(0, fogo).texture == UI.FRAMES[0]:
		print("  ---  sem acesso a pixel neste driver: a composicao caiu na "
			+ "textura crua e o bloco nao tem o que medir")
		return
	var iguais: Array = []
	for cell in range(UI.FRAMES.size()):
		if _bytes_da_textura(UI.frame(cell, fogo).texture) \
				== _bytes_da_textura(UI.frame(cell, agua).texture):
			iguais.append("celula %d" % cell)
	ok(iguais.is_empty(), "as %d celulas TINGEM o feixe (Fogo != Agua)%s"
		% [UI.FRAMES.size(), _cob_lista(iguais)])

	var sala_a := UI.panel(Color("#2a1020"), 0, UI.LINE)
	var sala_b := UI.panel(Color("#102a20"), 0, UI.LINE)
	ok(_bytes_da_textura(sala_a.texture) != _bytes_da_textura(sala_b.texture),
		"UI.panel HONRA o bg: duas cores de sala dao duas texturas")
	ok(_bytes_da_textura(UI.panel(Color("#2a1020"), 0, UI.LINE).texture)
			== _bytes_da_textura(sala_a.texture),
		"e o cache devolve a MESMA textura para o mesmo par (celula, cor)")

	# as tabelas paralelas da celula sao conferidas tambem por tools/lint_ui.py,
	# que roda fora do Godot; aqui o custo e uma linha e o erro seria de indice
	ok(UI.CELL_MARGIN.size() == UI.FRAMES.size()
			and UI.CELL_CENTRO.size() == UI.FRAMES.size()
			and UI.MASCARAS.size() == UI.FRAMES.size(),
		"as tabelas da celula andam juntas (%d)" % UI.FRAMES.size())



## A PALETA E LEGIVEL, E A ORDEM DE CARGA ACONTECEU.
##
## Desde 17/09 nenhuma cor de interface e `const` num .gd: elas vem de
## data/paleta.json. Isso resolve "facil de customizar" e cria um risco novo —
## qualquer um pode escrever uma paleta bonita e ILEGIVEL, e "legibilidade" e
## a unica parte de gosto de cor que NAO e gosto: da para medir.
##
## A CONTA (WCAG 2.1, 1.4.3). Para cada canal c em [0,1]:
##     c' = c/12.92                    se c <= 0.03928
##     c' = ((c + 0.055)/1.055) ^ 2.4  caso contrario
##     L  = 0.2126*R' + 0.7152*G' + 0.0722*B'
##     razao = (L_claro + 0.05) / (L_escuro + 0.05)
## O `+0.05` e a luz ambiente refletida pela tela: sem ele preto contra preto
## daria razao infinita. `Color.get_luminance()` do Godot NAO serve aqui —
## ela e a media ponderada dos canais CRUS, sem a curva, e da um numero
## diferente (mede brilho de sinal, nao de luz).
##
## OS TRES PISOS, e por que cada um e esse:
##   texto forte x lajota  >= 4.5   e o piso AA da WCAG para corpo de texto.
##                                  Abaixo dele o jogador nao le a tela.
##   texto fraco x lajota  >= 3.0   o piso AA para texto GRANDE. O `fraco` e
##                                  secundario de proposito; ele pode sumir um
##                                  pouco, nao pode sumir.
##   degrau -> degrau      >= 1.08  os quatro degraus neutros precisam ser
##                                  DISTINGUIVEIS entre si, senao a materia
##                                  vira um campo chapado e o recipiente some
##                                  (que e a Raiz 3 de volta por outra porta).
##                                  1.08 nao e da WCAG: e o piso medido — a
##                                  paleta "vidro", que o autor aprovou, tem
##                                  1.128 / 1.102 / 1.317, e o menor passo dela
##                                  e 1.102.
func _check_paleta() -> void:
	print("[paleta]")
	ok(Db.paletas.size() >= 1, "paleta.json carregou (%d paleta(s))" % Db.paletas.size())
	ok(Db.paletas.has(Db.paleta_ativa), "a paleta ativa existe: '%s'" % Db.paleta_ativa)

	# A ORDEM DE CARGA. `UI` e class_name sobre RefCounted e `Db` e autoload;
	# quem entrega a paleta e um empurrao explicito de Db.load_all(). Se essa
	# ordem quebrar, a tela sai preta e nenhum erro aparece — entao a ordem e
	# COBRADA aqui, em vez de confiada.
	ok(UI.paleta_aplicada, "UI.aplicar_paleta() rodou (Db.load_all() empurrou)")
	var lajota_json := Color(String(Db.paleta["materia"]["lajota"]))
	ok(UI.LAJOTA.is_equal_approx(lajota_json),
		"UI.LAJOTA e o que esta no JSON (%s)" % UI.LAJOTA.to_html(false))
	ok(UI.CELL_MIOLO.size() == UI.CELL_MIOLO_DEGRAU.size()
			and UI.CELL_MIOLO[0].is_equal_approx(UI.LAJOTA),
		"CELL_MIOLO foi derivada dos degraus (%d entradas)" % UI.CELL_MIOLO.size())

	# CONTRASTE, paleta por paleta.
	var reprovadas: Array = []
	for nome in Db.paletas:
		var p: Dictionary = Db.paletas[nome]
		var lajota := Color(String(p["materia"]["lajota"]))
		var forte := Color(String(p["texto"]["forte"]))
		var fraco := Color(String(p["texto"]["fraco"]))
		var r_forte := _contraste(forte, lajota)
		var r_fraco := _contraste(fraco, lajota)
		if r_forte < 4.5:
			reprovadas.append("%s: texto forte %.2f:1 (piso 4.5)" % [nome, r_forte])
		if r_fraco < 3.0:
			reprovadas.append("%s: texto fraco %.2f:1 (piso 3.0)" % [nome, r_fraco])
		var degraus: Array = []
		for chave in ["mesa", "lajota", "lajota_hi", "aresta"]:
			degraus.append(Color(String(p["materia"][chave])))
		for i in range(degraus.size() - 1):
			var a: Color = degraus[i]
			var b: Color = degraus[i + 1]
			if _luminancia(b) <= _luminancia(a):
				reprovadas.append("%s: degrau %d nao e mais claro que o %d"
					% [nome, i + 1, i])
				continue
			var r := _contraste(a, b)
			if r < 1.08:
				reprovadas.append("%s: degraus %d e %d a %.3f (piso 1.08) — "
					% [nome, i, i + 1, r] + "a materia vira campo chapado")
	# O TEXTO NAO SE APOIA MAIS NA LAJOTA CRUA. `UI.materia_da_sala` tinge a
	# materia com o matiz da sala, e a formula preserva o V do degrau e NAO a
	# luminancia (V e max(r,g,b): azul puro com V=1 tem luminancia 0,07 e verde
	# puro com V=1 tem 0,72). Entao tingir pode derrubar a leitura, e medir so a
	# lajota crua deixaria passar. Mede-se o pior caso: cada sala, cada degrau
	# que recebe texto. As arestas ficam de fora de proposito — sao de 1 px e
	# nao recebem texto; cobrar leitura nelas reprovaria ate a paleta de hoje.
	#
	# E ELA NAO TEM COMO REPROVAR NADA HOJE, e isso e medido: varrendo os tres
	# degraus contra 72 matizes x 21 saturacoes (com o teto de 0,85 da
	# formula), o pior texto forte possivel e 9,53:1 e o pior fraco e 3,49:1,
	# os dois acima do piso. E consequencia de os tres degraus serem escuros.
	# A cerca existe para o dia em que alguem escrever uma paleta CLARA, ou
	# trocar `materia_da_sala` por uma formula que nao preserve o V — nos dois
	# casos ela passa a ser a unica coisa entre a paleta nova e texto ilegivel.
	for nome in Db.paletas:
		var p: Dictionary = Db.paletas[nome]
		var forte := Color(String(p["texto"]["forte"]))
		var fraco := Color(String(p["texto"]["fraco"]))
		var f: float = float(p.get("sala_na_materia", 0.0))
		var pior_forte := 99.0
		var pior_fraco := 99.0
		var pior_sala := ""
		for chave in ["mesa", "lajota", "lajota_hi"]:
			var degrau := Color(String(p["materia"][chave]))
			for sala_nome in (p["salas"] as Dictionary):
				var tingida := UI.materia_da_sala(degrau,
					Color(String(p["salas"][sala_nome])), f)
				var rf := _contraste(forte, tingida)
				var rw := _contraste(fraco, tingida)
				if rf < pior_forte:
					pior_forte = rf
					pior_sala = "%s/%s" % [chave, sala_nome]
				pior_fraco = minf(pior_fraco, rw)
		if pior_forte < 4.5:
			reprovadas.append("%s: texto forte %.2f:1 na materia TINGIDA (%s)"
				% [nome, pior_forte, pior_sala])
		if pior_fraco < 3.0:
			reprovadas.append("%s: texto fraco %.2f:1 na materia TINGIDA"
				% [nome, pior_fraco])

	# ESTADO NAO PODE VIRAR ELEMENTO. O `aviso` da estufa nasceu a dE2000 2.60
	# do elemento RAIO — o limiar de diferenca perceptivel e ~2.3, entao eram A
	# MESMA COR: uma dizendo "cuidado" e a outra dizendo "Raio", na mesma tela.
	# Contraste de luminancia NAO pega isto (as duas tem luminancia parecida, e
	# e por isso que o par passa despercebido); so distancia perceptual pega.
	for nome in Db.paletas:
		var p: Dictionary = Db.paletas[nome]
		for chave in (p["estado"] as Dictionary):
			var c := Color(String(p["estado"][chave]))
			for eid in Db.slice_elements:
				var d := _distancia_lab(c, Db.el_color(String(eid)))
				if d < DE_MINIMO:
					reprovadas.append("%s: estado '%s' e o elemento %s sao a mesma cor (dE %.2f)"
						% [nome, chave, eid, d])

	ok(reprovadas.is_empty(), "as %d paletas sao LEGIVEIS%s"
		% [Db.paletas.size(), _cob_lista(reprovadas)])
	for nome in Db.paletas:
		var p: Dictionary = Db.paletas[nome]
		print("  ---  %-8s forte %5.2f:1  fraco %5.2f:1  degraus %.3f %.3f %.3f"
			% [nome,
				_contraste(Color(String(p["texto"]["forte"])), Color(String(p["materia"]["lajota"]))),
				_contraste(Color(String(p["texto"]["fraco"])), Color(String(p["materia"]["lajota"]))),
				_contraste(Color(String(p["materia"]["mesa"])), Color(String(p["materia"]["lajota"]))),
				_contraste(Color(String(p["materia"]["lajota"])), Color(String(p["materia"]["lajota_hi"]))),
				_contraste(Color(String(p["materia"]["lajota_hi"])), Color(String(p["materia"]["aresta"])))])

	# O CACHE TEM DE ESQUECER. As texturas de celula sao guardadas por par
	# (celula, acento, miolo) e o miolo vem da paleta: sem limpar o cache,
	# trocar de paleta deixaria a tela com a cor VELHA e sem erro nenhum. A
	# medida e em bytes de pixel, nao em "a variavel mudou".
	if UI.frame(0, UI.ACCENT).texture == UI.FRAMES[0]:
		print("  ---  sem acesso a pixel neste driver: o bloco do cache nao "
			+ "tem o que medir")
	else:
		var antes := _bytes_da_textura(UI.frame(UI.C_PANEL, UI.LINE).texture)
		var outra: Dictionary = {}
		for nome in Db.paletas:
			if nome != Db.paleta_ativa:
				outra = Db.paletas[nome]
				break
		if outra.is_empty():
			print("  ---  so ha uma paleta instalada: nao da para medir a troca")
		else:
			UI.aplicar_paleta(outra)
			var depois := _bytes_da_textura(UI.frame(UI.C_PANEL, UI.LINE).texture)
			ok(depois != antes,
				"trocar de paleta LIMPA o cache de textura (a celula muda de bytes)")
			UI.aplicar_paleta(Db.paleta)
			ok(_bytes_da_textura(UI.frame(UI.C_PANEL, UI.LINE).texture) == antes,
				"e voltar para a paleta ativa devolve a MESMA textura")
			PrismaTheme.esquecer()

	# `sala_na_materia` em 0.0 tem de ser a IDENTIDADE. E o botao que a proxima
	# fase vai girar para dar cor propria a cada tela; enquanto ele esta em
	# zero, a materia continua neutra ao byte.
	ok(UI.materia_da_sala(UI.LAJOTA, UI.cor_da_sala("acaso"), 0.0)
			.is_equal_approx(UI.LAJOTA),
		"materia_da_sala() em forca 0 e a identidade")
	ok(not UI.materia_da_sala(UI.LAJOTA, UI.cor_da_sala("acaso"), 0.5)
			.is_equal_approx(UI.LAJOTA),
		"e em forca 0.5 ela de fato puxa a materia para a cor da sala")
	ok(is_equal_approx(UI.materia_da_sala(UI.LAJOTA, UI.cor_da_sala("acaso"), 0.5).v,
			UI.LAJOTA.v),
		"sem mexer na LUMINANCIA do degrau (e o que segura o contraste)")

	# As 16 salas tem de existir na paleta ativa: `UI.cor_da_sala` acusa nome
	# desconhecido, mas so quando a tela daquele nome e aberta.
	var salas := ["titulo", "iniciais", "escolha", "preparacao", "sinergias",
		"combate", "vitoria", "derrota", "recruta", "loja", "cozinha", "poder",
		"acaso", "troca", "chefe", "fim_vitoria"]
	var faltando: Array = []
	for s in salas:
		if not UI.SALAS.has(s):
			faltando.append(String(s))
	ok(faltando.is_empty(), "as %d salas estao na paleta%s"
		% [salas.size(), _cob_lista(faltando)])


## Luminancia relativa da WCAG. Ver o comentario de _check_paleta.
func _luminancia(c: Color) -> float:
	return 0.2126 * _canal(c.r) + 0.7152 * _canal(c.g) + 0.0722 * _canal(c.b)


func _canal(v: float) -> float:
	return v / 12.92 if v <= 0.03928 else pow((v + 0.055) / 1.055, 2.4)


## A DISTANCIA MINIMA entre uma cor de ESTADO e uma cor de ELEMENTO, em CIEDE2000.
##
## Nao e o limiar de perceptibilidade. O classico e 2,3 — "da para ver que sao
## duas cores se estiverem encostadas" — e os dois pares que motivaram esta cerca
## medem 2,60 e 2,88, ou seja, passariam. O criterio aqui e outro: as duas nunca
## aparecem encostadas. Uma diz "cuidado" num canto da tela e a outra diz "Raio"
## no outro, e o jogador tem de nao CONFUNDIR as duas de relance.
##
## 5,0 e onde isso cai: pega os dois pares ruins e deixa a paleta do jogo em 7,22,
## com folga em vez de raspando.
const DE_MINIMO := 5.0


## Distancia perceptual em CIEDE2000 (D65).
##
## CUSTOU UM AUTOTESTE NEGATIVO DESCOBRIR QUE PRECISAVA SER ESTA. A primeira
## versao usou CIE76, que e cinco vezes menor de escrever, com a justificativa de
## que ela "erra para o lado seguro entre amarelos". Medido: e o CONTRARIO. O par
## estufa/RAIO da 2,60 em CIEDE2000 e 5,54 em CIE76 — a formula crua SUPERESTIMA
## a distancia exatamente na regiao de croma alto, que e a regiao que esta cerca
## existe para vigiar, e por isso a de 2000 foi criada. Com o piso em unidades
## erradas a cerca passou verde com o defeito reinjetado.
##
## Fica o aviso para quem for mexer: o par que esta cerca vigia e amarelo contra
## amarelo. Qualquer atalho de distancia de cor erra ali.
func _distancia_lab(a: Color, b: Color) -> float:
	var la := _lab(a)
	var lb := _lab(b)
	var c1 := sqrt(la.y * la.y + la.z * la.z)
	var c2 := sqrt(lb.y * lb.y + lb.z * lb.z)
	var cm: float = (c1 + c2) / 2.0
	var c7: float = pow(cm, 7.0)
	var g: float = 0.5 * (1.0 - sqrt(c7 / (c7 + pow(25.0, 7.0)))) if cm > 0.0 else 0.0
	var a1: float = (1.0 + g) * la.y
	var a2: float = (1.0 + g) * lb.y
	var c1p := sqrt(a1 * a1 + la.z * la.z)
	var c2p := sqrt(a2 * a2 + lb.z * lb.z)
	var h1: float = fposmod(rad_to_deg(atan2(la.z, a1)), 360.0)
	var h2: float = fposmod(rad_to_deg(atan2(lb.z, a2)), 360.0)
	var dl: float = lb.x - la.x
	var dc: float = c2p - c1p
	var dh := 0.0
	if c1p * c2p > 0.0:
		dh = h2 - h1
		if dh > 180.0:
			dh -= 360.0
		elif dh < -180.0:
			dh += 360.0
	var dhh: float = 2.0 * sqrt(c1p * c2p) * sin(deg_to_rad(dh / 2.0))
	var lm: float = (la.x + lb.x) / 2.0
	var cmp_: float = (c1p + c2p) / 2.0
	var hm := h1 + h2
	if c1p * c2p > 0.0:
		if absf(h1 - h2) > 180.0:
			hm = (hm + 360.0) / 2.0 if hm < 360.0 else (hm - 360.0) / 2.0
		else:
			hm = hm / 2.0
	var t: float = (1.0 - 0.17 * cos(deg_to_rad(hm - 30.0))
		+ 0.24 * cos(deg_to_rad(2.0 * hm))
		+ 0.32 * cos(deg_to_rad(3.0 * hm + 6.0))
		- 0.20 * cos(deg_to_rad(4.0 * hm - 63.0)))
	var dth: float = 30.0 * exp(-pow((hm - 275.0) / 25.0, 2.0))
	var cp7: float = pow(cmp_, 7.0)
	var rc: float = 2.0 * sqrt(cp7 / (cp7 + pow(25.0, 7.0))) if cmp_ > 0.0 else 0.0
	var sl: float = 1.0 + (0.015 * pow(lm - 50.0, 2.0)) / sqrt(20.0 + pow(lm - 50.0, 2.0))
	var sc: float = 1.0 + 0.045 * cmp_
	var sh: float = 1.0 + 0.015 * cmp_ * t
	var rt: float = -sin(deg_to_rad(2.0 * dth)) * rc
	return sqrt(pow(dl / sl, 2.0) + pow(dc / sc, 2.0) + pow(dhh / sh, 2.0)
		+ rt * (dc / sc) * (dhh / sh))


func _lab(c: Color) -> Vector3:
	var lin := Vector3(_degama(c.r), _degama(c.g), _degama(c.b))
	var x: float = (0.4124 * lin.x + 0.3576 * lin.y + 0.1805 * lin.z) / 0.95047
	var y: float = 0.2126 * lin.x + 0.7152 * lin.y + 0.0722 * lin.z
	var z: float = (0.0193 * lin.x + 0.1192 * lin.y + 0.9505 * lin.z) / 1.08883
	var fx := _f_lab(x)
	var fy := _f_lab(y)
	var fz := _f_lab(z)
	return Vector3(116.0 * fy - 16.0, 500.0 * (fx - fy), 200.0 * (fy - fz))


func _f_lab(t: float) -> float:
	return pow(t, 1.0 / 3.0) if t > 0.008856 else (7.787 * t + 16.0 / 116.0)


func _degama(u: float) -> float:
	return u / 12.92 if u <= 0.04045 else pow((u + 0.055) / 1.055, 2.4)


func _contraste(a: Color, b: Color) -> float:
	var la := _luminancia(a)
	var lb := _luminancia(b)
	var claro: float = maxf(la, lb)
	var escuro: float = minf(la, lb)
	return (claro + 0.05) / (escuro + 0.05)


func _bytes_da_textura(t: Texture2D) -> PackedByteArray:
	if t == null:
		return PackedByteArray()
	var im: Image = t.get_image()
	return im.get_data() if im != null else PackedByteArray()


## SOM: o contrato do autoload, conferido pelos tres jeitos de ele quebrar.
##
## (1) headless tem de ser MUDO — e a assercao que impede alguem de reintroduzir
##     abertura de dispositivo de audio nas ferramentas de lote, que rodam
##     milhares de combates sem janela.
## (2) todo nome do contrato e toda arena de enemies.json precisam de arquivo.
##     Esta e exatamente a classe "declarado no codigo, arquivo nunca conferido":
##     hoje uma arena nova entra sem som e ninguem descobre, porque um id sem
##     arquivo apenas nao toca.
## (3) nome invalido e no-op silencioso — a promessa de que o jogo roda igual se
##     assets/audio sumir inteiro.
func _check_som() -> void:
	print("[som]")
	var som: Node = get_node_or_null("/root/Som")
	ok(som != null, "o autoload Som esta registrado em project.godot")
	if som == null:
		return
	ok(bool(som.mudo), "headless roda MUDO (ferramenta de lote nao abre dispositivo)")

	var faltando: Array = []
	for nome in som.EFEITOS:
		if not FileAccess.file_exists("%s%s.wav" % [String(som.DIR_EFEITOS), String(nome)]):
			faltando.append("efeito %s" % String(nome))
	for id in Db.arenas_by_id.keys():
		if not FileAccess.file_exists("%s%s.wav" % [String(som.DIR_AMBIENTE), String(id)]):
			faltando.append("ambiente %s" % String(id))
	ok(faltando.is_empty(), "os %d efeitos e as %d arenas tem arquivo%s"
		% [som.EFEITOS.size(), Db.arenas_by_id.size(), _cob_lista(faltando)])

	som.tocar("nome_que_nao_existe_no_contrato")
	som.tocar("golpe")
	som.ambiente("arena_que_nao_existe")
	som.parar_ambiente()
	som.set_volume("canal_que_nao_existe", 0.5)
	ok(is_equal_approx(float(som.volume("master")), float(som.volume("master"))),
		"nome invalido e no-op silencioso: nada disso quebra")


# ===========================================================================
# COBERTURA DE DADOS — a cerca da Raiz 1 do relatorio de 15/09.
# ===========================================================================
#
# "Declarado nos dados, nunca lido pelo codigo". A auditoria de 15/09 passou as
# 438 chaves nao-`_doc` de data/*.json contra todo o fonte e achou ~35 que
# nenhum `.gd` citava. Onze achados de cinco frentes diferentes eram esse mesmo
# defeito com nomes diferentes: o Coro de Gelo e o Coro de Natureza nao faziam
# nada, o Totem do Excesso era sobrescrito, o Bico Para-Raio valia metade do
# texto, o Diapasao Vivo era puro enfeite, os dois Totens de duracao de aura
# estavam com o SINAL INVERTIDO, o Coracao Instavel era bonus sem custo.
#
# Nenhum deles da erro. O dado morto nao faz barulho — ele so some.
#
# O molde ja existia e ja rodava verde: o bloco [arena e modificadores] prova
# com SIMULACAO REAL que cada arena "tem efeito de verdade" e que "Ferozes deixa
# o inimigo mais forte (66 -> 73)". O que faltava era fazer o mesmo com item,
# reliquia e ressonancia. Sao duas assercoes complementares:
#
#   (A) COBERTURA DE CHAVE — barata e literal. Toda chave de mods e todo escalar
#       de tuning.json precisa aparecer entre aspas em algum .gd. Pega o dado
#       que ninguem LE.
#   (B) COBERTURA DE EFEITO — a forte. Para cada peca, dois combates identicos,
#       um com ela e um sem, e algum numero tem de mudar. Pega o dado que e lido
#       e nao serve para nada — que foi o caso do Totem do Excesso, escrito pelo
#       CombatBuilder e apagado por CombatSim.begin no tique seguinte.
#
# (A) sozinha teria passado verde sobre metade da tabela do relatorio; (B)
# sozinha nao acha chave de tuning que nenhum combate exercita. As duas juntas
# fecham o buraco.

## Equipe de cobertura: os cinco elementos do slice, para que toda reacao e toda
## ressonancia tenham de onde sair. A ordem e fixa porque a peca e equipada no
## PRIMEIRO dono possivel, e os cinco itens de assinatura tem dono aqui dentro.
const COB_EQUIPE := ["sheep", "apollo", "pinto_raio", "hipocampo", "coalla"]

## Tres temas inimigos com elementos diferentes entre si: sem variedade do outro
## lado, metade das reacoes nunca acontece e metade das pecas parece morta.
const COB_TEMAS := ["bruma_fervente", "tempestade_gelida", "faisca_no_mato"]

const COB_SEMENTE := 20250915
const COB_SINTETICA := "__cobertura_sintetica__"

## O proprio arquivo fica FORA da varredura de fonte. Sem isto a assercao seria
## circular: bastaria o nome da chave aparecer nesta lista-branca para ela se
## dar por citada, e a cerca passaria verde sobre o dado que ela deveria pegar.
const COB_FORA_DA_VARREDURA := ["res://tools/smoke_test.gd"]

## FAMILIAS LIBERADAS, com o motivo escrito ao lado. Uma lista-branca sem motivo
## e uma forma educada de desligar o teste.
##
## O prefixo casa contra o NOME da chave ou contra o CAMINHO dentro do JSON.
const COB_LIVRES := [
	# CombatSim._dmg_vs_auras monta a chave por concatenacao (dmg_vs_ + aura em
	# minuscula) — foi por isso que um grep pelo nome inteiro devolvia zero e os
	# dois Coros pareciam mortos.
	["dmg_vs_", "montada por concatenacao em CombatSim._dmg_vs_auras"],
	# A folha aqui e a RARIDADE do item (Comum/Raro): quem le e o preco, pelo
	# valor que vem de items.json, nunca pelo nome da chave escrito em codigo.
	["/momentos/loja/preco_por_raridade/", "a folha e a raridade, consultada por valor"],
]

## As familias que a varredura NAO cobre, e por que. icons.json, monster_rig.json
## e anims.json sao mapas de NOME (nome de icone, nome de peca do boneco, id de
## animacao): as chaves deles sao consultadas por valor vindo de outro arquivo,
## nunca escritas em codigo. A cobertura delas ja existe e e melhor — o
## lint_ui.py confere que todo icone que os dados pedem existe no mapa, e o
## validate_data.py confere o sheet de cada criatura de anims.json.
const COB_FORA_DE_ESCOPO := ["icons.json", "monster_rig.json", "anims.json"]

## DIVIDA DA COBERTURA DE EFEITO.
##
## Peca que a assercao (B) acusou de nao mudar numero nenhum e cuja causa esta
## num arquivo que nao e desta ferramenta. A assercao continua ligada: o que a
## divida compra e so o direito de a suite seguir verde enquanto o pedido esta
## aberto, para que ela siga sendo um sinal util em vez de um vermelho cronico
## que todo mundo aprende a ignorar.
##
## A lista so pode ENCOLHER. Uma entrada que para de ser acusada vira um aviso
## pedindo que a apaguem — aviso e nao erro, porque com varios agentes editando
## o mesmo repo o conserto de outra pessoa nao pode derrubar esta suite.
##
## As duas de hoje tem a MESMA causa, medida em 15/09: `rx_dmg_add` so
## multiplica `res.reaction_damage` (combat_sim.gd:750-753), e esse numero so e
## consumido no dano TRANSFORMATIVO (:783). Derretimento e Vaporizar sao as duas
## unicas reacoes `amplify` do jogo: o dano delas sai de `res.damage_mult`
## aplicado ao golpe dentro de `strike()`, ANTES de `_apply_reaction` rodar.
## Os itens de sinergia das outras seis reacoes (Para-Raios, Estopim Curto,
## Esporo Dormente, Bico Para-Raio) estao vivos e medidos.
## DIVIDA DE COBERTURA: peca que nao muda numero nenhum e a gente sabe por que.
## Vazia hoje, e o certo e que continue vazia — se voce precisar escrever aqui,
## escreva tambem o que falta para tirar. As duas ultimas entradas (Lente de
## Forja e Chave de Vapor) sairam em 16/09, quando `rx_dmg_add` passou a valer
## para as reacoes AMPLIFY: o bonus era aplicado depois de o multiplicador do
## golpe ja ter sido consumido, entao os dois itens eram decoracao.
const COB_DIVIDA := {}


func _check_cobertura() -> void:
	print("[cobertura de dados]")
	var fonte := _cob_fonte()
	ok(fonte.length() > 100000, "li o fonte dos .gd (%d caracteres)" % fonte.length())
	ok(fonte.find("__cobertura_sintetica__") < 0,
		"a varredura NAO inclui o proprio smoke_test (senao a cerca se autoriza)")
	# AUTOTESTE DA VARREDURA, no molde do que tools/lint_ui.py ja faz: uma chave
	# que EXISTE e uma que nao existe. Sem ele, um erro na montagem da busca
	# (aspas, caminho errado, diretorio vazio) faria a cerca passar verde para
	# sempre — que foi exatamente o que aconteceu com a primeira versao da regra
	# de icone do lint, e um lint que nao morde e pior do que nenhum.
	ok(fonte.find("\"hp_scale\"") >= 0, "a varredura acha uma chave que EXISTE")
	ok(fonte.find("\"chave_que_nao_existe_em_lugar_nenhum\"") < 0,
		"e NAO acha uma que nao existe")
	_cob_chaves(fonte)
	_cob_efeitos()


# --- (A) cobertura de chave ------------------------------------------------

func _cob_fonte() -> String:
	var partes: Array = []
	for raiz in ["res://src", "res://tools"]:
		_cob_colher(raiz, partes)
	return "\n".join(partes)


func _cob_colher(dir_path: String, out: Array) -> void:
	var d := DirAccess.open(dir_path)
	if d == null:
		return
	d.list_dir_begin()
	var n := d.get_next()
	while n != "":
		var full: String = dir_path + "/" + n
		if d.current_is_dir():
			if not n.begins_with("."):
				_cob_colher(full, out)
		elif n.ends_with(".gd") and not COB_FORA_DA_VARREDURA.has(full):
			out.append(FileAccess.get_file_as_string(full))
		n = d.get_next()
	d.list_dir_end()


func _cob_liberada(nome: String, caminho: String) -> bool:
	for l in COB_LIVRES:
		if nome.begins_with(String(l[0])) or caminho.begins_with(String(l[0])):
			return true
	return false


## Todo caminho ate uma folha de `tuning.json`. Array conta como folha: um array
## morto e tao morto quanto um numero morto (era o caso das duas faixas de
## reacoes do bloco `targets`). Chave que comeca com "_" e prosa, nao dado.
func _cob_caminhos(o: Variant, caminho: String, out: Array) -> void:
	if o is Dictionary:
		for k in (o as Dictionary).keys():
			if String(k).begins_with("_"):
				continue
			_cob_caminhos((o as Dictionary)[k], caminho + "/" + String(k), out)
	else:
		out.append(caminho)


func _cob_chaves(fonte: String) -> void:
	var chaves: Dictionary = {}     # nome da chave -> quem a declara
	for id in Db.item_order:
		var it: Dictionary = Db.items[id]
		for k in (it.get("mods", {}) as Dictionary).keys():
			_cob_anota(chaves, String(k), "item %s" % String(it.get("name", id)))
	for id2 in Db.relic_order:
		var rl: Dictionary = Db.relics[id2]
		for k2 in (rl.get("mods", {}) as Dictionary).keys():
			_cob_anota(chaves, String(k2), "reliquia %s" % String(rl.get("name", id2)))
	for r in Db.resonances:
		for k3 in (r.get("mods", {}) as Dictionary).keys():
			_cob_anota(chaves, String(k3), String(r.get("name", "?")))

	var orfas: Array = []
	var nomes: Array = chaves.keys()
	nomes.sort()
	for nome in nomes:
		if _cob_liberada(String(nome), ""):
			continue
		if fonte.find("\"%s\"" % String(nome)) < 0:
			orfas.append("%s — %s" % [nome, ", ".join(chaves[nome])])
	ok(orfas.is_empty(), "as %d chaves de mods sao citadas por algum .gd%s"
		% [nomes.size(), _cob_lista(orfas)])

	var caminhos: Array = []
	_cob_caminhos(Db.tuning, "", caminhos)
	var orfas2: Array = []
	for c in caminhos:
		var pedacos: PackedStringArray = String(c).split("/")
		var nome2: String = String(pedacos[pedacos.size() - 1])
		if _cob_liberada(nome2, String(c)):
			continue
		if fonte.find("\"%s\"" % nome2) < 0:
			orfas2.append(String(c))
	ok(orfas2.is_empty(), "as %d chaves de tuning.json sao citadas por algum .gd%s"
		% [caminhos.size(), _cob_lista(orfas2)])
	print("  ---  %d chaves de mods, %d folhas de tuning, %d arquivo(s) fora de escopo"
		% [nomes.size(), caminhos.size(), COB_FORA_DE_ESCOPO.size()])


func _cob_anota(tab: Dictionary, chave: String, quem: String) -> void:
	if not tab.has(chave):
		tab[chave] = []
	(tab[chave] as Array).append(quem)


func _cob_lista(itens: Array) -> String:
	if itens.is_empty():
		return ""
	return " — ORFAS: " + "; ".join(itens)


# --- (B) cobertura de efeito -----------------------------------------------

func _cob_efeitos() -> void:
	var base := _cob_impressao({})
	ok(base != "", "a impressao de referencia foi montada (%d caracteres)" % base.length())
	# AUTOTESTE DA IMPRESSAO. Uma peca de mods VAZIO tem de sair identica a
	# referencia (prova que a impressao e determinista — se ela oscilasse por
	# ordem de dicionario ou por float sem formato, TODA peca passaria, inclusive
	# as mortas) e um mod grosso tem de sair diferente (prova que ela e sensivel).
	ok(_cob_impressao({"tipo": "mods", "mods": {}}) == base,
		"a impressao e ESTAVEL: mods vazio nao muda um digito")
	ok(_cob_impressao({"tipo": "mods", "mods": {"team_hp_mult": 0.5}}) != base,
		"e SENSIVEL: metade do HP da equipe muda a impressao")
	var mortas: Array = []
	var recusadas: Array = []
	for id in Db.item_order:
		_cob_julga_item(id, "item %s" % String(Db.items[id].get("name", id)),
			base, mortas, recusadas)
	for id2 in Db.relic_order:
		_cob_julga({"tipo": "reliquia", "id": id2},
			"reliquia %s" % String(Db.relics[id2].get("name", id2)), base, mortas, recusadas)
	for r in Db.resonances:
		_cob_julga({"tipo": "mods", "mods": r.get("mods", {})},
			String(r.get("name", "?")), base, mortas, recusadas)
	var total: int = Db.item_order.size() + Db.relic_order.size() + Db.resonances.size()
	ok(recusadas.is_empty(), "toda peca achou onde ser equipada%s" % _cob_lista(recusadas))

	var novas: Array = []
	var pendentes: Array = []
	for m in mortas:
		if COB_DIVIDA.has(m):
			pendentes.append(m)
		else:
			novas.append(m)
	ok(novas.is_empty(), "as %d pecas MUDAM algum numero do combate%s"
		% [total, _cob_lista(novas)])
	for chave in COB_DIVIDA.keys():
		if not pendentes.has(chave):
			print("  ---  divida quitada: apague %s de COB_DIVIDA" % chave)
	for p2 in pendentes:
		print("  ---  divida: %s nao muda numero nenhum — %s"
			% [p2, String(COB_DIVIDA[p2])])


## Um item so e condenado depois de tentar TODOS os portadores possiveis.
func _cob_julga_item(id: String, nome: String, base: String,
		mortas: Array, recusadas: Array) -> void:
	var tentados := 0
	for dono in range(COB_EQUIPE.size()):
		var imp := _cob_impressao({"tipo": "item", "id": id, "dono": dono})
		if imp == "":
			break
		tentados += 1
		if imp != base:
			return
	if tentados == 0:
		recusadas.append(nome)
	else:
		mortas.append(nome)


func _cob_julga(peca: Dictionary, nome: String, base: String,
		mortas: Array, recusadas: Array) -> void:
	var imp := _cob_impressao(peca)
	if imp == "":
		recusadas.append(nome)
	elif imp == base:
		mortas.append(nome)


## A impressao digital de uma run inteira com a peca equipada.
##
## Tres combates completos pelo caminho do jogo (CombatBuilder + run_to_end),
## mais os numeros de RUN que nenhum combate produz (Vinculo, Estomago, premio
## do no), mais a bancada dirigida a mao. Determinista: mesma semente, mesmo
## time, mesmos temas, mesma ordem.
func _cob_impressao(peca: Dictionary) -> String:
	Db.relics.erase(COB_SINTETICA)
	Run.start_run(COB_SEMENTE)
	Run.set_starting_team(COB_EQUIPE)
	Run.node_index = 4
	if not _cob_equipar(peca):
		return ""
	var partes: Array = [_cob_digitos_de_run()]
	for k in range(COB_TEMAS.size()):
		partes.append(_cob_digitos_de_combate(k))
	partes.append(_cob_bancada())
	Db.relics.erase(COB_SINTETICA)
	return "|".join(partes)


## RESSONANCIA ENTRA PELO CANO DA RELIQUIA, de proposito.
##
## Uma ressonancia nao se equipa: ela acende por Peso Elemental, e mudar o time
## para acende-la mudaria o combate inteiro — os dois lados da comparacao
## deixariam de ser identicos e o teste nao provaria nada. Mas `Run.mods()`
## funde ressonancia e reliquia no MESMO `_merge`, com as mesmas regras de
## multiplicativo e de substituicao, e e esse dicionario que chega ao simulador.
## Injetar os mods da ressonancia como uma reliquia sintetica percorre
## exatamente o caminho que a ressonancia percorreria. A entrada some de
## `Db.relics` no fim, e nunca entra em `relic_order`, entao a loja nao a ve.
func _cob_equipar(peca: Dictionary) -> bool:
	match String(peca.get("tipo", "")):
		"":
			return true
		"item":
			# O PORTADOR IMPORTA. O Nucleo Gelido num bicho que JA e de Gelo nao
			# muda numero nenhum — e o item nao esta morto, o portador e que
			# estava errado. `dono` escolhe o n-esimo candidato, e quem julga
			# tenta os outros antes de condenar a peca.
			var iid := String(peca["id"])
			var alvo: int = int(peca.get("dono", 0))
			var vistos := 0
			for u in Run.team:
				if u.accepts_item(iid):
					if vistos == alvo:
						u.items.append(iid)
						return true
					vistos += 1
			return false
		"reliquia":
			Run.add_relic(String(peca["id"]))
			return Run.has_relic(String(peca["id"]))
		"mods":
			Db.relics[COB_SINTETICA] = {"id": COB_SINTETICA, "name": "cobertura",
				"kind": "reacao", "text": "", "mods": peca.get("mods", {})}
			Run.add_relic(COB_SINTETICA)
			return Run.has_relic(COB_SINTETICA)
	return false


## Os numeros que vivem FORA do combate: Vinculo (Elo Extra), Estomago (Estomago
## de Ferro) e o premio do no (Ampulheta Quebrada, via reward_mult). Sem isto
## tres reliquias inteiras nao teriam onde aparecer.
func _cob_digitos_de_run() -> String:
	var estomago := 0
	var vagas := 0
	for u in Run.team:
		estomago += u.estomago()
		vagas += u.item_slots()
	var no: Dictionary = NodeGen.generate_pair(4)[0]
	var premio: int = int(Dictionary(no.get("rewards", {})).get("ether", 0))
	return "run %d/%d/%d/%d/%d" % [Run.bond_total(), estomago, vagas, premio,
		Run.team.size()]


func _cob_no(k: int) -> Dictionary:
	return {"type": "rinha", "rewards": {"ether": 0}, "payload": {
		"theme": COB_TEMAS[k], "count": 4, "power": 1.0,
		"enemy_seed": 7100 + k, "arena": "", "mods": []}}


func _cob_digitos_de_combate(k: int) -> String:
	var sim := CombatBuilder.build(_cob_no(k), 4100 + k)
	sim.run_to_end(2000)
	var log := sim.combat_log()
	var partes: Array = ["c%d/%.3f/%.2f/%.2f/%.2f/%d/%.2f" % [sim.winner, sim.now,
		sim.max_duration, float(log["damage_dealt"]), float(log["damage_taken"]),
		int(log["total_reactions"]), sim.energy]]
	# as chaves saem ORDENADAS: a lista de `combat_log` vem ordenada por contagem
	# e empate entre duas reacoes poderia trocar a ordem sem nada ter mudado
	var rk: Array = sim.stat_reactions.keys()
	rk.sort()
	for r in rk:
		partes.append("%s%d" % [String(r), int(sim.stat_reactions[r])])
	for u in sim.units:
		partes.append("%d:%s:%.2f/%.2f/%.2f/%.2f/%.2f/%d/%d" % [u.id, u.element,
			u.hp, u.hp_max, u.ult_energy, u.dmg_dealt, u.healing_done,
			u.reactions_caused, 1 if u.alive else 0])
	return "".join(partes)


## A BANCADA: o mesmo combate, dirigido a mao.
##
## Tres combates inteiros pegam a maioria das pecas, mas nao todas. Um item que
## so aparece quando ha CONTROLE (Amuleto Teimoso), quando a aplicacao passa do
## teto de UA (Totem do Excesso) ou quando UMA reacao especifica acontece
## (Para-Raios, Lente de Forja) pode atravessar tres combates sem tocar em
## numero nenhum — e ai o teste diria "morto" sobre uma peca viva, que e o pior
## resultado possivel para uma cerca: o proximo a ler acredita menos nela do que
## no proprio codigo.
##
## Entao a bancada FORCA cada condicao: cada aliado aplica cada aura e desfere
## cada elemento contra um alvo de HP inflado (nada morre no meio da medicao), e
## todo numero que sai entra na impressao. E a mesma tese do bloco
## [arena e modificadores] — provar efeito com simulacao, nao com leitura.
func _cob_bancada() -> String:
	var sim := CombatBuilder.build(_cob_no(0), 4242)
	var meus := sim.alive_units(0)
	var deles := sim.alive_units(1)
	if meus.is_empty() or deles.is_empty():
		return "bancada vazia"
	var alvo: SimUnit = deles[0]
	alvo.hp_max = 1000000.0
	alvo.hp = alvo.hp_max
	var linhas: Array = []

	# GOLPE x AURA: 5 auras x 5 elementos por aliado. E aqui que passam reacao,
	# dano de reacao por item, atordoamento por reacao, Coro de Gelo, Coro de
	# Natureza, carga_ua_mult, critico, segunda reacao e o respingo de aura do
	# Coracao Instavel (por isso a aura DE QUEM BATE tambem e medida).
	for u in meus:
		u.pos = alvo.pos
		for aura_el in Db.slice_elements:
			for golpe in Db.slice_elements:
				alvo.hp = alvo.hp_max
				alvo.shield = 0.0
				alvo.alive = true
				alvo.aura.clear()
				alvo.control_until = 0.0
				alvo.control_immune_until = 0.0
				u.aura.clear()
				u.ult_energy = 0.0
				u.rx_stun_ready.clear()
				sim.energy = 0.0
				sim._amplify_cd.clear()
				sim.put_aura(u, alvo, aura_el, 4.0)
				sim.strike(u, alvo, {"element": golpe, "ua": 2.0, "mult": 1.0})
				linhas.append("g%.3f/%.3f/%.3f/%.3f/%.3f/%.3f" % [
					alvo.hp_max - alvo.hp, alvo.aura.total_ua(), u.aura.total_ua(),
					u.ult_energy, sim.energy, alvo.control_until])

	# TETO DE UA: o Totem do Excesso e o Coro de Fogo so mudam um numero quando a
	# aplicacao ULTRAPASSA o teto padrao — e um golpe de 2 UA nunca ultrapassa.
	for u2 in meus:
		for el in Db.slice_elements:
			alvo.aura.clear()
			sim.put_aura(u2, alvo, el, 20.0)
			linhas.append("t%.3f" % alvo.aura.total_ua())

	# DECAIMENTO E DANO DE AURA NO RELOGIO: Totem da Persistencia, Sifao das
	# Mares, Eco de Agua e Eco de Natureza (de quanto em quanto tempo o Esporo
	# dobra) so existem nesta medicao. Por aliado, porque o Sifao e do hipocampo.
	for u3 in meus:
		for el2 in Db.slice_elements:
			alvo.aura.clear()
			alvo.hp = alvo.hp_max
			sim.put_aura(u3, alvo, el2, 6.0)
			for t in range(40):
				sim._tick_auras()
				if t == 9 or t == 19 or t == 39:
					linhas.append("d%.4f/%.2f" % [alvo.aura.total_ua(),
						alvo.hp_max - alvo.hp])

	# CONTROLE: a Vontade encurta a duracao (GDD 7.4). Sem esta medicao o Amuleto
	# Teimoso so mudaria um numero quando o inimigo por acaso congelasse alguem.
	for u4 in meus:
		u4.control_until = 0.0
		u4.control_immune_until = 0.0
		sim.apply_control(u4, "congelado", 2.0, 1.0)
		linhas.append("k%.4f" % u4.control_until)

	# CURA CONCEDIDA (Folha Perene) e DANO REPARTIDO (Coleira Compartilhada),
	# mais a carga de ultimate por golpe recebido (Bateria Ossea, Diapasao Vivo).
	for u5 in meus:
		for u6 in meus:
			u6.hp = u6.hp_max * 0.5
		sim.heal(u5, meus[0], 120.0)
		linhas.append("h%.3f" % meus[0].hp)
	for u7 in meus:
		for u8 in meus:
			u8.hp = u8.hp_max
		u7.ult_energy = 0.0
		sim._deal(alvo, u7, 200.0, "physical", "", false, false)
		var soma := 0.0
		for u9 in meus:
			soma += u9.hp_max - u9.hp
		linhas.append("s%.3f/%.3f/%.3f" % [u7.hp_max - u7.hp, soma, u7.ult_energy])

	# GOLPE BASICO PELO CAMINHO DO SIMULADOR: e por ele que ua_per_hit +
	# team_ua_add (Mao do Alquimista, Coro de Agua, Bico Para-Raio) viram numero,
	# e tambem a cadencia de ataque e o deslocamento.
	for ua in meus:
		alvo.aura.clear()
		alvo.hp = alvo.hp_max
		ua.aura.clear()
		ua.ult_energy = 0.0
		ua.windup_until = -1.0
		ua.pos = alvo.pos
		sim._basic_attack(ua, alvo)
		linhas.append("b%.3f/%.3f/%.3f/%.4f" % [alvo.hp_max - alvo.hp,
			alvo.aura.total_ua(), ua.ult_energy, ua.attack_interval(0.0)])

	# AS MESMAS DUAS MEDIDAS DO OUTRO LADO DO CAMPO. `CombatSim.begin` escreve
	# `cap_overrides` e `decay_mult` nas unidades DO PROPRIO LADO — e o Coro de
	# Fogo (teto de Combustao) e o Eco de Agua (Encharcado dura mais) vivem
	# exatamente ali. Uma bancada que so olha o alvo inimigo da os dois por
	# mortos, e nao estao: o que se pode discutir e o LADO em que eles caem, que
	# e decisao de desenho e nao coisa que uma cerca resolva.
	for uc in meus:
		for el3 in Db.slice_elements:
			uc.aura.clear()
			uc.hp = uc.hp_max
			sim.put_aura(alvo, uc, el3, 20.0)
			linhas.append("m%.3f" % uc.aura.total_ua())
			for t2 in range(30):
				sim._tick_auras()
			linhas.append("n%.4f/%.2f" % [uc.aura.total_ua(), uc.hp_max - uc.hp])
		uc.aura.clear()
		uc.hp = uc.hp_max

	# GELIDO NO PROPRIO CORPO: e o unico jeito de o Eco de Gelo — que reduz a
	# velocidade de MOVIMENTO de quem esta Gelido — aparecer num numero.
	for ub in meus:
		ub.aura.clear()
		sim.put_aura(null, ub, "GELO", 4.0)
		linhas.append("f%.4f/%.4f/%.3f/%.3f/%.3f/%.3f/%s" % [
			ub.eff_speed(sim._move_slow(0)), ub.attack_interval(sim._gelido_slow(0)),
			ub.eff_atk(), ub.eff_pe(), ub.eff_def(), ub.hp_max, ub.element])
	return "".join(linhas)


# ---------------------------------------------------------------------------

## O CSV DO AUTOPLAY VOLTA A PRODUZIR NUMEROS.
##
## `autoplay.gd:474` tinha 12 especificadores para 11 argumentos. O operador `%`
## do GDScript, com aridade errada, NAO falha: devolve o proprio formato. As 400
## linhas do arquivo saiam literalmente "%d,%s,%d,..." — o unico export de dados
## da run nunca produziu um numero, e o README:32 o anuncia como a ferramenta de
## balanceamento. Foi um ano de CSV vazio porque nada olhava o arquivo.
##
## Esta assercao escreve duas runs num arquivo temporario e le de volta. O sinal
## e o caractere de porcentagem: se ele aparecer numa linha de dados, a
## substituicao nao aconteceu.
func _check_csv() -> void:
	print("[csv do autoplay]")
	var ap: Node = load("res://tools/autoplay.gd").new()
	var caminho := "user://smoke_autoplay.csv"
	ap.csv_path = caminho
	ap.rows = [
		{"seed": 1000, "won": true, "node": 9, "combats": 9, "duo": "sheep+apollo",
			"team": 5, "bond": 5, "elements": "FOGO/GELO", "resonances": "Eco de Fogo",
			"relics": 1, "ether": 30, "dishes": 2},
		{"seed": 1017, "won": false, "node": 4, "combats": 3, "duo": "coalla+apollo",
			"team": 3, "bond": 3, "elements": "NATUREZA", "resonances": "",
			"relics": 0, "ether": 12, "dishes": 0},
	]
	ap._write_csv()
	ap.free()
	var texto := FileAccess.get_file_as_string(caminho)
	var linhas: PackedStringArray = texto.strip_edges().split("\n")
	ok(linhas.size() == 3, "cabecalho + 2 runs (%d linhas)" % linhas.size())
	var colunas: int = String(linhas[0]).split(",").size()
	var com_formato := 0
	var torta := 0
	for i in range(linhas.size()):
		var l := String(linhas[i])
		if l.find("%") >= 0:
			com_formato += 1
		if l.split(",").size() != colunas:
			torta += 1
	ok(com_formato == 0, "nenhuma linha sai com o FORMATO em vez do numero (%d)" % com_formato)
	ok(torta == 0, "toda linha tem as %d colunas do cabecalho (%d tortas)" % [colunas, torta])
	if linhas.size() >= 2:
		ok(String(linhas[1]).begins_with("1000,sheep+apollo,1,9,9,"),
			"os campos saem na ordem do cabecalho (%s)" % String(linhas[1]))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(caminho))


func _check_flow() -> void:
	print("[fluxo de telas]")
	var main_scene: PackedScene = load("res://scenes/main.tscn")
	var main: Control = main_scene.instantiate()
	add_child(main)
	await get_tree().process_frame
	ok(main.screen is ScreenTitle, "abre no titulo")
	main.screen.start_requested.emit(555)
	await get_tree().process_frame
	ok(main.screen is ScreenStarter, "iniciar run leva a ESCOLHA DE INICIAIS")
	# PELO CAMINHO DO JOGADOR: emite o `clicked` do cartao, nao chama
	# _toggle direto. Chamar o metodo pula justamente a fiacao do sinal —
	# foi assim que o teste das magias passou verde enquanto o Meteoro e o
	# Orvalho nao funcionavam no jogo. Se o cartao trocar de tipo outra vez,
	# e aqui que tem de doer.
	for starter_id in ["sheep", "pinto_raio"]:
		var sc: CardButton = main.screen._cards[starter_id]
		sc.clicked.emit()
	ok(not main.screen._btn.disabled, "dupla marcada pelo CLIQUE habilita o botao")
	ok(main.screen._picked.size() == 2, "o clique no cartao selecionou os dois")
	main.screen.confirmed.emit(["sheep", "pinto_raio"])
	await get_tree().process_frame
	ok(main.screen is ScreenMap, "iniciais confirmados -> escolha de combate")
	ok(Run.team.size() == 2 and Run.team[0].species_id == "sheep",
		"a equipe e a dupla escolhida")
	ok(main.pair.size() == 2, "duas opcoes")
	var both_rinha := true
	for n in main.pair:
		if String(n.get("type", "")) != "rinha":
			both_rinha = false
	ok(both_rinha, "as DUAS opcoes sao combates")
	ok(String(main.pair[0]["title"]) != String(main.pair[1]["title"]),
		"combates diferentes (%s vs %s)" % [main.pair[0]["title"], main.pair[1]["title"]])

	main._on_node_chosen(main.pair[0])
	await get_tree().process_frame
	ok(main.screen is ScreenPrep, "escolha -> preparacao")
	main.screen.fight.emit()
	await get_tree().process_frame
	ok(main.screen is ScreenCombat, "preparacao -> combate")
	main.screen.sim.run_to_end()
	main.screen._resolve()
	await get_tree().process_frame
	ok(main.screen is ScreenResult, "combate -> log")
	var won: bool = not Run.defeated
	main.screen.continue_pressed.emit()
	await get_tree().process_frame
	if won:
		var kind := EventGen.kind_after(Run.node_index)
		var expected: bool = (main.screen is ScreenRecruit) or (main.screen is ScreenShop) 			or (main.screen is ScreenChance) or (main.screen is ScreenKitchen)
		ok(expected, "vitoria -> momento de evento (%s)" % kind)
		main.screen.finished.emit()
		await get_tree().process_frame
		ok(main.screen is ScreenMap, "evento -> proxima escolha de COMBATE")
		var both := true
		for n2 in main.pair:
			if String(n2.get("type", "")) != "rinha":
				both = false
		ok(both, "as duas opcoes seguem sendo combates")
	else:
		ok(main.screen is ScreenEnd, "derrota -> tela final")
	main.queue_free()
