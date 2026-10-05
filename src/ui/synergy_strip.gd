class_name SynergyStrip
extends VBoxContainer
## A tira de sinergias: o que a equipe produz, em ÍCONES (revisão 31/08).
##
## O painel completo virou consulta atrás de um botão. O que fica à vista quando
## a subseção EQUIPE está aberta é isto: um par de losangos por reação — os dois
## elementos que a produzem — e o nome. Sem parágrafo, sem multiplicador, sem
## custo de aura.
##
## A regra: o que se lê de relance fica; o que se lê com calma abre por botão.
##
## ------------------------------------------------------------------------
## 16/09 — A TIRA PERDEU A CAIXA E VIROU COLUNA.
##
## Ela era um PanelContainer com moldura própria, pousado EM CIMA das criaturas
## na preparação: o print do autor mostra o bloco "O QUE ESTA EQUIPE PRODUZ"
## ocupando a faixa inteira acima do elenco, com oito pastilhas coloridas. Foi
## um dos três blocos que cercavam os bonecos.
##
## Agora ela mora dentro da subseção EQUIPE do painel de consulta, que já é uma
## moldura — então a própria tira não desenha mais nenhuma: seria retângulo
## dentro de retângulo dentro de retângulo, que é o defeito que o projeto já
## batizou de "menos quadrados".
##
## E o cabeçalho deixou de ser uma LINHA (rótulo à esquerda, botão à direita):
## na coluna de 430 px o rótulo pede 264 px e o botão 282, e os dois na mesma
## linha somam 546. Empilhados, cada um usa a largura inteira.

signal open_requested

var _row: HFlowContainer


func _ready() -> void:
	add_theme_constant_override("separation", 7)
	add_child(UI.label("O QUE ESTA EQUIPE PRODUZ", 11, UI.TEXT_DIM))

	_row = HFlowContainer.new()
	_row.add_theme_constant_override("h_separation", 6)
	_row.add_theme_constant_override("v_separation", 5)
	add_child(_row)

	# NEUTRO, não ACCENT. O roxo passou a significar "recuar/pular" no contrato
	# do kit, e abrir a consulta não é nem avançar nem recuar — é o botão de
	# saber mais. A altura sai de UI.button (58), como todo botão do jogo.
	var btn := UI.button("  ANALISAR SINERGIAS  ", UI.F_SMALL)
	btn.tooltip_text = "Abre a matriz completa, o efeito de cada reação e o que falta destravar."
	btn.pressed.connect(func(): open_requested.emit())
	add_child(btn)

	Run.team_changed.connect(rebuild)
	rebuild()


func rebuild() -> void:
	if _row == null:
		return
	for c in _row.get_children():
		_row.remove_child(c)
		c.queue_free()

	var pairs := _active_pairs()
	if pairs.is_empty():
		_row.add_child(UI.label("nenhuma — todos do mesmo elemento, ou elementos que não se conversam",
			UI.F_SMALL, UI.BAD))
		return
	for p in pairs:
		_row.add_child(_chip(p))


## As reações que a equipe produz. Mesma lógica do painel, sem o filtro.
func _active_pairs() -> Array:
	var counts: Dictionary = {}
	for u in Run.team:
		var e: String = u.element()
		counts[e] = int(counts.get(e, 0)) + 1

	var out: Array = []
	var seen: Dictionary = {}
	for a in Db.slice_elements:
		var ea := String(a)
		if int(counts.get(ea, 0)) == 0:
			continue
		var aura_id := String(Db.el(ea).get("aura_id", ""))
		if aura_id == "":
			continue
		for b in Db.slice_elements:
			var eb := String(b)
			if ea == eb or int(counts.get(eb, 0)) == 0:
				continue
			var hit := Db.lookup_reaction(aura_id, eb)
			if hit.is_empty():
				continue
			var rid := String(hit["rule"]["id"])
			var key := "%s|%s" % [rid, ea if ea < eb else eb]
			if seen.has(key):
				continue
			seen[key] = true
			out.append({"rule": hit["rule"], "a": ea, "b": eb})
	return out


## Um par de losangos e o nome. O efeito inteiro vive no tooltip e no painel.
func _chip(p: Dictionary) -> Control:
	var rule: Dictionary = p["rule"]
	var col := Color(String(rule.get("color", "#ffffff")))
	var card := PanelContainer.new()
	# cor crua: `frame()` queima o feixe. E a lajota erguida deixou de ser
	# neutra (17/09) — a mesma regra do painel de sinergias, para a tira da
	# preparação e o painel completo falarem a mesma língua: cada pastilha é
	# feita da cor da reação que ela nomeia.
	card.add_theme_stylebox_override("panel",
		UI.frame(UI.C_PANEL_HI, col, 10, 6, UI.materia_da_sala(UI.LAJOTA_HI, col)))
	card.tooltip_text = "%s — %s × %s\n%s\n%s" % [String(rule["name"]),
		Db.el_name(String(p["a"])), Db.el_name(String(p["b"])),
		String(rule.get("text", "")), SynergyView.efeito_lido(rule)]
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	card.mouse_entered.connect(func() -> void: UI.som("hover"))

	# o par de losangos e UMA coisa (as duas energias que produzem a reacao):
	# anda junto, com folga menor entre eles do que entre o par e o nome.
	var row := UI.box(false, 8)
	card.add_child(row)
	var gems := UI.box(false, 3)
	gems.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(gems)
	gems.add_child(Gem.make(Db.el_color(String(p["a"])), 5))
	gems.add_child(Gem.make(Db.el_color(String(p["b"])), 5))
	var nm := UI.label(String(rule["name"]), UI.F_SMALL, col.lightened(0.25))
	nm.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(nm)
	return card
