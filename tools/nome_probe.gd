extends Node
## OS NOMES AGUENTAM O CLINCH? Este e o cenario que quebrava o desenho antigo:
## oito criaturas empurradas para o mesmo pedaco de arena, com nomes de
## comprimentos bem diferentes. Era ai que o rotulo do Coalla descia duas
## pistas e ficava longe do dono (print do autor, 04/09).
##
## O probe roda a simulacao de verdade ate os corpos se encostarem, monta o
## FieldView real e salva UM print. A regra que ele existe para provar:
## nenhum nome aparece fora da faixa logo abaixo da barra de vida do dono.

const ESPECIES := ["coalla", "apollo", "sheep", "pinto_raio"]


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
	# vida alta de proposito: o clinch precisa DURAR para o print pega-lo
	u.hp_max = float(s.get("hp", 400)) * 8.0
	u.atk = float(s.get("atk", 30))
	u.def = float(s.get("def", 10))
	u.vel = float(s.get("vel", 1.0))
	u.pe = float(s.get("pe", 50))
	u.vontade = float(s.get("vontade", 40))
	u.ua_per_hit = float(s.get("ua_per_hit", 2.0))
	u.ult = {}
	return sim.add_unit(u)


func _ready() -> void:
	Juice.enabled = false
	# sem isto `PrismaTheme.body_font` e null fora do jogo e a conferencia de
	# posicao roda em cima de uma fonte inexistente
	get_window().theme = PrismaTheme.build()
	get_window().size = Vector2i(1280, 720)

	var sim := CombatSim.new(1234)
	sim.node_index = 7
	sim.max_duration = 90.0
	for i in ESPECIES.size():
		_mk(sim, ESPECIES[i], 0)
		_mk(sim, ESPECIES[(i + 1) % ESPECIES.size()], 1)
	sim.begin()
	# 60 passos de simulacao = 6 s: tempo de sobra para todos se encostarem
	for i in 60:
		sim.step()

	var bg := ColorRect.new()
	bg.color = UI.BG
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var campo := FieldView.new()
	campo.sim = sim
	campo.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.add_child(campo)

	# alguns quadros para o alfa dos nomes assentar (eles nascem em 0 e sobem)
	for i in 20:
		await get_tree().process_frame

	# A CONFERENCIA, e nao so o print. O bug antigo era um rotulo DESCER mais
	# que os outros, entao o que se mede aqui e a DISPERSAO: se a distancia do
	# nome ate os pes do dono e a mesma em todo mundo, ninguem foi empurrado.
	var dists: Array = []
	for u in sim.units:
		if not u.alive:
			continue
		var base: float = campo._ancora_nome(u,
			PrismaTheme.body_font, UI.fs(UI.F_SMALL)).y
		var pes: float = campo.to_screen(campo._dp(u)).y + float(
			MonsterArt.metrics(u.species_id, u.element,
				MonsterArt.size_of(u.species_id))["feet"])
		dists.append(base - pes)
	var menor: float = dists.min()
	var maior: float = dists.max()
	var falhas := 0
	if maior - menor > 0.5:
		falhas += 1
		print("  EMPURRADO: os nomes variam %.0f px entre si" % (maior - menor))
	if maior > 48.0:
		falhas += 1
		print("  LONGE: o nome cai %.0f px abaixo dos pes" % maior)
	print("clinch com %d unidades, %d de pe" % [sim.units.size(), dists.size()])
	print("  nome fica a %.0f px dos pes (dispersao %.1f px)" % [maior, maior - menor])
	print("  visiveis agora: %d de %d — o resto perdeu o espaco e esmaeceu"
		% [campo._nomes.size(), dists.size()])
	print("=> %s" % ("OK" if falhas == 0 else "FALHOU"))

	get_viewport().get_texture().get_image().save_png("res://docs/probe_nomes.png")
	get_tree().quit(0 if falhas == 0 else 1)
