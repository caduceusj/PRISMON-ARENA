extends Node
## O COMBATE NO PIOR CASO: equipe CHEIA (5 fichas) contra um bando grande, com
## os corpos no clinch. E o estado que os prints do autor mostram e que
## `tools/screenshots.gd` nunca captura — la o 05_combate sai com DUAS fichas,
## porque a tela anterior do roteiro troca a equipe por uma dupla.
##
##   godot --path . --resolution 1600x900 res://tools/combate_cheio_probe.tscn -- --out=res://shots
##
## Sai em `z_combate_cheio*.png`. Roda MUDO como toda ferramenta sob res://tools/.

var out_dir := "res://shots"
var holder: Control


func _ready() -> void:
	Juice.enabled = false
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out_dir = a.split("=")[1]
	DirAccess.make_dir_recursive_absolute(out_dir)
	get_window().size = Vector2i(1600, 900)
	holder = Control.new()
	holder.theme = PrismaTheme.get_theme()
	holder.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(holder)
	await get_tree().process_frame
	await _rodar()
	get_tree().quit(0)


func _bg() -> void:
	var r := ColorRect.new()
	r.color = UI.BG
	r.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	holder.add_child(r)


func _capture(nome: String) -> void:
	for i in range(3):
		await get_tree().process_frame
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("%s/%s.png" % [out_dir, nome])
	print("  ", nome)


## Equipe cheia: o teto de Vinculo e 5 corpos, e e com 5 que o painel tem de
## caber. Os inimigos vem do passo 7, que e o unico em que o jogador fica em
## minoria (4x5 medido na revisao).
func _rodar() -> void:
	Run.start_run(4242)
	Run.set_starting_team(["sheep", "pinto_raio", "apollo", "coalla", "hipocampo"])
	Run.node_index = 7
	var par: Array = NodeGen.generate_pair(7)
	var no: Dictionary = par[0]
	for p in par:
		if String(p.get("type", "")) == "combat":
			no = p
			break
	print("equipe: ", Run.team.size(), " | inimigos: ",
		int(Dictionary(no.get("payload", {})).get("count", 0)))

	_bg()
	var cb := ScreenCombat.new()
	cb.setup(no)
	cb.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	holder.add_child(cb)
	await get_tree().process_frame
	cb.set_process(false)

	# ate o clinch: os corpos ja se encontraram e as reacoes estao correndo.
	# 2 passos por quadro = o combate em 2x, que e quando a nuvem de numeros
	# aperta de verdade — em 1x o olho tem tempo de separar os digitos.
	for i in range(40):
		for j in range(2):
			if not cb.sim.finished:
				cb.sim.step()
		cb.field.feed(cb.sim.drain_events())
		cb._time_bar.set_value(cb.sim.now, cb.sim.max_duration)
		cb._refresh_actives()
		cb.panel.refresh()
		await get_tree().process_frame
	await _capture("z_combate_cheio")

	for i in range(22):
		for j in range(2):
			if not cb.sim.finished:
				cb.sim.step()
		cb.field.feed(cb.sim.drain_events())
		cb.panel.refresh()
		await get_tree().process_frame
	await _capture("z_combate_cheio_b")

	# A MEDIDA DA PAREDE DE NUMEROS: quantos digitos por vitima ficam no ar ao
	# mesmo tempo, e quantos anuncios repetem o mesmo texto. As duas queixas do
	# autor ("os numeros se empilham em parede", "as faixas aparecem
	# duplicadas") sao exatamente estas duas contagens, e as duas tem teto 1.
	var pior_por_vitima := 0
	var pior_repetido := 0
	for i in range(120):
		for j in range(2):
			if not cb.sim.finished:
				cb.sim.step()
		cb.field.feed(cb.sim.drain_events())
		await get_tree().process_frame
		var por_vitima: Dictionary = {}
		for f in cb.field._floaters:
			var k := "%d|%s" % [int(f["dst"]), String(f["tipo"])]
			por_vitima[k] = int(por_vitima.get(k, 0)) + 1
			pior_por_vitima = maxi(pior_por_vitima, int(por_vitima[k]))
		var por_texto: Dictionary = {}
		for p in cb.field._pops:
			var b := String(p["base"])
			por_texto[b] = int(por_texto.get(b, 0)) + 1
			pior_repetido = maxi(pior_repetido, int(por_texto[b]))
	print("numeros por vitima (pico): ", pior_por_vitima,
		" | anuncios com o mesmo texto (pico): ", pior_repetido)
	# QUANTO O RECORTE CUSTA. O campo tem 872 px e a arena de movimento tem
	# 1060: um lutador no extremo cai fora do retangulo e agora e CORTADO (antes
	# era desenhado por cima do painel, que e o defeito que o autor relatou).
	# Este numero diz quantas vezes isso acontece de verdade.
	var fora := 0
	var amostras := 0
	for i in range(140):
		if not cb.sim.finished:
			cb.sim.step()
		await get_tree().process_frame
		for u in cb.sim.units:
			if not u.alive:
				continue
			amostras += 1
			var x: float = cb.field.to_screen(cb.field._dp(u)).x
			if x < 26.0 or x > cb.field.size.x - 26.0:
				fora += 1
	print("corpos fora do recorte: %.2f%% das amostras (%d de %d)"
		% [float(fora) * 100.0 / maxf(float(amostras), 1.0), fora, amostras])
	if pior_por_vitima > 1:
		print("  FALHA: dois numeros do mesmo tipo em cima da mesma vitima")
	if pior_repetido > 1:
		print("  FALHA: o mesmo anuncio esta na tela duas vezes")

	# A MEDIDA, e nao o olho: o painel cabe na coluna que a tela reservou?
	var alt_painel: float = cb.panel.size.y
	var alt_coluna: float = cb.panel.get_parent().size.y
	print("painel: ", alt_painel, " px | coluna: ", alt_coluna,
		" px | topo do painel: ", cb.panel.global_position.y)
	if alt_painel > alt_coluna:
		print("  FALHA: o painel e ", alt_painel - alt_coluna,
			" px mais alto que a coluna — ele vaza para fora da tela")
	print("campo: pos ", cb.field.global_position, " tam ", cb.field.size,
		" | recorta: ", cb.field.clip_contents)
