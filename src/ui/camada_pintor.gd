class_name CamadaPintor
extends Control
## UM CONTROL VAZIO COM MATERIAL PROPRIO, que pinta o que o dono mandar.
##
## POR QUE ELE EXISTE. No Godot 4 o material pertence ao CanvasItem, nao ao
## comando de desenho: dentro de um unico `_draw` nao ha como desenhar tres
## criaturas normais e uma quarta com shader. Toda vez que o combate precisa de
## uma passada com outro material — a silhueta branca do hit-flash, o desmanche
## da morte, o halo aditivo — a saida e uma CAMADA: um Control filho, com o seu
## material, que redesenha por cima (ou por baixo) do pai.
##
## A camada nao sabe nada sobre combate. O dono passa um Callable em `pintar`,
## e a camada so o chama de dentro do proprio `_draw` — e assim o estado
## continua todo no FieldView, num lugar so.
##
## ORDEM DE DESENHO: filho de Control desenha DEPOIS do pai, salvo
## `show_behind_parent`. Silhueta e desmanche vao na frente (precisam cobrir o
## corpo); o halo aditivo vai ATRAS, senao ele lavaria os numeros e os nomes,
## que sao a informacao que o jogador precisa ler.

var pintar: Callable = Callable()

var _mat: Material = null


static func com_shader(caminho: String, atras: bool = false) -> CamadaPintor:
	var c := CamadaPintor.new()
	c._preparar(atras)
	var sh: Shader = load(caminho) if ResourceLoader.exists(caminho) else null
	if sh != null:
		var m := ShaderMaterial.new()
		m.shader = sh
		c._mat = m
		c.material = m
	return c


## BLOOM SEM SHADER E SEM BACKBUFFER: basta um CanvasItemMaterial em
## BLEND_MODE_ADD. Todo desenho desta camada soma luz em vez de cobrir.
static func aditiva(atras: bool = false) -> CamadaPintor:
	var c := CamadaPintor.new()
	c._preparar(atras)
	var m := CanvasItemMaterial.new()
	m.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	c._mat = m
	c.material = m
	return c


func _preparar(atras: bool) -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	show_behind_parent = atras


func parametro(nome: String, valor: Variant) -> void:
	if _mat is ShaderMaterial:
		(_mat as ShaderMaterial).set_shader_parameter(nome, valor)


func _draw() -> void:
	if pintar.is_valid():
		pintar.call(self)


## O HALO DO BLOOM, gerado em codigo: 32x32, radial, branco no centro.
##
## 32 px DE PROPOSITO. Esticado para 120 px com filtro NEAREST ele sai em
## degraus de ~4 px — e essa e a gramatica certa aqui. Um halo liso ao lado de
## pixel art 1:1 denuncia na hora que veio de outro jogo; o degrau grosso
## pertence a mesma grade que as criaturas.
static var _halo: GradientTexture2D = null

static func halo_radial() -> Texture2D:
	if _halo != null:
		return _halo
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.45, 1.0])
	g.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0.34),
		Color(1, 1, 1, 0)])
	var t := GradientTexture2D.new()
	t.gradient = g
	t.width = 32
	t.height = 32
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(1.0, 0.5)
	_halo = t
	return _halo
