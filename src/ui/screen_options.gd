class_name ScreenOptions
extends Control
## Configurações (pedido do autor, 04/09).
##
## Só entra aqui o que MUDA alguma coisa. Uma tela de opções cheia de chaves
## decorativas é pior que nenhuma: ensina o jogador a não confiar nela. Por
## isso são sete ajustes, e cada um age no mesmo quadro em que é tocado.
##
## Os três volumes entraram em 15/09 junto com o autoload `Som` — e entraram
## LIGADOS de verdade: cada arrasto chama `Som.set_volume` no mesmo quadro, e
## o de Ambiente acende uma prévia porque esta tela não tem arena para ouvir.
##
## Persistem em `user://config.cfg`, então valem entre sessões — sem isso o
## jogador reconfiguraria tudo a cada abertura, e a tela viraria um imposto.

signal closed

const ARQUIVO := "user://config.cfg"

## O que se guarda, com o valor de fábrica. A tela é montada a partir DESTE
## mapa: acrescentar uma opção é acrescentar uma linha aqui e um caso em
## `_aplicar`, e não mexer no layout.
const PADRAO := {
	"tela_cheia": false,
	"velocidade": 0,        # índice em ScreenCombat.SPEEDS (1× / 2× / 4×)
	"tremor": true,         # tremor de tela nas reações
	"numeros": true,        # números de dano flutuantes
	# 0..1 lineares, um por barramento de `Som`. Nem um nem zero: 0,8 deixa
	# margem para o jogador SUBIR (num jogo que estreia em 100% o único
	# controle possível é abaixar), e o ambiente entra mais baixo de propósito
	# — laço de sala que disputa com o golpe vira ruído.
	"volume_master": 0.6,
	"volume_efeitos": 0.55,
	"volume_ambiente": 0.32,
}

static var cfg: Dictionary = {}

## A prévia do Ambiente só é desligada por quem a ligou (ver `_exit_tree`).
var _previa := false


## Lê do disco uma vez, no arranque. Chamado por Main antes da primeira tela.
static func carregar() -> void:
	cfg = PADRAO.duplicate()
	var f := ConfigFile.new()
	if f.load(ARQUIVO) == OK:
		for k in PADRAO.keys():
			if f.has_section_key("jogo", String(k)):
				cfg[k] = f.get_value("jogo", String(k))
	# OS DOIS APLICADORES RODAM SEMPRE, inclusive na primeira execução, quando
	# não existe config.cfg e a função saía aqui. Era inofensivo enquanto o
	# único aplicador era a janela (o padrão é janela mesmo); com áudio deixa
	# de ser: o jogo estrearia com os três barramentos em 100%, ignorando os
	# padrões escritos logo acima.
	_aplicar_janela()
	_aplicar_audio()


static func salvar() -> void:
	var f := ConfigFile.new()
	for k in cfg.keys():
		f.set_value("jogo", String(k), cfg[k])
	f.save(ARQUIVO)


static func get_opt(chave: String) -> Variant:
	if cfg.is_empty():
		cfg = PADRAO.duplicate()
	return cfg.get(chave, PADRAO.get(chave))


static func _aplicar_janela() -> void:
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN
		if bool(get_opt("tela_cheia")) else DisplayServer.WINDOW_MODE_WINDOWED)


## Os volumes valem desde o arranque, antes da primeira tela: o clique do menu
## de título já sai no volume que o jogador deixou na sessão passada.
static func _aplicar_audio() -> void:
	Som.set_volume("master", float(get_opt("volume_master")))
	Som.set_volume("efeitos", float(get_opt("volume_efeitos")))
	Som.set_volume("ambiente", float(get_opt("volume_ambiente")))


## O modo REAL da janela manda mais que o que está guardado. F11 (main.gd) muda
## a janela sem passar por aqui, e a tela abria dizendo "Desligado" com o jogo
## em tela cheia. Uma opção que mente sobre o próprio estado não estraga só a
## si mesma: ensina a não confiar em nenhuma das outras seis.
static func _reler_janela() -> void:
	if cfg.is_empty():
		cfg = PADRAO.duplicate()
	var modo := DisplayServer.window_get_mode()
	cfg["tela_cheia"] = (modo == DisplayServer.WINDOW_MODE_FULLSCREEN
		or modo == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN)


func _ready() -> void:
	_reler_janela()
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var col := UI.box(true, 14)
	col.custom_minimum_size = Vector2(640, 0)
	center.add_child(col)

	col.add_child(UI.banner("CONFIGURAÇÕES"))
	col.add_child(UI.spacer(6, false))

	var card := UI.card()
	col.add_child(card)
	var v := UI.box(true, 10)
	card.add_child(v)

	v.add_child(_liga("tela_cheia", "Tela cheia",
		"Alterna entre janela e tela cheia. Vale já."))
	v.add_child(UI.hsep())
	v.add_child(_velocidade())
	v.add_child(UI.hsep())
	v.add_child(_liga("tremor", "Tremor de tela",
		"A tela treme quando uma reação estoura. Desligue se incomodar."))
	v.add_child(UI.hsep())
	v.add_child(_liga("numeros", "Números de dano",
		"Os números que sobem das criaturas durante o combate."))
	v.add_child(UI.hsep())
	v.add_child(_volume("volume_master", "master", "Volume geral",
		"Manda em tudo. No zero o jogo fica mudo."))
	v.add_child(UI.hsep())
	v.add_child(_volume("volume_efeitos", "efeitos", "Efeitos",
		"Golpes, reações, cliques. É o som que o combate faz."))
	v.add_child(UI.hsep())
	v.add_child(_volume("volume_ambiente", "ambiente", "Ambiente",
		"O laço de fundo da arena. Arraste para ouvir uma prévia."))

	col.add_child(UI.spacer(10, false))
	var foot := UI.box(false, 12)
	foot.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_child(foot)
	var back := UI.button("  VOLTAR  ", UI.F_H2)
	# So a LARGURA: a altura vem de UI.BTN_H, escrita dentro de UI.button.
	back.custom_minimum_size.x = 300
	back.pressed.connect(func():
		salvar()
		closed.emit())
	foot.add_child(back)


## Uma linha de liga/desliga: rótulo à esquerda, explicação embaixo, botão à
## direita. O botão diz o ESTADO ("Ligado"), não a ação — em pixel art um
## interruptor desenhado fica ilegível no tamanho do texto.
func _liga(chave: String, titulo: String, ajuda: String) -> Control:
	var row := UI.box(false, 12)
	var v := UI.box(true, 1)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(v)
	v.add_child(UI.label(titulo, UI.F_BODY))
	v.add_child(UI.label(ajuda, UI.F_SMALL, UI.TEXT_DIM))

	var b := UI.button("", UI.F_BODY)
	b.custom_minimum_size.x = 170
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_pintar(b, bool(get_opt(chave)))
	b.pressed.connect(func():
		cfg[chave] = not bool(get_opt(chave))
		_pintar(b, bool(cfg[chave]))
		if chave == "tela_cheia":
			_aplicar_janela()
		salvar())
	row.add_child(b)
	return row


func _pintar(b: Button, ligado: bool) -> void:
	b.text = "  Ligado  " if ligado else "  Desligado  "
	b.add_theme_color_override("font_color", UI.GOOD if ligado else UI.TEXT_DIM)


## Velocidade padrão do combate. É a única opção com mais de dois estados, e
## por isso cicla no próprio botão em vez de abrir uma lista.
func _velocidade() -> Control:
	var row := UI.box(false, 12)
	var v := UI.box(true, 1)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(v)
	v.add_child(UI.label("Velocidade do combate", UI.F_BODY))
	v.add_child(UI.label("Com que velocidade a briga começa. TAB troca durante o combate.",
		UI.F_SMALL, UI.TEXT_DIM))

	var b := UI.button("", UI.F_BODY, UI.ACCENT)
	b.custom_minimum_size.x = 170
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var atual: int = int(get_opt("velocidade"))
	b.text = "  %d×  " % int(ScreenCombat.SPEEDS[atual])
	b.pressed.connect(func():
		var i: int = (int(get_opt("velocidade")) + 1) % ScreenCombat.SPEEDS.size()
		cfg["velocidade"] = i
		b.text = "  %d×  " % int(ScreenCombat.SPEEDS[i])
		salvar())
	row.add_child(b)
	return row


## Uma linha de volume. Mesma anatomia do liga/desliga — rótulo à esquerda,
## explicação embaixo, controle de 170×58 à direita — para que a coluna não
## mude de forma ao ganhar três opções. O número por extenso existe porque um
## punho de 8 px não diz "70%": volume é a única opção desta tela cujo estado
## não cabe numa palavra.
func _volume(chave: String, canal: String, titulo: String, ajuda: String) -> Control:
	var row := UI.box(false, 12)
	var v := UI.box(true, 1)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(v)
	v.add_child(UI.label(titulo, UI.F_BODY))
	v.add_child(UI.label(ajuda, UI.F_SMALL, UI.TEXT_DIM))

	var caixa := UI.box(false, 8)
	caixa.custom_minimum_size = Vector2(170, UI.BTN_H)
	caixa.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var s := _slider(float(get_opt(chave)))
	var pct := UI.label(_pct(s.value), UI.F_SMALL, UI.TEXT_DIM,
		HORIZONTAL_ALIGNMENT_RIGHT)
	# 48 px e não 42: "80%" mede 34 px no print e "100%" mede 45. Com a largura
	# menor que 45 o rótulo empurraria a calha para a esquerda justamente ao
	# chegar no fim do curso, e o controle tremeria debaixo do cursor.
	pct.custom_minimum_size = Vector2(48, 0)
	pct.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	caixa.add_child(s)
	caixa.add_child(pct)
	row.add_child(caixa)

	s.value_changed.connect(func(x: float):
		cfg[chave] = x
		pct.text = _pct(x)
		Som.set_volume(canal, x)
		if canal == "ambiente":
			_acender_previa())
	# gravar a cada pixel arrastado escreveria o .cfg dezenas de vezes por
	# segundo. O fim do arrasto é o evento certo — e o VOLTAR salva por cima.
	s.drag_ended.connect(func(_mudou: bool):
		salvar()
		if canal != "ambiente":
			Som.tocar("clique"))
	return row


func _pct(x: float) -> String:
	return "%d%%" % int(round(x * 100.0))


## Calha de 14 px: a altura sai das margens de conteúdo, que é o que o Slider
## usa como altura do desenho. Canto vivo e borda de 1 px, como todo o resto.
func _calha(fundo: Color, borda: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = fundo
	sb.border_color = borda
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(0)
	sb.content_margin_top = 7
	sb.content_margin_bottom = 7
	sb.content_margin_left = 0
	sb.content_margin_right = 0
	return sb


## Passo de 5%: com passo contínuo o jogador nunca consegue voltar ao valor
## em que estava, e "79%" não quer dizer nada que "80%" não diga.
func _slider(valor: float) -> HSlider:
	var s := HSlider.new()
	s.min_value = 0.0
	s.max_value = 1.0
	s.step = 0.05
	s.value = valor
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	s.custom_minimum_size = Vector2(0, 22)
	s.focus_mode = Control.FOCUS_NONE
	# CALHA CHAPADA, e não o 9-patch do resto do kit. Medido: `UI.frame` tem 6 px
	# de margem de textura em cima e embaixo; numa calha de 14 px as duas bordas
	# se encostam, a faixa esticável some e o trecho vazio vira uma caixinha solta
	# à direita do punho, não um sulco. Retângulo de 1 px lê como sulco em 14 px.
	s.add_theme_stylebox_override("slider", _calha(UI.BG, UI.LINE))
	s.add_theme_stylebox_override("grabber_area", _calha(UI.GOOD.darkened(0.30),
		UI.GOOD.darkened(0.55)))
	s.add_theme_stylebox_override("grabber_area_highlight", _calha(UI.GOOD,
		UI.GOOD.darkened(0.45)))
	var g := _punho()
	s.add_theme_icon_override("grabber", g)
	s.add_theme_icon_override("grabber_highlight", g)
	s.add_theme_icon_override("grabber_disabled", g)
	return s


## O punho é a única peça do kit que não existe em assets/ui. São 8×22 px —
## um retângulo claro com contorno da cor da mesa — e desenhá-lo aqui custa
## menos que uma célula nova no sheet da Kenney e o script que a gera.
static var _tex_punho: ImageTexture = null

static func _punho() -> ImageTexture:
	if _tex_punho != null:
		return _tex_punho
	var img := Image.create_empty(8, 22, false, Image.FORMAT_RGBA8)
	img.fill(UI.TEXT)
	for x in 8:
		img.set_pixel(x, 0, UI.BG)
		img.set_pixel(x, 21, UI.BG)
	for y in 22:
		img.set_pixel(0, y, UI.BG)
		img.set_pixel(7, y, UI.BG)
	_tex_punho = ImageTexture.create_from_image(img)
	return _tex_punho


## O controle de Ambiente é o único desta tela que não se ouve: aqui não há
## arena. Tocar o laço da primeira arena do catálogo enquanto a tela existe é
## o que mantém verdadeira a regra escrita no topo do arquivo — só entra aqui
## o que MUDA alguma coisa, e "mudar" inclui poder perceber a mudança.
func _acender_previa() -> void:
	if _previa:
		return
	var ids := Db.arenas_by_id.keys()
	if ids.is_empty():
		return
	_previa = true
	Som.ambiente(String(ids[0]))


## Só desliga o que esta tela ligou: se um dia as Configurações abrirem por
## cima de um combate, o ambiente da arena continua onde estava.
func _exit_tree() -> void:
	if _previa:
		Som.parar_ambiente()
