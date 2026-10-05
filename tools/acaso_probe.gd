extends Node
## O ACASO DEPOIS DO ACEITE — o estado que nenhuma ferramenta capturava.
##
## `tools/screenshots.gd` fotografa a tela de Acaso no repouso, antes de o
## jogador decidir. Só que os dois momentos interessantes dela vêm DEPOIS: o
## desfecho que saiu, e o prêmio. Foi por isso que o cartão de revelação da
## relíquia pôde nascer errado sem ninguém ver, e por isso que o autor precisou
## pedir "mostre qual foi a relíquia que o personagem ganhou ali".
##
## A sonda força o evento do altar (o único com `relic` nos desfechos), aceita, e
## fotografa. Não afirma nada sobre o resultado — quem julga é o olho. O valor
## dela é existir a imagem.

const SAIDA := "res://shots/z_acaso_premio.png"


func _ready() -> void:
	print("=== PRISMON :: sonda do Acaso (pos-aceite) ===")
	Juice.enabled = false
	get_window().size = Vector2i(1600, 900)
	await get_tree().process_frame

	Run.start_run(4242)
	Run.set_starting_team(["sheep", "apollo"])
	# um item e um prato equipados, para o risco de perder algo ter o que tirar
	for u in Run.team:
		for it in Db.item_order:
			if u.accepts_item(String(it)):
				u.items.append(String(it))
				break

	var ev := _evento_com_reliquia()
	if ev.is_empty():
		print("  nenhum evento com op 'relic' em data/random_events.json")
		get_tree().quit(1)
		return
	print("  evento: ", String(ev.get("title", "?")))

	# O TEMA E O QUE DA A FONTE DE PIXEL. Sem ele a sonda fotografa a tela com
	# a fonte do sistema e a imagem nao representa o jogo — foi o que saiu na
	# primeira captura, e por um instante parecia defeito da tela.
	var raiz := Control.new()
	raiz.theme = PrismaTheme.get_theme()
	raiz.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(raiz)
	var tela := ScreenChance.new()
	tela.setup(ev, 5)
	tela.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	raiz.add_child(tela)
	await get_tree().process_frame
	await get_tree().process_frame

	# ACEITA PELO CAMINHO DO JOGADOR: aperta o botao, nao chama _accept direto.
	# Chamar o metodo pula a fiacao do sinal — foi assim que um teste antigo
	# deste projeto passou verde enquanto duas magias nao funcionavam.
	var apertou := _apertar_aceitar(tela)
	print("  botao de aceitar apertado: ", apertou)
	for i in 6:
		await get_tree().process_frame

	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(ProjectSettings.globalize_path(SAIDA))
	print("  -> ", SAIDA)
	get_tree().quit(0)


## O altar rachado e o unico evento cujo desfecho bom concede uma reliquia.
func _evento_com_reliquia() -> Dictionary:
	for e in Db.random_events:
		for r in (e.get("outcomes", []) as Array):
			for o in (r.get("ops", []) as Array):
				if String(o.get("op", "")) == "relic":
					return e
	return {}


func _apertar_aceitar(n: Node) -> bool:
	for f in n.get_children():
		if f is BaseButton:
			var b := f as BaseButton
			# o de aceitar e o PRIMEIRO; o segundo e o de recusar
			b.pressed.emit()
			return true
		if _apertar_aceitar(f):
			return true
	return false
