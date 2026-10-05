class_name CombatPanel
extends PanelContainer
## O painel lateral do combate — a leitura da equipe enquanto a briga corre.
##
## Antes essa informação só existia sobre a cabeça da unidade: uma barrinha de
## 5 px e um nome minúsculo, disputando espaço com os números de dano. Quem
## está morrendo, quem está com qual aura e de quem é a ultimate que vai sair
## eram perguntas que o jogador não conseguia responder no meio da luta.
##
## Aqui cada Cara ocupa uma ficha larga: vida em barra grande com número,
## carga da ultimate e as auras ativas. O que a criatura está fazendo agora
## saiu daqui em 16/09 — o campo já mostra isso em movimento (ver o fim do
## arquivo).
##
## GEOMETRIA (revisão 02/09, prints do autor). A ficha errava três coisas ao
## mesmo tempo, e cada uma tinha uma causa diferente:
##
##   1. O NÚMERO DA VIDA transbordava a barra. Ele estava desenhado POR CIMA de
##      uma barra de 20 px, num corpo que o snap resolve para 26 — não cabia,
##      nunca ia caber. Agora o número tem coluna própria, à direita do nome:
##      não existe mais como o texto e a barra se sobreporem.
##   2. A BARRA DE VIDA e a de ultimate não se alinhavam. A de vida usava
##      `set_anchors_preset`, que muda as âncoras e NÃO mexe nos offsets — o nó
##      ficava com o tamanho antigo dentro do wrapper, deslocado em relação à
##      de ultimate, que era filha direta da coluna. As duas agora são filhas
##      da mesma coluna, com a mesma largura por construção.
##   3. As ALTURAS esticavam a arte. As texturas de barra são 18 px de altura;
##      20 e 8 px são 1.11x e 0.44x, frações que borram o traço. Agora as duas
##      barras têm 18 — escala 1:1.

## A FICHA EMAGRECEU (autor, 16/09: "o painel da equipe cresceu para quatro
## fichas e encosta no topo"; "simplifique mais como essas informacoes sao
## mostradas").
##
## A conta que mandava: o teto de Vinculo e CINCO corpos, e cinco fichas de
## 104 px mais o cabecalho e a linha do "CONTRA" davam 693 px numa coluna de
## 740 — ou seja, cabiam por 23 px de cada lado, sem margem declarada e sem
## folga nenhuma para uma linha de "CONTRA" que quebre em duas. Encostado na
## borda de cima, o CenterContainer entrega a primeira ficha cortada.
##
## O QUE SAIU E O QUE FICOU. Saiu a LINHA DE ESTADO ("procurando alvo", "indo
## ate Apollo", "armando o golpe"): cinco linhas de texto que mudam a cada
## passo da simulacao, dizendo em palavras o que o campo ja mostra em
## movimento — e a queixa do autor e literalmente sobre caixa de texto que
## repete o que outra camada ja mostra. O nome da ultimate, que morava nessa
## linha, virou a DICA da ficha: continua consultavel, deixou de gritar.
##
## Ficou o que so existe aqui: quem e (medalhao e nome), quanto falta (barra
## de vida grande e o numero exato), quanto falta para a ultimate (a segunda
## barra) e quais auras estao em cima do bicho (os pontos).
##
## Resultado medido em `tools/combate_cheio_probe.gd`: 693 -> 561 px com CINCO
## fichas, dentro de uma coluna que agora tambem reserva 14 px de margem.
const W := 336.0          # painel; a ficha ocupa a largura inteira dele
const NUM_W := 84.0       # coluna do número de vida, à direita do nome
## 32 E A ESCALA NATIVA DO MEDALHAO (os icones e as pecas sao 32 px; ver
## UI.icon_px). 44 reamostrava a arte em 1,375x — fracao quebrada em pixel art
## — e ainda era quem definia a altura da ficha inteira, porque o retrato e
## mais alto que as duas linhas de texto ao lado dele.
const PORTRAIT := 32.0
const BAR_H := 18         # altura NATIVA das texturas de barra (assets/ui/bar_*.png)

var sim: CombatSim
var _rows: Dictionary = {}     # id da unidade -> Dictionary de nós
var _list: VBoxContainer
var _contra: Label


func _ready() -> void:
	custom_minimum_size = Vector2(W, 0)
	# materia neutra (ver RosterRail._ready): o painel do combate divide a tela
	# com a arena, que e o unico lugar do jogo onde a cor tem de queimar
	add_theme_stylebox_override("panel", UI.panel(UI.MESA, 0, UI.LINE))
	var col := UI.box(true, 6)
	add_child(col)
	col.add_child(UI.label("SUA EQUIPE", 11, UI.TEXT_DIM))
	_list = UI.box(true, 6)
	col.add_child(_list)

	# CONTRA QUEM, nas mesmas palavras das duas telas anteriores.
	#
	# A escolha de combate diz "3 Apollos"; a preparação desenha três medalhões
	# mudos; e aqui, na briga, a oposição não existia como texto em lugar nenhum
	# — o jogador só tinha os rótulos de 11 px em cima das criaturas, que é
	# exatamente o que a revisão mediu como ilegível. A contagem vem VIVA: ela
	# cai enquanto o combate corre, e é o placar que faltava.
	col.add_child(UI.spacer(4, false))
	_contra = UI.label("", 11, UI.TEXT_DIM)
	_contra.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(_contra)
	_build()


func _build() -> void:
	if sim == null:
		return
	for u in sim.units:
		if u.side != 0:
			continue
		# COR CRUA no `border`: `frame()` queima o feixe sozinho desde 15/09, e
		# escurecer aqui antes só devolvia o brilho travado que a revisão mediu
		# ("a cor virou chave de consulta e nunca clima"). O miolo fica na
		# lajota neutra — a ficha é matéria, o elemento é o feixe dela.
		var card := UI.card(UI.LAJOTA, Db.el_color(u.element))
		# sem largura mínima própria: a ficha ocupa o que o painel der. A versão
		# anterior pedia W - 18 = 282 px dentro de uma coluna de 276 e empurrava
		# o painel para fora da largura declarada.
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var v := UI.box(true, 4)
		card.add_child(v)

		var head := UI.box(false, 8)
		v.add_child(head)
		# MEDALHAO, nao `make`: `make` tem largura dependente da especie, e o
		# nome de cada ficha comecava num x diferente. O medalhao e quadrado
		# de lado fixo, entao a coluna do nome e a mesma em todas as fichas.
		var port := MonsterPortrait.medallion(u.species_id, u.element, PORTRAIT)
		port.mouse_filter = Control.MOUSE_FILTER_IGNORE
		port.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		head.add_child(port)

		# UMA LINHA SO, e ela e a ordem de leitura da ficha: quem, em que
		# estado, quanto falta. Eram duas linhas porque a segunda carregava o
		# texto de estado; sem ele, as auras e a coroa cabem ao lado do nome e a
		# ficha perde altura sem perder um dado sequer.
		var line1 := UI.box(false, 8)
		line1.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		line1.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		head.add_child(line1)
		# clip_text trava a largura minima do Label em 1 px (medido em
		# fit_probe): sem ele o nome mais comprido da equipe definiria a
		# largura do painel, e o painel pulsaria a cada troca de equipe.
		var name_l := UI.label(u.display_name, UI.F_BODY,
			Db.el_color(u.element).lightened(0.35))
		name_l.clip_text = true
		name_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		line1.add_child(name_l)

		# auras como PONTOS coloridos, nao como chips com numero: o que importa
		# no relance e "tem aura de que elemento", nao "tem 6.4 UA de
		# Encharcado" -- esse detalhe esta na dica.
		var auras := UI.box(false, 4)
		auras.alignment = BoxContainer.ALIGNMENT_END
		auras.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		auras.custom_minimum_size = Vector2(UI.icon_px(11) * 2.0 + 4.0, UI.icon_px(11))
		line1.add_child(auras)

		# O RAIO SAIU DO TEXTO (revisao 15/09). O glifo nao existe em nenhuma
		# fonte do projeto -- vem de um fallback do sistema operacional, que muda
		# de maquina para maquina (assets/CREDITOS.md). Aqui ele e um icone do
		# atlas que acende junto com a ultimate; escondido, nao ocupa espaco
		# nenhum no HBox, entao a linha nao muda de largura por causa dele.
		var ic_ult := Icons.node("g_crown", UI.icon_px(11), UI.GOLD)
		ic_ult.visible = false
		ic_ult.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		line1.add_child(ic_ult)

		var hp_txt := UI.label("", 11, UI.TEXT, HORIZONTAL_ALIGNMENT_RIGHT)
		hp_txt.custom_minimum_size = Vector2(NUM_W, 0)
		hp_txt.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		line1.add_child(hp_txt)

		# O NOME DA ULTIMATE VIRA DICA. Ele morava na linha de estado, que saiu;
		# aqui ele continua ao alcance de quem quiser CONSULTAR, sem gastar uma
		# linha por criatura enquanto ninguem perguntou nada.
		card.tooltip_text = "%s - %s" % [u.display_name,
			String(u.ult.get("name", "sem ultimate"))]

		# as duas barras são irmãs na MESMA coluna: mesma largura, sem âncora
		var bar := PrismaBar.make("green", BAR_H)
		v.add_child(bar)
		var ult := PrismaBar.make("yellow", BAR_H)
		v.add_child(ult)

		_list.add_child(card)
		_rows[u.id] = {"card": card, "bar": bar, "hp": hp_txt, "ult": ult,
			"auras": auras, "ult_ic": ic_ult, "nome": name_l}


## Chamado pela tela de combate a cada quadro. Só toca no que mudou.
func refresh() -> void:
	if sim == null:
		return
	for u in sim.units:
		if not _rows.has(u.id):
			continue
		var r: Dictionary = _rows[u.id]
		var ratio: float = 0.0 if u.hp_max <= 0.0 else clampf(u.hp / u.hp_max, 0.0, 1.0)
		r["bar"].set_value(maxf(u.hp, 0.0), u.hp_max)
		var want := "green" if ratio > 0.45 else ("yellow" if ratio > 0.2 else "red")
		if r["bar"].fill_name != want:
			r["bar"].fill_name = want
			r["bar"].reload()
		r["hp"].text = "%d / %d" % [maxi(roundi(u.hp), 0), roundi(u.hp_max)]
		r["hp"].add_theme_color_override("font_color",
			UI.BAD.lightened(0.2) if ratio <= 0.2 else UI.TEXT)
		r["ult"].set_value(u.ult_energy, Db.combat("ultimate_max", 100.0))
		var pronta: bool = u.ult_energy >= Db.combat("ultimate_max", 100.0)
		# A ULTIMATE PRONTA ACENDE O NOME, e nao uma linha de texto a mais: e o
		# mesmo dado (esta pronta) com um elemento a menos na ficha.
		r["ult_ic"].visible = pronta and r["ult_ic"].texture != null
		var cor_nome: Color = UI.GOLD if pronta 			else Db.el_color(u.element).lightened(0.35)
		if Color(r["nome"].get_theme_color("font_color")) != cor_nome:
			r["nome"].add_theme_color_override("font_color", cor_nome)
		r["card"].modulate = Color(1, 1, 1, 1.0 if u.alive else 0.42)
		_sync_auras(u, r["auras"])
	_sync_contra()


## "3 Apollos · 1 Sheep", com a contagem dos que ainda estão de pé.
##
## A gramática é a de `RunRibbon.plural` — a mesma que a tela de escolha usa
## para dizer quem está do outro lado. Só o texto é remontado, e só quando ele
## muda: isto roda a cada quadro.
func _sync_contra() -> void:
	if _contra == null or sim == null:
		return
	var vivos: Dictionary = {}
	for u in sim.units:
		if u.side == 0 or not u.alive:
			continue
		# agrupa por ESPECIE e não por `display_name`: o pedido aberto de
		# desambiguar cópias ("Pinto-Raio II") faria cada corpo virar um grupo
		# de um. O chefe não está em species.json, e aí o nome dele é o que a
		# própria unidade carrega.
		var base := Db.sp_base_id(u.species_id)
		var nome: String = Db.sp_name(base) if not Db.sp(base).is_empty() \
			else String(u.display_name)
		vivos[nome] = int(vivos.get(nome, 0)) + 1
	var partes: Array = []
	for nome in vivos:
		partes.append(RunRibbon.plural(String(nome), int(vivos[nome])))
	var txt: String = "CONTRA: " + (" · ".join(partes) if not partes.is_empty()
		else "ninguém de pé")
	if _contra.text != txt:
		_contra.text = txt


## A LINHA DE ESTADO SAIU DA FICHA (autor, 16/09). `_doing` escrevia
## "procurando alvo", "indo ate Apollo", "armando o golpe" — uma linha por
## criatura, reescrita a cada quadro, dizendo em palavras o que o campo ja
## mostra em movimento. Com cinco fichas eram cinco textos piscando ao lado
## de cinco barras que nao piscam, e era o texto que ganhava o olho.
##
## O que so ela dizia continua na tela por outro caminho: a ultimate pronta
## acende o nome e a coroa, o nocaute apaga a ficha inteira, e o nome da
## ultimate esta na dica do cartao.


func _sync_auras(u: SimUnit, box: BoxContainer) -> void:
	var want: Array = []
	for a in u.aura.auras:
		want.append(a.aura_id)
	if String(box.get_meta("sig", "")) == "|".join(want):
		return
	box.set_meta("sig", "|".join(want))
	for c in box.get_children():
		box.remove_child(c)
		c.queue_free()
	for a in u.aura.auras:
		box.add_child(Icons.element(String(a.element), UI.icon_px(11)))
