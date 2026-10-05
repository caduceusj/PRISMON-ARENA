class_name PrismaBar
extends Control
## Barra de 3 fatias do UI Pack RPG da Kenney: um trilho e um preenchimento,
## cada um com ponta esquerda, meio esticável e ponta direita.
##
## Não usa ProgressBar de propósito. O ProgressBar do Godot desenha o
## preenchimento a partir de (0,0) sobre TODO o retângulo, ignorando as margens
## do fundo — com uma moldura 9-patch, a barra cheia cobria a própria moldura.
## Aqui a ordem é explícita: trilho, depois preenchimento por dentro.

const TRACK := preload("res://assets/ui/bar_track.png")
const FILLS := {
	"green": preload("res://assets/ui/bar_green.png"),
	"red": preload("res://assets/ui/bar_red.png"),
	"blue": preload("res://assets/ui/bar_blue.png"),
	"yellow": preload("res://assets/ui/bar_yellow.png"),
}
const SLICE := 9          # largura das pontas nas peças originais (9/18/9)
const MIN_FILL := 18.0    # abaixo disso as duas pontas se sobrepõem

## A barra ANIMA (04/09). Antes ela saltava: a simulação anda a 10 Hz e a
## tela a 60, então um golpe encolhia a barra num quadro só e o olho não via
## nada acontecer — via o resultado.
##
## Duas velocidades, técnica clássica de barra de vida: o preenchimento corre
## rápido para o valor novo, e um RASTRO mais claro corre atrás devagar. O
## rastro é a leitura do golpe — ele mostra QUANTO se perdeu, e por quanto
## tempo, sem precisar de número.
var ratio: float = 0.0 : set = _set_ratio
var _mostrado: float = -1.0   # o que o preenchimento desenha agora
var _rastro: float = -1.0     # o que o rastro desenha agora

const VEL_FRENTE := 6.0       # o preenchimento alcança o alvo em ~0.17 s
const VEL_RASTRO := 1.6       # o rastro leva ~0.6 s — é ele que se lê
const PAUSA_RASTRO := 0.25    # o rastro só começa a andar depois disto
var _espera := 0.0
var fill_name: String = "blue"
var tint: Color = Color.WHITE

var _track: StyleBoxTexture
var _fill: StyleBoxTexture
var _ghost: StyleBoxTexture
var _trail: StyleBoxTexture


static func make(color_name: String, height: int = 18, tint_color: Color = Color.WHITE) -> PrismaBar:
	var b := PrismaBar.new()
	b.fill_name = color_name if FILLS.has(color_name) else "blue"
	b.tint = tint_color
	b.custom_minimum_size = Vector2(0, height)
	b.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return b


## Troca o preenchimento em tempo de execucao (a vida muda de verde para
## amarelo e vermelho durante o combate, sem recriar a barra).
func reload() -> void:
	if FILLS.has(fill_name):
		_fill = _slice(FILLS[fill_name], tint)
		_ghost = _slice(FILLS[fill_name], Color(tint.r, tint.g, tint.b, 0.16))
		_trail = _slice(FILLS[fill_name], Color(1.0, 1.0, 1.0, 0.42))
		queue_redraw()


func _ready() -> void:
	# O trilho era escuro demais: uma barra quase vazia sumia contra o painel, e
	# o jogador não via que existia barra até ela encher. A barra de ultimate
	# passa a maior parte do combate perto de zero — se o trilho não aparece,
	# ela lê como um vão vazio no rodapé da ficha em vez de "ainda não carregou".
	# O TRILHO JA NASCE OPACO no sheet novo (canal de vidro proprio: 1 px
	# escuro em cima, 2 px claros embaixo). O clareamento de 1,9x existia
	# porque o trilho da Kenney era preto com 10% de alfa e nenhum modulate
	# clareia preto — a barra vazia virava um vao sem motivo no rodape do
	# cartao. Com o desenho proprio, multiplicar de novo so estouraria o
	# canal. Ver DIV_TRILHO em tools/build_ui_sheet.py, que anda com isto.
	_track = _slice(TRACK, Color.WHITE)
	_fill = _slice(FILLS[fill_name], tint)
	# FANTASMA: a barra inteira na cor dela, quase transparente. Ele nasceu
	# porque o trilho da Kenney era preto com 10% de alfa — nenhum `modulate`
	# clareia preto — e uma barra vazia virava um vao sem motivo no rodape do
	# cartao (a de ultimate passa quase o combate inteiro assim). O trilho novo
	# ja e opaco e tem canal de vidro proprio, entao o fantasma deixou de ser
	# necessario para AVISAR que ha barra; fica porque ainda diz QUAL barra e,
	# na cor dela, e usa a MESMA silhueta de pontas arredondadas.
	_ghost = _slice(FILLS[fill_name], Color(tint.r, tint.g, tint.b, 0.16))
	# RASTRO POR ALFA, NAO POR CLAREAMENTO (16/09). Era Color(1.7, 1.7, 1.75):
	# multiplicar acima de 1.0 funcionava enquanto o preenchimento era claro e
	# translucido, e estoura agora que ele e opaco — os tres canais saturam e o
	# rastro vira uma barra branca chapada, mais forte que o proprio
	# preenchimento que ele deveria estar deixando para tras. Com alfa ele
	# empalidece contra o trilho escuro, que e a leitura certa: o que ficou para
	# tras aparece menos, nao mais.
	_trail = _slice(FILLS[fill_name], Color(1.0, 1.0, 1.0, 0.42))
	queue_redraw()


func _slice(t: Texture2D, mod: Color) -> StyleBoxTexture:
	var sb := StyleBoxTexture.new()
	sb.texture = t
	sb.texture_margin_left = SLICE
	sb.texture_margin_right = SLICE
	sb.texture_margin_top = 0
	sb.texture_margin_bottom = 0
	sb.axis_stretch_horizontal = StyleBoxTexture.AXIS_STRETCH_MODE_TILE
	sb.modulate_color = mod
	return sb


func _set_ratio(v: float) -> void:
	var novo := clampf(v, 0.0, 1.0)
	# primeiro valor: aparece pronto, sem animar de zero
	if _mostrado < 0.0:
		_mostrado = novo
		_rastro = novo
	elif novo < ratio:
		# perdeu: segura o rastro um instante antes de ele correr atrás
		_espera = PAUSA_RASTRO
	ratio = novo
	set_process(true)
	queue_redraw()


func _process(delta: float) -> void:
	if not Juice.enabled:
		_mostrado = ratio
		_rastro = ratio
		set_process(false)
		queue_redraw()
		return
	_mostrado = move_toward(_mostrado, ratio, delta * VEL_FRENTE)
	if _espera > 0.0:
		_espera -= delta
	else:
		_rastro = move_toward(_rastro, ratio, delta * VEL_RASTRO)
	# ganhar vida: o rastro não fica para trás, ele acompanha
	_rastro = maxf(_rastro, _mostrado)
	queue_redraw()
	if is_equal_approx(_mostrado, ratio) and is_equal_approx(_rastro, ratio):
		set_process(false)


func set_value(v: float, maximum: float) -> void:
	_set_ratio(v / maxf(maximum, 0.0001))


func _draw() -> void:
	if _track == null:
		return
	if _ghost != null:
		draw_style_box(_ghost, Rect2(Vector2.ZERO, size))
	draw_style_box(_track, Rect2(Vector2.ZERO, size))
	# RASTRO primeiro, por baixo: a faixa entre ele e o preenchimento é o que
	# acabou de se perder
	if _rastro > _mostrado + 0.001 and _trail != null:
		var wr: float = maxf(size.x * _rastro, MIN_FILL)
		draw_style_box(_trail, Rect2(0.0, 0.0, minf(wr, size.x), size.y))
	if _mostrado <= 0.001:
		return
	var w: float = maxf(size.x * _mostrado, MIN_FILL)
	draw_style_box(_fill, Rect2(0.0, 0.0, minf(w, size.x), size.y))
