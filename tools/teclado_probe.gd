extends Node
## PROVA QUE DA PARA JOGAR SEM MOUSE (16/09).
##
## A navegacao por teclado ficou tres agentes parada porque e um conserto de
## duas pontas — `focus_mode` no CardButton e alguem para RECEBER o foco — e
## meia troca produz uma ordem de tabulacao meio pronta, que e pior que nenhuma.
## Esta sonda existe para a afirmacao "da para jogar sem mouse" parar de ser uma
## opiniao.
##
## O QUE ELA NAO FAZ, de proposito: nao chama `grab_focus` nem `_toggle` a mao.
## Ela empurra EVENTOS DE TECLA pelo `Input`, que e o caminho do jogador, e
## depois pergunta ao viewport quem esta com o foco. Foi exatamente por chamar o
## metodo em vez de emitir o sinal que um teste antigo deste projeto passou
## verde enquanto duas magias nao funcionavam no jogo.
##
## E A SONDA E VERIFICADA: `_autoteste` reintroduz o defeito (FOCUS_NONE num
## CardButton de mentira) e confere que a checagem o PEGA. Sem isso, uma sonda
## quebrada diz OK para sempre — ja aconteceu aqui, com o probe de tooltip.

var falhas := 0
var total := 0


func ok(cond: bool, msg: String) -> void:
	total += 1
	if cond:
		print("  ok   ", msg)
	else:
		falhas += 1
		print("  FAIL ", msg)


func _ready() -> void:
	print("=== PRISMON :: sonda de teclado ===")
	await get_tree().process_frame
	_autoteste()
	await _fluxo()
	print("")
	if falhas == 0:
		print("=== TUDO OK (%d asercoes) ===" % total)
	else:
		print("=== %d FALHA(S) de %d ===" % [falhas, total])
	get_tree().quit(1 if falhas > 0 else 0)


## A sonda tem de saber reprovar. Monta um CardButton, quebra o foco dele na
## mao, e confere que a pergunta "isto aceita foco?" responde nao.
func _autoteste() -> void:
	print("[autoteste da sonda]")
	var bom := CardButton.make()
	add_child(bom)
	ok(_aceita_foco(bom), "um CardButton normal ACEITA foco")
	var ruim := CardButton.make()
	add_child(ruim)
	for f in ruim.get_children():
		if f is Button:
			(f as Button).focus_mode = Control.FOCUS_NONE
	ok(not _aceita_foco(ruim), "com FOCUS_NONE a sonda REPROVA (o defeito volta a doer)")
	bom.queue_free()
	ruim.queue_free()


func _aceita_foco(n: Node) -> bool:
	for f in n.get_children():
		if f is Control and (f as Control).focus_mode != Control.FOCUS_NONE:
			return true
	return false


## Empurra uma tecla pelo caminho do jogador e deixa a arvore processar.
func _tecla(acao: String) -> void:
	var ev := InputEventAction.new()
	ev.action = acao
	ev.pressed = true
	Input.parse_input_event(ev)
	await get_tree().process_frame
	var up := InputEventAction.new()
	up.action = acao
	up.pressed = false
	Input.parse_input_event(up)
	await get_tree().process_frame


func _foco() -> Control:
	return get_viewport().gui_get_focus_owner()


func _fluxo() -> void:
	print("[o foco chega sozinho em cada tela]")
	var main: Control = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	await get_tree().process_frame

	ok(main.screen is ScreenTitle, "abre no titulo")
	ok(_foco() != null, "o titulo entrega o foco a alguem sem ninguem pedir")
	# O campo de Semente NAO pode ser o primeiro: a primeira seta do jogador
	# andaria o cursor de texto em vez de trocar de opcao.
	ok(not (_foco() is LineEdit), "e o foco inicial NAO e o campo de texto")

	main.screen.start_requested.emit(555)
	await get_tree().process_frame
	await get_tree().process_frame
	ok(main.screen is ScreenStarter, "run comecada -> escolha de iniciais")
	var f0 := _foco()
	ok(f0 != null, "a tela de iniciais tambem entrega o foco")

	# A PROVA: andar com a seta muda de quem e o foco, sem mouse nenhum.
	await _tecla("ui_down")
	var f1 := _foco()
	if f1 == f0:
		await _tecla("ui_right")
		f1 = _foco()
	ok(f1 != null and f1 != f0, "a seta MOVE o foco para outro controle")

	# E o `ui_accept` aperta o que estiver focado — e o que faz o teclado
	# valer alguma coisa depois de andar.
	var antes: int = main.screen._picked.size()
	await _tecla("ui_accept")
	ok(main.screen._picked.size() != antes,
		"ENTER no cartao focado SELECIONA (%d -> %d)" % [antes, main.screen._picked.size()])

	print("[o combate NAO recebe foco, de proposito]")
	main.screen._picked = ["sheep", "pinto_raio"]
	main.screen.confirmed.emit(["sheep", "pinto_raio"])
	await get_tree().process_frame
	await get_tree().process_frame
	ok(main.screen is ScreenMap, "iniciais -> escolha de combate")
	ok(_foco() != null, "a escolha de combate entrega o foco")
	main.screen.chosen.emit(main.pair[0])
	await get_tree().process_frame
	await get_tree().process_frame
	if main.screen is ScreenPrep:
		ok(_foco() != null, "a preparacao entrega o foco")
		main.screen.fight.emit()
		await get_tree().process_frame
		await get_tree().process_frame
	# No combate as teclas sao do JOGO (1/2/3, ESPACO, TAB). Um botao focado
	# come ESPACO e TAB antes de o jogo ver — foi o defeito relatado.
	if main.screen is ScreenCombat:
		ok(_foco() == null, "no COMBATE ninguem fica com o foco (ESPACO e TAB ficam livres)")
	else:
		print("  ---  nao cheguei ao combate neste caminho; o resto vale")
	main.queue_free()
