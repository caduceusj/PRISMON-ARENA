class_name FieldView
extends Control
## Camada VISUAL do combate. GDD 22.3: e apenas um OBSERVADOR da simulacao --
## nunca decide nada, so le o estado e consome eventos.
##
## GDD 21.2/21.4 -- legibilidade: o anel de aura e a unica camada 100% confiavel.
## Espessura do anel = UA restante. Duas auras = dois aneis concentricos.

var sim: CombatSim = null
var aim_radius: float = 0.0
var aim_color: Color = Color.WHITE
signal clicked(local: Vector2)

var aim_mode: String = ""

var _floaters: Array = []     # numeros de dano
var _pops: Array = []         # nomes de reacao
var _rings: Array = []        # ondas de area (ativos, reacoes com raio)

## A ARENA TINGE O PISO (autor, 03/09: "trocar os visuais dos backgrounds para
## indicar esses efeitos acontecendo"). É a única pista contínua de que a briga
## tem uma regra a mais: o nome da arena aparece uma vez na preparação e some.
##
## A COR QUE O CHÃO REALMENTE PINTA, já dentro do contrato de cor — banda
## escura e dessaturada, ver ArenaPiso.cor_de_piso. Fica aqui para quem
## inspeciona o combate de fora poder ler o que está na tela; quem pinta é o
## shader do piso, não o `_draw` deste arquivo.
var arena_tint: Color = ArenaPiso.cor_de_piso(Color(1, 1, 1, 1))
## A cor CHEIA da arena, sem o corte da banda escura. Particulas, faiscas e
## marcas de chao usam esta: brasa alaranjada e anel de runa sao o que deve
## saltar, e sao eles que ocupam a banda clara junto com as criaturas.
var arena_cor: Color = Color(1, 1, 1, 1)
var _pulse := 0.0             # brilho do piso quando a arena dispara

## O CENARIO DA ARENA (autor, 09/09: "faz umas ilustracoes de arenas diferentes
## pra decorar a arena"; 10/09: "eu queria editar dentro do Godot mesmo, mexer
## algumas posicoes, ao inves de deixar tudo solto").
##
## CADA ARENA E UMA CENA, `assets/arenas/<id>.tscn`, com um Sprite2D por
## elemento — montanha, poste, lapide. Abre no editor do Godot, arrasta, salva.
##
## ANTES ERA UM PNG ACHATADO. Decorava igual, mas para mover uma lapide era
## preciso abrir o Aseprite, arrastar, exportar e rodar um script. Com a cena, o
## ajuste fino acontece onde ele deve acontecer: olhando o jogo.
##
## O desenho tem 1280x260 e e usado em 1:1 — a paisagem e a criatura tem o mesmo
## grao de pixel. O horizonte (y=170) e ancorado na borda de cima da elipse do
## piso, entao o chao da arena passa na frente da paisagem e a cena ganha
## profundidade sem nenhuma conta de camera.
##
## `show_behind_parent` poe a cena ATRAS do que o FieldView desenha. Sem isso
## ela cobriria as criaturas: filho de um Control desenha DEPOIS do pai.
##
## Arena sem cena deixa `_cenario` nulo e nada muda.
## FOLGA ENTRE O CENARIO E A ARENA (autor, 11/09: "as arenas estao se
## misturando com as montanhas de um jeito muito estranho... puxe as montanhas
## mais pra cima ou a arena pra baixo pra nao se misturar").
##
## O horizonte do cenario ficava EXATAMENTE na borda de cima da elipse, para os
## adereços espiarem por tras. So que a borda de cima e uma curva e o horizonte
## era uma reta: eles se cruzavam, e a montanha aparecia cortada pelo piso no
## meio da tela. A folga afasta os dois; a curvatura (ver cenario_fade) faz o
## resto, deixando o horizonte PARALELO a borda em vez de cruzando com ela.
## O CENARIO E ANCORADO PELO RODAPE, nao pelo horizonte.
##
## Ancorando o horizonte, o avental do desenho (os 66 px abaixo dele) caia
## DENTRO da elipse — e como o piso e translucido, a montanha aparecia por baixo
## dele no meio da arena. Era isso o "se misturando de um jeito estranho".
##
## Agora quem encosta na arena e a ultima linha visivel do desenho: o cenario
## acaba pouco acima da borda de tras do piso e nao entra nele em momento algum.
## A curvatura (ver cenario_fade) mantem essa distancia constante ao longo de
## toda a largura, porque cenario e borda descem juntos.
const CENARIO_RODAPE := 236.0
const CENARIO_FOLGA := 26.0
const CENARIO_LARGURA := 1280.0
## A ALTURA DO DESENHO (1280x260). O shader precisa dela para saber onde fica o
## horizonte dentro da imagem; ate agora ele usava o valor padrao do uniform, e
## por isso a constante nao existia deste lado. Passou a existir porque
## `tamanho` deixou de ser o padrao — ver `_posicionar_cenario`.
const CENARIO_ALTURA := 260.0
const CENARIO_HORIZONTE := 170.0   # linha do horizonte dentro da cena
## O fundo treme MENOS que a frente: paralaxe barata, e o tremor de tela para de
## parecer que a paisagem inteira esta presa na camera.
const CENARIO_TREMOR := 0.35

var _cenario: Node2D = null
## O id da arena em campo. Vale para o que muda de arena para arena sem estar
## na cena — hoje, o ar quente do Solo Vulcanico.
var _arena_id := ""
## O material COMPARTILHADO pelos sprites da cena. Guardado aqui porque
## o corte das bordas depende de onde o cenario esta no canvas, e isso
## muda com o tamanho do campo — e preciso avisar o shader todo quadro.
var _cenario_mat: ShaderMaterial = null
## O clima da arena — chuva, brasa, neve. Ver ArenaParticulas.
var _particulas := ArenaParticulas.new()
## As marcas no piso — rachadura, poca, ladrilho. Ver ArenaChao.
var _marcas: Array = []

## Tetos de simultaneidade. Sem eles, uma rajada de reacoes enche a arena de
## circulos e o corredor de avisos de rotulos empilhados.
const MAX_RINGS := 4
## ERA 5 (autor, 16/09: "sobreposicao... simplifique mais como essas
## informacoes sao mostradas"). Cinco anuncios simultaneos ocupam as cinco
## pistas inteiras sobre o clinch e nao sobra linha nenhuma para os nomes das
## criaturas, que sao a informacao permanente. Com a agregacao consertada,
## cinco rotulos so acontecem quando ha cinco reacoes DIFERENTES no ar — e
## nesse caso as tres mais novas dizem o mesmo que as cinco.
const MAX_POPS := 3

## OS NOMES DAS UNIDADES (autor, 04/09: "voltar com os nomes, mas evitar aquele
## bug de o nome do nada descer muito, que nem o anexo do Coalla").
##
## O DEFEITO ERA O EMPILHAMENTO POR PISTAS. Quando dois rótulos se encostavam,
## o segundo descia uma pista, o terceiro descia duas — e no clinch o nome
## acabava dezenas de pixels abaixo do dono, apontando para o vazio. Nenhum
## ajuste de altura de pista resolve isso: o problema não é QUANTO ele desce,
## é que ele desce.
##
## AGORA O RÓTULO NÃO SE MEXE. Fica sempre no mesmo ponto em relação ao dono —
## centrado sob a barra de vida — e conflito não empurra ninguém: quem perde o
## espaço ESMAECE, e volta assim que o vizinho sai. Um nome ausente por dois
## décimos de segundo confunde muito menos que um nome no lugar errado.
##
## Quem ganha sai de uma chave ESTÁVEL (sua equipe primeiro, e dentro dela o id
## da unidade), nunca da posição. Com uma chave que muda de quadro a quadro os
## dois rótulos ficariam trocando de vez e piscando juntos.
const NOME_FOLGA := Vector2(7.0, 3.0)   # respiro contado na colisão
const NOME_FADE := 6.0                  # 1/s: ~0.17 s para sumir ou voltar

var _nomes: Array = []            # pronto para desenhar: {pos, text, a, side}
var _nome_alfa: Dictionary = {}   # unit id -> alfa atual (0..1)
var _flash: float = 0.0
var _flash_color := Color.WHITE
var _shake: float = 0.0
## O DESLOCAMENTO DO TREMOR DESTE QUADRO, sorteado uma vez no `_process`. Era
## sorteado dentro do `_draw`; agora as camadas com material proprio desenham
## em `_draw` separados e precisam tremer JUNTO — com dois sorteios a silhueta
## branca sairia deslocada do corpo.
var _shake_v := Vector2.ZERO
var _hover_id := 0

## A simulacao anda a 10 Hz; a tela desenha a 60. Sem suavizacao o combate
## fica em stop-motion. As posicoes desenhadas perseguem as da simulacao --
## a simulacao continua sendo a unica fonte de verdade.
var _draw_pos: Dictionary = {}   # unit id -> Vector2 suavizado
var _bob: float = 0.0
var _swings: Array = []          # projeteis em voo (ataques a distancia)
var _lunge: Dictionary = {}      # (sem uso com sprites animados; mantido inerte)
var _attacks: Dictionary = {}    # unit id -> {start, dur} da animacao de ataque

## O ANGULO DO CHAO (autor, 09/09: "faz as esferas das magias serem
## posicionadas em relacao ao cenario no mesmo angulo, ja que esta um formato de
## esfera errado").
##
## A arena e vista de cima e de lado — o piso e uma elipse achatada, e a sombra
## e os aneis de aura ja obedeciam a esse achatamento. A mira do Ativo e as
## ondas de reacao nao: eram `draw_circle` e `draw_arc`, circulos perfeitos.
## Uma bola redonda sobre um chao inclinado nao lE como estando NO chao — lE
## como um adesivo colado na tela, e era isso que estava errado na forma.
##
## Uma constante so, usada por todo mundo que desenha no chao: sombra, anel de
## aura, mira e onda. Se o angulo da camera mudar, muda aqui.
##
## ERA 0,34 E O ACHATAMENTO REAL DA ELIPSE E 0,443 (revisao 15/09): o piso tem
## `arena_half_height / arena_half_width` = 235/530 = 0,4434, e as marcas de
## chao estavam TODAS achatadas demais para o chao em que pousam. Uma sombra
## mais achatada que o piso le como vista de um angulo mais rasante que o da
## arena — o erro nao aparece sozinho, aparece como "nao sei o que esta errado".
## Sai da conta e nao de um chute: se a arena mudar de proporcao, a sombra
## acompanha.
const SQUASH := 0.443

const LUNGE_TIME := 0.20
const SHOT_TIME := 0.16

const SCALE := 1.0

## QUANTO O CAMPO DESCE NA TELA (autor, 11/09: "puxa a arena levemente pra baixo
## ou reduz um pouco o perimetro dela, eu realmente nao quero ver esse clipping
## nas montanhas").
##
## Era 14 px, uma correcao de centragem. Agora e o respiro entre a arena e a
## paisagem: descer o desenho do campo abre espaco em cima sem tocar em NADA da
## simulacao.
##
## E por isso que a saida foi descer e nao encolher. `arena_half_width` e
## `arena_half_height` sao parametros de MOVIMENTO — e onde as criaturas podem
## andar. Encolher a elipse desenhada sem encolher os limites deixaria as
## criaturas andando fora do piso; encolher os dois mudaria o espacamento do
## combate, que esta medido e equilibrado.
const DESCE := 68.0

## A CAMERA (revisao 15/09, "a briga acontece na casa do inimigo").
##
## MEDIDO pelos pixels das barras de vida em tres combates: nove unidades, nove
## com x > 0, entre +50 e +244, numa arena de +-530; mediana +167. A causa e
## uma fuga sem ancora na simulacao — o kiter quer distancia e o perseguidor
## quer encostar, e cada troca empurra o par `kite - hold` px na direcao da casa
## do kiter. Com 3 das 5 especies tendo kite e a dupla inicial sendo melee, a
## deriva e sempre para +x.
##
## DAS DUAS CORRECOES POSSIVEIS, ESTA E A QUE NAO TOCA A SIMULACAO. A outra
## (coleira de casa no kiter) e uma linha, mas mexe no movimento e obrigaria a
## remedir o equilibrio inteiro. Aqui o `to_screen` e o funil unico por onde
## TUDO passa — corpo, sombra, nome, numero, faisca, cenario, marca de chao —
## entao deslocar a camera desloca a cena inteira sem que nenhum deles saiba.
##
## O LIMITE E A PROPRIA ELIPSE: a camera nunca deixa a borda do piso entrar no
## quadro. Com o campo em 1134 px e a arena em 1060, sobram 37 px de curso para
## cada lado — pouco, e e o teto honesto do que a camera pode fazer sozinha. O
## resto dos 310 px medidos e a CENTRAGEM do FieldView na tela (o HBox da 364 px
## a esquerda e 102 a direita), que e de screen_combat.gd e esta em "pedidos".
const CAM_SUAVE := 3.2      # 1/s; ~0,3 s para a camera alcancar o centroide
## A vertical anda pela METADE. O cenario e ancorado no centro da arena e sobe
## e desce junto com a camera; em cheio, um clinch no fundo do campo fazia a
## paisagem inteira deslizar e o olho lia como o chao afundando.
const CAM_PESO_Y := 0.5

var _cam := Vector2.ZERO

## AS CAMADAS COM MATERIAL PROPRIO (ver CamadaPintor). No Godot 4 o material e
## do CanvasItem e nao do comando de desenho, entao cada passada com shader
## precisa do seu Control.
var _piso: ArenaPiso = null
var _silhuetas: CamadaPintor = null    # hit-flash
var _desmanche: CamadaPintor = null    # morte
var _brilho: CamadaPintor = null       # bloom aditivo

## HIT-FLASH: id da unidade -> tempo restante de branco.
var _flashes: Dictionary = {}
## MORTE: corpos em desmanche. Guardam a propria ficha porque a unidade some
## da simulacao — `alive` vira false e o sprite muda de tinta no mesmo quadro.
var _mortes: Array = []
## Halos aditivos de curta duracao (reacao, ativo, ultimate, critico).
var _halos: Array = []

## O AUDIO E DE OUTRO AGENTE (autoload `Som`). Resolvido por caminho e nao pelo
## nome global de proposito: assim este arquivo compila e roda com ou sem o
## autoload registrado em project.godot, e um combate sem som nunca vira crash.
var _som: Node = null
## Ultimo instante em que cada som tocou, no relogio da TELA. Sem isto um
## combate em 4x dispara "golpe" dezenas de vezes por segundo e o efeito vira
## serra eletrica.
var _som_quando: Dictionary = {}
const SOM_INTERVALO := {
	"golpe": 0.07, "critico": 0.12, "reacao": 0.10, "morte": 0.0,
	"ativo": 0.0, "cura": 0.18, "escudo": 0.18, "controle": 0.18,
}
var _relogio := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_PASS
	# a UI e pixel art (nearest), mas as pecas de criatura da Kenney sao
	# vetoriais e ficam serrilhadas sem interpolacao
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	# O CAMPO RECORTA NO PROPRIO RETANGULO (autor, 16/09: "uma sobreposicao do
	# cenario na interface muito indesejado").
	#
	# O QUE ACONTECIA. O cenario e uma CENA FILHA deste Control, desenhada com
	# 1280 px de largura centrada no campo. O campo tem 872 px (a tela menos as
	# duas colunas de 364), entao a paisagem transbordava 204 px para cada lado
	# — e como o FieldView e irmao POSTERIOR da coluna da esquerda dentro do
	# HBox, ele desenha DEPOIS dela: a montanha e o poste passavam POR CIMA das
	# fichas de "SUA EQUIPE". No print do autor da para ler o numero de vida da
	# segunda ficha atraves do morro.
	#
	# `clip_contents` e o conserto de raiz, e nao um painel opaco por cima: ele
	# vira um retangulo de tesoura no CanvasItem, e no Godot 4 esse retangulo
	# desce para TODA a subarvore de desenho — inclusive os filhos com
	# `show_behind_parent` (cenario, piso, brilho), que sao justamente os que
	# vazavam. Particula, faisca, halo, numero e rotulo saem do `_draw` deste
	# proprio Control e ficam presos pelo mesmo retangulo.
	#
	# O desbote lateral do cenario foi reancorado na largura do CAMPO (ver
	# `_posicionar_cenario`) para o recorte nunca cair em cima de tinta opaca:
	# a paisagem chega transparente na tesoura em vez de ser cortada a faca.
	clip_contents = true
	_som = get_node_or_null("/root/Som")
	_particulas.squash = SQUASH
	_montar_camadas()
	set_process(true)


## A ORDEM DOS FILHOS E A ORDEM DE DESENHO. Filho de Control desenha DEPOIS do
## pai, salvo `show_behind_parent` — e entre os que ficam atras vale a ordem na
## arvore. De tras para a frente:
##   cenario (montanhas) -> piso -> brilho -> [o _draw do FieldView] ->
##   silhuetas -> desmanche
## O brilho fica ATRAS porque e aditivo: na frente ele lavaria os numeros e os
## nomes, que sao a informacao que precisa ser lida.
func _montar_camadas() -> void:
	_piso = ArenaPiso.new()
	add_child(_piso)
	_brilho = CamadaPintor.aditiva(true)
	_brilho.pintar = _pintar_brilho
	add_child(_brilho)
	_silhuetas = CamadaPintor.com_shader("res://assets/shaders/silhueta.gdshader")
	_silhuetas.pintar = _pintar_silhuetas
	add_child(_silhuetas)
	_desmanche = CamadaPintor.com_shader("res://assets/shaders/dissolve.gdshader")
	_desmanche.pintar = _pintar_desmanche
	add_child(_desmanche)


func to_screen(p: Vector2) -> Vector2:
	return size * 0.5 + (p - _cam) * SCALE + Vector2(0.0, DESCE)


func to_field(p: Vector2) -> Vector2:
	return (p - size * 0.5 - Vector2(0.0, DESCE)) / SCALE + _cam


## O centroide dos VIVOS, suavizado e preso dentro da elipse. Mortos ficam de
## fora: um corpo caido no canto puxaria a camera para um lugar onde nao
## acontece mais nada.
func _atualizar_camera(delta: float) -> void:
	var alvo := Vector2.ZERO
	if sim != null:
		var n := 0
		for u in sim.units:
			if u.alive:
				alvo += _dp(u)
				n += 1
		if n > 0:
			alvo /= float(n)
			alvo.y *= CAM_PESO_Y
		else:
			alvo = _cam
	var mv: Dictionary = Db.tuning.get("movement", {})
	var hw: float = float(mv.get("arena_half_width", 530.0))
	var hh: float = float(mv.get("arena_half_height", 235.0))
	# O CURSO E O MODULO DA DIFERENCA, e nao a diferenca capada em zero.
	#
	# A regra e sempre a mesma — "a camera anda ate a borda da elipse alcancar
	# a borda do quadro" — mas ela tem DOIS regimes, e o codigo so escrevia um.
	# Com o campo MAIS LARGO que a arena, o curso e `meia_tela - hw`: passar
	# disso deixaria o vazio entrar no quadro. Com o campo mais ESTREITO (e e
	# este o caso real: 872 px de campo contra 1060 px de arena), a janela
	# desliza DENTRO da arena e o curso e `hw - meia_tela` — a mesma borda, o
	# outro lado da conta.
	#
	# Capado em zero, o segundo regime dava curso ZERO: a camera nunca saia do
	# lugar, e a revisao de 15/09 creditou a ela 37 px de correcao que ela
	# nunca aplicou (a conta de la usava um campo de 1134 px, que era o de
	# antes das colunas simetricas). Com o modulo sao 94 px de curso de
	# verdade — e e o que impede um lutador no extremo da arena de ser cortado
	# pelo recorte novo do campo.
	var curso_x: float = absf(size.x * 0.5 - hw)
	var cima: float = minf(hh + DESCE - size.y * 0.5, 0.0)
	var baixo: float = maxf(size.y * 0.5 - hh + DESCE, 0.0)
	alvo.x = clampf(alvo.x, -curso_x, curso_x)
	alvo.y = clampf(alvo.y, cima, baixo)
	_cam = _cam.lerp(alvo, 1.0 - exp(-CAM_SUAVE * delta))


## Onde a unidade esta NA TELA agora — a posicao desenhada, que e interpolada
## e pode diferir de u.pos. E o ponto em que unit_at() a encontra, entao quem
## quiser clicar nela programaticamente (o teste) deve usar isto.
## O clique chega por AQUI, e não só pelo _unhandled_input da tela. O
## _unhandled_input só recebe eventos que nenhum Control consumiu — basta um
## painel novo no caminho para a mira parar de funcionar sem ninguém perceber.
## Com mouse_filter = PASS, o _gui_input é entregue ao Control sob o cursor e
## o evento continua subindo: os dois caminhos coexistem, e a mira não depende
## de sorte de ordenação da árvore.
func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed 			and event.button_index == MOUSE_BUTTON_LEFT:
		clicked.emit(get_local_mouse_position())


func screen_of(u: SimUnit) -> Vector2:
	return to_screen(_dp(u))


func unit_at(screen_pos: Vector2) -> SimUnit:
	if sim == null:
		return null
	var best: SimUnit = null
	var bd := 46.0
	for u in sim.units:
		if not u.alive:
			continue
		var d: float = to_screen(_dp(u)).distance_to(screen_pos)
		if d < bd:
			bd = d
			best = u
	return best


func feed(events: Array) -> void:
	for e in events:
		match String(e.get("kind", "")):
			"begin":
				# A arena tinge o piso e traz a ilustracao de fundo desde o
				# primeiro quadro: o jogador ve a regra da briga antes de ela
				# acontecer.
				#
				# ATE 09/09 ISTO NUNCA RODOU. O evento mandava apenas o `effect`
				# da arena sob a chave "arena", e o `tint` mora um nivel acima,
				# junto de `id` e `name` — a busca falhava em silencio e toda
				# arena desenhava com o cinza padrao. Agora o `begin` carrega a
				# ficha completa.
				var ar: Dictionary = e.get("arena", {})
				var t := String(ar.get("tint", ""))
				if t != "":
					var c := Color(t)
					arena_cor = Color(c.r, c.g, c.b, 1.0)
					# O VEU DO PISO PERDE SATURACAO E BRILHO; a cor cheia nao.
					#
					# Com o tint cru o Bosque virava um disco verde de plastico e
					# o Solo Vulcanico um disco vermelho, os dois engolindo as
					# criaturas — enquanto Nevasca e Camara, de matiz mais neutro,
					# ficavam discretos na MESMA opacidade. Nao era a opacidade, era
					# a saturacao.
					#
					# AGORA O CORTE E O CONTRATO DE COR INTEIRO (S <= 0,30 e
					# V entre 0,34 e 0,40, ver ArenaPiso): o chao fica na banda
					# escura e dessaturada seja qual for o hex que vier dos
					# dados. Os sete tints de enemies.json foram girados para
					# longe do elemento que luta em cada arena (15/09) — o
					# bosque_vivo era literalmente UI.GOOD, a cor da barra de
					# vida aliada —, entao hoje isto e cinto E suspensorio.
					#
					# Particula, faisca e marca de chao continuam na cor CHEIA:
					# brasa alaranjada e anel de runa sao o que deve saltar.
					arena_tint = ArenaPiso.cor_de_piso(arena_cor)
				_carregar_cenario(String(ar.get("id", "")))
			"arena_pulse":
				_pulse = 1.0
				var el := String(e.get("element", ""))
				# no CENTRO da arena e na faixa de cima: e um evento de fundo,
				# nao pode competir com o anuncio da reacao. E dos poucos que
				# CONTINUAM no corredor do ceu — ele e de campo, nao de ninguem.
				_push_pop(Vector2.ZERO, _arena_label(e),
					Db.el_color(el) if el != "" else UI.WARN, true, 1, -1, true)
			"ghost":
				_push_pop(e.get("pos", Vector2.ZERO),
					"%s virou fantasma" % String(e.get("name", "")),
					Color("#a86fe0"), false, 1, int(e.get("id", -1)))
			"damage":
				# O FILTRO DE 3% SAIU (revisao 15/09). Ele jogava fora TODO
				# golpe abaixo de 3% do HP do alvo — e esses golpes nao
				# produziam retorno nenhum: nem numero, nem corpo, nem som.
				# Numa briga com hp_scale 3,7 isso e a maioria dos ataques
				# basicos, entao a arena passava minutos sem confirmar que
				# alguem estava batendo em alguem. Agora o golpe pequeno tem o
				# hit-flash e a faisca; e quem impede a nuvem de digitos e a
				# agregacao POR VITIMA, que so agora funciona de verdade.
				var dt := String(e["type"])
				var crit: bool = bool(e.get("crit", false))
				var alvo_id: int = int(e["dst"])
				var cor_d: Color = UI.damage_color(dt, String(e.get("element", "")))
				_push_floater(e["pos"], alvo_id, roundi(float(e["amount"])),
					"dano", cor_d, 15.0 if dt == "reaction" else 10.0, crit)
				_flashes[alvo_id] = FLASH_CORPO
				_particulas.faiscar(e["pos"], cor_d, 5 if crit else 2,
					150.0 if crit else 88.0)
				if crit:
					_halo(e["pos"], 66.0, cor_d, 0.22)
				_som_tocar("critico" if crit else "golpe")
			"death":
				# O EVENTO EXISTIA DESDE SEMPRE e ninguem o consumia: o momento
				# mais importante da briga era um corte seco de cor.
				_matar(int(e.get("id", -1)), e.get("pos", Vector2.ZERO))
			"reaction":
				var col := Color(String(e.get("color", "#ffffff")))
				var dst_r: int = int(e.get("dst", -1))
				_push_pop(e["pos"], String(e["name"]), col, true, 0, dst_r)
				_flash = maxf(_flash, float(e.get("flash", 0.3)))
				_flash_color = col
				if bool(ScreenOptions.get_opt("tremor")):
					_shake = maxf(_shake, float(e.get("flash", 0.3)) * 5.0)
				# O RAIO REAL, e nao 54 fixo. reactions.json da radius 140 a
				# Detonacao e 120 a Superconducao, e combat_sim.gd:709 USA esse
				# raio para causar dano em area — mas a view desenhava o mesmo
				# circulo para tudo, entao Detonacao (area) e Eletrocussao (alvo
				# unico) eram visualmente identicas e nao havia como aprender
				# quais reacoes pegam o grupo. O `get` com padrao faz isto
				# funcionar antes e depois de o evento passar a carregar o raio.
				var raio_r: float = float(e.get("radius", 0.0))
				if raio_r <= 0.0:
					raio_r = 54.0
				_rings.append({"pos": e["pos"], "color": col, "life": 0.0, "r": raio_r})
				while _rings.size() > MAX_RINGS:
					_rings.pop_front()
				_particulas.faiscar(e["pos"], col, 9, 165.0)
				_halo(e["pos"], maxf(raio_r, 70.0), col, 0.30)
				_som_tocar("reacao")
			"attack":
				_attacks[int(e["src"])] = {"start": float(e["t"]),
					"dur": float(e["interval"])}
			"swing":
				var col := Db.el_color(String(e.get("element", "")))
				if bool(e.get("ranged", false)):
					_swings.append({"from": e["from"], "to": e["to"], "color": col, "life": 0.0})
				else:
					var dir: Vector2 = Vector2(e["to"]) - Vector2(e["from"])
					if dir.length() > 0.01:
						_lunge[int(e["src"])] = {"dir": dir.normalized(), "life": 0.0}
			"heal", "shield":
				# Cura e escudo abaixo de 3% do HP máximo não viram número. Com
				# hp_scale 3.7 um "+29" numa unidade de 2886 HP é 1% — ruído
				# verde piscando sem informar nada. (O filtro do DANO saiu, este
				# fica: o golpe pequeno agora tem faisca e hit-flash para
				# confirmar que aconteceu, a cura pequena nao precisa de nada.)
				var quem: int = int(e.get("dst", -1))
				var who: SimUnit = sim.by_id.get(quem) if sim != null else null
				var pct: float = float(e["amount"]) / maxf(who.hp_max if who else 1.0, 1.0)
				var cura: bool = String(e["kind"]) == "heal"
				if pct >= 0.03:
					_push_floater(e["pos"], quem, roundi(float(e["amount"])),
						"cura" if cura else "escudo",
						UI.GOOD if cura else Color("#9fd8ff"), 10.0, false)
					_som_tocar("cura" if cura else "escudo")
			"control":
				# sem rotulo: "FREEZE" duplicava o pop de "Congelar" da propria reacao.
				# O estado ja e lido pelo simbolo e pelo halo desenhado na unidade.
				_som_tocar("controle")
			"control_immune":
				_push_pop(e["pos"], "IMUNE", UI.TEXT_DIM, true, 0,
					int(e.get("dst", -1)))
			"active":
				var ac := Color(String(e.get("color", "#ffffff")))
				_rings.append({"pos": e["pos"], "color": ac, "life": 0.0,
					"r": maxf(float(e.get("radius", 0.0)), 120.0)})
				_push_pop(e["pos"], String(e["name"]), ac, false, 1)
				_flash = maxf(_flash, 0.45)
				_flash_color = ac
				_particulas.faiscar(e["pos"], ac, 12, 190.0)
				_halo(e["pos"], maxf(float(e.get("radius", 0.0)), 120.0), ac, 0.40)
				_som_tocar("ativo")
			"rewrite":
				_push_pop(e["pos"], "→ " + Db.el_name(String(e["element"])),
					Db.el_color(String(e["element"])), false, 0,
					int(e.get("id", e.get("dst", -1))))
			"ult":
				_push_pop_ult(e["pos"], "⚡ " + String(e["name"]),
					Db.el_color(String(e.get("element", ""))).lightened(0.3), false, 1,
					int(e.get("src", -1)))
			"boss_hunger":
				_push_pop(e["pos"], "%s −%d" % [String(e["name"]), int(e["eaten"])],
					UI.WARN, false, 1, -1, true)
			"boss_rage":
				_push_pop(e["pos"], "FAMINTO +50% ATK", UI.BAD, false, 1, -1, true)


## UM NUMERO POR VITIMA, E SO UM (autor, 16/09: "os numeros de dano AINDA se
## empilham em parede no clinch... com quatro corpos encostados sobra
## ilegivel").
##
## O TETO ANTERIOR ERA TRES POR VITIMA, E ALEM DELE HAVIA UM LEQUE. Com quatro
## corpos encostados sao doze numeros permitidos, e o leque — que abria em
## zigue-zague conforme a VIZINHANCA, nao conforme a vitima — ainda espalhava
## cada um deles por uma grade de 3x2. A parede do print e a soma das duas
## coisas: a agregacao virou por vitima em 15/09, mas o TETO e o DESENHO
## continuaram contando lugar.
##
## AGORA A REGRA E ARITMETICA E NAO DE ACASO: enquanto um numero esta no ar,
## todo golpe novo na mesma vitima SOMA nele e ele cresce. Fechada a janela de
## agregacao, o numero velho e RETIRADO no mesmo quadro em que o novo nasce —
## nunca existem dois do mesmo tipo em cima do mesmo bicho, nem por um quadro.
## O teto de digitos na tela passa a ser o numero de CORPOS que estao apanhando,
## e nao o numero de golpes que cairam.
const AGREGA_FLOATER := 0.45
const FLOATER_VIDA := 0.75

## Altura de uma pista de numero, e quantas existem. Elas so entram em uso
## quando duas VITIMAS VIZINHAS teriam o numero no mesmo palmo de tela — nunca
## para separar dois golpes do mesmo bicho, que agora e sempre um numero so.
const FLOATER_PISTA := 20.0
const FLOATER_PISTAS := 3

## O sinal que abre cada tipo de numero. E o que separa "levou 900" de
## "recuperou 900" sem precisar da cor, que um daltonico nao tem.
const FLOATER_PREFIXO := {"dano": "", "cura": "+", "escudo": "◇"}


## Numeros de dano. Os digitos usam a Pixeled, que desenha bem maior que o
## tamanho nominal, entao a largura sai medida da fonte e nunca estimada.
##
## Os números de dano podem ser desligados nas Configurações. Não é enfeite:
## num combate com maré elemental são 36 reações, e para quem lê a briga pelas
## AURAS os números viram cortina.
func _push_floater(pos: Vector2, dst: int, valor: int, tipo: String,
		color: Color, sz: float, crit: bool) -> void:
	if not bool(ScreenOptions.get_opt("numeros")):
		return
	var velho: Dictionary = {}
	for f in _floaters:
		if int(f.get("dst", -1)) == dst and String(f.get("tipo", "")) == tipo:
			velho = f
			break
	if not velho.is_empty():
		if float(velho["idade"]) < AGREGA_FLOATER:
			velho["valor"] = int(velho["valor"]) + valor
			velho["life"] = 0.0
			# cresce a cada soma, com teto: o numero que mais doi e o maior.
			# O teto desceu de 1,6x para 1,35x — o numero somado de uma cadeia
			# ja tem quatro digitos, e crescer 60% em cima disso era o que
			# fazia dois vizinhos se tocarem mesmo estando um por corpo.
			velho["size"] = minf(float(velho["size"]) + 2.0, sz * 1.35)
			velho["crit"] = bool(velho["crit"]) or crit
			# A COR E A DO MAIOR PEDACO. Somar um tapa de 40 dentro de uma
			# reacao de 900 nao pode repintar o numero com a cor do tapa: quem
			# olha lE a cor para saber de que natureza foi o golpe que doeu.
			if valor > int(velho["maior"]):
				velho["maior"] = valor
				velho["color"] = color
			_medir_floater(velho)
			return
		# Janela fechada: o velho sai AGORA, no mesmo quadro em que o novo
		# entra. E esta linha que impede o par "um nitido e um apagado" —
		# o mesmo defeito que as faixas de reacao tinham.
		_floaters.erase(velho)
	var novo := {"pos": pos, "dst": dst, "tipo": tipo, "valor": valor,
		"maior": valor, "color": color, "life": 0.0, "idade": 0.0,
		"size": sz, "crit": crit, "text": "", "w": 0.0, "pista": 0,
		"off": Vector2.ZERO}
	_medir_floater(novo)
	_floaters.append(novo)


## O texto, a largura e o deslocamento do numero, num lugar so.
##
## `text`, `size` e `off` sao lidos DE FORA — `tools/numeros_probe.gd` mede a
## sobreposicao por eles e nao roda o `_process` desta classe. Por isso os tres
## precisam estar corretos no instante em que o dicionario e criado, e nao
## apenas depois da primeira passada de pistas.
func _medir_floater(f: Dictionary) -> void:
	f["text"] = String(FLOATER_PREFIXO.get(String(f["tipo"]), "")) 		+ str(int(f["valor"]))
	var fnt: Font = PrismaTheme.digit_font if PrismaTheme.digit_font != null 		else ThemeDB.fallback_font
	# O CRITICO DESENHA MAIOR, entao a largura tem de ser medida no corpo
	# DESENHADO. Medindo no corpo nominal, um critico saia 35% mais largo que a
	# caixa que o centrou — e o numero ficava deslocado para a direita do dono,
	# que era mais um jeito de dois vizinhos se tocarem.
	f["desenho"] = float(f["size"]) * (1.35 if bool(f["crit"]) else 1.0)
	f["w"] = fnt.get_string_size(String(f["text"]), HORIZONTAL_ALIGNMENT_LEFT,
		-1, int(f["desenho"])).x
	# CENTRADO NO DONO, e nao ancorado a esquerda dele: com o numero crescendo a
	# cada soma, a ancora a esquerda fazia o rotulo caminhar para a direita
	# enquanto a vitima ficava parada.
	f["off"] = Vector2(-float(f["w"]) * 0.5, -float(f["pista"]) * FLOATER_PISTA)


## AS PISTAS DOS NUMEROS. Com um numero por vitima, o unico conflito que sobra
## e entre vitimas VIZINHAS: dois corpos separados por 64 px de raio de
## separacao podem carregar numeros de 56 px de largura.
##
## A ordem e ESTAVEL (id da vitima, depois tipo) e nao por posicao: com uma
## chave que muda de quadro a quadro, dois numeros trocariam de pista a cada
## passo da simulacao e piscariam juntos — e o mesmo erro ja foi cometido e
## corrigido nos rotulos de nome.
func _arrumar_floaters() -> void:
	if _floaters.is_empty():
		return
	var ordem := _floaters.duplicate()
	ordem.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if int(a["dst"]) != int(b["dst"]):
			return int(a["dst"]) < int(b["dst"])
		return String(a["tipo"]) < String(b["tipo"]))
	var caixas: Array = []
	for f in ordem:
		var w: float = float(f["w"])
		var sz: float = float(f["size"])
		var base := to_screen(Vector2(f["pos"]))
		var pista := 0
		while pista < FLOATER_PISTAS:
			var r := Rect2(base.x - w * 0.5 - 3.0,
				base.y - 34.0 - float(pista) * FLOATER_PISTA - sz,
				w + 6.0, sz + 4.0)
			var livre := true
			for c in caixas:
				if r.intersects(c):
					livre = false
					break
			if livre:
				caixas.append(r)
				break
			pista += 1
		f["pista"] = mini(pista, FLOATER_PISTAS - 1)
		_medir_floater(f)


## GDD 21.2 -- o nome da reacao precisa ser LIDO. Repeticoes proximas viram
## "Derretimento x4" em vez de quatro rotulos empilhados no mesmo pixel.
## Ultimates agregam como as reacoes: tres "Arco Voltaico" ao mesmo tempo
## viram "Arco Voltaico ×3" em vez de tres rotulos no mesmo pixel.
func _push_pop_ult(pos: Vector2, text: String, color: Color, _a: bool, band: int,
		uid: int = -1) -> void:
	_push_pop(pos, text, color, true, band, uid)


## VIDA E FADE DO ANUNCIO, num lugar so. Antes o desenho e o alocador de pistas
## tinham numeros proprios: a pista era liberada aos 0,6 s e o desenho pintava
## a 100% de alfa ate 1,1 s. Ou seja, por quase meio segundo um rotulo novo
## caia exatamente em cima de um antigo ainda opaco — o alocador de pistas
## estava desligado justamente nos decimos em que ele importa.
const POP_VIDA := 1.1
const POP_FADE := 0.55       # fracao da vida em que o rotulo comeca a sumir
## Abaixo disto a pista e considerada livre. 0,25 de alfa corresponde a 0,98 s
## de vida — e nao aos 0,6 s de antes.
const POP_PISTA_LIVRE := 0.25

## POR QUANTO TEMPO UM ANUNCIO CONTINUA ACEITANDO REPETICOES.
##
## ERA MEIO SEGUNDO, E A VIDA DELE E 1,1 s (autor, 16/09: "as faixas de reacao
## aparecem DUPLICADAS e uma por cima da outra — uma nitida e outra apagada
## logo abaixo, no mesmo texto").
##
## Esse era o defeito inteiro, e ele estava nos numeros: entre 0,5 s e 1,1 s de
## vida o rotulo ainda esta na tela — e ate 0,605 s ainda esta com alfa CHEIO —
## mas ja tinha deixado de aceitar soma. A sexta Eletrocussao de uma cadeia
## abria um rotulo NOVO ao lado do que ainda estava aceso, com o mesmo texto:
## um nitido (recem-nascido) e um apagado (o velho esmaecendo). Nao eram dois
## avisos diferentes, era o mesmo aviso duas vezes.
##
## Agora a janela de soma cobre a vida inteira e sobra: enquanto ela vale, a
## repeticao soma no contador; quando ela fecha, o rotulo velho e RETIRADO no
## mesmo quadro em que o novo nasce. Nos dois regimes existe UM rotulo por
## texto e por vizinhanca — nunca dois, nem por um quadro.
const POP_AGREGA := 1.3

## A QUE DISTANCIA DUAS REACOES DE MESMO NOME VIRAM UMA SO.
##
## ERAM 190 px, E O PRINT DO AUTOR MOSTRA O PAR A 200. "Eletrocussão ×6" em
## cima de um bicho e "Eletrocussão ×7" em cima do vizinho, os dois no ar ao
## mesmo tempo, dez pixels alem do limiar — foi por isso que ele os leu como
## um rotulo duplicado e nao como dois avisos. E ele tem razao: o que o aviso
## diz e "esta acontecendo Eletrocussao", e essa frase nao melhora dita duas
## vezes.
##
## 340 px cobre um clinch inteiro (o raio de separacao e 64 px e cinco corpos
## empilhados ocupam ~300) e ainda deixa separadas duas brigas em cantos
## opostos de uma arena de 1060 px — que ai sao mesmo dois acontecimentos.
const POP_JUNTA := 340.0
## A que altura acima da CABECA o anuncio da unidade fica.
##
## MEDIDO NO PRINT, e nao chutado: os numeros de dano ocupam de 34 a 54 px
## acima do centro da criatura, mais ate 9 px de leque — ou seja, ate 63. Com
## uma criatura de 44 px (cabeca a 22 do centro), qualquer valor abaixo de 41
## poe o nome da reacao DENTRO da nuvem de digitos, que foi exatamente o que o
## primeiro print mostrou. 48 deixa o anuncio logo acima da faixa dos numeros.
##
## Sai da CABECA e nao do centro de proposito: o chefe tem 120 px de altura e o
## anuncio dele sobe junto, em vez de nascer no meio do corpo.
const POP_ACIMA := 48.0


func _pop_alfa(life: float) -> float:
	var t: float = life / POP_VIDA
	return clampf(1.0 - maxf(t - POP_FADE, 0.0) / (1.0 - POP_FADE), 0.0, 1.0)


## O ponto de onde o anuncio LOCAL sai: logo acima da cabeca do dono. Segue a
## unidade quadro a quadro — e por isso que recebe o id e nao so a posicao.
func _ancora_pop(uid: int, pos: Vector2) -> Vector2:
	var u: SimUnit = sim.by_id.get(uid) if sim != null and uid >= 0 else null
	if u == null:
		return to_screen(pos)
	return to_screen(_dp(u)) - Vector2(0.0, MonsterArt.size_of(u.species_id) * 0.5)


## `ceu` manda o rotulo para o corredor fixo do alto da arena. Ele ficou SO
## para o que e de campo — mare elemental, estimulo, avisos do chefe. Tudo o
## que tem dono (reacao, ultimate, imunidade, reescrita, fantasma) e ancorado
## em quem causou: as faixas de reacao moravam numa linha fixa do ceu, a ate
## 580 px de onde a reacao aconteceu, e nenhuma quantidade de bom desenho faz
## um rotulo a meia tela de distancia apontar para alguem.
func _push_pop(pos: Vector2, text: String, color: Color, aggregate: bool,
		band: int = 0, uid: int = -1, ceu: bool = false) -> void:
	# UM ROTULO POR TEXTO E POR VIZINHANCA. O primeiro laco soma no que ja
	# esta no ar; o segundo RETIRA o homonimo velho que nao aceita mais soma,
	# para o novo nascer sozinho em vez de ao lado dele.
	var velho: Dictionary = {}
	for p in _pops:
		if String(p["base"]) != text:
			continue
		if Vector2(p["pos"]).distance_to(pos) >= POP_JUNTA:
			continue
		velho = p
		break
	if not velho.is_empty():
		if aggregate and float(velho["idade"]) < POP_AGREGA:
			velho["count"] = int(velho["count"]) + 1
			velho["life"] = 0.0
			velho["text"] = "%s ×%d" % [text, int(velho["count"])]
			velho["half"] = _pop_width(String(velho["text"]),
				int(velho["size"])) * 0.5
			return
		_pops.erase(velho)
	# A faixa 1 (ultimates, avisos do chefe) e rara e importante: fonte maior.
	# A faixa 0 (nomes de reacao) e frequente: menor, para nao virar sopa.
	var sz: int = UI.fs(20) if band == 1 else UI.fs(15)
	var half: float = _pop_width(text, sz) * 0.5

	# Pista LIVRE, medida: sobe de pista so quando o rotulo REALMENTE encostaria
	# em outro que ja esta no ar. Com a fonte maior (revisao 31/08) o teste
	# antigo por distancia fixa empilhava rotulos que nem se tocavam — e
	# deixava outros sobrepostos.
	# Corredor UNICO de anuncios. Duas faixas com bases proprias (74 e 114) e
	# alturas de pista diferentes (22 e 34 px) se cruzavam: um ultimate caia
	# em cima de um nome de reacao. Agora todos disputam as mesmas pistas — a
	# faixa decide so o TAMANHO, e a checagem de sobreposicao usa a largura
	# real, entao um rotulo grande e um pequeno convivem na mesma linha.
	#
	# A PISTA DEIXOU DE SER UM NUMERO E VIROU UM RETANGULO. Enquanto todos os
	# rotulos saiam da MESMA linha do ceu, "mesma pista" e "mesma altura" eram
	# a mesma coisa e bastava comparar o x. Ancorados em donos diferentes, nao
	# sao: a pista 0 de quem esta atras cai exatamente na pista 1 de quem esta
	# na frente, e foi isso que o print mostrou ("CaudaSolarltaico ×4" — dois
	# anuncios no mesmo pixel, em pistas diferentes). Agora a checagem e de
	# interseccao de caixa contra caixa, que nao depende de baseline comum.
	var ancora := _ancora_pop(uid, pos)
	var cx: float = to_screen(pos).x if ceu else ancora.x
	# OS CORPOS TAMBEM BLOQUEIAM A PISTA (autor, 16/09: "os bonecos estao
	# amontoados em meio a muita informacao").
	#
	# O alocador so olhava para outros ANUNCIOS, entao um rotulo achava a
	# pista 0 livre e pousava em cima da criatura de tras — escondendo
	# exatamente o bicho a que o aviso se refere. A regra ja existia para os
	# NOMES (ver `_resolver_nomes`, "os corpos tambem ocupam"); aqui ela era a
	# mesma regra faltando no outro lugar. Quando todas as pistas estao
	# ocupadas o anuncio sobe para a mais alta, que e acima do amontoado: em
	# duvida entre cobrir e subir, ele sobe.
	var corpos: Array = []
	if sim != null and not ceu:
		for ub in sim.units:
			if not ub.alive:
				continue
			var hb: float = MonsterArt.size_of(ub.species_id)
			var pb := to_screen(_dp(ub))
			var wb: float = float(MonsterArt.metrics(ub.species_id, ub.element, hb)["w"])
			corpos.append(Rect2(pb.x - wb * 0.5, pb.y - hb * 0.5, wb, hb))
	# DUAS PASSADAS, E A ORDEM DELAS E A HIERARQUIA DA TELA. Na primeira o
	# corpo bloqueia; se nenhuma das cinco pistas sobreviver a isso, a segunda
	# ignora os corpos e so evita OUTROS ANUNCIOS. Um aviso por cima de um
	# bicho ainda se lE; dois avisos no mesmo pixel viram "ElVaporizario", que
	# foi literalmente o que a primeira versao desta regra produziu quando o
	# clinch tapou as cinco pistas e o `mini(lane, 4)` empilhou todo mundo na
	# ultima.
	var lane: int = _pista_livre(cx, half, sz, ceu, ancora, corpos)
	if lane < 0:
		lane = _pista_livre(cx, half, sz, ceu, ancora, [])
	if lane < 0:
		lane = 4
	_pops.append({"pos": pos, "base": text, "text": text, "color": color,
		"life": 0.0, "idade": 0.0, "count": 1, "lane": clampi(lane, 0, 4),
		"band": band, "size": sz, "half": half, "uid": uid, "ceu": ceu,
		"ancora": ancora})
	# Sem teto, a sétima reação simultânea caía numa pista já ocupada e os
	# rótulos se sobrepunham. Agora o mais antigo dá lugar ao novo.
	while _pops.size() > MAX_POPS:
		_pops.pop_front()


## A PRIMEIRA PISTA LIVRE, ou -1 se nao houver nenhuma. `bloqueios` sao caixas
## extras que tambem invalidam a pista — na pratica, os corpos das criaturas.
## Devolver -1 em vez de uma pista qualquer e o que permite ao chamador ter uma
## segunda opiniao com menos exigencia, em vez de empilhar rotulos na ultima.
func _pista_livre(cx: float, half: float, sz: int, ceu: bool, ancora: Vector2,
		bloqueios: Array) -> int:
	for lane in range(5):
		var cand := _pop_caixa(cx, half, float(sz), lane, ceu, ancora.y)
		var livre := true
		for p2 in _pops:
			if bool(p2["ceu"]) != ceu:
				continue
			if _pop_alfa(float(p2["life"])) <= POP_PISTA_LIVRE:
				continue
			if cand.intersects(_pop_caixa_de(p2)):
				livre = false
				break
		if livre:
			for b in bloqueios:
				if cand.intersects(b):
					livre = false
					break
		if livre:
			return lane
	return -1


## ONDE UM ANUNCIO CABE, em coordenadas de tela. E a fonte unica: o alocador de
## pistas, o desenho e a decisao de quem cede espaco ao nome leem todos daqui,
## entao nao existe a possibilidade de o rotulo ser desenhado num lugar e
## reservado em outro.
##
## `y` e a LINHA DE BASE do texto (e o que `draw_string` recebe), por isso a
## caixa comeca em `y - sz`.
func _pop_caixa(cx: float, half: float, sz: float, lane: int, ceu: bool,
		ancora_y: float) -> Rect2:
	var y: float
	if ceu:
		y = 68.0 + float(lane) * (UI.fs(20) + 9.0)
	else:
		y = maxf(ancora_y - POP_ACIMA - float(lane) * (sz + 6.0), sz + 6.0)
	var x: float = clampf(cx, half + 12.0, maxf(size.x - half - 12.0, half + 12.0))
	return Rect2(x - half - 4.0, y - sz, half * 2.0 + 8.0, sz + 6.0)


func _pop_caixa_de(pp: Dictionary) -> Rect2:
	var ceu: bool = bool(pp["ceu"])
	var cx: float = to_screen(Vector2(pp["pos"])).x if ceu else float(Vector2(pp["ancora"]).x)
	return _pop_caixa(cx, float(pp["half"]), float(pp["size"]), int(pp["lane"]),
		ceu, float(Vector2(pp["ancora"]).y))


func _pop_width(text: String, sz: int) -> float:
	var f: Font = PrismaTheme.body_font if PrismaTheme.body_font != null 			else ThemeDB.fallback_font
	return f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, sz).x


func _process(delta: float) -> void:
	_relogio += delta
	_pulse = maxf(_pulse - delta * 1.4, 0.0)
	_smooth_positions(delta)
	_atualizar_camera(delta)
	for f in _floaters.duplicate():
		f["life"] += delta
		# `idade` conta do NASCIMENTO e `life` conta do ultimo golpe: a primeira
		# fecha a janela de soma, a segunda governa o fade. Com um relogio so,
		# uma cadeia longa reacenderia o mesmo numero para sempre.
		f["idade"] = float(f["idade"]) + delta
		if f["life"] > FLOATER_VIDA:
			_floaters.erase(f)
			continue
		# O ROTULO SEGUE A VITIMA. Agregar por vitima e deixar o numero parado
		# onde o primeiro golpe caiu seria meio conserto: em 0,45 s de janela a
		# criatura anda ate 90 px, e o numero ficaria apontando para o chao.
		var vf: SimUnit = sim.by_id.get(int(f.get("dst", -1))) if sim != null else null
		if vf != null and vf.alive:
			f["pos"] = _dp(vf)
	# depois de todos seguirem os donos, decide quem sobe de pista
	_arrumar_floaters()
	for p in _pops.duplicate():
		p["life"] += delta
		p["idade"] = float(p["idade"]) + delta
		if p["life"] > POP_VIDA:
			_pops.erase(p)
			continue
		if not bool(p["ceu"]):
			p["ancora"] = _ancora_pop(int(p["uid"]), Vector2(p["pos"]))
	for r in _rings.duplicate():
		r["life"] += delta
		if r["life"] > 0.45:
			_rings.erase(r)
	_flash = maxf(_flash - delta * 3.2, 0.0)
	_shake = maxf(_shake - delta * 22.0, 0.0)
	_shake_v = Vector2(randf_range(-_shake, _shake), randf_range(-_shake, _shake)) \
		if _shake > 0.1 else Vector2.ZERO
	_bob += delta
	for sw in _swings.duplicate():
		sw["life"] += delta
		if sw["life"] > SHOT_TIME:
			_swings.erase(sw)
	for k in _lunge.keys():
		_lunge[k]["life"] = float(_lunge[k]["life"]) + delta
	for k in _lunge.keys().filter(func(x): return float(_lunge[x]["life"]) > LUNGE_TIME):
		_lunge.erase(k)
	_atualizar_efeitos(delta)
	_resolver_nomes(delta)
	_particulas.atualizar(delta, size)
	_posicionar_cenario(Vector2.ZERO)
	_atualizar_piso()
	queue_redraw()
	# as camadas tem `_draw` proprio e nao redesenham sozinhas
	_silhuetas.queue_redraw()
	_desmanche.queue_redraw()
	_brilho.queue_redraw()


## HIT-FLASH, DESMANCHE E HALO andam juntos: sao os tres efeitos curtos que
## nascem de evento e morrem no relogio da TELA.
func _atualizar_efeitos(delta: float) -> void:
	for id in _flashes.keys():
		var t: float = float(_flashes[id]) - delta
		if t <= 0.0:
			_flashes.erase(id)
		else:
			_flashes[id] = t
	for m in _mortes.duplicate():
		m["life"] = float(m["life"]) + delta
		if float(m["life"]) > MORTE_TEMPO:
			_mortes.erase(m)
	for h in _halos.duplicate():
		h["life"] = float(h["life"]) + delta
		if float(h["life"]) > float(h["total"]):
			_halos.erase(h)


func _atualizar_piso() -> void:
	if _piso == null:
		return
	var mv: Dictionary = Db.tuning.get("movement", {})
	_piso.atualizar(to_screen(Vector2.ZERO),
		Vector2(float(mv.get("arena_half_width", 530.0)),
			float(mv.get("arena_half_height", 235.0))),
		_pulse * 0.10)


## QUANTO TEMPO A CRIATURA FICA BRANCA ao apanhar. 0,09 s sao ~5 quadros a 60
## Hz: menos que isso e invisivel num combate acelerado, mais que isso vira
## estroboscopio quando quatro unidades apanham ao mesmo tempo.
const FLASH_CORPO := 0.09
## O desmanche da morte. Mais curto que isto e um corte; mais longo e o corpo
## fica pairando enquanto a briga ja seguiu.
const MORTE_TEMPO := 0.55
const MAX_HALOS := 8


## A MORTE, finalmente consumida. Guarda a ficha do corpo porque a unidade ja
## saiu do jogo no instante em que o evento chega: `alive` e false e
## `_draw_unit` ja a pinta cinza no mesmo quadro.
func _matar(id: int, pos: Vector2) -> void:
	var u: SimUnit = sim.by_id.get(id) if sim != null else null
	var p := pos
	var cor := UI.TEXT
	var ficha := {"especie": "", "altura": 40.0, "facing": 1.0,
		"pos": p, "life": 0.0, "cor": cor}
	if u != null:
		p = _dp(u)
		cor = Db.el_color(u.element)
		ficha = {"especie": u.species_id, "altura": MonsterArt.size_of(u.species_id),
			"facing": u.facing, "pos": p, "life": 0.0, "cor": cor}
	_mortes.append(ficha)
	# um corpo que esta desmanchando nao pode continuar piscando de branco
	_flashes.erase(id)
	_particulas.faiscar(p, cor, 16, 205.0)
	_halo(p, 96.0, cor, 0.45)
	_som_tocar("morte")


func _halo(pos: Vector2, raio: float, cor: Color, dur: float) -> void:
	while _halos.size() >= MAX_HALOS:
		_halos.pop_front()
	_halos.append({"pos": pos, "r": raio, "cor": cor, "life": 0.0, "total": dur})


## O SOM E DE OUTRO AGENTE. Chamado por `call` sobre o no do autoload em vez do
## nome global: assim o combate roda identico com ou sem o autoload registrado,
## e a ausencia de audio nunca vira crash nem erro de compilacao aqui.
##
## COM ESPERA POR NOME. Em 4x o feed cospe dezenas de "damage" por segundo de
## relogio de parede; sem a espera, "golpe" viraria serra eletrica. O intervalo
## e por nome porque "morte" e "ativo" sao raros e nao podem ser engolidos.
func _som_tocar(nome: String) -> void:
	if _som == null:
		return
	var espera: float = float(SOM_INTERVALO.get(nome, 0.08))
	if espera > 0.0 and _relogio - float(_som_quando.get(nome, -99.0)) < espera:
		return
	_som_quando[nome] = _relogio
	_som.call("tocar", nome)


## HIT-FLASH: quem apanhou agora, redesenhado em branco chapado.
func _pintar_silhuetas(ci: CanvasItem) -> void:
	if sim == null or _flashes.is_empty():
		return
	for u in sim.units:
		if not u.alive or not _flashes.has(u.id):
			continue
		var f: float = clampf(float(_flashes[u.id]) / FLASH_CORPO, 0.0, 1.0)
		var est := anim_state(u)
		MonsterArt.draw_anim(ci, u.species_id, String(est["anim"]), int(est["frame"]),
			to_screen(_dp(u)) + _shake_v, MonsterArt.size_of(u.species_id), u.facing,
			Color(1.0, 1.0, 1.0, f * 0.85))


## MORTE: o corpo se desfaz em blocos do tamanho do pixel do jogo.
##
## `cor_saida` e UNIFORM, e uniform vale para a camada inteira: duas mortes no
## mesmo quadro dividem a cor de saida da mais recente. E o preco de desenhar
## em lote — a alternativa seria um CanvasItem por corpo — e sao 0,55 s em que
## ninguem separa as duas de todo jeito.
func _pintar_desmanche(ci: CanvasItem) -> void:
	if _mortes.is_empty():
		return
	_desmanche.parametro("cor_saida", Color(_mortes.back()["cor"]))
	for m in _mortes:
		var prog: float = clampf(float(m["life"]) / MORTE_TEMPO, 0.0, 1.0)
		if String(m["especie"]) == "":
			continue
		MonsterArt.draw_anim(ci, String(m["especie"]), "idle", 0,
			to_screen(Vector2(m["pos"])) + _shake_v, float(m["altura"]),
			float(m["facing"]), Color(1.0, 1.0, 1.0, prog))


## BLOOM: halos aditivos deitados no chao, com o mesmo achatamento de tudo o
## que pousa na arena. Sao pocas de luz, nao bolhas coladas na tela.
func _pintar_brilho(ci: CanvasItem) -> void:
	if _halos.is_empty():
		return
	var tex := CamadaPintor.halo_radial()
	for h in _halos:
		var t: float = clampf(float(h["life"]) / maxf(float(h["total"]), 0.01), 0.0, 1.0)
		var r: float = float(h["r"]) * (0.55 + t * 0.75)
		var c: Color = h["cor"]
		c.a = (1.0 - t) * (1.0 - t) * 0.50
		var tam := Vector2(r * 2.0, r * 2.0 * SQUASH)
		ci.draw_texture_rect(tex,
			Rect2(to_screen(Vector2(h["pos"])) + _shake_v - tam * 0.5, tam), false, c)


## Decide QUAIS nomes aparecem neste quadro, e com quanto alfa. Fica no
## `_process` e não no `_draw` porque é uma decisão sobre o conjunto: cada
## rótulo só existe se nenhum vizinho já tomou aquele retângulo.
func _resolver_nomes(delta: float) -> void:
	_nomes.clear()
	if sim == null:
		return
	var font: Font = PrismaTheme.body_font if PrismaTheme.body_font != null 		else ThemeDB.fallback_font
	var sz: int = UI.fs(UI.F_SMALL)

	# ORDEM ESTÁVEL: a sua equipe fica com o espaço na dúvida, e dentro da
	# equipe o id desempata. Ordenar por posição faria os dois rótulos trocarem
	# de vencedor a cada passo da simulação — os dois piscariam.
	#
	# FANTASMA TAMBEM TEM NOME. Ele continua desenhado como um lutador normal
	# (`_draw_unit` nao o distingue) e continua aplicando aura, entao deixa-lo
	# sem rotulo criaria uma diferenca visivel que nao quer dizer nada para
	# quem olha. So o CORPO caido fica sem nome.
	var ordem: Array = []
	for u in sim.units:
		if u.alive:
			ordem.append(u)
	ordem.sort_custom(func(a: SimUnit, b: SimUnit) -> bool:
		if a.side != b.side:
			return a.side < b.side
		return a.id < b.id)

	# OS CORPOS TAMBEM OCUPAM. Um rótulo pousado na cabeça de outra criatura
	# parece o nome DELA — o mesmo engano que o rótulo empurrado causava, só
	# que na horizontal. Então o corpo alheio bloqueia igual a um rótulo: quem
	# cair em cima esmaece.
	var corpos: Array = []
	for u in ordem:
		var h: float = MonsterArt.size_of(u.species_id)
		var pc := to_screen(_dp(u))
		var lw: float = float(MonsterArt.metrics(u.species_id, u.element, h)["w"])
		corpos.append({"id": u.id,
			"r": Rect2(pc.x - lw * 0.5, pc.y - h * 0.5, lw, h)})

	# O ANUNCIO FRESCO TAMBEM OCUPA. A ordem de importancia da tela e
	# anuncio > nome > numero: o numero cede porque o nome e desenhado por cima
	# com tarja, e o nome cede ao anuncio porque um "Detonação ×4" dura um
	# segundo e diz o que acabou de acontecer, enquanto o nome volta em 0,17 s.
	# CONTA ENQUANTO O ANUNCIO ESTIVER VISIVEL, e nao so enquanto estiver
	# forte. O corte era em 0,5 de alfa, mas um rotulo a 0,4 continua opaco o
	# bastante para embaralhar um nome por baixo dele — e era isso que o print
	# do autor mostrava, "Eletrocussão ×7" e "Sheep" no mesmo pixel. O limiar
	# passa a ser o MESMO que o alocador de pistas usa para considerar a pista
	# livre: uma regra so, e o que reserva espaco e o que ocupa espaco deixam
	# de discordar.
	var ocupado: Array = []
	for pp in _pops:
		if bool(pp["ceu"]) or _pop_alfa(float(pp["life"])) <= POP_PISTA_LIVRE:
			continue
		ocupado.append(_pop_caixa_de(pp))

	var vivos: Dictionary = {}
	for u in ordem:
		vivos[u.id] = true
		# COM A MARCA: tres 'Pinto-Raio' na tela nao se distinguiam.
		# Ver SimUnit.marca — ela existe so para este rotulo.
		var txt: String = u.nome_no_campo()
		var w: float = font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, sz).x
		var base := _ancora_nome(u, font, sz)
		# DENTRO DO CAMPO, SEMPRE. O rotulo nasce centrado no dono, e um dono
		# encostado na beirada da elipse punha metade do nome fora do
		# retangulo do FieldView — que agora RECORTA, entao o nome sairia
		# cortado ao meio em vez de invadir a coluna vizinha. Com a coleira, o
		# nome desliza para dentro e continua inteiro; e como ele tambem
		# continua testando colisao depois disso, deslizar nao o poe em cima
		# de ninguem.
		base.x = clampf(base.x, w * 0.5 + 6.0,
			maxf(size.x - w * 0.5 - 6.0, w * 0.5 + 6.0))
		base.y = minf(base.y, size.y - 4.0)
		var caixa := Rect2(
			base.x - w * 0.5 - NOME_FOLGA.x,
			base.y - float(font.get_ascent(sz)) - NOME_FOLGA.y,
			w + NOME_FOLGA.x * 2.0,
			float(sz) + NOME_FOLGA.y * 2.0)
		var livre := true
		for o in ocupado:
			if caixa.intersects(o):
				livre = false
				break
		if livre:
			for c in corpos:
				# o corpo do PROPRIO dono nao conta: o rotulo fica logo abaixo
				# dele e encostaria sempre
				if int(c["id"]) != u.id and caixa.intersects(c["r"]):
					livre = false
					break
		if livre:
			ocupado.append(caixa)
		# quem está saindo continua desenhando enquanto esmaece, mas NÃO entra
		# em `ocupado`: o espaço já é do vencedor, senão o rótulo seguinte
		# esperaria o fade acabar para poder aparecer
		var a: float = move_toward(float(_nome_alfa.get(u.id, 0.0)),
			1.0 if livre else 0.0, delta * NOME_FADE)
		_nome_alfa[u.id] = a
		if a > 0.01:
			_nomes.append({"pos": base - Vector2(w * 0.5, 0.0), "text": txt,
				"a": a, "side": u.side, "w": w})

	# quem morreu sai do dicionário; sem isso ele cresceria pela run inteira e
	# um id reaproveitado herdaria o alfa do antigo dono
	for id in _nome_alfa.keys():
		if not vivos.has(id):
			_nome_alfa.erase(id)


## A LINHA DE BASE do nome, logo abaixo da barra de vida do dono. É o único
## lugar onde ele fica. A conta sai das constantes da barra, e não de números
## soltos: mexer na altura da barra passou a mover o nome junto.
func _ancora_nome(u: SimUnit, font: Font, sz: int) -> Vector2:
	var p := to_screen(_dp(u))
	var m: Dictionary = MonsterArt.metrics(u.species_id, u.element,
		MonsterArt.size_of(u.species_id))
	return Vector2(p.x, p.y + float(m["feet"]) + BARRA_TOPO + BARRA_H + 5.0
		+ float(font.get_ascent(sz)))


func _smooth_positions(delta: float) -> void:
	if sim == null:
		return
	var k: float = 1.0 - exp(-22.0 * delta)
	for u in sim.units:
		if not _draw_pos.has(u.id):
			_draw_pos[u.id] = u.pos
		else:
			_draw_pos[u.id] = Vector2(_draw_pos[u.id]).lerp(u.pos, k)


func _dp(u: SimUnit) -> Vector2:
	var base := Vector2(_draw_pos.get(u.id, u.pos))
	var l: Dictionary = _lunge.get(u.id, {})
	if l.is_empty():
		return base
	# vai rapido e volta devagar: le-se como uma pancada, nao como um passo
	var t: float = clampf(float(l["life"]) / LUNGE_TIME, 0.0, 1.0)
	var amount: float = sin(t * PI) * 18.0
	return base + Vector2(l["dir"]) * amount


## O que dizer quando a arena dispara. Curto: o corredor de avisos ja e
## disputado pelas reacoes, e este e um evento de FUNDO.
## Instancia a cena da arena, se existir. Silencioso de proposito: uma arena sem
## cena simplesmente nao tem fundo, e o combate segue igual.
func _carregar_cenario(id: String) -> void:
	if _cenario != null and is_instance_valid(_cenario):
		_cenario.queue_free()
	_cenario = null
	_cenario_mat = null
	_arena_id = id
	# a cor das particulas e a MESMA do tint, mas cheia: o tint do piso e
	# quase transparente de proposito, e uma brasa nessa opacidade some
	_particulas.trocar(id, arena_cor)
	if _piso != null:
		_piso.aplicar_cor(arena_cor)
	# O AMBIENTE E DE OUTRO AGENTE (autoload `Som`): trocar de arena troca a
	# camada de fundo, e id vazio a desliga.
	if _som != null:
		_som.call("ambiente", id)
	var mv: Dictionary = Db.tuning.get("movement", {})
	_marcas = ArenaChao.gerar(id, sim.semente if sim != null else 0,
		float(mv.get("arena_half_width", 530.0)),
		float(mv.get("arena_half_height", 235.0)),
		arena_cor)
	if id == "":
		return
	var caminho := "res://assets/arenas/%s.tscn" % id
	if not ResourceLoader.exists(caminho):
		return
	var cena: PackedScene = load(caminho)
	if cena == null:
		return
	_cenario = cena.instantiate() as Node2D
	if _cenario == null:
		return
	_cenario.show_behind_parent = true
	add_child(_cenario)
	# A PAISAGEM E O PRIMEIRO DE TODOS. `add_child` o poe no fim da lista, e
	# entre irmaos com `show_behind_parent` vale a ordem da arvore: sem esta
	# linha, trocar de arena poria as montanhas na frente do piso.
	move_child(_cenario, 0)
	# basta o material de UM filho: a cena inteira divide a mesma
	# SubResource, entao mexer nele mexe em todos
	for f in _cenario.get_children():
		if f is CanvasItem and (f as CanvasItem).material is ShaderMaterial:
			_cenario_mat = (f as CanvasItem).material
			break
	_posicionar_cenario(Vector2.ZERO)


func _arena_label(e: Dictionary) -> String:
	if String(e.get("op", "")) == "estimulo":
		return "estímulo ×%d" % int(e.get("stacks", 1))
	return "%s no campo" % Db.el_name(String(e.get("element", "")))


func _draw() -> void:
	var font: Font = PrismaTheme.body_font if PrismaTheme.body_font != null 		else ThemeDB.fallback_font
	var digits: Font = PrismaTheme.digit_font if PrismaTheme.digit_font != null else font
	var shake := _shake_v

	# O PISO INTEIRO SAIU DAQUI. Ele era dois discos concentricos mais duas
	# elipses de contorno branco — 148 vertices por quadro para produzir um
	# degrau mensuravel e um alvo de dardos. Agora e um quad com shader
	# (ArenaPiso / piso.gdshader), desenhado numa camada atras.
	#
	# OS ANEIS BRANCOS NAO VOLTARAM, e nao por economia: medido, o piso tinha
	# 14/255 de contraste contra o vazio e o anel branco tinha 22 — a LINHA
	# aparecia mais que o CHAO. A linha do meio (0,030 de alfa) foi junto pelo
	# mesmo motivo: ela nao diz nada que o jogo use.
	_desenhar_marcas(shake)

	# ondas de area
	# Ondas de reação MENORES e mais discretas. Elas cresciam até 70×1.1 px e
	# ficavam a meio de opacidade: com quatro reações ao mesmo tempo, quatro
	# círculos grandes se cruzavam sobre os lutadores e a arena virava um
	# emaranhado. Aqui elas continuam marcando ONDE reagiu, sem tapar QUEM.
	for r in _rings:
		var t: float = float(r["life"]) / 0.45
		var col: Color = r["color"]
		col.a = (1.0 - t) * 0.30
		_ground_ellipse(to_screen(r["pos"]) + shake,
			float(r["r"]) * (0.3 + t * 0.5), col, false, 2.0 * (1.0 - t) + 0.8)

	if sim == null:
		return

	# mira do Ativo
	if aim_mode != "" and aim_radius > 0.0:
		var mp := get_local_mouse_position()
		var ac := aim_color
		ac.a = 0.20
		_ground_ellipse(mp, aim_radius, ac, true)
		ac.a = 0.8
		_ground_ellipse(mp, aim_radius, ac, false, 2.0)

	for sw in _swings:
		var t: float = clampf(float(sw["life"]) / SHOT_TIME, 0.0, 1.0)
		var a := to_screen(sw["from"]) + shake
		var b := to_screen(sw["to"]) + shake
		var head: Vector2 = a.lerp(b, t)
		var tail: Vector2 = a.lerp(b, maxf(t - 0.34, 0.0))
		var col: Color = sw["color"]
		col.a = 0.85 * (1.0 - t * 0.5)
		draw_line(tail, head, col, 2.6, true)
		draw_circle(head, 3.4, col)

	# O CLIMA VEM ANTES DAS CRIATURAS. Chuva por cima de um Prismon de
	# 44 px o apagaria, e a criatura e o que precisa ser lido.
	_particulas.desenhar(self, shake)

	for u in sim.units:
		_draw_unit(u, font, shake)

	# A FAISCA VEM DEPOIS. Ela e o retorno do golpe, e golpe que acontece atras
	# do corpo nao aconteceu. E a unica passada de particula na frente.
	_particulas.desenhar_faiscas(self, to_screen, shake)

	# A ORDEM DO TEXTO INVERTEU (revisao 15/09). Os numeros vinham por cima dos
	# nomes, e sao muito mais numerosos: e por isso que "Apollo" virava
	# "5giono" e "Sheep" virava "Shoe31" nos prints. `_resolver_nomes` testava
	# o nome contra outros nomes e contra os corpos, e contra mais nada.
	#
	# O NOME E INFORMACAO PERSISTENTE, O NUMERO E TRANSITORIO: quem cede e o
	# numero. Desenhar o nome por ultimo, sobre uma tarja escura, resolve o
	# conflito sem nenhuma conta de colisao a mais — e a tarja ainda devolve o
	# nome sobre o clima e sobre o piso claro.
	for f in _floaters:
		var t2: float = float(f["life"]) / FLOATER_VIDA
		var col2: Color = f["color"]
		col2.a = 1.0 - t2 * t2
		# A SUBIDA ENCURTOU de 34 para 20 px. O numero subia ate 68 px acima do
		# centro e invadia a faixa do anuncio da reacao; encurtar a viagem
		# devolve a faixa sem tirar o movimento, que e o que diz que o numero e
		# transitorio.
		var p: Vector2 = to_screen(f["pos"]) + shake + Vector2(f["off"]) 			+ Vector2(0.0, -34.0 - t2 * 20.0)
		_outlined(digits, p, String(f["text"]), int(f["desenho"]), col2)

	for pp in _pops:
		# O CORREDOR DO CEU ficou so para o que e de CAMPO — mare, estimulo,
		# avisos do chefe. Eles nao tem dono, e uma linha fixa da arena e o
		# lugar certo justamente porque nao aponta para ninguem.
		#
		# TODO O RESTO E ANCORADO NO DONO, logo acima da cabeca de quem reagiu.
		# A caixa sai de `_pop_caixa`, a mesma que o alocador de pistas usou.
		var col3: Color = pp["color"]
		var t3: float = float(pp["life"]) / POP_VIDA
		col3.a = _pop_alfa(float(pp["life"]))
		var caixa := _pop_caixa_de(pp)
		# a deriva para cima e do desenho, nao da reserva: dois pixels de
		# movimento nao mudam quem cabe onde, e entrar na reserva faria a
		# vizinhanca inteira recalcular a cada quadro
		var sobe: float = t3 * (14.0 if bool(pp["ceu"]) else 10.0)
		var desl := shake - Vector2(0.0, sobe)
		if not bool(pp["ceu"]):
			# TARJA SO NO ANUNCIO LOCAL. Ele divide o ar com os numeros de
			# dano, e o contorno preto de 2 px nao bastava: no print os digitos
			# apareciam pelos vaos das letras ("12A2co Voltaico ×4"). O do ceu
			# nao precisa — la em cima nao ha nada para disputar, e uma tarja
			# sobre a paisagem so pesaria.
			var t := NOME_TARJA
			t.a *= col3.a
			draw_rect(Rect2(caixa.position + desl, caixa.size), t)
		_outlined(font, caixa.position + Vector2(4.0, float(pp["size"])) + desl,
			String(pp["text"]), int(pp["size"]), col3)

	_desenhar_nomes(font, shake)

	# O FLASH DEIXOU DE SER UM RETANGULO.
	#
	# Era `draw_rect` na caixa inteira do campo, e a caixa inteira do campo
	# agora termina numa TESOURA: o clarao virava um retangulo colorido com
	# quatro arestas retas, medido em 6 de luma contra o vazio — uma moldura
	# piscando a cada reacao, 33 vezes por combate. O halo radial diz a mesma
	# coisa (o campo acendeu) sem ter aresta nenhuma para o recorte encontrar,
	# e ainda concentra a luz onde a briga esta, que e onde ela deveria estar.
	if _flash > 0.01:
		var luz := CamadaPintor.halo_radial()
		var tam := size * 1.25
		draw_texture_rect(luz,
			Rect2(to_screen(Vector2.ZERO) + shake - tam * 0.5, tam), false,
			Color(_flash_color.r, _flash_color.g, _flash_color.b, _flash * 0.17))


## O CONTORNO DO TEXTO, em DOIS comandos e nao em CINCO.
##
## ERAM CINCO draw_string POR ROTULO — quatro diagonais escuras mais o texto. O
## pior quadro do combate gastava 5 x (10 nomes x 10 glifos + 30 floaters x 3 +
## 5 pops x 16) = 1.350 quads de glifo, contra 150 quads de particula no teto: o
## TEXTO custava nove vezes o clima. `draw_string_outline` desenha o mesmo
## contorno num comando so, e ainda fecha os cantos que as quatro diagonais
## deixavam abertos. So esta troca paga o hit-flash, o desmanche, as faiscas e
## o bloom somados.
const CONTORNO := 2

func _outlined(font: Font, pos: Vector2, text: String, sz: int, col: Color) -> void:
	draw_string_outline(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, sz,
		CONTORNO, Color(0, 0, 0, col.a * 0.85))
	draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, sz, col)


## Pinta os rótulos que `_resolver_nomes` aprovou. Vem DEPOIS de todos os
## corpos E DEPOIS DOS NÚMEROS: um nome atrás de um corpo vizinho seria pior
## que nome nenhum, e um nome atrás de um número é o que produzia "5giono".
##
## A TARJA ESCURA é o que fecha a conta. Sem ela, desenhar por último só
## inverteria o prejuízo — o número é que ficaria ilegível por baixo do texto
## do nome. Com a tarja, os dois convivem: o nome recorta o seu retângulo e o
## número continua inteiro em volta dele.
##
## O `shake` entra só aqui. Ele é um tremor da tela inteira, então some da
## conta de colisão — se entrasse lá, dois rótulos podiam trocar de vencedor
## no meio de um tremor e piscar junto com ele.
const NOME_TARJA := Color(0.04, 0.035, 0.07, 0.72)

func _desenhar_nomes(font: Font, shake: Vector2) -> void:
	var sz: int = UI.fs(UI.F_SMALL)
	var asc: float = float(font.get_ascent(sz))
	for n in _nomes:
		# a equipe já se lê pela cor da barra de vida; o nome só acompanha,
		# claro no seu lado e apagado no do inimigo, para o olho não ter de
		# escolher entre duas informações do mesmo tamanho
		var col: Color = UI.TEXT if int(n["side"]) == 0 else UI.TEXT_DIM
		var a: float = float(n["a"])
		col.a = a
		var p: Vector2 = Vector2(n["pos"]) + shake
		var tarja := NOME_TARJA
		tarja.a *= a
		draw_rect(Rect2(p.x - 3.0, p.y - asc - 1.0,
			float(n["w"]) + 6.0, float(sz) + 3.0), tarja)
		draw_string(font, p, String(n["text"]), HORIZONTAL_ALIGNMENT_LEFT, -1, sz, col)


## Que quadro de que animação esta unidade mostra AGORA.
##
## O relógio é o da SIMULAÇÃO, não o da tela: em 2× e 4× as animações aceleram
## junto com a briga.
func anim_state(u: SimUnit) -> Dictionary:
	var atk: Dictionary = _attacks.get(u.id, {})
	if not atk.is_empty():
		var tt: float = sim.now - float(atk["start"])
		if tt < float(atk["dur"]) and u.alive:
			return {"anim": "attack", "frame": int(tt / maxf(float(atk["dur"]), 0.01)
				* float(MonsterArt.frames_of("attack")))}
		_attacks.erase(u.id)
	var alvo: SimUnit = sim.by_id.get(u.target_id)
	var andando: bool = alvo != null and alvo.alive 		and _dp(u).distance_to(alvo.pos) > u.attack_range + 6.0
	if andando and not u.is_controlled(sim.now):
		return {"anim": "walk", "frame": int(sim.now * MonsterArt.fps_of("walk")
			+ float(u.id)) % MonsterArt.frames_of("walk")}
	return {"anim": "idle", "frame": int(sim.now * MonsterArt.fps_of("idle")
		+ float(u.id) * 3.0) % MonsterArt.frames_of("idle")}


func _draw_unit(u: SimUnit, font: Font, shake: Vector2) -> void:
	var world := _dp(u)
	var p := to_screen(world) + shake
	var c := Db.el_color(u.element)

	# altura de desenho por especie (data), chefe maior (enemies.json)
	var height: float = MonsterArt.size_of(u.species_id)
	var m: Dictionary = MonsterArt.metrics(u.species_id, u.element, height)
	var bw: float = float(m["w"])
	var feet: float = float(m["feet"])
	var ground := p + Vector2(0.0, feet)

	if not u.alive:
		_ground_ellipse(ground, bw * 0.5, Color(0.25, 0.23, 0.3, 0.28), true)
		MonsterArt.draw_anim(self, u.species_id, "idle", 0, p, height, u.facing,
			Color(0.42, 0.40, 0.48, 0.32))
		return

	# estado de animacao: attack (com windup em curso) > walk > idle.
	# O relogio e o da SIMULACAO: em 2x/4x as animacoes aceleram junto.
	var est := anim_state(u)
	var anim := String(est["anim"])
	var frame := int(est["frame"])
	var bob := 0.0

	# sombra no chao, sob os pes
	_ground_ellipse(ground, bw * 0.50, Color(0, 0, 0, 0.30), true)

	# GDD 21.4, camada 1 -- aneis de aura no chao. Espessura = UA restante.
	# E a unica camada 100% confiavel, e no chao ela nao tampa a criatura.
	# Anéis de aura CONTIDOS no corpo. Antes o raio crescia com a carga e podia
	# passar de 40 px de sobra — dois lutadores colados tinham os anéis
	# cruzando um pelo outro, e a arena virava um emaranhado de círculos. Agora
	# o anel fica dentro da metade do espaço de separação: ele diz QUAL aura e
	# QUANTO (pela espessura), sem invadir o vizinho.
	var sep_half: float = float(Db.tuning.get("movement", {}).get("separation_radius", 64.0)) * 0.5
	var rr: float = minf(bw * 0.5, sep_half - 8.0)
	for a in u.aura.auras:
		var ac := Db.aura_color(a.aura_id)
		var cap: float = u.aura.cap_for(a.aura_id)
		var f: float = clampf(a.ua / maxf(cap, 1.0), 0.0, 1.0)
		var w: float = 2.0 + f * 4.0
		ac.a = 0.55 + 0.45 * f
		_ground_ellipse(ground, rr + w * 0.5, ac, false, w)
		rr += w + 2.0

	MonsterArt.draw_anim(self, u.species_id, anim, frame, p + Vector2(0.0, bob),
		height, u.facing, MonsterArt.tint_for(u.species_id, u.element))

	# escudo: casca clara em volta do corpo
	if u.shield > 0.0:
		draw_arc(p + Vector2(0.0, bob), bw * 0.62, 0.0, TAU, 40, Color(0.62, 0.85, 1.0, 0.75),
			2.5, true)

	# controle
	if u.control_until > sim.now:
		draw_circle(p + Vector2(0.0, bob), bw * 0.60, Color(0.66, 0.94, 1.0, 0.18))
		_outlined(font, p + Vector2(-7.0, -height * 0.60), "❄", 17, Color("#bff0ff"))

	# UMA barra por unidade. Antes eram tres empilhadas (escudo, ultimate, HP)
	# com 2 a 5 px cada — trinta pixels de informacao que ninguem consegue ler
	# no meio de uma briga. A carga de ultimate vive no painel da esquerda, que
	# tem espaco para ela; o escudo ja aparece como a casca em volta do corpo.
	_desenhar_barra(u, p, ground)

	# O NOME é desenhado depois, numa passada só (ver `_desenhar_nomes`): ele
	# precisa ficar por cima de TODOS os corpos, e a decisão de quem aparece
	# depende dos rótulos vizinhos — não dá para resolver unidade a unidade.


## A BARRA DE VIDA.
##
## ERA 4 px DE ALTURA E DE LARGURA VARIAVEL: `maxf(bw * 0.92, 40)`, com `bw`
## saindo da arte da especie. Isso queria dizer que a barra do Hipocampo e a do
## Sheep tinham comprimentos de referencia DIFERENTES — e portanto comprimento
## nao significava porcentagem. Duas barras do mesmo tamanho na tela podiam ser
## 100% de uma e 78% da outra, e comparar duas criaturas de olho era impossivel.
##
## AGORA A LARGURA E FIXA. 52 px para todo mundo, 7 px de altura, moldura de
## 1 px — a moldura e o que separa o vazio da barra vazia, que antes eram a
## mesma coisa preta.
const BARRA_W := 52.0
const BARRA_H := 7.0
const BARRA_TOPO := 8.0    # distancia dos pes ao topo da moldura

## O LADO POR FORMA, e nao so por brilho (revisao 15/09: "duas criaturas com o
## mesmo nome e nenhuma marca de lado"). Verde-claro contra vermelho ja separa
## os times para quem enxerga cor; o triangulo separa para quem nao enxerga, e
## num print em escala de cinza. Aliado aponta para CIMA (o seu time sobe),
## inimigo para BAIXO. 5 px de lado, na ponta esquerda da barra.
##
## O desambiguador do NOME (duas criaturas da mesma especie chamadas "Sheep")
## mora em src/run/ e e de outro dono — esta registrado em "pedidos".
const MARCA := 5.0

func _desenhar_barra(u: SimUnit, p: Vector2, ground: Vector2) -> void:
	var bx: float = p.x - BARRA_W * 0.5
	var by: float = ground.y + BARRA_TOPO
	var cor: Color = UI.GOOD if u.side == 0 else UI.BAD
	draw_rect(Rect2(bx - 1.0, by - 1.0, BARRA_W + 2.0, BARRA_H + 2.0),
		Color(0, 0, 0, 0.78))
	draw_rect(Rect2(bx, by, BARRA_W, BARRA_H), Color(0.10, 0.09, 0.15, 0.85))
	var hp_ratio: float = clampf(u.hp / maxf(u.hp_max, 1.0), 0.0, 1.0)
	draw_rect(Rect2(bx, by, BARRA_W * hp_ratio, BARRA_H), cor)

	var mx: float = bx - MARCA - 3.0
	var my: float = by + BARRA_H * 0.5
	var pts := PackedVector2Array()
	if u.side == 0:
		pts.append(Vector2(mx + MARCA * 0.5, my - MARCA * 0.6))
		pts.append(Vector2(mx + MARCA, my + MARCA * 0.5))
		pts.append(Vector2(mx, my + MARCA * 0.5))
	else:
		pts.append(Vector2(mx + MARCA * 0.5, my + MARCA * 0.6))
		pts.append(Vector2(mx, my - MARCA * 0.5))
		pts.append(Vector2(mx + MARCA, my - MARCA * 0.5))
	draw_colored_polygon(pts, cor)


## As marcas do piso. Tudo achatado pelo mesmo SQUASH da sombra e do anel de
## aura: e o que faz a marca parecer deitada no chao e nao colada na tela.
##
## `mancha` e `risco` SAIRAM do desenho junto com os perfis que os geravam
## (ArenaChao, revisao 11/09): marca sorteada no chao vira ruido, e o que
## sobrou foi o que tem estrutura.
##
## OS ANEIS COM `pulsa` VARREM PARA FORA no ritmo da arena. Campo Magnetico e
## Camara sao as duas arenas cujo efeito e um estimulo periodico, e ate agora
## nada na tela dizia que ele tinha disparado. Como `_pulse` cai de 1 a 0 em
## ~0,7 s, `1 - _pulse` cresce de 0 a 1 — a onda sai do centro sozinha, sem
## nenhum estado novo.
func _desenhar_marcas(shake: Vector2) -> void:
	for m in _marcas:
		var op := String(m["op"])
		var cor: Color = m["cor"]
		if op == "anel":
			var esc := 1.0
			if bool(m.get("pulsa", false)) and _pulse > 0.001:
				esc = 1.0 + (1.0 - _pulse) * 0.34
				# O TETO E 0,24 e nao 0,5 (medido no primeiro print): com meio
				# alfa os tres aneis do Campo Magnetico voltavam a ser um alvo
				# de dardos — exatamente o defeito que tirou os aneis brancos
				# do piso. A marca tem de dizer que a arena disparou, nao
				# disputar a leitura com as criaturas.
				cor.a = minf(cor.a * (1.0 + _pulse * 1.4), 0.20)
			_ground_ellipse(to_screen(m["pos"]) + shake, float(m["r"]) * esc, cor,
				false, float(m["w"]) + _pulse * 1.0)
		elif op == "placa":
			var c := to_screen(m["pos"]) + shake
			var t: Vector2 = m["tam"]
			draw_rect(Rect2(c - Vector2(t.x, t.y * SQUASH) * 0.5,
				Vector2(t.x, t.y * SQUASH)), cor)


## Onde a cena do cenario fica. O horizonte dela (y=170) e ancorado na borda de
## cima da elipse do piso: assim o avental do desenho — pedras, lapides — cobre
## a parte de tras da arena e as pecas aparecem espiando por tras dela.
##
## Roda todo quadro porque o campo muda de tamanho com a janela, e porque o
## tremor de tela entra aqui reduzido: paralaxe barata.
func _posicionar_cenario(shake: Vector2) -> void:
	if _cenario == null or not is_instance_valid(_cenario):
		return
	var mv: Dictionary = Db.tuning.get("movement", {})
	var hh: float = float(mv.get("arena_half_height", 235.0))
	var centro := to_screen(Vector2.ZERO)
	_cenario.position = Vector2(
		centro.x - CENARIO_LARGURA * 0.5,
		centro.y - hh - CENARIO_FOLGA - CENARIO_RODAPE) \
		+ shake * CENARIO_TREMOR
	if _cenario_mat != null:
		# O DESBOTE LATERAL PASSA A SER MEDIDO NA LARGURA DO CAMPO, nao na do
		# desenho. O shader apaga `lateral` (16%) de cada ponta do retangulo
		# que `origem`/`tamanho` descrevem; com os 1280 px da arte, os 16%
		# fechavam em x = 365, que e EXATAMENTE a borda do campo — ou seja, a
		# paisagem chegava na borda com alfa cheio e os 204 px de fora ficavam
		# visiveis por cima da coluna da esquerda.
		#
		# Descrevendo o retangulo do CAMPO, a mesma conta apaga a paisagem
		# ANTES da borda e nao ha tinta nenhuma para transbordar. O recorte de
		# `clip_contents` continua como garantia estrutural, mas nao e ele que
		# aparece: quem termina o desenho e o fade, como sempre foi.
		# ANCORADO NO RETANGULO DO CAMPO, e nao no centro da arena: o desbote e
		# propriedade da JANELA, e a janela nao anda. Ancorado no centro da
		# arena ele deslizava junto com a camera, e no fim do curso a paisagem
		# chegava opaca na borda direita — uma linha reta subindo a tela
		# inteira, que e o mesmo defeito de novo, so que 94 px mais tarde.
		#
		# Na vertical nada muda: `origem.y` continua sendo o topo do DESENHO e
		# a altura continua sendo a da arte, porque ali o desbote e mesmo uma
		# propriedade da imagem ("na linha 170 fica o horizonte").
		_cenario_mat.set_shader_parameter("origem",
			Vector2(global_position.x, _cenario.global_position.y))
		_cenario_mat.set_shader_parameter("tamanho",
			Vector2(size.x, CENARIO_ALTURA))
		# A CURVA SAI DA ELIPSE, mas MAIS RASA que ela.
		#
		# Com `curvatura` igual a meia-altura o cenario desceria exatamente
		# junto com a borda de tras, mantendo uma folga constante de 8 px — e
		# 8 px nao bastam: as montanhas tem 150 px de altura e encostavam no
		# piso ao longo de quase toda a largura, que era o "se misturando" do
		# print. Descendo MENOS que a borda, a folga cresce para as laterais:
		# no centro sao 8 px, nas pontas passam de 130. O arco continua legivel
		# e a paisagem nunca toca a arena.
		var hw: float = float(mv.get("arena_half_width", 530.0))
		_cenario_mat.set_shader_parameter("arena_centro",
			global_position + centro + shake * CENARIO_TREMOR)
		_cenario_mat.set_shader_parameter("arena_raio", hw)
		_cenario_mat.set_shader_parameter("curvatura", hh * 0.45)
		# O AR QUENTE E DE UMA ARENA SO. A cena da arena e de outro dono, entao
		# quem liga o uniform e aqui — e o padrao do shader e 0, entao as
		# outras seis arenas nem chegam no `if` do calor.
		_cenario_mat.set_shader_parameter("calor",
			1.0 if _arena_id == "solo_vulcanico" else 0.0)


## Elipse achatada no chao: usada para sombra e para os aneis de aura.
## draw_arc so faz circulo, e um circulo no chao le como bolha, nao como marca.
func _ground_ellipse(at: Vector2, radius: float, col: Color, filled: bool,
		width: float = 2.0) -> void:
	# SEGMENTOS PELO RAIO. Fixo em 28, a mira do Ativo (raio de ate 265 px)
	# saia como um poligono de lados visiveis; a sombra de uma criatura de 20 px
	# gastava 28 segmentos para nada.
	var segs: int = clampi(int(radius * 0.5), 16, 72)
	var pts := PackedVector2Array()
	for i in range(segs + 1):
		var a: float = TAU * float(i) / float(segs)
		pts.append(at + Vector2(cos(a) * radius, sin(a) * radius * SQUASH))
	if filled:
		draw_colored_polygon(pts, col)
	else:
		draw_polyline(pts, col, width, true)
