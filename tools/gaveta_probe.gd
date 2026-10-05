extends Node
## A GAVETA DO DETALHE, ABERTA — e medida.
##
## O autor relatou: "o botão de ver bando inimigo projetando pra baixo bugou a
## visualização toda, o botão fugiu de alcance e não foi mais possível ver
## nada".
##
## `tools/screenshots.tscn` fotografa a tela de resultado com a gaveta FECHADA,
## que é como ela nasce. O estado que quebra é o de DEPOIS do clique, e ele não
## existia em imagem nenhuma — a mesma cegueira que deixou o cartão do Acaso
## nascer errado.
##
## A regra que esta sonda cobra é uma só, e é a queixa do autor por escrito:
## **todo botão da tela continua dentro da janela com a gaveta aberta**. Um
## botão que existe na árvore e mora em y=1180 não existe.

const SAIDA := "res://shots/z_resultado_gaveta.png"
const ALTURA := 900.0

var _falhas := 0


func _ready() -> void:
	print("=== PRISMON :: sonda da gaveta do resultado ===")
	Juice.enabled = false
	get_window().size = Vector2i(1600, 900)
	await get_tree().process_frame

	# EQUIPE CHEIA CONTRA BANDO CHEIO: é o número de linhas das duas tabelas
	# que decide a altura da gaveta, e o print do autor é de uma run avançada,
	# não da primeira rinha.
	Run.start_run(4242)
	Run.set_starting_team(["sheep", "apollo"])
	for id in ["hipocampo", "pinto_raio", "coalla"]:
		if Run.bond_used() < Run.bond_total():
			Run.recruit(id)
	print("  sua equipe: %d corpos" % Run.team.size())

	var rinha := _rinha_grande()
	print("  rinha: %s (perigo %d)" % [String(rinha.get("title", "?")), int(rinha.get("danger", 0))])

	var raiz := Control.new()
	raiz.theme = PrismaTheme.get_theme()
	raiz.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(raiz)

	# O LOG VEM DO CAMINHO DO JOGO. `combat_log()` não monta o lado inimigo —
	# quem monta é ScreenCombat._enemy_units, com o `sim` ainda vivo.
	var cb := ScreenCombat.new()
	cb.setup(rinha)
	raiz.add_child(cb)
	await get_tree().process_frame
	cb.set_process(false)
	cb.sim.run_to_end()
	var registro := cb.sim.combat_log()
	registro["won"] = cb.sim.winner == CombatSim.Winner.PLAYER
	registro["gained"] = {"ether": 22}
	registro["enemy_units"] = cb._enemy_units()
	print("  tabelas: %d suas x %d dele"
		% [(registro.get("units", []) as Array).size(),
			(registro.get("enemy_units", []) as Array).size()])
	raiz.remove_child(cb)
	cb.queue_free()

	var tela := ScreenResult.new()
	tela.setup(rinha, registro)
	tela.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	raiz.add_child(tela)
	for i in 4:
		await get_tree().process_frame

	print("[gaveta fechada]")
	_medir(tela)

	tela._alternar_detalhe()
	for i in 6:
		await get_tree().process_frame
	print("[gaveta ABERTA]")
	_medir(tela)

	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(ProjectSettings.globalize_path(SAIDA))
	print("  -> ", SAIDA)

	print("")
	if _falhas == 0:
		print("=== TUDO OK ===")
		get_tree().quit(0)
	else:
		print("=== %d FALHA(S) ===" % _falhas)
		get_tree().quit(1)


## O bando mais cheio que o gerador de nós entrega neste Ato.
func _rinha_grande() -> Dictionary:
	var melhor: Dictionary = {}
	var mais := -1
	for tentativa in 6:
		for no in NodeGen.generate_pair(4 + tentativa):
			var corpos := 0
			for l in (no.get("payload", {}).get("band", []) as Array):
				corpos += int(l.get("n", 1))
			if corpos > mais:
				mais = corpos
				melhor = no
	return melhor


func _medir(tela: Control) -> void:
	var botoes: Array = []
	_coleta_botoes(tela, botoes)
	for b in botoes:
		var r: Rect2 = (b as Control).get_global_rect()
		_ok(r.end.y <= ALTURA + 1.0,
			"botao \"%s\" cabe na janela (termina em y=%.0f)" % [_texto_de(b), r.end.y])
	var todos: Array = []
	_coleta(tela, todos)
	var max_y := 0.0
	var quem := ""
	for c in todos:
		var y: float = (c as Control).get_global_rect().end.y
		if y > max_y:
			max_y = y
			quem = (c as Control).get_class()
	print("  fundo da arvore: %.0f px (%s)" % [max_y, quem])


func _coleta(n: Node, out: Array) -> void:
	if n is Control and (n as Control).is_visible_in_tree():
		out.append(n)
	for c in n.get_children():
		_coleta(c, out)


func _coleta_botoes(n: Node, out: Array) -> void:
	if n is BaseButton and (n as Control).is_visible_in_tree():
		out.append(n)
	for c in n.get_children():
		_coleta_botoes(c, out)


func _texto_de(n: Node) -> String:
	if n is Button and String((n as Button).text).strip_edges() != "":
		return String((n as Button).text).strip_edges()
	for c in n.get_children():
		if c is Label:
			return String((c as Label).text)
		var achado := _texto_de(c)
		if achado != "":
			return achado
	return ""


func _ok(cond: bool, msg: String) -> void:
	if cond:
		print("  ok   ", msg)
	else:
		print("  FALHA ", msg)
		_falhas += 1
