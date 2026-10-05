extends Node
## QUANTOS NUMEROS DE DANO FICAM NO AR AO MESMO TEMPO?
##
## O print do autor mostrava meia duzia de "50" disputando o mesmo palmo de
## arena. O leque ja existia; o que faltava era SOMAR em vez de abrir mais um.
## Aqui se conta o pico e a media de numeros simultaneos num combate real, e
## quantos pares deles se sobrepoem de fato na tela.

const COMBATES := 12


func _ready() -> void:
	Juice.enabled = false
	get_window().size = Vector2i(1280, 720)
	var bg := ColorRect.new()
	bg.theme = PrismaTheme.build()
	bg.color = UI.BG
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var pico := 0
	var soma := 0
	var amostras := 0
	var pares := 0

	for c in COMBATES:
		Run.start_run(300 + c)
		Run.set_starting_team(["sheep", "apollo"])
		Run.node_index = 5 + c % 4
		var sim := CombatBuilder.build(NodeGen.generate_pair(Run.node_index)[0], 800 + c)
		var campo := FieldView.new()
		campo.sim = sim
		campo.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		bg.add_child(campo)
		await get_tree().process_frame

		for i in range(260):
			if sim.finished:
				break
			sim.step()
			campo.feed(sim.drain_events())
			var n: int = campo._floaters.size()
			pico = maxi(pico, n)
			soma += n
			amostras += 1
			pares += _sobrepostos(campo)
			# envelhece os numeros como o jogo faz, sem depender do relogio real
			for f in campo._floaters.duplicate():
				f["life"] = float(f["life"]) + 0.1
				if float(f["life"]) > 0.75:
					campo._floaters.erase(f)
		campo.queue_free()
		await get_tree().process_frame

	print("=== numeros de dano (%d combates) ===" % COMBATES)
	print("  pico simultaneo        %d" % pico)
	print("  media simultanea       %.2f" % (float(soma) / maxf(float(amostras), 1.0)))
	print("  pares sobrepostos      %.2f por passo" % (float(pares) / maxf(float(amostras), 1.0)))
	get_tree().quit(0)


## Dois numeros se sobrepoem quando as caixas deles se cruzam na tela.
func _sobrepostos(campo: FieldView) -> int:
	var caixas: Array = []
	var fnt: Font = PrismaTheme.digit_font
	for f in campo._floaters:
		var sz: float = float(f["size"])
		var w: float = fnt.get_string_size(String(f["text"]),
			HORIZONTAL_ALIGNMENT_LEFT, -1, int(sz)).x
		# A SUBIDA ENTRA NA CONTA. O numero nao fica parado: ele sobe 34 px na
		# hora e mais 34 ao longo da vida. Medir sem isso comparava posicoes que
		# ninguem ve juntas — dois numeros de idades diferentes ocupam alturas
		# diferentes, e a primeira versao deste probe os dava como sobrepostos.
		var t2: float = float(f["life"]) / 0.75
		var p: Vector2 = campo.to_screen(f["pos"]) + Vector2(f["off"]) 			+ Vector2(0.0, -34.0 - t2 * 34.0)
		caixas.append(Rect2(p.x, p.y - sz, w, sz))
	var n := 0
	for i in caixas.size():
		for j in range(i + 1, caixas.size()):
			if (caixas[i] as Rect2).intersects(caixas[j]):
				n += 1
	return n
