extends Node
## A DICA SEGUE O CURSOR QUANDO ELE TROCA DE ALVO?
##
## Defeito relatado pelo autor (04/09): "esse tooltip ta bugado, as vezes passo
## o hover do mouse e ativa o hover do quadrado do encounter ao inves dos
## menores quando quero ler os quadrados menores".
##
## O caso e um alvo DENTRO do outro — a etiqueta de arena vive dentro do cartao
## do encontro, e os dois tem dica. Ir de um para o outro NUNCA passa pelo
## vazio, e era so no vazio que a camada escondia o painel.
##
## DUAS COISAS TORNAM ESTE PROBE CONFIAVEL:
##  * o `_process` da camada e chamado A MAO, com delta fixo, entao o resultado
##    nao depende da taxa de quadros de quem roda;
##  * depois de cada `warp_mouse` ele ESPERA o viewport reconhecer o novo alvo
##    em vez de contar dois quadros. Contando quadros o probe falhava sozinho,
##    e de forma diferente a cada rodada — um teste que mente nao serve.

const DT := 0.2
const QUADROS_ATE_DESISTIR := 90


class Caixa extends Control:
	func _init(dica: String, r: Rect2) -> void:
		tooltip_text = dica
		position = r.position
		size = r.size
		mouse_filter = Control.MOUSE_FILTER_STOP


var _camada: TooltipLayer
var _falhas := 0
var _probe_furado := 0


func _ready() -> void:
	Juice.enabled = false
	get_window().size = Vector2i(800, 500)
	# SEM FOCO O `warp_mouse` NAO ENTREGA EVENTO NENHUM, e o probe perdia todas
	# as conferencias em silencio. Trazer a janela para a frente e parte do
	# aparato de medida, nao enfeite.
	DisplayServer.window_move_to_foreground()
	get_window().grab_focus()
	var bg := ColorRect.new()
	bg.theme = PrismaTheme.get_theme()
	bg.color = UI.BG
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	# o cartao do encontro, e DENTRO dele a etiqueta de arena
	var cartao := Caixa.new("CARTAO\nPerigo 4 de 5", Rect2(80, 80, 420, 260))
	bg.add_child(cartao)
	var etiqueta := Caixa.new("ETIQUETA\nA cada 10 s, todos atacam mais rapido",
		Rect2(40, 150, 180, 40))
	cartao.add_child(etiqueta)

	_camada = TooltipLayer.new()
	bg.add_child(_camada)
	await get_tree().process_frame
	_camada.set_process(false)     # o probe e quem toca o relogio

	await _checar("cursor no CARTAO", Vector2(430, 110), cartao, "CARTAO")
	await _checar("desliza para a ETIQUETA", Vector2(210, 250), etiqueta, "ETIQUETA")
	await _checar("volta para o CARTAO", Vector2(430, 110), cartao, "CARTAO")
	await _checar("sai para o vazio", Vector2(700, 450), null, "")

	# ---- o CLIQUE (autor, 04/09: "os tooltips as vezes nao somem depois de eu
	# clicar") -----------------------------------------------------------------
	await _checar("de volta a ETIQUETA", Vector2(210, 250), etiqueta, "ETIQUETA")
	_clicar()
	_rodar()
	_ver("o clique fecha a dica", [""])
	_rodar()
	_rodar()
	_ver("e ela nao volta parada", [""])
	await _checar("volta depois de mover", Vector2(430, 110), cartao, "CARTAO")

	# ---- a TELA SE REFAZ sob o cursor -----------------------------------------
	# E o caso do print: clicar num prato refaz o painel, o que estava sob o
	# cursor sai dali — mas o mouse NAO se mexeu, entao o motor continua
	# apontando para o controle antigo e a dica fica pendurada na tela.
	#
	# O ESPERADO E NENHUMA DICA, e nao a do cartao que ficou por baixo. Saber o
	# que passou a estar sob o cursor exigiria refazer o teste de acerto do
	# motor a mao — com filtros de mouse, recorte e ordem de desenho. Nao vale:
	# a dica errada sumir ja resolve o defeito, e a certa volta no primeiro
	# movimento do mouse, que e a linha seguinte.
	await _checar("cursor na ETIQUETA", Vector2(210, 250), etiqueta, "ETIQUETA")
	etiqueta.position = Vector2(40, 10)      # ela sai de baixo do cursor
	await get_tree().process_frame
	_rodar()
	_rodar()
	# NENHUMA dica ou a do cartao que ficou por baixo — as duas servem. O que
	# NAO pode e continuar a da etiqueta, que ja nao esta ali. Qual das duas
	# sai depende de o motor ter recalculado o hover ao mover o no, e isso
	# varia entre rodadas: exigir uma delas seria um teste instavel.
	_ver("alvo saiu de baixo do cursor", ["", "CARTAO"])
	await _checar("e o certo volta ao mover", Vector2(300, 300), cartao, "CARTAO")

	# ---- A TELA INTEIRA E TROCADA -------------------------------------------
	# O caso do segundo print do autor: ele clica no encontro, o roteador troca
	# a tela de escolha pela de preparacao, e a dica da tela ANTIGA continua na
	# tela nova. `queue_free` nao apaga na hora — a tela velha ainda esta na
	# arvore no quadro do clique, com o cursor parado em cima dela.
	await _checar("cursor no CARTAO de novo", Vector2(430, 110), cartao, "CARTAO")
	cartao.queue_free()
	var nova := Caixa.new("", Rect2(80, 80, 420, 260))   # a tela seguinte, sem dica
	bg.add_child(nova)
	for i in 8:
		await get_tree().process_frame
		_camada._process(DT)
	_ver("a tela trocou sob o cursor", [""])

	if _probe_furado > 0:
		# um teste que perde conferencias e nao diz nao serve para nada
		print("=> INCONCLUSIVO: %d conferencias perdidas (o cursor nao chegou)"
			% _probe_furado)
	else:
		print("=> %s" % ("OK" if _falhas == 0 else "FALHOU (%d)" % _falhas))
	get_tree().quit(0 if _falhas == 0 and _probe_furado == 0 else 1)


## Um clique de verdade, pelo caminho de entrada do motor.
func _clicar() -> void:
	for apertado in [true, false]:
		var ev := InputEventMouseButton.new()
		ev.button_index = MOUSE_BUTTON_LEFT
		ev.pressed = apertado
		ev.position = get_viewport().get_mouse_position()
		ev.global_position = ev.position
		get_viewport().push_input(ev)


func _rodar() -> void:
	for i in 6:
		_camada._process(DT)


## O que esta na tela agora, sem mexer no cursor. `aceitos` e uma LISTA: em
## alguns casos mais de uma resposta esta certa, e exigir uma delas seria
## testar um detalhe do motor em vez do que o jogador precisa.
func _ver(o_que: String, aceitos: Array) -> void:
	var visto := _visivel()
	var esperado := " ou ".join(aceitos.map(func(x): return "'" + String(x) + "'"))
	var ok: bool = visto in aceitos
	if not ok:
		_falhas += 1
	print("  %-28s esperava %-20s viu %-11s %s"
		% [o_que, esperado, "'" + visto + "'", "ok" if ok else "FALHA"])


func _visivel() -> String:
	if not _camada._painel.visible:
		return ""
	if "ETIQUETA" in _camada._rt.text:
		return "ETIQUETA"
	return "CARTAO" if "CARTAO" in _camada._rt.text else "?"


func _checar(o_que: String, onde: Vector2, alvo: Control, esperado: String) -> void:
	if not await _esperar_hover(onde, alvo):
		_probe_furado += 1
		print("  %-28s PERDIDA (o cursor nao chegou)" % o_que)
		return
	_rodar()
	var visto := _visivel()
	var ok: bool = visto == esperado
	if not ok:
		_falhas += 1
	print("  %-28s esperava %-11s viu %-11s %s"
		% [o_que, "'" + esperado + "'", "'" + visto + "'", "ok" if ok else "FALHA"])


## Espera o viewport reconhecer `alvo` sob o cursor. Devolve false se desistir —
## ai a conferencia nao vale, e o probe diz isso em vez de acusar o produto.
##
## COMPARA O ALVO JA RESOLVIDO, e nao o controle cru sob o cursor. Duas razoes,
## e as duas fizeram o probe mentir antes:
##  * a etiqueta e FILHA do cartao, entao "e o cartao ou um descendente dele"
##    dava verdadeiro com o cursor ainda parado na etiqueta — a espera passava
##    direto e o produto levava a culpa;
##  * o fundo da tela e um ColorRect, que recebe mouse: no "vazio" o controle
##    cru e o fundo, nunca null, e a espera estourava sozinha.
func _esperar_hover(onde: Vector2, alvo: Control) -> bool:
	for i in QUADROS_ATE_DESISTIR:
		# REPETE O WARP. Um `warp_mouse` isolado as vezes nao gera evento de
		# movimento — se o cursor ja estava naquele pixel, ou se a janela
		# acabou de receber foco. Repetir a cada 15 quadros custa nada e tira
		# a instabilidade do probe.
		if i % 15 == 0:
			get_viewport().warp_mouse(onde)
		await get_tree().process_frame
		if _camada._hovered_com_dica() == alvo:
			return true
	return false
