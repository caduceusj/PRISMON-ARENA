extends Node
## A DICA COBRE A LINHA QUE A ORIGINOU?
##
## Defeito relatado pelo autor (16/09), sobre o print da Feira de Passagem:
## "uma dica escura aparece POR CIMA da lista ... uma sobreposicao muito
## indesejada". O cursor pousa no meio de uma linha de lista de 520 x 90 px, a
## dica abre 16 px a direita e 20 px abaixo dele — ou seja, DENTRO da linha — e
## tapa justamente o texto que o jogador estava tentando ler.
##
## Este probe e o irmao de tools/tip_alvo_probe: aquele cobra QUAL dica aparece,
## este cobra ONDE ela aparece. Duas conferencias, e as duas tem de valer:
##
##   1. com o cursor sobre um alvo LARGO, o painel da dica nao encosta no
##      retangulo do alvo, e continua inteiro dentro da tela;
##   2. com o cursor sobre um alvo PEQUENO — icone, medalhao, etiqueta — o
##      painel fica exatamente onde sempre ficou (cursor + MARGEM). O conserto
##      da sobreposicao nao pode mexer no caso comum, que e a maioria das dicas
##      do jogo.
##
## AS MESMAS DUAS PRECAUCOES DO tip_alvo_probe, e pelos mesmos motivos: o
## `_process` da camada e chamado A MAO com delta fixo, e depois de cada
## `warp_mouse` o probe ESPERA o viewport reconhecer o alvo em vez de contar
## quadros. Um teste que mente sobre um conserto de tooltip ja aconteceu neste
## projeto uma vez.

const DT := 0.2
const QUADROS_ATE_DESISTIR := 90


class Caixa extends Control:
	func _init(dica: String, r: Rect2) -> void:
		tooltip_text = dica
		position = r.position
		size = r.size
		mouse_filter = Control.MOUSE_FILTER_STOP
		var l := UI.label(dica.split("\n")[0], UI.F_BODY, UI.TEXT)
		l.position = Vector2(18, 12)
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(l)

	## A caixa se DESENHA — nao por enfeite: sem isto o print da conferencia
	## (docs/probe_tip_ancora.png) sai com a dica flutuando no vazio, e um print
	## que nao mostra o alvo nao prova coisa nenhuma a olho nu.
	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), UI.PANEL, true)
		draw_rect(Rect2(Vector2.ZERO, size), UI.ACCENT.darkened(0.3), false, 2.0)


var _camada: TooltipLayer
var _falhas := 0
var _probe_furado := 0


func _ready() -> void:
	Juice.enabled = false
	Som.mudo = true                 # o autor reclamou do som das ferramentas
	get_window().size = Vector2i(900, 600)
	# sem foco o `warp_mouse` nao entrega evento nenhum (ver tip_alvo_probe)
	DisplayServer.window_move_to_foreground()
	get_window().grab_focus()

	var bg := ColorRect.new()
	bg.theme = PrismaTheme.get_theme()
	bg.color = UI.BG
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	# A LINHA DE LISTA DA FEIRA, na medida real: PickPanel.LIST_W e ROW_H.
	var texto := "Cauda de Brasa\nSó o Apollo pode usar\n+20 ATK e Derretimentos dele causam +35%."
	var linha := Caixa.new(texto, Rect2(40, 240, 520, 90))
	bg.add_child(linha)
	# o alvo pequeno: uma moeda de 24 px, como as do HUD
	var moeda := Caixa.new("Éter", Rect2(700, 60, 24, 24))
	bg.add_child(moeda)

	_camada = TooltipLayer.new()
	bg.add_child(_camada)
	await get_tree().process_frame
	_camada.set_process(false)      # o probe e quem toca o relogio

	# --- 1. o alvo LARGO: a dica sai de cima dele, onde quer que o cursor esteja
	await _fora("cursor no meio da linha", linha, Vector2(300, 285))
	await _fora("cursor no alto da linha", linha, Vector2(120, 248))
	await _fora("cursor no pe da linha", linha, Vector2(500, 322))
	await _fora("cursor na ponta direita", linha, Vector2(552, 285))

	# O PRINT DA CONFERENCIA. Um numero que diz "nao se cruzam" e prova, mas nao
	# e imagem: aqui fica a imagem, com a dica encostada embaixo da linha larga
	# em vez de em cima dela.
	await _retratar(Vector2(300, 285), linha)

	# --- 2. o alvo PEQUENO: nada muda
	await _junto_ao_cursor("alvo pequeno segue junto ao cursor", moeda,
		Vector2(710, 70))

	# --- 3. a regra do espelho, na peca de verdade
	await _linha_selecionada_sem_dica(bg)

	if _probe_furado > 0:
		print("=> INCONCLUSIVO: %d conferencias perdidas (o cursor nao chegou)"
			% _probe_furado)
	else:
		print("=> %s" % ("OK" if _falhas == 0 else "FALHOU (%d)" % _falhas))
	get_tree().quit(0 if _falhas == 0 and _probe_furado == 0 else 1)


## O retangulo do painel da dica, nas coordenadas da camada.
func _painel_rect() -> Rect2:
	return Rect2(_camada._painel.position, _camada._painel.size)


## O retangulo do alvo, nas MESMAS coordenadas.
func _alvo_rect(alvo: Control) -> Rect2:
	var r: Rect2 = alvo.get_global_rect()
	r.position -= _camada.global_position
	return r


func _fora(o_que: String, alvo: Control, onde: Vector2) -> void:
	if not await _abrir(o_que, alvo, onde):
		return
	var p := _painel_rect()
	var a := _alvo_rect(alvo)
	var limpo: bool = not p.intersects(a)
	var na_tela: bool = p.position.x >= 0.0 and p.position.y >= 0.0 \
		and p.end.x <= _camada.size.x + 0.5 and p.end.y <= _camada.size.y + 0.5
	_dizer("%s (nao cobre)" % o_que, limpo,
		"painel %s / alvo %s" % [str(p), str(a)])
	_dizer("%s (dentro da tela)" % o_que, na_tela, str(p))


func _junto_ao_cursor(o_que: String, alvo: Control, onde: Vector2) -> void:
	if not await _abrir(o_que, alvo, onde):
		return
	var esperado: Vector2 = onde + TooltipLayer.MARGEM
	var p := _painel_rect()
	var igual: bool = p.position.distance_to(esperado) < 1.5
	_dizer(o_que, igual, "esperava %s, viu %s" % [str(esperado), str(p.position)])


## Poe o cursor em `onde`, espera o alvo ser reconhecido e roda o relogio da
## camada ate a dica estar de fato assentada na tela. Devolve false se algo
## falhou — ai a conferencia nao vale, e o probe diz isso em vez de acusar o
## produto.
##
## O WARP SE REPETE A CADA QUADRO, e isto nao e zelo: o cursor aqui e o cursor
## de VERDADE do sistema, e basta ele sair de cima do alvo por um quadro para a
## camada esconder a dica (que e o comportamento certo dela). Sem repetir, o
## probe acusava "a dica nao abriu" em duas das cinco conferencias, de forma
## diferente a cada rodada — um teste intermitente sobre um conserto de tooltip
## e exatamente o que este projeto nao pode ter de novo.
func _abrir(o_que: String, alvo: Control, onde: Vector2) -> bool:
	if not await _esperar_hover(onde, alvo):
		_probe_furado += 1
		print("  %-38s PERDIDA (o cursor nao chegou)" % o_que)
		return false
	var assentou := 0
	for i in QUADROS_ATE_DESISTIR:
		get_viewport().warp_mouse(onde)
		_camada._process(DT)
		# o layout do painel so acontece entre quadros: sem isto, `_painel.size`
		# ainda e o da dica anterior quando a medida for lida
		await get_tree().process_frame
		if _camada._painel.visible and _camada._medir == 0:
			assentou += 1
			# dois quadros DEPOIS de assentar: o primeiro roda `_assentar`
			# (reset_size + posicao), o segundo confirma que a posicao nao
			# muda mais — e e essa posicao estavel que a conferencia le
			if assentou >= 2:
				return true
		else:
			assentou = 0
	_probe_furado += 1
	print("  %-38s PERDIDA (a dica nao assentou)" % o_que)
	return false


func _dizer(o_que: String, ok: bool, detalhe: String) -> void:
	if not ok:
		_falhas += 1
	print("  %-38s %-6s %s" % [o_que, "ok" if ok else "FALHA", detalhe])


func _esperar_hover(onde: Vector2, alvo: Control) -> bool:
	for i in QUADROS_ATE_DESISTIR:
		# repete o warp: um `warp_mouse` isolado as vezes nao gera evento de
		# movimento (ver a nota em tip_alvo_probe)
		if i % 15 == 0:
			get_viewport().warp_mouse(onde)
		await get_tree().process_frame
		if _camada._hovered_com_dica() == alvo:
			return true
	return false

## A LINHA SELECIONADA NAO TEM DICA (autor, 16/09: "nao precisa dessas caixas
## de texto se o overlay de atributo ja mostra").
##
## Esta conferencia nao mexe no cursor: ela monta uma `PickPanel` de verdade,
## com as ofertas que dao dica (as que tem dono), e le o `tooltip_text` de cada
## linha depois de cada selecao. E o produto, nao uma imitacao dele — se alguem
## trocar a regra dentro de `PickPanel._dicas_da_selecao`, isto acusa.
##
## As duas metades importam:
##   * a linha ESCOLHIDA fica sem dica, porque o preview ao lado ja mostra tudo;
##   * a linha NAO escolhida mantem a dica, e a dica VOLTA quando a selecao
##     muda. Apagar sem repor seria um conserto pela metade, e e o tipo de
##     detalhe que so aparece no segundo clique.
func _linha_selecionada_sem_dica(bg: Control) -> void:
	var especies: Array = Db.base_species
	if especies.size() < 2:
		_probe_furado += 1
		print("  %-38s PERDIDA (sem especies para montar as ofertas)"
			% "linha selecionada sem dica")
		return
	var painel := PickPanel.new()
	painel.offers = [
		{"id": "a", "name": "Cauda de Brasa", "text": "+20 ATK",
			"kind_label": "Item", "owner": String(especies[0])},
		{"id": "b", "name": "La Condutora", "text": "+45% de Carga",
			"kind_label": "Item", "owner": String(especies[1])},
	]
	bg.add_child(painel)
	await get_tree().process_frame
	await get_tree().process_frame

	var t0 := String(painel._rows[0].tooltip_text)
	var t1 := String(painel._rows[1].tooltip_text)
	_dizer("escolhida (0) fica sem dica", t0 == "", "viu '%s'" % t0)
	_dizer("a outra (1) mantem a dica", t1 != "", "viu '%s'" % t1)

	painel._select(1)
	await get_tree().process_frame
	var u0 := String(painel._rows[0].tooltip_text)
	var u1 := String(painel._rows[1].tooltip_text)
	_dizer("a dica VOLTA na linha 0", u0 != "", "viu '%s'" % u0)
	_dizer("e sai da linha 1", u1 == "", "viu '%s'" % u1)

	bg.remove_child(painel)
	painel.queue_free()


## Guarda o estado final em docs/probe_tip_ancora.png — o conserto visto, e nao
## so medido.
func _retratar(onde: Vector2, alvo: Control) -> void:
	if not await _abrir("print da conferencia", alvo, onde):
		return
	await get_tree().process_frame
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://docs/probe_tip_ancora.png")
	print("  print em docs/probe_tip_ancora.png")
