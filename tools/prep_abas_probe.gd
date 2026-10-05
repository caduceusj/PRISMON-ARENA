extends Node
## AS TRÊS ABAS DA PREPARAÇÃO, MEDIDAS — e não olhadas de relance.
##
## O autor relatou: "o botão de ver bando inimigo projetando pra baixo bugou a
## visualização toda, o botão fugiu de alcance e não foi mais possível ver
## nada". `tools/screenshots.tscn` fotografa a preparação com a aba BANDO
## aberta e uma equipe de DOIS — que é exatamente o caso que não estoura.
##
## Esta sonda fotografa as TRÊS abas com a equipe CHEIA, e mede: nenhum
## controle pode terminar abaixo dos 900 px da janela. Medir é o ponto; a
## imagem é só para o olho conferir depois.

const SAIDA := "res://shots/z_prep_aba_%s.png"
const ALTURA := 900.0
const LARGURA := 1600.0

var _falhas := 0


func _ready() -> void:
	print("=== PRISMON :: sonda das abas da preparacao ===")
	Juice.enabled = false
	get_window().size = Vector2i(1600, 900)
	await get_tree().process_frame

	Run.start_run(4242)
	Run.set_starting_team(["sheep", "apollo"])
	# EQUIPE CHEIA, com item e prato em todo mundo: o caso do autor, não o do
	# print. Uma tela que só foi vista com dois corpos nunca foi vista.
	for id in ["hipocampo", "pinto_raio", "coalla"]:
		if Run.bond_used() < Run.bond_total():
			Run.recruit(id)
	for u in Run.team:
		for it in Db.item_order:
			if u.accepts_item(String(it)):
				u.items.append(String(it))
				break
		for d in Db.dish_order:
			if String(Db.dishes[d].get("kind", "")) == "nutricao":
				u.dishes.append(String(d))
				break
	print("  equipe: %d corpos, vinculo %d/%d"
		% [Run.team.size(), Run.bond_used(), Run.bond_total()])

	var raiz := Control.new()
	raiz.theme = PrismaTheme.get_theme()
	raiz.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(raiz)

	var no := _um_no_de_combate()
	var tela := ScreenPrep.new()
	tela.setup(no)
	tela.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	raiz.add_child(tela)
	for i in 4:
		await get_tree().process_frame

	for i in range(3):
		var nome := String(ScreenPrep.ABAS[i])
		tela._abrir(i)
		for k in 4:
			await get_tree().process_frame
		print("[aba %s]" % nome)
		_medir(tela)
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		img.save_png(ProjectSettings.globalize_path(SAIDA % nome.to_lower()))

	print("")
	if _falhas == 0:
		print("=== TUDO OK ===")
		get_tree().quit(0)
	else:
		print("=== %d FALHA(S) ===" % _falhas)
		get_tree().quit(1)


func _um_no_de_combate() -> Dictionary:
	# o mesmo caminho do jogo e o mesmo de tools/screenshots.gd
	var pair: Array = NodeGen.generate_pair(4)
	return pair[1]


func _medir(tela: Control) -> void:
	# O BOTÃO TEM DE ESTAR NA TELA. É a queixa inteira do autor: ele "fugiu de
	# alcance". Um botão que existe na árvore e mora em y=1180 não existe.
	var fundo := 0.0
	var pior := ""
	_varre(tela, fundo, pior)
	for b in _todos_os_botoes(tela):
		var r: Rect2 = b.get_global_rect()
		var txt := _texto_de(b)
		_ok(r.position.y >= -1.0 and r.end.y <= ALTURA + 1.0,
			"botao \"%s\" cabe na tela (y %.0f..%.0f)" % [txt, r.position.y, r.end.y])
		_ok(r.position.x >= -1.0 and r.end.x <= LARGURA + 1.0,
			"botao \"%s\" cabe na largura (x %.0f..%.0f)" % [txt, r.position.x, r.end.x])


## Desce a árvore atrás do controle que termina mais embaixo.
func _varre(n: Node, fundo: float, pior: String) -> void:
	var lista: Array = []
	_coleta(n, lista)
	var max_y := 0.0
	var quem := ""
	for c in lista:
		var ct := c as Control
		var y: float = ct.get_global_rect().end.y
		if y > max_y:
			max_y = y
			quem = ct.get_class() + " " + ct.name
	print("  fundo da arvore: %.0f px (%s)" % [max_y, quem])
	_ok(max_y <= ALTURA + 1.0, "nada passa dos %d px de janela (%.0f)" % [int(ALTURA), max_y])


func _coleta(n: Node, out: Array) -> void:
	if n is Control and (n as Control).visible:
		out.append(n)
	for c in n.get_children():
		_coleta(c, out)


func _todos_os_botoes(n: Node) -> Array:
	var out: Array = []
	_coleta_botoes(n, out)
	return out


func _coleta_botoes(n: Node, out: Array) -> void:
	if n is BaseButton and (n as Control).visible:
		out.append(n)
	for c in n.get_children():
		_coleta_botoes(c, out)


func _texto_de(n: Node) -> String:
	if n is Button and String((n as Button).text) != "":
		return String((n as Button).text).strip_edges()
	var achado := ""
	for c in n.get_children():
		if c is Label:
			return String((c as Label).text)
		achado = _texto_de(c)
		if achado != "":
			return achado
	return achado


func _ok(cond: bool, msg: String) -> void:
	if cond:
		print("  ok   ", msg)
	else:
		print("  FALHA ", msg)
		_falhas += 1
