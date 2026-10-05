extends Node
## Como se TRAVA a largura de um Label? Medido, porque o palpite errado já
## custou caro: `clip_text` corta o desenho mas (será?) não corta a largura
## mínima, e essa mínima sobe pela árvore e empurra o painel inteiro.

const LONGO := "Prisma de Reescrita atacando Hipocampo"


func _probe(name: String, l: Label) -> void:
	var host := Control.new()
	host.theme = PrismaTheme.get_theme()
	host.custom_minimum_size = Vector2(120, 0)
	add_child(host)
	host.add_child(l)
	await get_tree().process_frame
	print("%-34s min do Label %6.1f | min do pai %6.1f" % [
		name, l.get_combined_minimum_size().x, host.get_combined_minimum_size().x])


func _mk() -> Label:
	var l := Label.new()
	l.text = LONGO
	l.add_theme_font_size_override("font_size", 26)
	return l


func _ready() -> void:
	var a := _mk()
	await _probe("cru", a)
	var b := _mk(); b.clip_text = true
	await _probe("clip_text", b)
	var c := _mk(); c.clip_text = true; c.custom_minimum_size = Vector2(120, 0)
	await _probe("clip_text + min 120", c)
	var d := _mk(); d.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	d.custom_minimum_size = Vector2(120, 0)
	await _probe("overrun elipse + min 120", d)
	var e := _mk(); e.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	e.custom_minimum_size = Vector2(120, 0)
	await _probe("autowrap + min 120", e)
	var f := _mk(); f.clip_text = true; f.size_flags_horizontal = Control.SIZE_FILL
	f.custom_minimum_size = Vector2(120, 0)
	f.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	await _probe("clip_text ancorado", f)
	get_tree().quit()
