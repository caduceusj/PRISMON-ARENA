class_name RosterRail
extends PanelContainer

## Altura NATIVA das texturas de barra (assets/ui/bar_*.png sao 18 px).
const BAR_H := 18
## O trilho do elenco, fixo na esquerda — o painel vermelho do How Many Dudes.
##
## Antes o elenco só existia na tela de preparação; nas outras o jogador
## decidia às cegas. Agora ele acompanha a run inteira: escolher combate,
## recrutar, comprar e aceitar um evento são decisões SOBRE a equipe, e a
## equipe precisa estar à vista enquanto se decide.

const W := 288.0

var _list: VBoxContainer
var _title: Label


func _ready() -> void:
	custom_minimum_size = Vector2(W, 0)
	# MATERIA NEUTRA, e nao o vermelho #2a1220 de antes. Este painel e a moldura
	# permanente da run: 288 x 864 px, a segunda maior superficie continua do
	# jogo depois da arena. Pintado num matiz, ele sozinho estoura o "saturado
	# nunca acima de 5% da tela" da direcao de arte — e disputa o olho com a
	# unica coisa colorida que precisa ser vista aqui, que e o ELEMENTO de cada
	# Cara. A cor entra so pelo feixe da ficha (ver `_card`).
	add_theme_stylebox_override("panel", UI.panel(UI.MESA, 0, UI.LINE))
	var col := UI.box(true, 7)
	add_child(col)

	_title = UI.label("", UI.F_H2, UI.GOLD, HORIZONTAL_ALIGNMENT_CENTER)
	col.add_child(_title)
	var sep := ColorRect.new()
	sep.color = UI.LINE
	sep.custom_minimum_size = Vector2(0, 1)
	col.add_child(sep)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	col.add_child(scroll)
	_list = UI.box(true, 6)
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_list)

	Run.team_changed.connect(rebuild)
	Run.resources_changed.connect(rebuild)
	rebuild()


func rebuild() -> void:
	if _list == null:
		return
	for c in _list.get_children():
		_list.remove_child(c)
		c.queue_free()
	_title.text = "%d/%d Caras" % [Run.bond_used(), Run.bond_total()]
	if Run.team.is_empty():
		_list.add_child(UI.label("sem elenco ainda", UI.F_SMALL, UI.TEXT_DIM,
			HORIZONTAL_ALIGNMENT_CENTER))
		return
	for u in Run.team:
		_list.add_child(_card(u))


## Cartão do How Many Dudes: cabeçalho com retrato + nome, e uma tira de
## estatísticas por baixo. Números crus, sem rótulo escrito — o ícone rotula.
func _card(u: UnitInstance) -> Control:
	var el := u.element()
	var c := Db.el_color(el)
	var card := UI.box(true, 0)

	# O FEIXE DO ELEMENTO no lugar da lajota vermelha. `frame` pinta o corte e a
	# barra de 3 px da aresta esquerda com a cor crua do elemento e deixa o
	# miolo no degrau neutro — a leitura de Afinidade acontece no mesmo lugar em
	# que ela acontece em toda outra peça do kit.
	var head := PanelContainer.new()
	head.add_theme_stylebox_override("panel", UI.frame(UI.C_PANEL, c, 10, 6))
	head.tooltip_text = _detail(u)
	head.mouse_filter = Control.MOUSE_FILTER_STOP
	# o som do hover acompanha a DICA: estas fichas não são clicáveis, e o único
	# gesto que elas respondem é justamente parar o cursor em cima para ler
	head.mouse_entered.connect(func() -> void: UI.som("hover"))
	card.add_child(head)
	var hrow := UI.box(false, 7)
	head.add_child(hrow)
	# medalhao de lado fixo: com `make` cada ficha do trilho tinha uma
	# largura de retrato diferente e os nomes nao alinhavam na coluna
	var port := MonsterPortrait.medallion(u.species_id, el, 32.0)
	port.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hrow.add_child(port)

	# O CONSERTO MAIS BARATO DO RELATORIO (revisao 15/09, achado ALTO).
	#
	# `clip_text` trava a largura MINIMA do Label em 1 px -- medido em
	# tools/fit_probe.gd e escrito por extenso em combat_panel.gd:86 e
	# screen_prep.gd:449. Num HBoxContainer o filho so recebe mais que o seu
	# minimo se tiver EXPAND: sem a bandeira, este rotulo nascia com 1 px, e o
	# `UI.spacer()` que vinha depois (esse sim EXPAND) ficava com TODA a folga
	# da linha. Resultado nos prints: um traco de 2 px no lugar do nome, em
	# toda ficha, em 288 x 864 px de moldura que acompanha a run inteira.
	# Medido depois do conserto: o rotulo passa a receber 205 px.
	#
	# EXPAND_FILL entrega a folga ao rotulo e o spacer some -- ele existia para
	# empurrar o nome para a esquerda, e um Label em FILL ja comeca na esquerda.
	# O `clip_text` continua, e agora faz o trabalho dele: cortar o nome
	# comprido em vez de esticar a coluna.
	var rname := UI.label(u.display_name(), UI.F_BODY, c.lightened(0.35))
	rname.clip_text = true
	rname.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rname.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hrow.add_child(rname)

	# LIMPEZA (31/08): a ficha tinha quatro números soltos (HP/ATK/DEF/VEL) mais
	# dois contadores (◆ itens, ◇ pratos) — seis coisas por Cara, seis Caras na
	# tela. Sobrou o que se lê de relance: NOME e VIDA. Os números continuam
	# todos no tooltip, que é onde se compara com calma.
	var body := PanelContainer.new()
	body.add_theme_stylebox_override("panel", UI.frame(UI.C_INSET, UI.LINE, 6, 4))
	card.add_child(body)
	var bcol := UI.box(true, 3)
	body.add_child(bcol)
	var bar := PrismaBar.make(_hp_fill(u), BAR_H)
	bar.set_value(u.hp_ratio, 1.0)
	bcol.add_child(bar)
	bcol.add_child(_vagas(u))
	return card


## QUANTO CABE AINDA NESTA CRIATURA — UMA LINHA ESCRITA, sem iconezinhos.
##
## Isto NAO desfaz a limpeza de 31/08. O que saiu dali eram quatro estatísticas
## de combate (HP/ATK/DEF/VEL), que já aparecem no campo e não decidem nada fora
## dele. Estes dois números decidem: o trilho fica visível justamente nas telas
## de Feira, Cozinha, Poder e Troca — é ali que o jogador compra PARA a equipe —
## e "quem ainda tem vaga de item" e "quem ainda tem estômago" não existiam em
## lugar nenhum da tela em que se gasta o Éter.
##
## == O QUE MUDOU EM 16/09 ==
##
## Eram dois pares "ícone 16 px + 0/3", e o autor olhou o trilho e viu "0/3 0/3"
## — quatro números sem nome, com dois desenhos de 16 px no meio deles fazendo
## as vezes de rótulo. Uma bigorna minúscula e uma fogueira minúscula, num corpo
## de 18 px, do lado de dois números idênticos: para saber qual era qual era
## preciso parar o cursor em cima. O desenho custava mais atenção do que a
## palavra que ele substituía.
##
## Agora a linha diz "0/3 itens · 0/3 pratos". Mesma altura, mesma cor apagada,
## dois desenhos a menos por ficha — e em seis fichas isso são doze ícones que
## saíram do trilho. O cartão continua sendo NOME e VIDA, e isto é o rodapé dele.
func _vagas(u: UnitInstance) -> Control:
	var itens: int = u.items.size()
	var slots: int = u.item_slots()
	var comidos: int = u.dishes_eaten()
	var estomago: int = u.estomago()
	var l := UI.label("%d/%d itens · %d/%d pratos"
		% [itens, slots, comidos, estomago], UI.F_SMALL, UI.TEXT_DIM)
	# clip_text + EXPAND_FILL andam em par (regra do lint, e o achado do trilho
	# vazio de 15/09): sem o EXPAND o Label nasceria com 1 px de largura.
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.clip_text = true
	# SEM DICA PRÓPRIA, de propósito. A dica daqui dizia "Itens 0 de 3 ·
	# Estômago 0 de 3" — exatamente o que a linha já tem escrito, por extenso,
	# a 18 px, sem precisar de cursor nenhum. É o caso que o autor apontou em
	# 16/09: *"não precisa dessas caixas de texto se o overlay já mostra"*.
	# O detalhe que a linha NÃO tem (itens e pratos pelo nome) continua na dica
	# do cabeçalho da ficha, logo acima — ver `_detail`.
	return l


static func _hp_fill(u: UnitInstance) -> String:
	if u.hp_ratio > 0.6:
		return "green"
	return "yellow" if u.hp_ratio > 0.25 else "red"


func _detail(u: UnitInstance) -> String:
	var s := u.stats()
	# `role_name` e nao `role()`: o id do Papel vive sem acento porque e chave de
	# filtro em enemy_gen e run_state, e era ele que aparecia na dica ("Guardiao")
	var lines: Array = ["%s — %s · %s · %s" % [u.display_name(),
		Db.el_name(u.element()), Db.role_name(u.role()), u.stance()]]
	lines.append("HP %d · ATK %d · DEF %d · VEL %.1f · PE %d · Vontade %d"
		% [int(s["hp"]), int(s["atk"]), int(s["def"]), float(s["vel"]),
		int(s["pe"]), int(s["vontade"])])
	var ult: Dictionary = u.ult()
	if not ult.is_empty():
		lines.append("")
		lines.append("⚡ %s — %s" % [String(ult.get("name", "")), String(ult.get("text", ""))])
	for it in u.items:
		lines.append("◆ %s — %s" % [String(Db.items[it]["name"]), String(Db.items[it]["text"])])
	for d in u.dishes:
		lines.append("◇ %s — %s" % [String(Db.dishes[d]["name"]), String(Db.dishes[d]["text"])])
	# O "Estômago 0/3" saiu daqui: a própria ficha escreve "0/3 pratos" duas
	# linhas abaixo do cabeçalho, e uma dica que repete o que está à vista é o
	# ruído que o autor pediu para tirar. O que sobra na dica é o que a ficha
	# NÃO mostra — números de combate, o Ativo, e item/prato pelo nome.
	return "\n".join(lines)
