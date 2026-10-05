class_name MonsterArt
extends RefCounted
## Renderizador das 5 criaturas de teste (sprites animados de mons-anims.zip).
##
## Substitui o montador de peças da Kenney: agora cada espécie tem sheets de
## idle (12 quadros), walk (6) e attack (18), em células de 160×160. O recorte
## e a linha do chão vêm de data/anims.json, MEDIDO por tools/build_anim_rig.py.
##
## Regra que ficou do GDD §21.4: a COR sinaliza a Afinidade ATUAL. Os sprites
## já são coloridos, então uma criatura reescrita (Núcleo, Guisado, Prisma)
## ganha uma TINTA do elemento novo por cima — leitura imediata de que ela não
## está mais no elemento nativo.

const DIR := "res://assets/creatures/"

static var _sheets: Dictionary = {}     # "anim/prefix" -> Texture2D


static func _cfg(species_id: String) -> Dictionary:
	var c: Dictionary = Db.anims.get("creatures", {}).get(species_id, {})
	if c.is_empty():
		# chefe: usa o sprite indicado em enemies.json
		if species_id == String(Db.boss.get("id", "")):
			c = Db.anims.get("creatures", {}).get(String(Db.boss.get("sprite", "")), {})
	return c


static func sheet(anim: String, species_id: String) -> Texture2D:
	var c := _cfg(species_id)
	if c.is_empty():
		return null
	var key := anim + "/" + String(c["prefix"])
	if _sheets.has(key):
		return _sheets[key]
	var path := DIR + "mon-%s-%s1.png" % [anim, String(c["prefix"])]
	var t: Texture2D = load(path) if ResourceLoader.exists(path) else null
	_sheets[key] = t
	return t


static func frames_of(anim: String) -> int:
	return int(Db.anims.get("sheets", {}).get(anim, {}).get("frames", 1))


static func fps_of(anim: String) -> float:
	return float(Db.anims.get("sheets", {}).get(anim, {}).get("fps", 8.0))


## Desenha um quadro. `at` é o CENTRO do retângulo útil do sprite; `height` é a
## altura desenhada desse retângulo. Sprites olham para a ESQUERDA no original,
## então `facing > 0` (olhando para a direita) espelha.
static func draw_anim(ci: CanvasItem, species_id: String, anim: String, frame: int,
		at: Vector2, height: float, facing: float = 1.0,
		tint: Color = Color.WHITE, retrato: bool = false) -> void:
	var t := sheet(anim, species_id)
	var c := _cfg(species_id)
	if t == null or c.is_empty():
		return
	var cell: int = int(Db.anims.get("cell", 160))
	var cols: int = int(Db.anims.get("sheets", {}).get(anim, {}).get("cols", 4))
	var total := frames_of(anim)
	frame = clampi(frame, 0, total - 1)
	var r := frame / cols
	var col := frame % cols
	# A caixa do RETRATO e a do idle; a do campo e a uniao de todas as
	# animacoes. A uniao existe para o sprite nao pular de escala ao trocar
	# de animacao no combate — mas num retrato parado ela enquadra espaco
	# que o quadro nao usa: no Pinto-Raio o ataque levanta um topete de
	# raio e sobram 21 px (medido por build_anim_rig.py), entao o passaro
	# saia pequeno e caido no fundo do medalhao.
	var bb: Array = c.get("bbox_idle", c["bbox"]) if retrato else c["bbox"]
	var src := Rect2(col * cell + int(bb[0]), r * cell + int(bb[1]),
		int(bb[2]) - int(bb[0]), int(bb[3]) - int(bb[1]))
	var k: float = height / maxf(src.size.y, 1.0)
	var s := Vector2(src.size.x * k, height)
	var flip: float = -1.0 if facing > 0.0 else 1.0
	ci.draw_set_transform(at, 0.0, Vector2(flip, 1.0))
	ci.draw_texture_rect_region(t, Rect2(-s * 0.5, s), src, tint)
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## Compatibilidade com os retratos: um quadro parado de idle.
static func draw_unit(ci: CanvasItem, species_id: String, element: String,
		at: Vector2, height: float, facing: float = 1.0,
		modulate: Color = Color.WHITE, retrato: bool = false) -> float:
	draw_anim(ci, species_id, "idle", 0, at, height, facing,
		tint_for(species_id, element) * modulate, retrato)
	var m := metrics(species_id, element, height, retrato)
	return float(m["w"]) * 0.5


## Tinta: neutra no elemento nativo; puxada para a cor do elemento quando a
## Afinidade foi reescrita — é assim que a mudança fica legível na criatura.
static func tint_for(species_id: String, element: String) -> Color:
	var native := String(Db.sp(species_id).get("element", element))
	if species_id == String(Db.boss.get("id", "")):
		native = String(Db.boss.get("element", element))
	if element == native:
		return Color.WHITE
	return Color.WHITE.lerp(Db.el_color(element), 0.45)


## Medidas do sprite desenhado, com o centro do retângulo útil na origem.
static func metrics(species_id: String, element: String, height: float,
		retrato: bool = false) -> Dictionary:
	var c := _cfg(species_id)
	if c.is_empty():
		return {"w": height, "wide": height, "h": height, "feet": height * 0.5,
			"top": height * 0.5, "total_h": height, "centre_off": 0.0,
			"radius": height * 0.5}
	var pw: float = float(c.get("px_w_idle", c["px_w"])) if retrato else float(c["px_w"])
	var ph: float = float(c.get("px_h_idle", c["px_h"])) if retrato else float(c["px_h"])
	var w: float = pw / maxf(ph, 1.0) * height
	return {"w": w, "wide": w, "h": height, "feet": height * 0.5,
		"top": height * 0.5, "total_h": height, "centre_off": 0.0,
		"radius": maxf(w, height) * 0.5}


## Altura de desenho da espécie (campo "size" nos dados; chefe em enemies.json).
static func size_of(species_id: String) -> float:
	if species_id == String(Db.boss.get("id", "")):
		return float(Db.boss.get("size", 120))
	return float(Db.sp(species_id).get("size", 50))
