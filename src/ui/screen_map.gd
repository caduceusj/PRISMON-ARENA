class_name ScreenMap
extends Control
## A escolha entre DOIS COMBATES.
##
## RECOMPOSIÇÃO DE 15/09. A revisão mediu a tela anterior: título espremido no
## canto superior esquerdo, as duas opções coladas na borda de baixo, o contador
## RODADA 1,5x MAIOR que o título da tela, e 65% do quadro em preto vazio.
##
## As três coisas tinham a mesma causa: a tela era um VBox com `spacer()` no
## meio, e o `spacer` comia tudo o que sobrava. Agora a tela é lida em três
## faixas de altura declarada — cabeçalho, palco, decisão — e o Rancho ocupa o
## palco de verdade, em vez de flutuar atrás de um vazio.
##
## A GRAMÁTICA DO INIMIGO, decidida aqui e registrada desde então: bando como
## TEXTO AGRUPADO ("3 Apollos"), nunca três medalhões repetidos. Desde 15/09 a
## tela SEGUINTE (preparação) fala a mesma língua — antes ela desenhava três
## medalhões idênticos sem contagem nem nome, na mesma run, um clique depois.

signal chosen(node: Dictionary)

var _pair: Array = []

## A SALA. Aço-noite para a escolha comum; ferrugem para a prova final. São as
## duas únicas salas deste momento, e nenhuma delas é a cor de um elemento.
## As duas vêm de `data/paleta.json` desde 17/09 — ver `PickPanel`.
static var SALA: Color:
	get: return UI.cor_da_sala("escolha")
static var SALA_CHEFE: Color:
	get: return UI.cor_da_sala("chefe")

## A ARENA ENTRA NA MATÉRIA PELO MATIZ, NÃO PELA SATURAÇÃO DO `tint`.
##
## As sete arenas de `data/enemies.json` já trazem `tint`, e é dele que a cor de
## cada cartão sai — mas as sete foram pintadas com saturações muito diferentes:
## Campo Magnético tem S 0,49 e Câmara de Estímulos S 0,10. `UI.materia_da_sala`
## multiplica pela saturação da cor que recebe, então usar o `tint` cru faria a
## Câmara chegar à lajota cinco vezes mais fraca que o Campo — e o par "Nevasca
## contra Câmara de Estímulos" voltaria a ser dois cartões idênticos.
##
## Medido no primeiro corte desta leva, com o `tint` cru: as duas lajotas saíram
## (35,31,33) e (31,30,35) — 4 níveis de diferença, indistinguíveis a olho.
##
## Então o `tint` entra aqui NORMALIZADO em saturação: o matiz continua sendo o
## que o dado escolheu (324° para o Solo Vulcânico, 249° para o Campo Magnético,
## 267° para a Nevasca) e QUANTO dele chega à matéria é uma decisão só, a mesma
## para as sete e para o jogo inteiro — `sala_na_materia`, em data/paleta.json.
##
## O `tint` cru continua intacto onde ele é tinta e não matéria: a etiqueta da
## arena em `UI.rules_strip` segue recebendo a cor exatamente como está no JSON.
const ARENA_S := 1.0

## Altura reservada para a faixa da decisão. Declarada, e não resultado de um
## `spacer`: é o que garante que as opções nunca encostem na borda de baixo.
const DECISAO_H := 300.0
const RODAPE := 44.0

const OPCAO_W := 430.0


func setup(pair: Array) -> void:
	_pair = pair


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var boss := _pair.size() == 1
	var sala: Color = SALA_CHEFE if boss else SALA
	add_child(UI.luz_de_sala(sala))

	# O Rancho fica ATRÁS da UI — mas agora num retângulo que TERMINA onde a
	# faixa da decisão começa. Ele centra a equipe em 52% da própria altura, e
	# ocupando a tela inteira ela nascia no meio do quadro, com metade do corpo
	# atrás dos cartões.
	var ranch := RanchView.new()
	ranch.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ranch.offset_top = 132.0
	ranch.offset_bottom = -(DECISAO_H + RODAPE)
	add_child(ranch)

	var col := UI.box(true, 0)
	col.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(col)

	# --- faixa 1: cabeçalho -------------------------------------------------
	col.add_child(UI.spacer(22, false))
	var bn := UI.banner("PROVA FINAL DO ATO" if boss else "ESCOLHA O PRÓXIMO COMBATE", sala)
	bn.custom_minimum_size.x = UI.BANNER_W
	bn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	col.add_child(bn)
	col.add_child(UI.spacer(8, false))
	col.add_child(_contador())

	# --- faixa 2: o palco. A equipe em pé, e nada mais. ---------------------
	# A dica "o mais perigoso paga mais" saiu (autor, 03/09). A regra virou
	# convenção de layout: a opção da DIREITA é sempre a mais perigosa e a
	# que paga mais (garantido em NodeGen.generate_pair). Uma regra que
	# vale sempre se aprende jogando; escrita, ela só ocupa a barra.
	col.add_child(UI.spacer())

	# --- faixa 3: a decisão -------------------------------------------------
	var foot := UI.box(false, 18)
	foot.alignment = BoxContainer.ALIGNMENT_CENTER
	foot.custom_minimum_size = Vector2(0, DECISAO_H)
	col.add_child(foot)
	# O CHEFE TEM UMA OPÇÃO SÓ, e uma opção só não precisa da largura de uma
	# comparação: o cartão único abre para 700 px e a prova final deixa de ser
	# um retângulo de 430 perdido num quadro de 1600 (medido na revisão:
	# 08_chefe.png tinha 2,0% de pixels não-fundo, o menor do jogo).
	var larg: float = OPCAO_W if _pair.size() > 1 else 700.0
	for n in _pair:
		foot.add_child(_option(n, larg))
	col.add_child(UI.spacer(RODAPE, false))


## "RODADA 4 DE 9", e não mais o contador de 34 px.
##
## Ele era a MAIOR tipografia da tela — 34 contra os 26 do título, medido pela
## revisão como "1,5x maior que o título" —, num dado que o jogador não decide
## nada com. Agora é uma pastilha de corpo 15 logo abaixo da faixa, na mesma
## escada de todo rótulo secundário do jogo.
func _contador() -> Control:
	var center := CenterContainer.new()
	var p := UI.card(UI.PANEL, UI.GOLD.darkened(0.45))
	var row := UI.box(false, 8)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	p.add_child(row)
	row.add_child(UI.label("RODADA", UI.F_SMALL, UI.TEXT_DIM))
	row.add_child(UI.label("%d" % Run.node_index, UI.F_BODY, UI.GOLD))
	row.add_child(UI.label("de %d" % Run.total_nodes(), UI.F_SMALL, UI.TEXT_DIM))
	center.add_child(p)
	return center


## Uma opção de combate: um objeto de 430 px com quatro leituras empilhadas —
## quanto paga, quanto dói, com que regras, e contra quem — e o botão de
## compromisso ocupando a base inteira do cartão.
func _option(n: Dictionary, larg: float = OPCAO_W) -> Control:
	var danger := int(n.get("danger", 1))
	var accent: Color = UI.GOLD if danger <= 2 else (UI.WARN if danger <= 4 else UI.BAD)

	# CADA CARTÃO É UM LUGAR (17/09, pedido do autor: "cores diferentes nas
	# escolhas").
	#
	# Os dois cartões eram o MESMO objeto: a lajota neutra da paleta nos dois, a
	# mesma aresta, e a única coisa colorida diferente na tela inteira era a
	# etiqueta da arena — ~90 px de tinta num quadro de 1600x900. Mas a escolha
	# desta tela é justamente entre DOIS LUGARES: cada opção já traz uma arena em
	# `data/enemies.json`, com nome, texto e `tint` próprios desde sempre.
	#
	# Agora a MATÉRIA do cartão é a do lugar: a lajota do Solo Vulcânico é
	# vinho e a do Campo Magnético é violeta-elétrico, e as duas se leem como
	# dois lugares antes de o olho chegar ao texto.
	#
	# O QUE NÃO MUDOU, DE PROPÓSITO: o feixe da aresta, a régua da célula de
	# perigo e as estrelas continuam saindo do PERIGO, não da arena. A arena é
	# onde você está; o perigo é o que pode acontecer com você — e o estado tem
	# de gritar mais alto que a matéria (GDD 21.4). Trocar o feixe pela cor da
	# arena teria apagado a única leitura de risco que sobrevive de relance.
	var miolo := UI.materia_da_sala(UI.PANEL, _cor_da_arena(n))
	# A célula de PERIGO existe no kit e não era usada em lugar nenhum do jogo:
	# régua de acento no pé, onde o olho termina a leitura da ficha.
	var card := PanelContainer.new()
	# a aresta segue a regra antiga ao pixel: acento só na célula de perigo,
	# `UI.LINE` (o que `UI.card()` passava) nas opções de passagem
	card.add_theme_stylebox_override("panel", UI.frame(
		UI.C_DANGER if danger >= 4 else UI.C_PANEL,
		accent if danger >= 4 else UI.LINE, 12, 8, miolo))
	card.custom_minimum_size = Vector2(larg, DECISAO_H)
	# SEM DICA NO CARTAO (autor, 04/09: "tira esse tooltip que fala o nome da
	# arena e qual a dificuldade dela, ele e desnecessario"). Ele repetia o que
	# o proprio cartao ja mostra — o titulo esta na faixa do topo, o perigo nas
	# estrelas, a arena na etiqueta logo abaixo. E, por envolver a etiqueta, era
	# ele que aparecia quando se queria ler a dica DELA.
	var v := UI.box(true, 6)
	card.add_child(v)

	var top := UI.box(false, 10)
	v.add_child(top)
	var reward := UI.box(false, 5)
	reward.add_child(Icons.node("ether", UI.icon_px(UI.F_H2)))
	reward.add_child(UI.label(str(int(n.get("rewards", {}).get("ether", 0))),
		UI.F_H2, UI.GOLD))
	top.add_child(reward)
	top.add_child(UI.spacer())
	top.add_child(UI.label(UI.stars(danger), UI.F_H2, accent))

	v.add_child(UI.hsep())

	# AS REGRAS DESTA BRIGA, antes de aceitar. Perigo em estrelas diz "quanto
	# dói"; isto diz "por quê" — e é o que faz escolher entre duas opções ser
	# uma decisão e não um sorteio de números.
	v.add_child(UI.rules_strip(n.get("payload", {}), UI.F_SMALL))

	# E O QUE A REGRA FAZ, escrito. O texto já existe em data/enemies.json e só
	# vivia no tooltip da etiqueta — ou seja, só era lido por quem já soubesse
	# que havia algo para ler ali. É a diferença entre "Solo Vulcânico" (um
	# nome) e "a cada 4 s todos ganham 2 UA de Combustão" (uma decisão).
	for t in _regras_texto(n):
		v.add_child(UI.wrap(t, UI.F_SMALL, UI.TEXT_DIM))

	# quem está do outro lado, uma linha por espécie
	for line in _enemy_lines(n):
		var row := UI.box(false, 8)
		# medalhao de 32: `make(.., 24)` desenhava o corpo com 24 px de altura
		# (um pontinho, nas criaturas pequenas) e com largura variavel por
		# especie, entao "3 Apollos" e "3 Pinto-Raios" comecavam em x diferentes
		var med := MonsterPortrait.medallion(String(line["sp"]), String(line["el"]), 32.0)
		med.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(med)
		# "1 O Devorador" lia como erro de concordância. Um corpo só dispensa o
		# número; é o plural que precisa contar.
		var nl := UI.label(rotulo_bando(line), UI.F_BODY, UI.TEXT)
		nl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		row.add_child(nl)
		v.add_child(row)

	v.add_child(UI.spacer())

	# O BOTÃO É VERDE E DIZ "ESCOLHER".
	#
	# Duas correções num lugar só. (1) A cor vinha do PERIGO — dourado, âmbar ou
	# vermelho conforme a opção —, então o mesmo ato tinha três cores na mesma
	# tela; `docs/pecas/botoes.png`, gerada do próprio código, define confirmar =
	# verde, e `UI.button_confirmar` ainda acrescenta um SEGUNDO canto cortado,
	# que é o sinal que sobrevive a escala de cinza. (2) O rótulo era "LUTAR!",
	# o mesmo da tela seguinte: dois botões idênticos para dois atos diferentes
	# (escolher o nó, e depois entrar nele). Aqui se ESCOLHE; lá se LUTA.
	var go := UI.button_confirmar("  ESCOLHER  ", UI.F_H2)
	go.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	go.pressed.connect(func(): chosen.emit(n))
	v.add_child(go)

	return card


## "4 Apollos", mas só "O Devorador" quando é um corpo só. Público porque a
## preparação usa a MESMA gramática (é o ponto do achado).
static func rotulo_bando(line: Dictionary) -> String:
	var q := int(line["n"])
	return String(line["name"]) if q <= 1 else "%d %s" % [q, String(line["name"])]


## A COR DO LUGAR DESTE COMBATE, lida do dado.
##
## `tint` já existe no array `arenas` de `data/enemies.json` e já tem as sete
## cores — até hoje ele só pintava a etiqueta de 90 px. O chefe não tem arena
## sorteada: ele recebe a própria sala (ferrugem), que é o lugar dele.
func _cor_da_arena(n: Dictionary) -> Color:
	var payload: Dictionary = n.get("payload", {})
	var arena: Dictionary = Db.arenas.get(String(payload.get("arena", "")), {})
	if arena.is_empty():
		return SALA_CHEFE if bool(payload.get("boss", false)) else SALA
	var c := Color(String(arena.get("tint", "#8f88a8")))
	return Color.from_hsv(c.h, ARENA_S, c.v, c.a)


func _regras_texto(n: Dictionary) -> Array:
	var payload: Dictionary = n.get("payload", {})
	var out: Array = []
	var arena: Dictionary = Db.arenas.get(String(payload.get("arena", "")), {})
	if not arena.is_empty():
		out.append(String(arena.get("text", "")))
	for mid in payload.get("mods", []):
		for m in Db.modifiers:
			if String(m["id"]) == String(mid):
				out.append("%s — %s" % [String(m["name"]), String(m["text"])])
	return out


## Agrupa a lista inimiga por espécie: "3 Hipocampos" em vez de três medalhões.
## É a linha "10 Bebês" do How Many Dudes — texto, não imagem repetida.
## O CHEFE TEM NOME. Até 15/09 o nó do chefe caía no ramo comum e a linha dizia
## "1 Coalla" — o `sprite` que O Devorador empresta —, com a escolta invisível.
## A escolta usa semente FIXA 1337 em `EnemyGen.build_boss`, então dá para
## mostrá-la aqui exatamente como ela vai nascer na arena.
static func enemy_lines(n: Dictionary) -> Array:
	var payload: Dictionary = n.get("payload", {})
	var ids: Array = []
	if bool(payload.get("boss", false)):
		var b: Dictionary = Db.boss
		var out_boss: Array = [{"sp": String(b.get("sprite", "coalla")), "n": 1,
			"name": String(b.get("name", "Chefe")),
			"el": String(b.get("element", "NATUREZA"))}]
		var esc: Dictionary = b.get("escort", {})
		if not esc.is_empty():
			for t in Db.themes:
				if String(t.get("id", "")) != String(esc.get("theme", "")):
					continue
				ids = EnemyGen.compose(t, int(esc.get("count", 2)), 1337,
					float(esc.get("power", 1.2)))
				break
			out_boss.append_array(_agrupar(ids))
		return out_boss
	else:
		var theme: Dictionary = {}
		for t in Db.themes:
			if String(t.get("id", "")) == String(payload.get("theme", "")):
				theme = t
		if theme.is_empty():
			return []
		ids = EnemyGen.compose(theme, int(payload.get("count", 3)),
			int(payload.get("enemy_seed", 1)), float(payload.get("power", 1.0)))
	return _agrupar(ids)


static func _agrupar(ids: Array) -> Array:
	var count: Dictionary = {}
	for e in ids:
		var id := Db.sp_base_id(String(e))
		count[id] = int(count.get(id, 0)) + 1
	var out: Array = []
	for id in count.keys():
		var sid := String(id)
		var nm := Db.sp_name(sid)
		var qty := int(count[sid])
		out.append({"sp": sid, "n": qty,
			"name": (nm + "s") if qty > 1 else nm,
			"el": String(Db.sp(sid).get("element", "FOGO"))})
	out.sort_custom(func(a, b): return int(a["n"]) > int(b["n"]))
	return out


func _enemy_lines(n: Dictionary) -> Array:
	return enemy_lines(n)
