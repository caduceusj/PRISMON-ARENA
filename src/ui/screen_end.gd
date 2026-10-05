class_name ScreenEnd
extends Control
## FIM DE RUN.
##
## Esta é a tela que ninguém tinha revisado: `tools/screenshots.gd` captura 16
## telas e nunca esta, então ela não tem print; e `grep -in "screen_end"` no
## NOTAS.md dá zero ocorrências em 1283 linhas. A revisão de 15/09 achou os dois
## defeitos que a falta de print escondia:
##
## 1. ELA NUNCA MOSTRAVA A SEMENTE, apesar de a tela de título ter um campo para
##    digitá-la. A run que acabou de acontecer era, por construção, a única que
##    o jogador poderia querer repetir — e o número que a repete morria com ela.
## 2. "A RUN EM NÚMEROS" era um cartão SEM UM ÚNICO NÚMERO DE COMBATE: peso
##    elemental, ressonâncias, relíquias, tamanho da equipe e pratos. Nenhum
##    deles produzido por uma briga. `Run.history` já era escrito a cada nó;
##    desde 15/09 `Main._on_combat_over` escreve os números do combate NELE, e
##    é daí que sai a coluna da esquerda.
##
## E o LOGOTIPO passou a aparecer aqui. Ele é a única peça feita à mão do jogo
## inteiro e não saía da primeira tela; o fim da run é o outro momento em que o
## jogo tem o direito de dizer o próprio nome.

signal restart

var _won := false

## A SALA. Dourado de troféu na vitória, o mesmo vermelho de "você perdeu vida"
## na derrota — aqui ele finalmente significa o que significa no combate.
const SALA_VITORIA := Color("#c9a13f")
const SALA_DERROTA := Color("#8f3f4e")


func setup(won: bool) -> void:
	_won = won


func _ready() -> void:
	add_child(UI.luz_de_sala(SALA_VITORIA if _won else SALA_DERROTA, 0.075))
	UI.som("vitoria" if _won else "derrota")

	# A TELA USA A TELA (16/09). Era um `CenterContainer` com uma coluna de 1060
	# px de largura fixa: 270 px de margem morta de cada lado, num quadro de
	# 1600 — "um bloco no meio com margens enormes", nas palavras do autor. As
	# margens agora são as mesmas 26 px de todas as outras telas do jogo, e o
	# rodapé fica ancorado embaixo em vez de flutuar atrás do conteúdo. De
	# quebra, a linha do peso elemental de uma equipe de cinco elementos deixou
	# de quebrar em duas: ela cabe inteira nos 575 px que o cartão agora tem.
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for s in ["left", "right"]:
		margin.add_theme_constant_override("margin_" + s, 26)
	margin.add_theme_constant_override("margin_top", 26)
	margin.add_theme_constant_override("margin_bottom", 22)
	add_child(margin)
	var col := UI.box(true, 10)
	margin.add_child(col)

	# O LOGOTIPO SAI DA PRIMEIRA TELA. Pequeno: ele assina, não anuncia.
	var logo := LogoView.make(300.0)
	if logo != null:
		col.add_child(logo)

	col.add_child(UI.label("VITÓRIA" if _won else "DERROTA", 52,
		UI.GOOD if _won else UI.BAD, HORIZONTAL_ALIGNMENT_CENTER))
	col.add_child(UI.label(
		"Você atravessou o Ato I." if _won else "A run terminou no passo %d de %d."
			% [Run.node_index, Run.total_nodes()],
		UI.F_H2, UI.TEXT_DIM, HORIZONTAL_ALIGNMENT_CENTER))
	col.add_child(UI.spacer(12, false))

	var row := UI.box(false, 14)
	col.add_child(row)
	row.add_child(_numeros_card())
	row.add_child(_equipe_card())

	col.add_child(_semente_card())
	col.add_child(UI.spacer())

	var foot := UI.box(false, 0)
	foot.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_child(foot)
	# "NOVA RUN" mentia: o botão leva ao MENU, e é de lá que se começa outra —
	# a tela de título é onde a semente se digita, que é justamente o que esta
	# tela acabou de oferecer.
	var b := UI.button_confirmar("  VOLTAR AO MENU  ", UI.F_H2)
	b.custom_minimum_size = Vector2(420, 0)
	b.pressed.connect(func(): restart.emit())
	foot.add_child(b)


## OS NÚMEROS DE COMBATE, que é o que o título do cartão sempre prometeu.
## Tudo aqui vem de `Run.history`, uma entrada por nó jogado.
func _numeros_card() -> Control:
	var card := UI.card()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# altura do proprio conteudo — ver a nota em `_equipe_card`
	card.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	var v := UI.box(true, 4)
	card.add_child(v)
	v.add_child(UI.label("A RUN EM NÚMEROS", 12, UI.TEXT_DIM))
	v.add_child(UI.hsep())

	var lutas := 0
	var vitorias := 0
	var tempo := 0.0
	var reacoes := 0
	var dano := 0.0
	var sofrido := 0.0
	var ativos := 0
	var maior := 0.0
	var maior_de := ""
	for h in Run.history:
		if not (h as Dictionary).has("duration"):
			continue
		lutas += 1
		if bool(h.get("won", false)):
			vitorias += 1
		tempo += float(h.get("duration", 0.0))
		reacoes += int(h.get("reactions", 0))
		dano += float(h.get("damage", 0.0))
		sofrido += float(h.get("taken", 0.0))
		ativos += int(h.get("actives", 0))
		if float(h.get("biggest", 0.0)) > maior:
			maior = float(h.get("biggest", 0.0))
			maior_de = String(h.get("biggest_src", ""))

	if lutas == 0:
		v.add_child(UI.label("nenhum combate registrado", UI.F_BODY, UI.TEXT_DIM))
		return card

	v.add_child(_linha("Combates", "%d vencidos de %d" % [vitorias, lutas], UI.GOOD))
	v.add_child(_linha("Tempo em briga", "%.1f s  ·  %.1f s por combate"
		% [tempo, tempo / float(lutas)], UI.TEXT))
	v.add_child(_linha("Reações causadas", "%d  ·  %.1f por combate"
		% [reacoes, float(reacoes) / float(lutas)], UI.ACCENT.lightened(0.2)))
	v.add_child(_linha("Dano causado", "%d" % roundi(dano), UI.GOLD))
	v.add_child(_linha("Dano sofrido", "%d" % roundi(sofrido), UI.BAD.lightened(0.15)))
	v.add_child(_linha("Ativos lançados", "%d" % ativos, UI.WARN))
	if maior > 0.0:
		v.add_child(_linha("Maior golpe", "%d  (%s)" % [roundi(maior), maior_de], UI.GOLD))
	return card


## O que a run MONTOU: é o cartão antigo, com o título honesto.
##
## LINHA QUE DIZ "NENHUM" NÃO ENTRA (16/09). Numa run curta este cartão saía com
## SEIS linhas das quais três eram "nenhuma", "nenhuma" e "nenhum" — metade do
## cartão gasta para informar que não há o que informar. É a mesma regra que
## `ScreenResult._resumo_card` já aplicava aos Ativos usados, e é o pedido do
## autor ("simplifique mais como essas informacoes sao mostradas") na sua forma
## mais barata: a linha some, o cartão encolhe, e o que sobrou é tudo verdade.
##
## E O CARTÃO TEM A ALTURA DO PRÓPRIO CONTEÚDO. Irmãos de um HBox esticam até a
## altura do mais alto por padrão, então encolher a lista não encolhia nada: as
## três linhas de uma run curta ficavam dentro de uma moldura de sete, com 160
## px de vazio DENTRO de um painel — que é o mesmo defeito que derrubou os dois
## painéis da tela de log. Com `SHRINK_BEGIN` os dois cartões encostam pelo topo
## e terminam onde o conteúdo termina.
func _equipe_card() -> Control:
	var card := UI.card()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	var v := UI.box(true, 4)
	card.add_child(v)
	v.add_child(UI.label("A MÁQUINA QUE VOCÊ MONTOU", 12, UI.TEXT_DIM))
	v.add_child(UI.hsep())

	var w := Run.elemental_weight()
	var parts: Array = []
	for e in w.keys():
		parts.append("%s %d" % [Db.el_name(String(e)), int(w[e])])
	if not parts.is_empty():
		v.add_child(_linha("Peso elemental", "  ·  ".join(parts), UI.TEXT))

	var res: Array = []
	for r in Run.active_resonances():
		res.append(String(r["name"]))
	if not res.is_empty():
		v.add_child(_linha("Ressonâncias", "  ·  ".join(res),
			UI.ACCENT.lightened(0.2)))

	v.add_child(_linha("Equipe final", "%d corpos  ·  Vínculo %d/%d"
		% [Run.team.size(), Run.bond_used(), Run.bond_total()], UI.TEXT))
	v.add_child(_linha("Éter que sobrou", "%d" % Run.ether, UI.GOLD))

	if not Run.relics.is_empty():
		var rrow := UI.box(false, 6)
		rrow.add_child(_rotulo("Relíquias"))
		for rid in Run.relics:
			var ri := Icons.relic(String(rid), 32.0)
			ri.tooltip_text = "%s — %s" % [String(Db.relics[rid]["name"]),
				String(Db.relics[rid]["text"])]
			ri.mouse_filter = Control.MOUSE_FILTER_PASS
			rrow.add_child(ri)
		v.add_child(rrow)

	var cooked: Array = []
	for u in Run.team:
		for d in u.dishes:
			cooked.append("%s (%s)" % [String(Db.dishes[d]["name"]), u.display_name()])
	if not cooked.is_empty():
		v.add_child(_linha("Pratos", "  ·  ".join(cooked), UI.TEXT_DIM))
	return card


## A SEMENTE, num campo que dá para SELECIONAR e copiar.
##
## A tela de título aceita uma semente digitada e é a única maneira de repetir
## uma run — e a run que o jogador quer repetir é justamente esta, a que acabou
## de terminar. Um Label não se copia; um LineEdit em `read_only` se copia, e o
## Theme já o desenha como encaixe vago (célula `C_SLOT`), então ele lê como
## campo sem virar um controle que pede ser editado.
func _semente_card() -> Control:
	var card := UI.card(UI.PANEL, UI.LINE)
	var row := UI.box(false, 10)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	card.add_child(row)
	row.add_child(_rotulo("SEMENTE DESTA RUN"))
	var f := LineEdit.new()
	f.text = str(Run.seed_value)
	f.editable = false
	f.custom_minimum_size = Vector2(180, 0)
	f.alignment = HORIZONTAL_ALIGNMENT_CENTER
	f.tooltip_text = "Digite este número na tela de título para jogar a MESMA run."
	row.add_child(f)
	var dica := UI.label("digite na tela de título para repetir esta run",
		UI.F_SMALL, UI.TEXT_DIM)
	dica.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(dica)
	return card


func _rotulo(t: String) -> Label:
	var l := UI.label(t, UI.F_SMALL, UI.TEXT_DIM)
	l.custom_minimum_size = Vector2(160, 0)
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return l


## Rótulo à esquerda em coluna de largura fixa, valor à direita. As duas colunas
## dos dois cartões usam a MESMA largura de rótulo, então os valores dos dois
## caem no mesmo x — que é o que faz duas listas lado a lado lerem como uma
## tabela e não como dois blocos de texto.
func _linha(rotulo: String, valor: String, cor: Color) -> Control:
	var row := UI.box(false, 8)
	row.add_child(_rotulo(rotulo))
	# QUEBRA, nao corta. Com `clip_text` a linha do peso elemental de uma equipe
	# de quatro elementos saia "Gelo 1 · Raio 1 · Fogo 1 · Naturez" — a tela que
	# existe para fechar a run terminando numa palavra pela metade.
	var v := UI.wrap(valor, UI.F_BODY, cor)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(v)
	return row
