class_name ScreenChance
extends Control
## Evento de acaso. O jogo escolhe QUE evento aparece; o jogador escolhe se
## ENTRA nele (decisão do autor, 31/08). Recusar nunca custa nada — o preço de
## recusar é a chance perdida.
##
## == A TELA DE PERSONAGEM (15/09) ==
##
## Esta tela voltou a ser alcançável em 15/09 (o Acaso entrou no passo 6 da
## sequência) e ela tem uma responsabilidade que nenhuma outra tem: `data/
## random_events.json` é a ÚNICA prosa com voz do projeto inteiro. Todo o resto
## do catálogo — espécies, itens, pratos, inimigos — é ficha técnica. Então esta
## não é mais um PickPanel com palavras: a coluna da esquerda é a ficção, em
## corpo grande e com espaço, e é a maior coisa da tela.
##
## A coluna da DIREITA é a correção do segundo achado. A revisão mediu: a tela
## ocupava 11,8% do quadro e ESCONDIA números que já estavam nos dados — pesos
## de 70/30, ops de "+14 Éter" e "-22% do HP" — a ponto de dois dos sete eventos
## (Caravana Perdida e Ninho Abandonado) serem 100% bons sem o jogador ter como
## saber. Uma aposta sem cotação não é uma decisão, é um botão.
##
## Agora as cotações estão na tela, tiradas do próprio JSON: cada desfecho com o
## peso em porcentagem, uma barra, a frase dele e o que ele faz em pastilhas. E
## no alto, a MANCHETE DE RISCO — a chance de o evento cobrar algo e o que
## pior caso. Quando ela diz "nenhum desfecho custa HP", isso é a informação que
## faltava para o evento existir como escolha.
##
## Depois de aceitar, a tabela não some: o desfecho que saiu ACENDE e os outros
## apagam. É o que fecha o laço de aprendizado — o jogador vê a aposta que fez
## e onde ela caiu.

signal finished

## A largura de casa é a mesma das outras telas de momento: `UI.BANNER_W`.
##
## MARGEM_PROSA é o que impede a linha de ter 90 caracteres. O cartão da ficção
## ocupa os 1180 px — ele precisa ser um OBJETO no quadro, não um bilhete solto —
## mas o texto dentro dele vive numa coluna de ~820, que é onde uma linha de 26
## px ainda se lê de uma passada só. A margem larga é o tratamento: é assim que
## se diagrama uma página, e é o oposto de um parágrafo grudado na borda.
const MARGEM_PROSA := 180
const GAP := 14

var _ev: Dictionary = {}
var _index := 0
var _buttons: HBoxContainer
var _resultado: VBoxContainer
var _fila: Array = []
var _cartoes: Array = []        # um Control por desfecho, na ordem do JSON


func setup(ev: Dictionary, index: int) -> void:
	_ev = ev
	_index = index


func _ready() -> void:
	add_child(UI.luz_de_sala(PickPanel.SALA_ACASO))

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	# A folga da coluna e PEQUENA (8) e as separacoes grandes entram como
	# espacador explicito. Com folga 12 mais um espacador de 4, a faixa de
	# titulo ficava a 28 px do proprio texto e a 32 px dos botoes: quase a
	# mesma distancia, entao o titulo nao se lia como titulo DAQUELE texto.
	var col := UI.box(true, 8)
	col.custom_minimum_size = Vector2(UI.BANNER_W, 0)
	center.add_child(col)

	col.add_child(UI.banner(String(_ev.get("title", "NO CAMINHO")).to_upper(),
		PickPanel.SALA_ACASO))
	col.add_child(UI.spacer(6, false))
	col.add_child(_a_ficcao())
	col.add_child(UI.spacer(6, false))
	col.add_child(_as_cotacoes())

	col.add_child(UI.spacer(16, false))
	_buttons = UI.box(false, 12)
	_buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_child(_buttons)

	var yes := UI.button_confirmar("  %s  " % String(_ev.get("accept_label", "ENTRAR")), UI.F_H2)
	yes.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	yes.pressed.connect(_accept)
	_buttons.add_child(yes)

	# SEGUIR EM FRENTE é recuar, e recuar é roxo. Eram dois `UI.button` — um
	# verde cru e um neutro — para as duas metades da mesma decisão.
	var no := UI.button_secundario("  %s  " % String(_ev.get("decline_label", "SEGUIR EM FRENTE")), UI.F_H2)
	no.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	no.pressed.connect(func(): finished.emit())
	_buttons.add_child(no)


# --- a ficção ---------------------------------------------------------------

func _a_ficcao() -> Control:
	# a matéria da estrada à noite: violeta frio, e não a lajota padrão
	var card := UI.card(UI.materia_da_sala(UI.PANEL, PickPanel.SALA_ACASO),
		PickPanel.SALA_ACASO.darkened(0.35))
	var margem := MarginContainer.new()
	margem.add_theme_constant_override("margin_left", MARGEM_PROSA)
	margem.add_theme_constant_override("margin_right", MARGEM_PROSA)
	margem.add_theme_constant_override("margin_top", 14)
	margem.add_theme_constant_override("margin_bottom", 14)
	card.add_child(margem)
	var v := UI.box(true, 10)
	margem.add_child(v)
	# CORPO GRANDE: 26 px e não 18. É a única prosa do jogo; ela merece o mesmo
	# tratamento tipográfico que os números recebem em toda outra tela.
	var t := UI.wrap(String(_ev.get("text", "")), UI.F_H2, UI.TEXT)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(t)

	# O QUE ACONTECEU, depois de aceitar. Fica aqui, embaixo da ficção, porque é
	# a continuação dela — e não no meio da tabela de cotações. O cartão CRESCE
	# quando o resultado chega, e é esse crescimento que dá o gesto de revelação.
	_resultado = UI.box(true, 4)
	v.add_child(_resultado)
	return card


# --- as cotações ------------------------------------------------------------

func _as_cotacoes() -> Control:
	var card := UI.card(UI.materia_da_sala(UI.PANEL_HI, PickPanel.SALA_ACASO),
		UI.LINE)
	var v := UI.box(true, 8)
	card.add_child(v)

	v.add_child(UI.label("O QUE PODE ACONTECER", UI.F_SMALL,
		UI.tint_of(PickPanel.SALA_ACASO, true), HORIZONTAL_ALIGNMENT_CENTER))
	v.add_child(_manchete_de_risco())
	v.add_child(UI.hsep())

	# LADO A LADO, e não empilhados: os desfechos de um evento são alternativas
	# de uma mesma aposta, e alternativas se comparam na horizontal. Com dois
	# eles ficam com 583 px cada; com três, 384.
	var row := UI.box(false, GAP)
	v.add_child(row)
	_cartoes.clear()
	for o in _ev.get("outcomes", []):
		var c := _cartao_de_desfecho(o)
		c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		c.size_flags_vertical = Control.SIZE_EXPAND_FILL
		_cartoes.append(c)
		row.add_child(c)
	return card


## A MANCHETE: a chance de este evento custar HP, e quanto no pior caso.
##
## É calculada dos `ops`, não do campo `good`, porque os dois não são a mesma
## coisa: em "Veio de Éter" o desfecho BOM (peso 0,7) também tira 10% do HP.
## Quem decide entrar quer saber o que pode DOER, não que rótulo o dado leva.
## O RISCO DEIXOU DE SER HP (16/09). Ele era medido em `damage`, e `damage` nao
## custava nada: a cura entre nos e TOTAL (NOTAS 5.23), entao a equipe voltava
## inteira na briga seguinte. Agora o desfecho ruim tira um ITEM ou um PRATO ja
## equipado, que e permanente — e a manchete tem de dizer isso, senao a tela
## troca um risco falso por um risco invisivel.
func _manchete_de_risco() -> Control:
	var chance := 0.0
	var so_prato := true
	for o in _ev.get("outcomes", []):
		var perde := false
		for op in o.get("ops", []):
			if String(op.get("op", "")) == "perde_equipado":
				perde = true
				if not bool(op.get("so_prato", false)):
					so_prato = false
		if perde:
			chance += float(o.get("weight", 0.0))

	var row := UI.box(false, 8)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	if chance <= 0.0:
		# DOIS DOS SETE EVENTOS SÃO ASSIM, e não havia como saber: a Caravana
		# Perdida e o Ninho Abandonado não têm um único desfecho que cobre nada.
		# Sem esta linha, recusá-los é uma jogada racional por falta de informação.
		row.add_child(UI.label("SEM RISCO — nenhum desfecho cobra nada",
			UI.F_BODY, UI.GOOD, HORIZONTAL_ALIGNMENT_CENTER))
		return row
	var cor: Color = UI.BAD if chance >= 0.5 else UI.WARN
	row.add_child(UI.label("RISCO %d%%" % roundi(chance * 100.0), UI.F_H2, cor))
	var oque := "de perder um prato equipado" if so_prato \
		else "de perder um item ou prato equipado"
	var det := UI.label(oque, UI.F_SMALL, UI.TEXT_DIM)
	det.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(det)
	return row


## Um desfecho: o peso em porcentagem, uma barra, a frase e o que ele faz.
func _cartao_de_desfecho(o: Dictionary) -> Control:
	var bom: bool = bool(o.get("good", true))
	var peso := float(o.get("weight", 0.0))
	var cor: Color = UI.GOOD if bom else UI.BAD
	var card := UI.card(UI.PANEL, cor.darkened(0.45))
	var v := UI.box(true, 5)
	card.add_child(v)

	var topo := UI.box(false, 8)
	v.add_child(topo)
	var pct := UI.label("%d%%" % roundi(peso * 100.0), UI.F_H2, cor.lightened(0.2))
	pct.custom_minimum_size = Vector2(72, 0)
	pct.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	topo.add_child(pct)
	var barra := PrismaBar.make("green" if bom else "red", 18)
	barra.custom_minimum_size = Vector2(120, 18)
	barra.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	barra.set_value(peso, 1.0)
	topo.add_child(barra)

	var frase := UI.wrap(String(o.get("text", "")), UI.F_SMALL, UI.TEXT)
	v.add_child(frase)

	var chips := HFlowContainer.new()
	chips.add_theme_constant_override("h_separation", 5)
	chips.add_theme_constant_override("v_separation", 4)
	v.add_child(chips)
	for op in o.get("ops", []):
		var t := _op_texto(op)
		if t == "":
			continue
		var c := _op_cor(op)
		var p := PanelContainer.new()
		p.add_theme_stylebox_override("panel", UI.flat(c.darkened(0.66), 4, c))
		p.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		p.add_child(UI.label(t, UI.F_SMALL, c.lightened(0.3)))
		chips.add_child(p)
	return card


## O que uma `op` FAZ, em português.
##
## É uma tradução de apresentação e não a de `EventGen._apply_op`, que escreve
## no passado ("+14 Éter" depois de aplicar). Aqui a frase é uma possibilidade,
## e o `-` do dano precisa estar visível ANTES de o jogador clicar. As duas
## viverem separadas é de propósito: uma descreve o que pode acontecer, a outra
## relata o que aconteceu.
static func _op_texto(op: Dictionary) -> String:
	match String(op.get("op", "")):
		"ether":
			return "+%d Éter" % int(op.get("n", 0))
		"heal":
			return "+%d%% de HP na equipe" % roundi(float(op.get("pct", 0.0)) * 100.0)
		"damage":
			# op antiga, sem uso nos dados de hoje — ver event_gen._apply_op
			return "-%d%% de HP na equipe" % roundi(float(op.get("pct", 0.0)) * 100.0)
		"perde_equipado":
			return "perde um prato equipado" if bool(op.get("so_prato", false)) \
				else "perde um item ou prato"
		"item":
			return "um item"
		"relic":
			return "uma relíquia"
		"dish_free":
			return "um prato de graça"
	return ""


static func _op_cor(op: Dictionary) -> Color:
	match String(op.get("op", "")):
		"ether":
			return UI.GOLD
		"heal":
			return UI.GOOD
		"damage", "perde_equipado":
			return UI.BAD
	return UI.ACCENT


func _accept() -> void:
	var res := EventGen.resolve_chance(_ev, _index)
	for c in _buttons.get_children():
		_buttons.remove_child(c)
		c.queue_free()

	# A TABELA NÃO SOME: o desfecho que saiu acende, os outros apagam. É onde o
	# jogador aprende que as cotações eram verdadeiras.
	var saiu := String(res["text"])
	var lista: Array = _ev.get("outcomes", [])
	for i in range(_cartoes.size()):
		var este: bool = i < lista.size() and String(lista[i].get("text", "")) == saiu
		_cartoes[i].modulate = Color(1, 1, 1, 1.0 if este else 0.28)

	var accent: Color = UI.GOOD if bool(res["good"]) else UI.BAD
	_resultado.add_child(UI.hsep())
	_resultado.add_child(UI.label(saiu, UI.F_H2, accent.lightened(0.2)))
	for line in res["lines"]:
		_resultado.add_child(UI.label("· " + String(line), UI.F_BODY, UI.TEXT_DIM))
	# O QUE VOCE GANHOU, com cara de premio e nao de nota de rodape.
	for g in (res.get("ganhos", []) as Array):
		_resultado.add_child(_cartao_de_premio(g))
	if res["lines"].is_empty() and (res.get("ganhos", []) as Array).is_empty():
		_resultado.add_child(UI.label("· nada mudou", UI.F_BODY, UI.TEXT_DIM))

	# O que o evento CONCEDEU mas não decidiu: quem fica com o item, quem come
	# o prato. O modelo não abre tela, então ele devolve a pendência e aqui
	# ela vira o mesmo painel de escolha da Feira e da Cozinha.
	_fila = (res.get("pendente", []) as Array).duplicate()
	_proxima_pendencia()


## O CARTAO DE REVELACAO (autor, 16/09: "quando o personagem cavar por uma
## reliquia mostre qual foi a reliquia que o personagem ganhou ali").
##
## Antes a reliquia chegava como um marcador cinza de corpo 15 — "· Reliquia:
## Mao do Alquimista" — no meio de uma lista onde o "+14 Eter" tinha o mesmo
## peso. Ela e a peca mais forte do jogo e 42% das runs terminam sem nenhuma;
## ganhar uma e o momento mais alto de um Acaso, e nao pode ler como rodape.
##
## O cartao diz as tres coisas que decidem se aquilo muda a run: o que e (icone),
## qual e (nome, na cor da peca) e o que faz (o texto, que ja existe no dado e
## que o jogador nao tinha como ler sem abrir outra tela).
func _cartao_de_premio(g: Dictionary) -> Control:
	var tipo := String(g.get("tipo", ""))
	var id := String(g.get("id", ""))
	var nome := ""
	var texto := ""
	var cor := UI.GOLD
	var icone: Control = null
	match tipo:
		"reliquia":
			var r: Dictionary = Db.relics.get(id, {})
			nome = String(r.get("name", id))
			texto = String(r.get("text", ""))
			icone = Icons.relic(id, 32.0)
		"item":
			var it: Dictionary = Db.items.get(id, {})
			nome = String(it.get("name", id))
			texto = String(it.get("text", ""))
			cor = UI.ACCENT
			icone = Icons.item(id, 32.0)
		_:
			return UI.label("· " + nome, UI.F_BODY, UI.TEXT_DIM)

	var cartao := UI.card(UI.LAJOTA, cor)
	var linha := UI.box(false, 10)
	if icone != null:
		linha.add_child(icone)
	var col := UI.box(true, 2)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var titulo := UI.label(nome, UI.F_H2, cor.lightened(0.25))
	col.add_child(titulo)
	if texto != "":
		var t := UI.label(texto, UI.F_SMALL, UI.TEXT_DIM)
		t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		col.add_child(t)
	linha.add_child(col)
	cartao.add_child(linha)
	# SOM DE PREMIO: a reliquia e a unica coisa do Acaso que muda a run inteira.
	UI.som("moeda")
	return cartao


## Resolve uma pendência por vez; quando acabam, mostra o SEGUIR EM FRENTE.
func _proxima_pendencia() -> void:
	if _fila.is_empty():
		var go := UI.button_confirmar("  SEGUIR EM FRENTE  ", UI.F_H2)
		go.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		go.pressed.connect(func(): finished.emit())
		_buttons.add_child(go)
		return
	var p: Dictionary = _fila.pop_front()
	if String(p["tipo"]) == "item":
		_escolher_dono(String(p["id"]))
	else:
		_escolher_comensal(String(p["id"]))


func _escolher_dono(id: String) -> void:
	var podem: Array = Run.team.filter(func(u): return u.accepts_item(id))
	if podem.size() <= 1:
		if not podem.is_empty():
			podem[0].items.append(id)
			Run.team_changed.emit()
			_anotar("%s ficou com %s" % [podem[0].display_name(),
				String(Db.items[id]["name"])])
		_proxima_pendencia()
		return
	var pk := PickerOverlay.new()
	pk.setup("Quem fica com %s?" % String(Db.items[id]["name"]),
		String(Db.items[id].get("text", "")),
		func(u): return u.accepts_item(id),
		func(u): return _efeito_em(id, u))
	pk.picked.connect(func(u):
		pk.queue_free()
		u.items.append(id)
		Run.team_changed.emit()
		_anotar("%s ficou com %s" % [u.display_name(), String(Db.items[id]["name"])])
		_proxima_pendencia())
	# recusar um achado é legítimo: nem todo item é bom para a build
	pk.cancelled.connect(func():
		pk.queue_free()
		_anotar("ninguém quis %s" % String(Db.items[id]["name"]))
		_proxima_pendencia())
	add_child(pk)


func _escolher_comensal(id: String) -> void:
	var pk := PickerOverlay.new()
	pk.setup("Quem come %s?" % String(Db.dishes[id]["name"]),
		"É de graça, mas ocupa Estômago — e o efeito é permanente.",
		func(u): return Run.unit_accepts(u, id),
		func(u): return "Estômago %d/%d" % [u.dishes_eaten(), u.estomago()])
	pk.picked.connect(func(u):
		pk.queue_free()
		_servir(id, u))
	pk.cancelled.connect(func():
		pk.queue_free()
		_anotar("ninguém comeu")
		_proxima_pendencia())
	add_child(pk)


## O Guisado Cromático precisa também do ELEMENTO — a mesma pergunta que a
## Cozinha faz, pelo mesmo motivo: sem ela o prato não faz nada.
func _servir(id: String, u: UnitInstance) -> void:
	if String(Db.dishes[id].get("effect", "")) == "set_element":
		var ep := ElementPicker.new()
		ep.setup("%s vira o quê?" % u.display_name(),
			"A Afinidade muda para sempre — e com ela as reações da equipe.",
			u.element())
		ep.picked.connect(func(el):
			ep.queue_free()
			_anotar(Run.cook_free(id, u, String(el)))
			_proxima_pendencia())
		ep.cancelled.connect(func():
			ep.queue_free()
			_anotar("ninguém comeu")
			_proxima_pendencia())
		add_child(ep)
		return
	_anotar(Run.cook_free(id, u))
	_proxima_pendencia()


## O que o item faria NAQUELE Prismon — num Núcleo, a troca de elemento.
func _efeito_em(id: String, u: UnitInstance) -> String:
	if UnitInstance.item_sets_element(id) and u.has_core():
		return "já usa um Núcleo"
	if not u.accepts_item(id):
		return "sem espaço de item (%d/%d)" % [u.items.size(), u.item_slots()]
	var novo := String(Db.items.get(id, {}).get("mods", {}).get("set_element", ""))
	if novo != "":
		if novo == u.element():
			return "já é de %s" % Db.el_name(novo)
		return "%s → %s" % [Db.el_name(u.element()), Db.el_name(novo)]
	return "itens %d/%d" % [u.items.size(), u.item_slots()]


func _anotar(linha: String) -> void:
	if linha == "" or _resultado == null:
		return
	_resultado.add_child(UI.label("· " + linha, UI.F_BODY, UI.TEXT_DIM))
