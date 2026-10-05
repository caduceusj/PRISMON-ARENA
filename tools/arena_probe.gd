extends Node
## AS SETE ARENAS, uma captura cada.
##
## O capturador normal tira uma briga so, com a arena que o sorteio deu — e
## conferir as sete assim exigiria sete rodadas com semente na mao. Aqui o campo
## e montado direto, a arena e imposta, e sai um PNG por arena em docs/arenas/.
##
## Serve para duas coisas: ver se a ilustracao de fundo encaixa no piso, e
## comparar as sete lado a lado depois de mexer no gerador de arte.

const LARG := 1280
const ALT := 720
const PASSOS := 40      # passos de simulacao antes da foto: as criaturas se espalham


func _ready() -> void:
	Juice.enabled = false
	get_window().size = Vector2i(LARG, ALT)
	DirAccess.make_dir_recursive_absolute("res://docs/arenas")

	var arenas: Array = []
	for a in Db.arenas.values():
		arenas.append(a)
	arenas.sort_custom(func(x, y): return String(x.get("id", "")) < String(y.get("id", "")))

	for a in arenas:
		await _tirar(a)
	print("=> %d arenas em docs/arenas/" % arenas.size())
	get_tree().quit(0)


func _tirar(arena: Dictionary) -> void:
	for f in get_children():
		f.queue_free()
	await get_tree().process_frame

	var bg := ColorRect.new()
	bg.theme = PrismaTheme.build()
	bg.color = UI.BG
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	Run.start_run(11)
	Run.set_starting_team(["sheep", "apollo"])
	Run.node_index = 5
	var no: Dictionary = NodeGen.generate_pair(Run.node_index)[0]
	# IMPOE a arena: o no sorteia a dele, e o probe existe justamente para
	# nao depender de sorteio
	var carga: Dictionary = no.get("payload", {})
	carga["arena"] = String(arena.get("name", ""))
	no["payload"] = carga

	var sim := CombatBuilder.build(no, 4242)
	var campo := FieldView.new()
	campo.sim = sim
	campo.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.add_child(campo)
	await get_tree().process_frame
	campo.feed(sim.drain_events())

	for i in PASSOS:
		sim.step()
		campo.feed(sim.drain_events())
	# alguns quadros de tela para as particulas nascerem e o layout assentar
	for i in 30:
		await get_tree().process_frame

	var id := String(arena.get("id", "sem_id"))
	get_viewport().get_texture().get_image().save_png(
		"res://docs/arenas/%s.png" % id)

	# A MIRA DO ATIVO, so na primeira arena. Ela e o motivo do pedido de 09/09
	# ("as esferas das magias... esta um formato de esfera errado") e so aparece
	# com o mouse sobre o campo, entao um print normal nunca a mostraria.
	if id == "arena_assombrada":
		get_viewport().warp_mouse(Vector2(LARG * 0.42, ALT * 0.56))
		campo.aim_mode = "ponto"
		campo.aim_radius = 190.0
		campo.aim_color = UI.ACCENT
		for i in 8:
			await get_tree().process_frame
		get_viewport().get_texture().get_image().save_png(
			"res://docs/arenas/_mira.png")
		campo.aim_mode = ""
	print("  %-22s %s" % [id, String(arena.get("name", ""))])
