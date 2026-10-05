class_name RunRibbon
extends PanelContainer
## A fita da run, no alto: ONDE VOCÊ ESTÁ e O QUE VEM A SEGUIR, em texto.
##
## == DEZESSETE CAIXAS PARA DIZER UM NÚMERO (autor, 16/09) ==
##
## Até aqui esta peça desenhava a sequência INTEIRA do Ato: nove combates mais
## os oito eventos entre eles, cada um numa lajota de 36 px. No alto de
## `shots/11_run_preparacao.png` e `shots/12_run_log.png` isso aparecia como uma
## fileira de dezessete quadradinhos com um X vermelho na maioria deles — o
## ícone `node_rinha` repetido — e o autor leu a fileira como "o lugar que
## mostra os slots livres": *"não precisa mostrar os quadradinhos, só dizer os
## slots restantes"*.
##
## Ele estava certo sobre o que a fileira comunicava. Quinze dos dezessete
## degraus eram idênticos entre si e nenhum deles decidia nada agora: o passado
## já passou, e o combate de daqui a seis passos é gerado na hora em que chegar.
## O que muda uma decisão HOJE são duas coisas — em que passo a run está, e qual
## é o próximo momento (comprar? cozinhar? recrutar?), porque é isso que diz se
## vale guardar Éter.
##
## Então a fita passa a escrever essas duas coisas e nada mais. A trilha inteira
## não sumiu: ela virou CONSULTA, no tooltip da própria fita, onde quem quiser
## planejar o Ato lê a sequência toda em texto. É a mesma troca que a doca e o
## trilho fizeram nesta leva — mostrar menos, guardar o resto atrás do cursor.

func _ready() -> void:
	# materia neutra: a fita e moldura permanente, e a cor dela tem de vir dos
	# degraus e nao de um roxo proprio (ver a nota de RosterRail._ready)
	add_theme_stylebox_override("panel", UI.panel(UI.LAJOTA, 0, UI.LINE))
	rebuild()


func rebuild() -> void:
	for c in get_children():
		remove_child(c)
		c.queue_free()

	var total: int = Run.total_nodes()
	var atual: int = clampi(Run.node_index, 1, total)
	var pela_frente := _pela_frente(atual, total)

	# A FITA INTEIRA É UM ALVO DE DICA SÓ.
	#
	# Antes eram dezessete alvos, um por degrau, e percorrer a fila com o cursor
	# dava dezessete dicas seguidas. Agora parar o cursor na fita é UMA pergunta
	# — "o que vem pela frente?" — e a resposta é a trilha inteira de uma vez.
	var row := UI.box(false, 10)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.mouse_filter = Control.MOUSE_FILTER_STOP
	row.tooltip_text = _trilha(atual, total, pela_frente)
	row.mouse_entered.connect(func() -> void: UI.som("hover"))
	add_child(row)

	row.add_child(_texto("PASSO", UI.F_SMALL, UI.TEXT_DIM))
	row.add_child(_texto("%d/%d" % [atual, total], UI.F_H2, UI.GOLD))

	# O PRÓXIMO MOMENTO, e só ele. Os outros quinze estão no tooltip.
	#
	# SEM ÍCONE, e isto foi medido no print e não decidido na cabeça: o ícone de
	# 16 px ao lado da palavra saía como uma mancha escura de três pixels de
	# tinta útil (`shots/11_run_preparacao.png`, recorte do topo). Subir para 32
	# — a próxima escala limpa de um sprite de 32x32 — devolveria à barra a
	# altura de quadradinho que ela acabou de perder. A palavra já diz o que é,
	# e a COR dela é a mesma que os degraus usavam: o alfabeto não mudou, só
	# parou de ser desenhado duas vezes.
	if not pela_frente.is_empty():
		row.add_child(_texto("·", UI.F_BODY, UI.ARESTA))
		row.add_child(_texto("A SEGUIR", UI.F_SMALL, UI.TEXT_DIM))
		var prox := String(pela_frente[0])
		row.add_child(_texto(_nome(prox), UI.F_BODY, _tint(prox).lightened(0.2)))


## Rótulo de UMA linha dentro da fita, centrado na vertical.
##
## O centro vertical é escrito aqui e não em cada chamada porque a fita é uma
## linha de dois corpos — 18 px nos rótulos, 26 px no número e no nome — e um
## Label sem alinhamento vertical num HBox nasce colado no topo da linha. Era
## isso que deixava o rótulo pequeno flutuando acima do número grande em vez de
## ao lado dele.
func _texto(t: String, corpo: int, cor: Color) -> Label:
	var l := UI.label(t, corpo, cor)
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return l


## O que vem DEPOIS do combate `atual`, em ordem: o evento entre os dois
## combates, o combate seguinte, o evento seguinte, e assim até o chefe.
##
## Com `Run.node_index` ainda em 0 (a run começou, mas o primeiro combate não
## aconteceu) o próprio combate 1 ainda está pela frente — sem esta linha a fita
## anunciaria o evento do passo 1 antes do combate do passo 1.
func _pela_frente(atual: int, total: int) -> Array:
	var out: Array = []
	if Run.node_index < 1:
		out.append("chefe" if total <= 1 else "rinha")
	for i in range(atual, total):
		var kind := EventGen.kind_after(i)
		if kind != "":
			out.append(kind)
		out.append("chefe" if i + 1 >= total else "rinha")
	return out


## A TRILHA INTEIRA, em texto — a consulta que substituiu as dezessete lajotas.
func _trilha(atual: int, total: int, pela_frente: Array) -> String:
	var linhas: Array = ["A trilha do Ato — passo %d de %d" % [atual, total]]
	if Run.node_index >= 1:
		linhas.append("Agora: %s" % _descricao("chefe" if atual >= total else "rinha"))
	if not pela_frente.is_empty():
		linhas.append("A seguir: %s" % _descricao(String(pela_frente[0])))
	if pela_frente.size() > 1:
		var nomes: Array = []
		for k in pela_frente.slice(1):
			nomes.append(_nome(String(k)))
		linhas.append("Depois: %s" % ", ".join(nomes))
	return "\n".join(linhas)


## A COR DE CADA TIPO DE MOMENTO, num lugar só — é ela que faz a fita ser
## legível de relance. Hoje ela pinta a PALAVRA do próximo momento, que é o
## único desenho que sobrou na fita — ver a nota dos sete casos em `_nome`.
static func _tint(kind: String) -> Color:
	match kind:
		"chefe":   return UI.BAD
		"recruta": return UI.GOOD
		"loja":    return UI.GOLD
		"cozinha": return Color("#5cb85c")
		"acaso":   return UI.ACCENT.lightened(0.25)
		"poder":   return UI.ACCENT
		"troca":   return Color("#8fd8e8")
	return Color("#e8886a")


## O NOME CURTO — o que cabe na fita e na lista da consulta.
##
## OS SETE CASOS, SEMPRE OS SETE (lição da revisão de 15/09, ALTO).
##
## `EventGen.kind_after` devolve sete valores — recruta, loja, cozinha, acaso,
## poder, troca e "" — e o `match` do ícone da fita antiga conhecia CINCO.
## "poder" e "troca" caíam no `_` e saíam anunciados como combate, bem no degrau
## em que o jogador ganha o seu segundo Ativo. Um `match` que erra assim não dá
## erro em lugar nenhum: ele escreve a palavra errada, em silêncio.
##
## Vale para os três `match` deste arquivo (`_nome`, `_descricao` e `_tint`):
## quem acrescentar um momento novo em `momentos.evento_apos_combate` tem de
## passar pelos três, e o `_` de cada um é COMBATE e nada mais.
static func _nome(kind: String) -> String:
	match kind:
		"chefe":   return "Prova Final"
		"recruta": return "Recruta"
		"loja":    return "Feira"
		"cozinha": return "Cozinha"
		"acaso":   return "Acaso"
		"poder":   return "Poder novo"
		"troca":   return "Troca"
	return "Combate"


## A FRASE INTEIRA — só na consulta, onde há espaço para ela.
static func _descricao(kind: String) -> String:
	match kind:
		"chefe":   return "a Prova Final do Ato — O Devorador"
		"recruta": return "uma criatura se aproxima (escolhe entre duas)"
		"loja":    return "Feira de Passagem — itens, em Éter"
		"cozinha": return "Cozinha — pratos, em Éter"
		"acaso":   return "evento de acaso (entra ou não)"
		"poder":   return "um Ativo novo para a Mão do Domador"
		"troca":   return "troca — uma criatura sai, outra entra"
	return "combate — escolha entre dois"


# --- a gramática do que vem pela frente -------------------------------------
#
# PERIGO E INIMIGOS EM DOIS ALFABETOS, EM TELAS CONSECUTIVAS (revisão 15/09).
#
# A escolha de combate (`screen_map`) diz quem está do outro lado em TEXTO
# AGRUPADO — "3 Apollos" — e defende a escolha por escrito na própria linha
# 138: "é a linha '10 Bebês' do How Many Dudes: texto, não imagem repetida".
# A tela SEGUINTE, a preparação, desenha três medalhões idênticos sem contagem
# e sem nome. O perigo tem o mesmo problema em menor escala: estrelas âmbar num
# lado, estrelas vermelhas do outro, tamanhos diferentes.
#
# As duas funções abaixo são o alfabeto único. Moram aqui porque a fita é a
# peça que responde "o que vem pela frente", e porque uma gramática partida em
# dois arquivos volta a divergir no mês seguinte.


## A COR DO PERIGO, uma regra só. Era `GOLD <= 2 / WARN <= 4 / BAD` na escolha
## e `BAD` sempre na preparação.
static func perigo_cor(danger: int) -> Color:
	if danger <= 2:
		return UI.GOOD
	return UI.WARN if danger <= 4 else UI.BAD


## PERIGO EM LOSANGOS, não em estrelas.
##
## `★★★☆☆` sai de uma fonte que o sistema operacional empresta (ver
## assets/CREDITOS.md e Icons.GLIFOS): a mesma linha muda de forma entre
## máquinas. O losango é desenhado por nós, é a forma da casa, e cheio-contra-
## oco sobrevive a escala de cinza — a cor sozinha não sobrevivia.
static func perigo(danger: int, total: int = 5, lado: int = 5) -> Control:
	var d: int = clampi(danger, 0, total)
	var row := UI.box(false, 3)
	row.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var c := perigo_cor(d)
	for i in range(total):
		row.add_child(Gem.make(c if i < d else UI.ARESTA, lado, 1.0, i < d))
	row.tooltip_text = "Perigo %d de %d\nO risco do combate — e o que ele paga em Éter." % [d, total]
	row.mouse_filter = Control.MOUSE_FILTER_STOP
	return row


## QUEM ESTÁ DO OUTRO LADO, agrupado por espécie: [{sp, n, name, el}].
##
## Saiu de `screen_map._enemy_lines` para cá inteiro, sem mudar uma linha da
## lógica — o que muda é que agora existe UM dono, e a preparação pode falar a
## mesma língua sem copiar o código.
static func agrupar(payload: Dictionary) -> Array:
	var ids: Array = []
	if bool(payload.get("boss", false)):
		ids = [String(Db.boss.get("sprite", "coalla"))]
	else:
		var theme: Dictionary = {}
		for t in Db.themes:
			if String(t.get("id", "")) == String(payload.get("theme", "")):
				theme = t
		if theme.is_empty():
			return []
		ids = EnemyGen.compose(theme, int(payload.get("count", 3)),
			int(payload.get("enemy_seed", 1)), float(payload.get("power", 1.0)))
	var count: Dictionary = {}
	for e in ids:
		var id := Db.sp_base_id(String(e))
		count[id] = int(count.get(id, 0)) + 1
	var out: Array = []
	for id in count.keys():
		var sid := String(id)
		var qty: int = int(count[sid])
		out.append({"sp": sid, "n": qty, "name": plural(Db.sp_name(sid), qty),
			"el": String(Db.sp(sid).get("element", "FOGO"))})
	out.sort_custom(func(a, b): return int(a["n"]) > int(b["n"]))
	return out


## "3 Apollos" / "1 Apollo". Uma regra só, para a escolha, a preparação e o
## painel de combate escreverem a mesma frase.
static func plural(nome: String, n: int) -> String:
	return "%d %s" % [n, (nome + "s") if n > 1 else nome]


## O BANDO, em linhas de medalhão + contagem + nome. É a peça que a preparação
## precisa para parar de desenhar medalhões anônimos repetidos.
static func bando(payload: Dictionary, diametro: float = 32.0) -> Control:
	var col := UI.box(true, 4)
	for linha in agrupar(payload):
		var row := UI.box(false, 6)
		var med := MonsterPortrait.medallion(String(linha["sp"]),
			String(linha["el"]), diametro)
		row.add_child(med)
		var l := UI.label(String(linha["name"]), UI.F_BODY, UI.TEXT)
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		row.add_child(l)
		col.add_child(row)
	return col
