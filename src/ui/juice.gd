class_name Juice
extends RefCounted
## O "game feel" da interface (pedido do autor, 04/09).
##
## Tudo aqui é curto de propósito. Animação de UI existe para dizer de ONDE a
## coisa veio e QUE ela respondeu ao toque — não para ser assistida. Acima de
## ~0.25 s o jogador começa a esperar a interface em vez de usá-la.
##
## As peças vivem aqui e são chamadas pelos pontos COMPARTILHADOS (`UI.button`,
## `CardButton`, `Main._swap`), então a interface inteira ganha o mesmo
## comportamento sem cada tela precisar saber disso.

## Desligável. As ferramentas headless (screenshots, testes) desligam para
## capturar o estado final: um print tirado no meio da transição não serve
## para comparar nada.
static var enabled := true

const ENTRADA := 0.13        # tela nova: some o véu, sobe um pouco
const SUBIDA := 22.0         # px de deslocamento na entrada
const ESCALONE := 0.024      # atraso entre itens de uma lista
const HOVER := 0.07
const TOQUE := 0.05

## NADA DE ESCALA EM CONTAINER (04/09, defeito relatado pelo autor: "a
## interface está vazando, os hovers estão quebrando").
##
## Escalar um Control faz ele DESENHAR maior sem que o container saiba: o pai
## continua reservando o tamanho antigo, e o nó transborda por cima do vizinho
## e da moldura. Numa lista dentro de painel dentro de tela — que é o desenho
## de quase toda tela deste jogo — o resultado é exatamente o vazamento dos
## prints.
##
## O sinal de hover passou a ser a MOLDURA acendendo (ver CardButton._paint e
## os styleboxes de hover em UI.button). Cor não ocupa espaço, então não há o
## que transbordar. Escala fica só para nós SOLTOS, fora de fluxo — o rótulo
## do Éter na barra do topo é o único caso hoje.


## Um tween por nó e por propriedade. SEM ISSO o hover fica travado: cada
## entrada e saída do mouse criava um tween novo, e dois tweens disputando a
## mesma `scale` produzem exatamente o tranco que o autor descreveu — o nó
## salta entre os dois destinos em vez de correr para um.
static func _tween(node: Control, chave: String) -> Tween:
	var meta := "_jt_" + chave
	if node.has_meta(meta):
		var velho: Tween = node.get_meta(meta)
		if velho != null and velho.is_valid():
			velho.kill()
	var t := node.create_tween()
	node.set_meta(meta, t)
	return t


## Uma TELA entrando. Aparece subindo — o movimento diz "isto é novo", e a
## direção (de baixo para cima) é a mesma da leitura.
static func enter_screen(node: Control) -> void:
	if not enabled or node == null or not node.is_inside_tree():
		return
	node.modulate.a = 0.0
	var alvo := node.position
	node.position = alvo + Vector2(0.0, SUBIDA)
	var t := node.create_tween()
	t.set_parallel(true)
	t.tween_property(node, "modulate:a", 1.0, ENTRADA)
	t.tween_property(node, "position", alvo, ENTRADA) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


## Um item de LISTA entrando, com atraso pelo índice.
static func enter_item(node: Control, indice: int) -> void:
	if not enabled or node == null:
		return
	node.modulate.a = 0.0
	var t := node.create_tween()
	t.tween_interval(float(indice) * ESCALONE)
	t.tween_property(node, "modulate:a", 1.0, ENTRADA * 0.8)


## Pulso de confirmação: a coisa cresce e volta. SÓ para nós que não estão
## dentro de um container apertado — escalar em fluxo transborda (ver a nota
## no topo). Hoje: o rótulo do Éter.
static func pulse(node: Control, forca: float = 1.06) -> void:
	if not enabled or node == null or not node.is_inside_tree():
		return
	_pivot(node)
	var t := _tween(node, "scale")
	t.tween_property(node, "scale", Vector2.ONE * forca, TOQUE) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	t.tween_property(node, "scale", Vector2.ONE, TOQUE * 1.8) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## Brilho de hover, SEM tocar no tamanho nem na posição: o nó clareia.
##
## ONDE MORA O "SOBE 2 PX / AFUNDA 3 PX" (15/09). Não é aqui, e é de propósito.
## Um Control dentro de Container tem a `position` reescrita pelo pai a cada
## ordenação: um deslocamento animado sobrevive até a primeira reordenação e
## depois fica alguns px fora do lugar para sempre. O subir e o afundar passaram
## a ser DESENHO — a célula 9-patch do hover tem a lajota 2 px mais alta e a
## sombra dura em 5 px; a do apertado não tem sombra e mostra a parede do
## buraco. A caixa do nó não muda um pixel, então o layout nem fica sabendo.
##
## AQUI SÓ SOBROU O BRILHO, e ele encolheu. Com o painel oco de antes, 1.14 era
## o único sinal de hover que existia; agora a lajota é sólida e sobe, então
## 1.14 sobre um miolo #262138 estourava a leitura e o cartão "piscava". 1.07 é
## o reforço, não o sinal. No apertado, 0.94: a célula afundada já é mais
## escura por construção.
static func hover(node: Control, ligado: bool, apertado: bool = false) -> void:
	if not enabled or node == null or not node.is_inside_tree():
		return
	var v := 0.94 if apertado else (1.07 if ligado else 1.0)
	var t := _tween(node, "hover")
	t.tween_property(node, "modulate", Color(v, v, v, node.modulate.a),
		TOQUE if apertado else HOVER) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


## Liga o feedback de toque num Control clicável. `fonte` é quem escuta o
## mouse — num CardButton é o botão invisível de cima, e não o painel: ligar
## os dois fazia um disparar a saída enquanto o outro disparava a entrada.
static func make_reactive(node: Control, fonte: Control = null) -> void:
	if node == null:
		return
	var f: Control = fonte if fonte != null else node
	f.mouse_entered.connect(func(): hover(node, true))
	f.mouse_exited.connect(func(): hover(node, false))
	if f is BaseButton:
		var b := f as BaseButton
		b.button_down.connect(func(): hover(node, true, true))
		b.button_up.connect(func(): hover(node, b.is_hovered()))


## O pivô precisa ficar no CENTRO, senão escalar empurra o nó para a direita e
## para baixo em vez de crescer no lugar.
static func _pivot(node: Control) -> void:
	node.pivot_offset = node.size * 0.5
	if not node.has_meta("_jy"):
		node.set_meta("_jy", node.position.y)
