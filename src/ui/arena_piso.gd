class_name ArenaPiso
extends Control
## O CHAO DA ARENA, desenhado por shader em vez de por poligonos.
##
## ANTES ERAM DOIS DISCOS CONCENTRICOS mais duas elipses de contorno branco.
## Medido em shots/11b_run_combate.png: o piso tinha 14/255 de contraste contra
## o vazio em volta enquanto o anel branco tinha 22/255 — ou seja, a LINHA
## aparecia mais que o CHAO, e o conjunto lia como alvo de dardos e nao como
## superficie. O degrau do disco interno era mensuravel: na linha y=522 a cor
## saltava de (36,38,50) para (43,47,61) em x=588 e voltava em x=1350,
## exatamente 0,72 x 530 do centro.
##
## AGORA E UM QUAD SO com queda continua e dither ordenado (ver piso.gdshader).
## O contraste do miolo contra o vazio vai de 14/255 para ~23/255 e nao ha
## nenhuma linha concentrica para competir com ele.
##
## O CONTRATO DE COR (revisao 15/09, secao 4): a arena fica na banda ESCURA e
## DESSATURADA, e a banda clara e saturada pertence as criaturas e aos
## anuncios. Medido: 96,8% dos pixels saturados de 05_combate.png cabiam numa
## fatia de 60 graus de matiz, porque o tint da arena era o hex EXATO do
## elemento que luta nela. Os sete tints foram girados em data/enemies.json
## (15/09), entao a colisao saiu tambem da FONTE; o veu fica porque ele e a
## garantia estrutural — o CHAO nunca entra na banda das criaturas, seja
## qual for o hex que chegar, inclusive um hex novo escrito amanha.

const SAT_MAX := 0.30
const VAL_MIN := 0.34
const VAL_MAX := 0.40

## Alfa do miolo e da borda. Somados a uma cor de V=0,40 sobre o fundo
## (15,13,24), dao luma ~37 no centro e ~23 na borda: um chao que tem miolo, e
## nao um contorno com nada dentro.
const ALFA_CENTRO := 0.26
const ALFA_BORDA := 0.09

var _mat := ShaderMaterial.new()
var _cor := Color(0.4, 0.4, 0.46, 1.0)


func _init() -> void:
	# o piso nao recebe clique: a mira do Ativo e do FieldView, que fica atras
	# dele na arvore mas na frente na captura de mouse
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var sh: Shader = load("res://assets/shaders/piso.gdshader")
	if sh != null:
		_mat.shader = sh
		material = _mat
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# DESENHADO ANTES DO PAI. Um filho de Control desenha DEPOIS do pai; sem
	# isto o chao cobriria as criaturas. E adicionado DEPOIS do cenario, entao
	# fica na frente da paisagem e atras de tudo que o FieldView pinta.
	show_behind_parent = true


## A cor cheia da arena entra; sai a cor do CHAO, ja na banda escura.
static func cor_de_piso(c: Color) -> Color:
	var out := Color(c.r, c.g, c.b, 1.0)
	out.s = minf(out.s, SAT_MAX)
	out.v = clampf(out.v, VAL_MIN, VAL_MAX)
	return out


func aplicar_cor(arena: Color) -> void:
	_cor = cor_de_piso(arena)
	if _mat.shader == null:
		return
	_mat.set_shader_parameter("cor", _cor)
	_mat.set_shader_parameter("alfa_centro", ALFA_CENTRO)
	_mat.set_shader_parameter("alfa_borda", ALFA_BORDA)
	_mat.set_shader_parameter("passo", _passo_dither())


## A AMPLITUDE DO DITHER tem de valer UM degrau de 8 bits na cor composta.
## Compondo `cor` sobre o fundo, um passo `da` de alfa move o canal em
## `da * (cor - fundo)`; para isso valer 1/255, `da = 1 / (255 * contraste)`.
## Com o contraste medido hoje (~0,34 no canal mais forte) da 0,0115 — se o
## dither fosse menor que isso ele nao cruzaria degrau nenhum e as faixas
## continuariam la, que e o erro classico de "por um ruidinho por cima".
func _passo_dither() -> float:
	var f := UI.BG
	var contraste: float = maxf(maxf(absf(_cor.r - f.r), absf(_cor.g - f.g)),
		absf(_cor.b - f.b))
	return 1.0 / maxf(255.0 * contraste, 1.0)


## Chamado todo quadro pelo FieldView: o centro anda com a camera e o pulso
## acende o piso quando a mare ou o estimulo da arena dispara.
## QUANTOS PIXELS O CHAO LEVA PARA SUMIR na borda do proprio retangulo.
##
## 90 px sai da conta e nao do gosto: o alfa no ponto em que o quad corta a
## elipse vale 0,136, e o dither resolve um degrau de 8 bits a cada ~0,0115 de
## alfa — sao ~12 degraus para percorrer, e abaixo de ~7 px por degrau eles
## voltam a ser faixas visiveis. 90 / 12 = 7,5 px por degrau.
const DESBOTE := 90.0


func atualizar(centro_local: Vector2, meia: Vector2, pulso: float) -> void:
	if _mat.shader == null:
		return
	_mat.set_shader_parameter("tamanho", size)
	_mat.set_shader_parameter("centro", centro_local)
	_mat.set_shader_parameter("raio", meia)
	_mat.set_shader_parameter("pulso", pulso)
	_mat.set_shader_parameter("margem", DESBOTE)


func _draw() -> void:
	# um quad so, no lugar dos dois poligonos de 72 vertices
	draw_rect(Rect2(Vector2.ZERO, size), Color.WHITE)
