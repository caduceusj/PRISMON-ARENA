class_name ItemDock
extends PanelContainer
## A doca de itens, na borda DIREITA — os ícones empilhados dos wireframes do
## How Many Dudes. Relíquias e itens equipados deixam de existir só como um
## contador no topo ("RELÍQUIAS 3") e passam a ser objetos visíveis, cada um
## com seu texto no tooltip.

const W := 74.0
const W_DETAIL := 224.0

## No combate a doca é uma tira de ícones: espaço é caro e o jogador só precisa
## lembrar do que tem. Na preparação ela abre (`detailed`) e mostra o RETRATO DO
## DONO ao lado de cada item — ali a pergunta é "quem carrega o quê", e isso não
## pode viver só no tooltip de quem for passar o mouse.
var detailed := false

var _list: VBoxContainer


func _ready() -> void:
	custom_minimum_size = Vector2(W_DETAIL if detailed else W, 0)
	# materia neutra, como o trilho e o painel de combate: a doca e moldura
	add_theme_stylebox_override("panel", UI.panel(UI.MESA, 0, UI.LINE))
	var col := UI.box(true, 5)
	add_child(col)
	_list = col
	Run.team_changed.connect(rebuild)
	Run.resources_changed.connect(rebuild)
	rebuild()


func rebuild() -> void:
	if _list == null:
		return
	for c in _list.get_children():
		_list.remove_child(c)
		c.queue_free()

	if not Run.relics.is_empty():
		_list.add_child(_tag("RELÍQUIAS" if detailed else "RELÍQ."))
		for r in Run.relics:
			_list.add_child(_relic_slot(String(r),
				"%s\n%s" % [String(Db.relics[r]["name"]), String(Db.relics[r]["text"])],
				Color("#c9a8ff")))

	var owned: Array = []
	var slots_totais: int = 0
	for u in Run.team:
		slots_totais += u.item_slots()
		for it in u.items:
			owned.append({"id": String(it), "who": u.display_name(),
				"species": u.species_id, "element": u.element()})
	if not owned.is_empty():
		# O CONTADOR ENTROU NO RÓTULO, e as vagas saíram da doca (ver a nota de
		# `_tag_itens`). "ITENS 2/6" diz as quatro vagas livres numa linha de
		# texto; a fileira de quadradinhos que dizia o mesmo saiu daqui.
		_list.add_child(_tag_itens(owned.size(), slots_totais))
		for o in owned:
			var id := String(o["id"])
			# A DICA DIZ O QUE A LINHA NÃO DIZ.
			#
			# Na doca ABERTA o nome do item e o retrato do dono já estão
			# desenhados na linha; repetir "Presa Rachada — em Sheep" numa caixa
			# escura por cima deles é o ruído que o autor apontou em 16/09. Lá a
			# dica fica só com o EFEITO. Na doca FECHADA o que existe é um ícone
			# de 32 px e mais nada — ali o "em quem" continua sendo a única
			# forma de saber de quem é.
			var nome := String(Db.items[id]["name"])
			var efeito := String(Db.items[id]["text"])
			if detailed:
				_list.add_child(_slot_detail(id, o, "%s\n%s" % [nome, efeito]))
			else:
				_list.add_child(_slot(Icons.item(id, 32.0),
					"%s — em %s\n%s" % [nome, String(o["who"]), efeito], UI.GOLD))

	# Doca vazia nao existe: uma caixinha escrita "VAZIO" flutuando na borda e
	# exatamente o tipo de informacao que so ocupa espaco. Ela aparece quando
	# houver o primeiro item.
	visible = not (Run.relics.is_empty() and owned.is_empty())


## "ITENS 2/6" — O CONTADOR NO LUGAR DA FILEIRA DE QUADRADINHOS.
##
## Autor, 16/09: *"o lugar que mostra os slots livres não precisa mostrar os
## quadradinhos, só dizer os slots restantes"*.
##
## Aqui viviam até quatro vagas por linha, cada uma uma célula 9-patch de
## 30 px com aresta tracejada — uma fila de buracos desenhados para dizer um
## número que cabe em nove caracteres. A leitura que elas davam ("ainda cabe
## item em alguém?") é exatamente a subtração `total - usados`, e a subtração
## agora está escrita.
##
## O DETALHE — quem tem vaga e quantas — foi para a consulta. Ele não sumiu
## porque a resposta "em QUEM cabe" é o que decide a compra na Feira; ele só
## deixou de ocupar moldura permanente. O trilho da esquerda também escreve
## isso por criatura, e é lá que o jogador compara.
func _tag_itens(usados: int, total: int) -> Control:
	# SÓ NA DOCA ABERTA o contador aparece. No combate a doca é uma tira de
	# 74 px e ninguém equipa no meio da briga: "quantas vagas sobram" não decide
	# nada ali, e um "2/6" solto numa coluna estreita ainda obrigaria o jogador
	# a adivinhar se a razão é de item ou de relíquia.
	var rotulo := "ITENS"
	if detailed:
		rotulo = "ITENS %d/%d" % [usados, total]
	var l := _tag(rotulo)
	var livres: int = maxi(total - usados, 0)
	var quem: Array = []
	for u in Run.team:
		var vagas: int = maxi(u.item_slots() - u.items.size(), 0)
		if vagas > 0:
			quem.append("%s %d" % [u.display_name(), vagas])
	# A DICA NÃO REPETE O RÓTULO. "ITENS 3/9" já está escrito a 18 px logo
	# abaixo do cursor; o que a consulta acrescenta é EM QUEM cabe, que é a
	# resposta que decide a compra na Feira e a única que não cabe no rótulo.
	var linhas: Array = ["As vagas de item da equipe"]
	if livres > 0:
		linhas.append("Ainda cabe em: %s" % ", ".join(quem))
	else:
		linhas.append("Nenhuma vaga livre — %d de %d ocupadas" % [usados, total])
	l.tooltip_text = "\n".join(linhas)
	l.mouse_filter = Control.MOUSE_FILTER_STOP
	l.mouse_entered.connect(func() -> void: UI.som("hover"))
	return l


## Slot aberto: ícone do item + nome + retrato de quem carrega. No combate
## um ícone basta; aqui a pergunta é QUEM carrega o quê, e essa resposta não
## pode depender de passar o mouse.
func _slot_detail(id: String, o: Dictionary, tip: String) -> Control:
	var el := String(o.get("element", "FOGO"))
	var p := PanelContainer.new()
	# cor CRUA: `frame()` queima o feixe sozinho, e `tint_of` capado devolvia
	# todas as cores no mesmo brilho — o achado da identidade visual
	p.add_theme_stylebox_override("panel",
		UI.frame(UI.C_PANEL, Db.el_color(el), 8, 6))
	p.tooltip_text = tip
	p.mouse_filter = Control.MOUSE_FILTER_STOP
	p.mouse_entered.connect(func() -> void: UI.som("hover"))
	var row := UI.box(false, 6)
	p.add_child(row)
	row.add_child(Icons.item(id, 32.0))
	var v := UI.box(true, 1)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(v)
	var nm := UI.label(String(Db.items[id]["name"]), 11, UI.GOLD)
	nm.clip_text = true
	nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_child(nm)
	var who := UI.box(false, 4)
	v.add_child(who)
	var owner_port := MonsterPortrait.medallion(String(o.get("species", "")), el, 22.0)
	owner_port.mouse_filter = Control.MOUSE_FILTER_IGNORE
	who.add_child(owner_port)
	var wn := UI.label(String(o["who"]), 11, Db.el_color(el).lightened(0.3))
	wn.clip_text = true
	wn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	wn.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	who.add_child(wn)
	return p


## Relíquia na doca. FECHADA (combate) é só o ícone; ABERTA (preparação) ela
## ganha nome, no mesmo formato do item equipado logo abaixo.
##
## Antes a relíquia usava o slot só-ícone nas duas situações. Na preparação a
## doca tem 300 px de largura e os ITENS abaixo mostram ícone + nome + dono —
## uma relíquia como ícone solitário centrado nessa moldura lia como um buraco
## na pilha: mesma doca, duas linguagens.
func _relic_slot(id: String, tip: String, accent: Color) -> Control:
	if detailed:
		return _relic_detail(id, tip, accent)
	return _slot(Icons.relic(id, 32.0), tip, accent)


## Sem retrato de dono, ao contrário do item: relíquia é da RUN inteira, não
## de um Prismon — não existe "quem carrega" para mostrar.
func _relic_detail(id: String, tip: String, accent: Color) -> Control:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", UI.frame(UI.C_GOLD, accent, 8, 6))
	p.tooltip_text = tip
	p.mouse_filter = Control.MOUSE_FILTER_STOP
	p.mouse_entered.connect(func() -> void: UI.som("hover"))
	var row := UI.box(false, 6)
	p.add_child(row)
	row.add_child(Icons.relic(id, 32.0))
	var nm := UI.label(String(Db.relics[id]["name"]), 11, accent.lightened(0.15))
	nm.clip_text = true
	nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nm.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(nm)
	return p


func _tag(text: String) -> Control:
	return UI.label(text, 10, UI.TEXT_DIM, HORIZONTAL_ALIGNMENT_CENTER)


## Slot com moldura: o item existe como objeto, não como número numa lista.
func _slot(icon: TextureRect, tip: String, accent: Color) -> Control:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", UI.frame(UI.C_PANEL, accent, 8, 6))
	p.tooltip_text = tip
	p.mouse_filter = Control.MOUSE_FILTER_STOP
	p.mouse_entered.connect(func() -> void: UI.som("hover"))
	icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	p.add_child(icon)
	return p
