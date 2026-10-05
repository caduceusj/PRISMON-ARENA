extends Node

func _ready() -> void:
	var samples := {
		"crlf": "Dano\r\nCausado",
		"lf": "Dano\nCausado",
		"cr": "Dano\rCausado",
		"one": "Nocautes",
	}
	for k in samples.keys():
		var l := Label.new()
		l.text = String(samples[k])
		l.add_theme_font_size_override("font_size", UI.fs(11))
		add_child(l)
		l.size = Vector2.ZERO
		var ms: Vector2 = l.get_combined_minimum_size()
		print("%s | lines=%d | min=%s | sfv=%d | bytes=%d" % [
			k, l.get_line_count(), str(ms), l.size_flags_vertical,
			String(samples[k]).to_utf8_buffer().size()])
	# valor real vindo do COLS do screen_result
	var real := ScreenResult.COLS
	for c in real:
		var l2 := Label.new()
		l2.text = String(c["head"])
		l2.add_theme_font_size_override("font_size", UI.fs(11))
		add_child(l2)
		l2.size = Vector2.ZERO
		print("COLS %s | raw=%s | lines=%d | min=%s" % [
			String(c["key"]), String(c["head"]).to_utf8_buffer(),
			l2.get_line_count(), str(l2.get_combined_minimum_size())])
	get_tree().quit()
