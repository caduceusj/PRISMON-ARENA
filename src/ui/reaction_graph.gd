class_name ReactionGraph
extends Control
## GDD 21.1 -- "a peca de UI que ensina o sistema inteiro".
## Nos = elementos presentes na equipe. Arestas = reacoes que a composicao
## CONSEGUE produzir. Espessura = frequencia esperada.
## Se a tela mostra nos soltos e nenhuma aresta, a equipe nao tem maquina.
##
## NENHUMA TELA MONTA ESTA PECA HOJE (conferido em 15/09: `grep -rn
## "ReactionGraph" src/ tools/` acha so este arquivo). O papel dela foi
## absorvido pela SynergyStrip, na preparacao, e pelo SynergyView, atras do
## botao — as duas dizem a mesma coisa em lista, que foi o pedido do autor de
## 03/09 ("esta muito nao legivel, menos matematico"). O arquivo fica porque o
## grafo continua sendo a leitura que mostra a MAQUINA da equipe de relance, e
## e barato mante-lo compilando; quem o ressuscitar comeca daqui.

var elements: Array = []          # element_id presentes
var appliers: Dictionary = {}     # element_id -> quantos aplicam
var _nodes: Dictionary = {}       # element_id -> Vector2
var _edges: Array = []
var _hover := -1


func set_team(els: Array, counts: Dictionary) -> void:
	elements = els
	appliers = counts
	_rebuild()
	queue_redraw()


func _ready() -> void:
	custom_minimum_size = Vector2(300, 230)
	mouse_filter = Control.MOUSE_FILTER_PASS
	resized.connect(func(): _rebuild(); queue_redraw())


func _rebuild() -> void:
	_nodes.clear()
	_edges.clear()
	var n := elements.size()
	if n == 0:
		return
	var c := size * 0.5
	var r: float = minf(size.x, size.y) * 0.34
	if n == 1:
		_nodes[elements[0]] = c
	else:
		for i in range(n):
			var ang: float = -PI * 0.5 + TAU * float(i) / float(n)
			_nodes[elements[i]] = c + Vector2(cos(ang), sin(ang)) * r

	var max_w := 1.0
	for link in Db.reactions_between(elements):
		var a := String(link["from"])   # elemento cuja AURA esta no alvo
		var b := String(link["to"])     # elemento do GOLPE que reage
		var w: float = float(int(appliers.get(a, 0)) * int(appliers.get(b, 0)))
		if w <= 0.0:
			continue
		max_w = maxf(max_w, w)
		_edges.append({"a": a, "b": b, "w": w,
			"color": Color(String(link["reaction"]["color"])),
			"name": String(link["reaction"]["name"]),
			"kind": String(link["reaction"]["kind"]),
			"forward": String(link["direction"]) == "forward"})
	for e in _edges:
		e["norm"] = float(e["w"]) / max_w


func _draw() -> void:
	if elements.is_empty():
		draw_string(_fonte(), size * 0.5 - Vector2(90, 0),
			"equipe vazia", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, UI.TEXT_DIM)
		return

	for i in range(_edges.size()):
		var e: Dictionary = _edges[i]
		var pa: Vector2 = _nodes[e["a"]]
		var pb: Vector2 = _nodes[e["b"]]
		var col: Color = e["color"]
		var norm: float = float(e["norm"])
		var width: float = 1.5 + norm * 5.0
		col.a = 0.35 + norm * 0.5
		if _hover == i:
			col.a = 1.0
			width += 2.0
		# curva leve para que ida e volta nao se sobreponham
		var mid: Vector2 = (pa + pb) * 0.5
		var perp: Vector2 = (pb - pa).orthogonal().normalized() * 16.0
		var ctrl: Vector2 = mid + (perp if e["forward"] else -perp)
		var pts := PackedVector2Array()
		for s in range(13):
			var t := float(s) / 12.0
			pts.append(pa.lerp(ctrl, t).lerp(ctrl.lerp(pb, t), t))
		draw_polyline(pts, col, width, true)
		# seta indicando a direcao da reacao (quem aplica primeiro)
		var tip: Vector2 = pts[9]
		var dir: Vector2 = (pts[10] - pts[8]).normalized()
		draw_line(tip, tip - dir.rotated(0.5) * 9.0, col, width * 0.8, true)
		draw_line(tip, tip - dir.rotated(-0.5) * 9.0, col, width * 0.8, true)

	var font := _fonte()
	for el in elements:
		var p: Vector2 = _nodes[el]
		var c: Color = Db.el_color(el)
		var count: int = int(appliers.get(el, 0))
		var rad: float = 15.0 + float(count) * 2.5
		draw_circle(p, rad + 3.0, Color(c.r, c.g, c.b, 0.16))
		draw_circle(p, rad, UI.PANEL)
		draw_arc(p, rad, 0.0, TAU, 40, c, 2.5, true)
		var txt: String = Db.el_name(el)
		var tw: float = font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
		draw_string(font, p + Vector2(-tw * 0.5, rad + 15.0), txt,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 12, c)
		var cnt := str(count)
		var cw: float = font.get_string_size(cnt, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
		draw_string(font, p + Vector2(-cw * 0.5, 5.0), cnt,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 13, UI.TEXT)

	if _hover >= 0 and _hover < _edges.size():
		var e2: Dictionary = _edges[_hover]
		var label: String = "%s  (%s)" % [e2["name"], e2["kind"]]
		draw_string(font, Vector2(6, size.y - 6), label,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 13, e2["color"])


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var best := -1
		var bd := 14.0
		for i in range(_edges.size()):
			var e: Dictionary = _edges[i]
			var d: float = _dist_to_segment(event.position, _nodes[e["a"]], _nodes[e["b"]])
			if d < bd:
				bd = d
				best = i
		if best != _hover:
			_hover = best
			if best >= 0:
				UI.som("hover")
			queue_redraw()


## A FONTE DO PROJETO, e nao `ThemeDB.fallback_font`.
##
## O fallback e a fonte que o SISTEMA OPERACIONAL empresta — a mesma origem
## dos glifos que a revisao apontou (assets/CREDITOS.md). Aqui ele desenhava
## TUDO: o nome de cada elemento, a contagem dentro do no e o rotulo da aresta
## sob o cursor. Num grafo em que os nomes sao a unica legenda, isso e a peca
## inteira mudando de forma entre maquinas.
static func _fonte() -> Font:
	return PrismaTheme.body_font if PrismaTheme.body_font != null else ThemeDB.fallback_font


static func _dist_to_segment(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var t: float = clampf((p - a).dot(ab) / maxf(ab.length_squared(), 0.001), 0.0, 1.0)
	return p.distance_to(a + ab * t)
