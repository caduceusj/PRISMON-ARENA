class_name ScreenRecruit
extends Control
## Momento de recruta: DUAS criaturas, escolhe uma. Leva-se a criatura inteira
## (decisão do autor: "melhor pegar o pokemon inteiro").
##
## == AS DUAS OPÇÕES FICAM NA MESMA LINHA (15/09) ==
##
## A revisão mediu o defeito e a prova do conserto na mesma tela: em
## `07a_recruta.png` nada nos dois cartões se alinha — para comparar
## "Gelo·Guardião" com "Raio·Arcano" o olho anda na diagonal — e em
## `13_run_evento.png`, onde os DOIS cartões têm o bloco "desbloqueia", a mesma
## tela bate ao pixel nas cinco linhas.
##
## A causa eram duas, e as duas estão consertadas aqui:
##
##   1. o bloco "desbloqueia" só era acrescentado quando havia reação nova, e o
##      conteúdo é centrado — então um cartão com um bloco a mais RE-CENTRA
##      tudo o que está acima dele. Agora o bloco existe SEMPRE; quando não há
##      reação nova ele escreve isso, que também é informação (uma criatura que
##      não abre reação nenhuma é uma escolha diferente, não uma escolha sem
##      dado);
##   2. `MonsterPortrait.make` dimensiona pela SILHUETA da espécie, então um
##      Sheep alto e um Pinto-Raio baixo empurravam a primeira linha de texto
##      para alturas diferentes. O retrato agora mora num palco de altura FIXA.
##
## E o terceiro achado, o de peso: "o maior controle da tela de recruta é o
## botão de NÃO FAZER NADA". SEGUIR SEM RECRUTAR ocupava a largura inteira da
## coluna (880 px) enquanto cada criatura tinha 340. Agora os cartões dividem
## os 1180 px da tela e a saída é um botão estreito, centrado, embaixo.

signal finished

## Altura do palco do retrato. 108 px cobre a mais alta das silhuetas do slice
## com folga; o que importa não é o número e sim ele ser o MESMO nos dois lados.
const PALCO_H := 108.0

var _ids: Array = []


func setup(ids: Array) -> void:
	_ids = ids


func _ready() -> void:
	add_child(UI.luz_de_sala(PickPanel.SALA_RECRUTA))

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var col := UI.box(true, 12)
	# a mesma largura de casa das outras telas de momento (UI.BANNER_W)
	col.custom_minimum_size = Vector2(UI.BANNER_W, 0)
	center.add_child(col)

	col.add_child(UI.banner("UMA CRIATURA SE APROXIMA", PickPanel.SALA_RECRUTA))
	col.add_child(UI.label("Duas seguem seu rastro. Só há espaço para uma.",
		UI.F_SMALL, UI.TEXT_DIM, HORIZONTAL_ALIGNMENT_CENTER))
	col.add_child(UI.spacer(8, false))

	if _ids.is_empty():
		col.add_child(UI.label("Nenhuma criatura se aproximou — o Vínculo está cheio.",
			UI.F_BODY, UI.TEXT_DIM, HORIZONTAL_ALIGNMENT_CENTER))
	else:
		var row := UI.box(false, 16)
		row.alignment = BoxContainer.ALIGNMENT_CENTER
		col.add_child(row)
		for id in _ids:
			row.add_child(_card(String(id)))

	col.add_child(UI.spacer(10, false))
	# A SAÍDA ENCOLHEU. Era a peça mais larga da tela; agora é um botão
	# estreito e roxo (recuar), e o peso visual fica onde a decisão está.
	var skip := UI.button_secundario("  SEGUIR SEM RECRUTAR  ", UI.F_SMALL)
	skip.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	skip.custom_minimum_size = Vector2(320, UI.BTN_H)
	skip.pressed.connect(func(): finished.emit())
	col.add_child(skip)


func _card(id: String) -> Control:
	var s := Db.sp(id)
	var el := String(s.get("element", "FOGO"))
	var c := Db.el_color(el)

	# CardButton, nao Button com filhos ancorados: conteudo ancorado ignora a
	# margem da moldura 9-patch, e o texto "desbloqueia Supercondução ·
	# Congelar" saia pelas bordas do cartao. Aqui o container mede o conteudo
	# e respeita a borda — o texto quebra linha em vez de vazar.
	# A LAJOTA É DO CREPÚSCULO (a sala do recruta, em data/paleta.json), o feixe
	# é do elemento da criatura. Era `UI.PANEL` nos dois cartões — a mesma
	# lajota roxa de toda tela do jogo.
	var card := CardButton.make(
		UI.materia_da_sala(UI.PANEL, PickPanel.SALA_RECRUTA), c)
	# os dois cartões dividem a linha em partes iguais: sem isto, a largura de
	# cada um saía do conteúdo dele e os dois ficavam de tamanhos diferentes
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.tooltip_text = "HP %d · ATK %d · DEF %d · VEL %.1f · PE %d
⚡ %s — %s" % [
		int(s.get("hp", 0)), int(s.get("atk", 0)), int(s.get("def", 0)),
		float(s.get("vel", 1.0)), int(s.get("pe", 0)),
		String(s.get("ult", {}).get("name", "")), String(s.get("ult", {}).get("text", ""))]
	card.clicked.connect(_take.bind(id))

	var v := card.body
	v.add_theme_constant_override("separation", 8)
	v.alignment = BoxContainer.ALIGNMENT_CENTER

	# O PALCO DO RETRATO, de altura fixa. `MonsterPortrait.make` mede pela
	# silhueta da espécie; sem o palco, a primeira linha de texto de cada cartão
	# começa numa altura diferente e nada mais alinha depois disso.
	var palco := CenterContainer.new()
	palco.custom_minimum_size = Vector2(0, PALCO_H)
	v.add_child(palco)
	palco.add_child(MonsterPortrait.make(id, el, 84.0))

	v.add_child(UI.label(Db.sp_name(id), UI.F_H1, c.lightened(0.3),
		HORIZONTAL_ALIGNMENT_CENTER))

	# GRADE de duas colunas, centrada como BLOCO — não duas linhas centradas
	# cada uma por si. Centradas isoladamente, o ícone do elemento e o da
	# ultimate caíam em x diferentes (as frases têm larguras diferentes) e as
	# duas linhas ficavam desencontradas: era o "ícones esparsos" do print.
	# Numa grade a coluna do ícone é a mesma para as duas linhas.
	var info := GridContainer.new()
	info.columns = 2
	info.add_theme_constant_override("h_separation", 7)
	info.add_theme_constant_override("v_separation", 4)
	info.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	v.add_child(info)

	var px := UI.icon_px(UI.F_SMALL)
	info.add_child(Icons.element(el, px))
	info.add_child(_info_line("%s · %s" % [Db.el_name(el), Db.role_name(String(s.get("role", "")))],
		UI.TEXT_DIM))
	info.add_child(Icons.node("g_sword", px, UI.ACCENT.lightened(0.2)))
	info.add_child(_info_line(String(s.get("ult", {}).get("name", "")),
		UI.ACCENT.lightened(0.2)))

	# O BLOCO EXISTE SEMPRE — ver a nota no topo do arquivo. "Nenhuma reação
	# nova" é uma resposta, não uma ausência.
	var novo := _new_reactions(el)
	var texto := "nenhuma reação nova"
	var cor_rx := UI.TEXT_DIM
	if not novo.is_empty():
		texto = " · ".join(novo)
		cor_rx = UI.GOOD
	v.add_child(UI.hsep())
	v.add_child(UI.label("desbloqueia", UI.F_SMALL, UI.TEXT_DIM,
		HORIZONTAL_ALIGNMENT_CENTER))
	var rx := UI.wrap(texto, UI.F_SMALL, cor_rx)
	rx.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(rx)
	return card


## Linha da grade de informação: alinhada à esquerda e centrada na vertical,
## para encostar no ícone da coluna ao lado em vez de flutuar acima dele.
func _info_line(text: String, color: Color) -> Label:
	var l := UI.label(text, UI.F_SMALL, color)
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return l


## Reacoes que a equipe AINDA NAO produz e que esta criatura traria.
func _new_reactions(el: String) -> Array:
	var mine: Array = []
	for u in Run.team:
		if not mine.has(u.element()):
			mine.append(u.element())
	var before: Dictionary = {}
	for l in Db.reactions_between(mine):
		before[String(l["reaction"]["id"])] = true
	var out: Array = []
	var after: Array = mine.duplicate()
	if not after.has(el):
		after.append(el)
	for l in Db.reactions_between(after):
		var rid := String(l["reaction"]["id"])
		if not before.has(rid) and not out.has(String(l["reaction"]["name"])):
			out.append(String(l["reaction"]["name"]))
	return out


func _take(id: String) -> void:
	Run.recruit(id)
	UI.som("recruta")
	finished.emit()
