extends Node
## Captura PNG de cada tela do protótipo (fluxo 2-combates + eventos).
##   godot --path . res://tools/screenshots.tscn -- --out=res://shots

var out_dir := "res://shots"
var holder: Control


func _ready() -> void:
	# SEM ANIMACAO nas ferramentas: um print tirado no meio da transicao
	# nao serve para comparar nada, e um teste que espera o fim do tween
	# vira lento e intermitente.
	Juice.enabled = false
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out_dir = a.split("=")[1]
	DirAccess.make_dir_recursive_absolute(out_dir)
	var w := 1600
	var h := 900
	for a2 in OS.get_cmdline_user_args():
		if a2.begins_with("--res="):
			var parts := a2.split("=")[1].split("x")
			w = int(parts[0])
			h = int(parts[1])
	get_window().size = Vector2i(w, h)
	holder = Control.new()
	holder.theme = PrismaTheme.get_theme()
	holder.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(holder)
	await get_tree().process_frame
	await _shoot_all()
	print("shots em ", ProjectSettings.globalize_path(out_dir))
	get_tree().quit(0)


func _bg() -> void:
	var r := ColorRect.new()
	r.color = UI.BG
	r.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	holder.add_child(r)


func _clear() -> void:
	for c in holder.get_children():
		holder.remove_child(c)
		c.queue_free()
	await get_tree().process_frame


func _capture(name: String) -> void:
	for i in range(4):
		await get_tree().process_frame
	# Sob --headless este sinal NUNCA retoma a corrotina: o processo gira
	# para sempre e nao escreve PNG nenhum (medido em 15/09, cinco tentativas
	# de ate 540 s). A espera existe para o quadro estar DESENHADO quando a
	# imagem for lida, e so ha o que esperar quando ha desenho.
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("%s/%s.png" % [out_dir, name])
	print("  ", name)


func _add(c: Control) -> void:
	c.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	holder.add_child(c)


## A Mao do Domador, do jeito mais simples que ainda conta: lanca o que couber
## na Energia, mirando no lado CERTO. Sem isto "Ativos lancados" saia 0 na tela
## de fim, e um revisor leria o cartao como quebrado em vez de le-lo como e.
func _lancar_ativo(sim: CombatSim) -> void:
	for aid in Run.actives:
		if not sim.can_cast(String(aid)):
			continue
		var modo := String(Db.actives.get(String(aid), {}).get("aim", ""))
		var lado: int = 0 if modo.begins_with("ally") else 1
		var pool := sim.alive_units(lado)
		if pool.is_empty():
			return
		var c := Vector2.ZERO
		for u in pool:
			c += u.pos
		var inimigos := sim.alive_units(1)
		var alvo: SimUnit = inimigos[0] if not inimigos.is_empty() else null
		sim.cast_active(String(aid), c / float(pool.size()), alvo, "GELO")
		return


## Uma run JOGADA de verdade ate o passo pedido.
##
## "A RUN EM NUMEROS" da tela de fim le `Run.history`, e quem escreve os numeros
## de combate la e `Main._on_combat_over`. Um print montado com uma run recem
## criada mostraria "nenhum combate registrado" — que e exatamente o estado que
## ninguem precisa revisar. Aqui os combates acontecem (CombatBuilder +
## run_to_end, o mesmo caminho do autoplay) e o historico recebe os MESMOS
## campos que o roteador escreve.
func _jogar_ate(passo_final: int) -> void:
	while Run.node_index < passo_final:
		Run.node_index += 1
		var no: Dictionary = NodeGen.generate_pair(Run.node_index)[0]
		Run.history.append({"index": Run.node_index, "type": String(no.get("type", ""))})
		var sim := CombatBuilder.build(no, Run.seed_value * 31 + Run.node_index)
		while not sim.finished:
			sim.step()
			_lancar_ativo(sim)
			sim.drain_events()
		CombatBuilder.writeback(sim)
		var log := sim.combat_log()
		var h: Dictionary = Run.history[Run.history.size() - 1]
		h["won"] = sim.winner == CombatSim.Winner.PLAYER
		h["duration"] = float(log["duration"])
		h["reactions"] = int(log["total_reactions"])
		h["damage"] = float(log["damage_dealt"])
		h["taken"] = float(log["damage_taken"])
		h["actives"] = (log["actives"] as Array).size()
		var big: Dictionary = log.get("biggest_hit", {})
		h["biggest"] = float(big.get("amount", 0.0))
		h["biggest_src"] = String(big.get("src", ""))
		Run.add_ether(int(Dictionary(no.get("rewards", {})).get("ether", 0)))
		Run.heal_between_nodes()


func _shoot_all() -> void:
	# 1) titulo
	await _clear(); _bg()
	_add(ScreenTitle.new())
	await _capture("01_titulo")

	# CONFIGURACOES: a tela nova do menu
	await _clear(); _bg()
	var op := ScreenOptions.new()
	_add(op)
	await get_tree().process_frame
	await _capture("01b_opcoes")

	# 1b) escolha de iniciais, com dupla marcada e reacoes visiveis
	Run.start_run(4242)
	await _clear(); _bg()
	var st := ScreenStarter.new()
	_add(st)
	await get_tree().process_frame
	st._toggle("sheep")
	st._toggle("hipocampo")
	await _capture("02_iniciais")

	# run de exemplo com equipe crescida
	Run.start_run(4242)
	Run.node_index = 4
	Run.add_ether(22)
	Run.recruit("apollo")
	Run.recruit("coalla")
	Run.recruit("pinto_raio")
	Run.add_relic("mao_alquimista")
	Run.add_ether(16)
	Run.add_ether(12)
	Run.add_ether(8)
	for u in Run.team:
		if u.can_equip():
			u.items.append("totem_fole")
			break
	Run.cook("espeto_flamejante", Run.team[0])

	# 2) escolha entre DOIS combates
	await _clear(); _bg()
	var m := ScreenMap.new()
	m.setup(NodeGen.generate_pair(4))
	_add(m)
	await _capture("03_escolha_de_combate")

	# 3) preparacao
	var pair := NodeGen.generate_pair(4)
	var rinha: Dictionary = pair[1]
	await _clear(); _bg()
	Run.add_relic("mao_alquimista")
	Run.add_relic("lente_fratal")
	for u2 in Run.team:
		if u2.can_equip():
			u2.items.append("presa_rachada")
	var p := ScreenPrep.new()
	p.setup(rinha)
	_add(p)
	await _capture("04_preparacao")
	p._open_synergies()
	for i in range(3):
		await get_tree().process_frame
	await _capture("04b_sinergias")

	# A MESMA tela com equipe POBRE (dois elementos): e o caso que estourava
	# a altura, porque quase toda reacao fica trancada. Se voltar a vazar,
	# e neste print que aparece.
	await _clear(); _bg()
	Run.start_run(4242)
	Run.set_starting_team(["apollo", "pinto_raio"])
	var p2 := ScreenPrep.new()
	p2.setup(rinha)
	_add(p2)
	await get_tree().process_frame
	p2._open_synergies()
	for i in range(3):
		await get_tree().process_frame
	await _capture("04c_sinergias_pobre")

	# 4) combate em andamento (animacoes de verdade)
	await _clear(); _bg()
	var cb := ScreenCombat.new()
	cb.setup(rinha)
	_add(cb)
	await get_tree().process_frame
	cb.set_process(false)
	for i in range(70):
		for j in range(2):
			if not cb.sim.finished:
				cb.sim.step()
		cb.field.feed(cb.sim.drain_events())
		cb._time_bar.set_value(cb.sim.now, cb.sim.max_duration)
		cb._refresh_actives()
		cb._refresh_actives()
		await get_tree().process_frame
	await _capture("05_combate")

	# 5) log pos-combate
	cb.sim.run_to_end()
	var log := cb.sim.combat_log()
	log["won"] = cb.sim.winner == CombatSim.Winner.PLAYER
	log["gained"] = {"ether": 22}
	# A SEGUNDA TABELA vem da MESMA funcao que o jogo usa. Sem esta linha o
	# print saia com "O BANDO INIMIGO / sem dados deste lado" — metade da tela
	# vazia — porque `combat_log()` nao monta o lado 1: quem monta e
	# ScreenCombat._enemy_units, onde o `sim` ainda esta vivo. O print mostrava
	# um estado que o jogo nunca produz, que e o pior defeito que uma
	# ferramenta de revisao visual pode ter.
	log["enemy_units"] = cb._enemy_units()
	await _clear(); _bg()
	var r := ScreenResult.new()
	r.setup(rinha, log)
	_add(r)
	await _capture("06_log_de_combate")

	# 6) esteira de eventos automaticos
	Run.node_index = 2
	await _clear(); _bg()
	# 7) os tres MOMENTOS de evento
	Run.node_index = 1
	await _clear(); _bg()
	var rc := ScreenRecruit.new()
	rc.setup(EventGen.recruit_offer(1))
	_add(rc)
	await _capture("07a_recruta")

	Run.node_index = 4
	Run.add_ether(70)
	await _clear(); _bg()
	var sh := ScreenShop.new()
	# a banca do print inclui de proposito um item DE DONO e um de dono que
	# a equipe nao tem: sao os dois casos que a tela precisa saber desenhar
	var banca: Array = EventGen.shop_offer(4)
	banca.resize(mini(banca.size(), 2))
	# O PRECO SAI DA MESMA TABELA QUE O JOGO LE. Estava escrito 14 a mao, e
	# quando a economia foi reapertada (Raro 24 -> 32) o print passou a mostrar
	# um item RARO mais barato que um COMUM de 15 — um revisor leria a tela
	# como defeito de precificacao, e o defeito estava no print.
	var p_raro: int = int(Db.tuning.get("momentos", {}).get("loja", {})
		.get("preco_por_raridade", {}).get("Raro", 32))
	banca.append({"kind": "item", "id": "cauda_de_brasa", "price": p_raro,
		"name": String(Db.items["cauda_de_brasa"]["name"]),
		"text": String(Db.items["cauda_de_brasa"]["text"]),
		"tag": "Raro", "owner": "apollo"})
	banca.append({"kind": "item", "id": "la_condutora", "price": p_raro,
		"name": String(Db.items["la_condutora"]["name"]),
		"text": String(Db.items["la_condutora"]["text"]),
		"tag": "Raro", "owner": "sheep"})
	sh.setup(banca, 4)
	_add(sh)
	# o print seleciona o item DE DONO: e o caso em que o preview tem mais a
	# mostrar (retrato + "So o Apollo pode usar")
	await get_tree().process_frame
	sh._panel._select(2)
	await get_tree().process_frame
	await _capture("07b_loja")

	# o momento de PODER usa a MESMA peca da Feira (PickPanel)
	await _clear(); _bg()
	var pw := ScreenPower.new()
	pw.setup(EventGen.power_offer(2), 2)
	_add(pw)
	await get_tree().process_frame
	await _capture("07f_poder")

	# o Mercador com um Prismon INVESTIDO: e o caso em que o comparativo
	# tem o que mostrar dos dois lados
	await _clear(); _bg()
	Run.team[0].items.append("presa_rachada")
	Run.team[0].dishes.append("espeto_flamejante")
	var tr := ScreenTrade.new()
	tr.setup(EventGen.trade_offer(4), 4)
	_add(tr)
	await get_tree().process_frame
	await _capture("07g_troca")

	Run.node_index = 2
	Run.add_ether(16)
	Run.add_ether(12)
	Run.add_ether(8)
	await _clear(); _bg()
	var kt := ScreenKitchen.new()
	kt.setup(EventGen.kitchen_offer(2), 2)
	_add(kt)
	await get_tree().process_frame
	await _capture("07d_cozinha")
	kt._open_picker(String(EventGen.kitchen_offer(2)[0]["id"]))
	for i in range(3):
		await get_tree().process_frame
	await _capture("07e_cozinha_escolha")

	Run.node_index = 2
	await _clear(); _bg()
	var ch := ScreenChance.new()
	ch.setup(EventGen.chance_offer(2), 2)
	_add(ch)
	await _capture("07c_acaso")

	# 8) chefe
	Run.node_index = 9
	await _clear(); _bg()
	var m2 := ScreenMap.new()
	m2.setup(NodeGen.generate_pair(9))
	_add(m2)
	await _capture("08_chefe")

	# 8b/8c) FIM DE RUN, nos dois estados.
	#
	# A revisao de 15/09 achou que esta e a unica tela do jogo que nunca foi
	# discutida — `grep -in "screen_end"` em 1283 linhas de NOTAS.md da zero — e
	# a causa era esta ferramenta: sem print, ninguem revisa. Os dois estados
	# vao juntos de proposito, porque o cartao "A RUN EM NUMEROS" e o mesmo nos
	# dois e so lado a lado da para julgar se ele responde a pergunta certa.
	#
	# A vitoria e uma run ATRAVESSADA (equipe montada, oito combates rodados); a
	# derrota para no meio do Ato com uma equipe magra e um corpo caido, que e a
	# run que o jogador de fato perde.
	Run.start_run(4242)
	Run.set_starting_team(["sheep", "hipocampo"])
	Run.add_ether(90)
	Run.recruit("apollo")
	Run.recruit("pinto_raio")
	Run.recruit("coalla")
	Run.add_relic("mao_alquimista")
	Run.add_relic("lente_fratal")
	Run.cook("espeto_flamejante", Run.team[0])
	_jogar_ate(Run.total_nodes())
	await _clear(); _bg()
	var fim_v := ScreenEnd.new()
	fim_v.setup(true)
	_add(fim_v)
	await get_tree().process_frame
	await _capture("08b_fim_vitoria")

	Run.start_run(4242)
	Run.set_starting_team(["apollo", "hipocampo"])
	_jogar_ate(4)
	Run.team[0].hp_ratio = 0.0
	await _clear(); _bg()
	var fim_d := ScreenEnd.new()
	fim_d.setup(false)
	_add(fim_d)
	await get_tree().process_frame
	await _capture("08c_fim_derrota")

	# o resto do roteiro roda pelo roteador, que reinicia a run do zero
	Run.start_run(4242)

	# 8b) o jogo real pelo roteador, tela a tela — e aqui o trilho e a fita
	# aparecem, que e como o jogador ve
	await _clear()
	var live_scene: PackedScene = load("res://scenes/main.tscn")
	var live: Control = live_scene.instantiate()
	holder.add_child(live)
	await get_tree().process_frame
	live.screen.start_requested.emit(4242)
	await get_tree().process_frame
	live.screen.confirmed.emit(["sheep", "pinto_raio"])
	for i in range(3):
		await get_tree().process_frame
	await _capture("10_run_escolha")

	live._on_node_chosen(live.pair[0])
	for i in range(3):
		await get_tree().process_frame
	await _capture("11_run_preparacao")

	live.screen.fight.emit()
	await get_tree().process_frame
	# o combate pelo roteador: o topo tem de ter sumido
	live.screen.set_process(false)
	for i in range(40):
		for j in range(2):
			if not live.screen.sim.finished:
				live.screen.sim.step()
		live.screen.field.feed(live.screen.sim.drain_events())
		live.screen.panel.refresh()
		await get_tree().process_frame
	await _capture("11b_run_combate")
	live.screen.sim.run_to_end()
	live.screen._resolve()
	for i in range(3):
		await get_tree().process_frame
	await _capture("12_run_log")

	live.screen.continue_pressed.emit()
	for i in range(3):
		await get_tree().process_frame
	await _capture("13_run_evento")
	live.queue_free()
	await get_tree().process_frame

	# 8) o jogo real pelo roteador (HUD)
	await _clear()
	var main_scene: PackedScene = load("res://scenes/main.tscn")
	var main: Control = main_scene.instantiate()
	holder.add_child(main)
	await get_tree().process_frame
	main.screen.start_requested.emit(4242)
	await get_tree().process_frame
	main.screen.confirmed.emit(["sheep", "pinto_raio"])
	for i in range(4):
		await get_tree().process_frame
	await _capture("09_hud_e_escolha")
	main.queue_free()
	await get_tree().process_frame
