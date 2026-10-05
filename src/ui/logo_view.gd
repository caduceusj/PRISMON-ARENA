class_name LogoView
extends TextureRect
## O logotipo do PRISMON, pixelizado (pedido do autor, 04/09).
##
## O logo é arte vetorial de traço limpo; o resto do jogo é pixel art de 18 px
## por em. Sem tratamento os dois não pertencem à mesma tela. O shader amostra
## a arte numa grade grossa, então o logotipo passa a ser feito de blocos — a
## mesma gramática da interface.
##
## Na entrada a grade AFINA: começa em `PX_INICIAL` e desce até `PX_REPOUSO`,
## e o logo "se resolve" na tela em vez de simplesmente aparecer.
##
## SE O ARQUIVO NÃO EXISTIR, isto devolve `null` em `make()` e a tela de título
## cai no nome escrito — o jogo não depende de um asset que pode não ter sido
## commitado ainda.

const CAMINHO := "res://assets/ui/logo_prismon.png"
const SHADER := preload("res://assets/shaders/pixelize.gdshader")

const PX_INICIAL := 20.0      # blocos grossos, mas a silhueta ainda se lê
const PX_REPOUSO := 4.0       # onde ele para — ainda visivelmente pixelizado
const DURACAO := 1.1

var _t := 0.0
var _mat: ShaderMaterial


## Devolve null quando o PNG do logo ainda não está no projeto.
static func make(largura: float = 720.0) -> LogoView:
	if not ResourceLoader.exists(CAMINHO):
		return null
	var v := LogoView.new()
	v.texture = load(CAMINHO)
	v.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	v.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	var t: Texture2D = v.texture
	var prop: float = float(t.get_height()) / maxf(float(t.get_width()), 1.0)
	v.custom_minimum_size = Vector2(largura, largura * prop)
	v.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# NEAREST: com filtro linear o shader pixeliza e a placa suaviza de volta,
	# e o bloco volta a ter borda macia — o efeito se anula.
	v.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	return v


func _ready() -> void:
	_mat = ShaderMaterial.new()
	_mat.shader = SHADER
	material = _mat
	# As ferramentas headless desligam animacao (Juice.enabled): sem esta
	# guarda o print saia com a grade no INICIO da transicao — blocos de 34 px,
	# logotipo irreconhecivel — e parecia defeito do shader.
	if not Juice.enabled:
		_mat.set_shader_parameter("pixel_size", PX_REPOUSO)
		# set_process(FALSE) é obrigatório: um nó cujo script define _process
		# já vem processando por padrão, então o `return` sozinho não impedia
		# a animação de sobrescrever o valor de repouso no quadro seguinte —
		# e o print saía com a grade grossa mesmo com a animação "desligada".
		set_process(false)
		return
	_mat.set_shader_parameter("pixel_size", PX_INICIAL)
	set_process(true)


func _process(delta: float) -> void:
	if _t >= DURACAO:
		return
	_t = minf(_t + delta, DURACAO)
	# desacelera no fim (ease-out): o logo cai rápido para perto do nítido e
	# assenta devagar, que lê como "focando" em vez de "encolhendo"
	var f: float = 1.0 - pow(1.0 - _t / DURACAO, 3.0)
	_mat.set_shader_parameter("pixel_size", lerpf(PX_INICIAL, PX_REPOUSO, f))
	if _t >= DURACAO:
		set_process(false)
