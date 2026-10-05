extends Node
## A FOLHA DE COMPARACAO DAS PALETAS -- a peca que o autor OLHA para escolher.
##
##   godot --path . res://tools/paleta_probe.tscn
##
## Sai em docs/paletas.png. Uma faixa por paleta instalada em data/paleta.json,
## e cada faixa mostra a MESMA coisa, na mesma ordem, para a comparacao ser
## honesta:
##
##   1. os QUATRO DEGRAUS da materia e os quatro fundos do recipiente, chapados
##      -- cor de verdade, sem moldura por cima, para dar para julgar o passo
##      entre eles a olho;
##   2. os CINCO ESTADOS e os dois pesos de texto, com o contraste medido ao
##      lado (a mesma conta da WCAG que o smoke test cobra);
##   3. as DEZESSEIS SALAS, que sao a resposta ao pedido "cores diferentes por
##      tela" -- e a fileira que mostra se uma paleta tem variedade ou se todas
##      as telas dela vao parecer a mesma;
##   4. PECAS DE VERDADE montadas com o kit: uma linha de lista, um botao de
##      confirmar, um de recuar e uma barra. Um retangulo de cor nao diz nada
##      sobre como a paleta se comporta depois de passar pelo 9-patch, pelo
##      feixe da aresta e pela sombra dura -- estas quatro dizem.
##
## POR QUE UM SubViewport E NAO A JANELA: a folha cresce com o numero de
## paletas instaladas E com o tamanho da nota de cada uma. Amarra-la aos 900
## px da janela faria a terceira paleta ser cortada em silencio, que e o
## defeito que uma ferramenta de comparacao menos pode ter. A altura final e
## MEDIDA depois que o layout assenta, nao chutada -- chutar ja cortou a
## ultima faixa duas vezes enquanto esta ferramenta era escrita.
##
## COMO ELA TROCA DE PALETA NO MEIO DO DESENHO: `UI.frame()` ASSA a textura no
## momento em que o StyleBox e criado. Entao da para montar a faixa da paleta
## A, chamar `UI.aplicar_paleta(B)`, e montar a faixa de B logo abaixo -- as
## duas convivem na mesma imagem. O `Theme` da raiz nao: ele e um so e e
## herdado, por isso cada faixa recebe o SEU, remontado depois de
## `PrismaTheme.esquecer()`. No fim a paleta ativa e devolvida.

const LARGURA := 1500
## Estimativa SO para o SubViewport nascer grande o bastante; a altura de
## verdade e medida depois do layout.
const ALTURA_FAIXA := 480
const ALTURA_TOPO := 86

## O tamanho de um quadrado de cor chapada.
const AMOSTRA := Vector2(76, 40)
const AMOSTRA_SALA := Vector2(84, 30)


func _ready() -> void:
	get_window().size = Vector2i(1600, 900)
	var nomes: Array = []
	for n in Db.paletas:
		nomes.append(String(n))
	nomes.sort()
	# a paleta ATIVA vem primeiro: e contra ela que as outras sao comparadas
	if nomes.has(Db.paleta_ativa):
		nomes.erase(Db.paleta_ativa)
		nomes.push_front(Db.paleta_ativa)

	# uma folga generosa para montar; a altura REAL e medida depois que o
	# layout assenta (ver o recorte mais abaixo) -- uma faixa cresce com o
	# tamanho da nota da paleta, e chutar a altura cortava a ultima delas.
	var sv := SubViewport.new()
	sv.size = Vector2i(LARGURA, ALTURA_TOPO + ALTURA_FAIXA * nomes.size())
	sv.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	sv.transparent_bg = false
	add_child(sv)

	var fundo := ColorRect.new()
	fundo.color = UI.MESA
	fundo.set_anchors_preset(Control.PRESET_FULL_RECT)
	sv.add_child(fundo)

	var col := UI.box(true, 10)
	col.position = Vector2(24, 18)
	col.custom_minimum_size = Vector2(LARGURA - 48, 0)
	fundo.add_child(col)
	col.add_child(UI.label("PALETAS INSTALADAS", UI.F_H1, UI.TEXT))
	col.add_child(UI.label(
		"data/paleta.json — a ativa e a primeira. Contraste em razao de "
		+ "luminancia WCAG; o piso de leitura e 4.5:1.",
		UI.F_SMALL, UI.TEXT_DIM))

	for nome in nomes:
		col.add_child(_faixa(String(nome)))

	# devolve a paleta ativa ao kit antes de qualquer outra coisa desenhar
	UI.aplicar_paleta(Db.paleta)
	PrismaTheme.esquecer()

	if DisplayServer.get_name() == "headless":
		print("paleta_probe precisa de janela: sem render, nao ha o que salvar")
		get_tree().quit(1)
		return

	# ALTURA MEDIDA, nao chutada: espera o layout assentar e pergunta a coluna
	# quanto ela ocupou de fato.
	await get_tree().process_frame
	await get_tree().process_frame
	var altura: int = int(col.position.y + col.size.y) + 20
	sv.size = Vector2i(LARGURA, altura)
	await get_tree().process_frame
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var im: Image = sv.get_texture().get_image()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://docs"))
	im.save_png("res://docs/paletas.png")
	print("docs/paletas.png  —  %d paletas, %dx%d" % [nomes.size(), LARGURA, altura])
	get_tree().quit(0)


## Uma faixa inteira, JA na paleta dela.
func _faixa(nome: String) -> Control:
	var p: Dictionary = Db.paletas[nome]
	UI.aplicar_paleta(p)
	PrismaTheme.esquecer()

	var caixa := PanelContainer.new()
	caixa.theme = PrismaTheme.get_theme()
	caixa.add_theme_stylebox_override("panel",
		UI.frame(UI.C_PANEL, UI.ACCENT, 14, 10, UI.LAJOTA))
	caixa.custom_minimum_size = Vector2(LARGURA - 48, 0)

	var col := UI.box(true, 6)
	caixa.add_child(col)

	# --- cabecalho: nome, chave, e se e a ativa
	var topo := UI.box(false, 12)
	col.add_child(topo)
	topo.add_child(UI.label(String(p.get("nome", nome)), UI.F_H2, UI.TEXT))
	var chave := UI.label('"%s"' % nome, UI.F_SMALL, UI.ACCENT)
	topo.add_child(chave)
	if nome == Db.paleta_ativa:
		topo.add_child(UI.label("← ATIVA", UI.F_SMALL, UI.GOOD))
	# a nota fica na SUA linha: no cabecalho ela era cortada no meio da frase,
	# e a frase e justamente o argumento da proposta.
	var nota := UI.wrap(String(p.get("nota", "")), UI.F_SMALL, UI.TEXT_DIM)
	nota.custom_minimum_size = Vector2(LARGURA - 90, 0)
	col.add_child(nota)

	# --- fileira 1: materia, recipiente, estados, texto
	var f1 := UI.box(false, 18)
	col.add_child(f1)
	f1.add_child(_grupo("MATERIA — os quatro degraus", [
		["mesa", UI.MESA], ["lajota", UI.LAJOTA],
		["lajota_hi", UI.LAJOTA_HI], ["aresta", UI.ARESTA]], AMOSTRA))
	f1.add_child(_grupo("RECIPIENTE", [
		["fundo", UI.BG], ["painel", UI.PANEL],
		["painel_hi", UI.PANEL_HI], ["linha", UI.LINE]], AMOSTRA))
	f1.add_child(_grupo("ESTADO", [
		["bom", UI.GOOD], ["ruim", UI.BAD], ["aviso", UI.WARN],
		["ouro", UI.GOLD], ["acento", UI.ACCENT]], AMOSTRA))
	f1.add_child(_texto_medido())

	# --- fileira 2: as 16 salas
	var f2 := UI.box(true, 2)
	col.add_child(f2)
	f2.add_child(UI.label("SALAS — a cor de cada tela", UI.F_SMALL, UI.TEXT_DIM))
	var linha_salas := UI.box(false, 4)
	f2.add_child(linha_salas)
	var ordem := ["titulo", "iniciais", "escolha", "preparacao", "sinergias",
		"combate", "recruta", "loja", "cozinha", "poder", "acaso", "troca",
		"chefe", "vitoria", "derrota", "fim_vitoria"]
	for s in ordem:
		linha_salas.add_child(_amostra_sala(String(s), UI.cor_da_sala(String(s))))

	# --- fileira 3: pecas de verdade montadas com o kit
	var f3 := UI.box(false, 14)
	col.add_child(f3)
	f3.add_child(_linha_de_lista())
	var bts := UI.box(false, 8)
	f3.add_child(bts)
	bts.add_child(UI.button_confirmar("AVANÇAR"))
	bts.add_child(UI.button_secundario("VOLTAR"))
	var barras := UI.box(true, 4)
	barras.custom_minimum_size = Vector2(230, 0)
	f3.add_child(barras)
	barras.add_child(UI.label("HP", UI.F_SMALL, UI.TEXT_DIM))
	var b1 := UI.bar("green", 18)
	b1.ratio = 0.62
	b1.custom_minimum_size = Vector2(230, 18)
	barras.add_child(b1)
	var b2 := UI.bar("blue", 18)
	b2.ratio = 0.35
	b2.custom_minimum_size = Vector2(230, 18)
	barras.add_child(b2)
	return caixa


## Um titulo e uma fileira de amostras chapadas com o hex escrito embaixo.
func _grupo(titulo: String, pares: Array, tam: Vector2) -> Control:
	var col := UI.box(true, 2)
	col.add_child(UI.label(titulo, UI.F_SMALL, UI.TEXT_DIM))
	var linha := UI.box(false, 4)
	col.add_child(linha)
	for par in pares:
		var uma := UI.box(true, 1)
		var quad := ColorRect.new()
		quad.color = par[1]
		quad.custom_minimum_size = tam
		uma.add_child(quad)
		uma.add_child(UI.label(String(par[0]), UI.F_SMALL, UI.TEXT_DIM))
		uma.add_child(UI.label("#" + (par[1] as Color).to_html(false),
			UI.F_SMALL, UI.TEXT_DIM))
		linha.add_child(uma)
	return col


## Os dois pesos de texto SOBRE A LAJOTA, com a razao de contraste ao lado.
## E a unica parte de "gosto de cor" que nao e gosto: ou da para ler, ou nao.
func _texto_medido() -> Control:
	var col := UI.box(true, 2)
	col.add_child(UI.label("TEXTO sobre a lajota", UI.F_SMALL, UI.TEXT_DIM))
	var cartao := PanelContainer.new()
	cartao.add_theme_stylebox_override("panel",
		UI.frame(UI.C_PANEL, UI.LINE, 10, 6, UI.LAJOTA))
	var dentro := UI.box(true, 1)
	cartao.add_child(dentro)
	dentro.add_child(UI.label("Faúlha — Fogo · Arcano   %.2f:1"
		% _contraste(UI.TEXT, UI.LAJOTA), UI.F_BODY, UI.TEXT))
	dentro.add_child(UI.label("HP 390 · ATK 36 · DEF 15   %.2f:1"
		% _contraste(UI.TEXT_DIM, UI.LAJOTA), UI.F_SMALL, UI.TEXT_DIM))
	col.add_child(cartao)
	return col


func _amostra_sala(nome: String, cor: Color) -> Control:
	var col := UI.box(true, 1)
	var quad := ColorRect.new()
	quad.color = cor
	quad.custom_minimum_size = AMOSTRA_SALA
	col.add_child(quad)
	var rot := UI.label(nome, UI.F_SMALL, UI.TEXT_DIM)
	rot.clip_text = true
	rot.custom_minimum_size = Vector2(AMOSTRA_SALA.x, 0)
	col.add_child(rot)
	return col


## A LINHA DE LISTA do kit, 430x90 com folga 6 (a grade do projeto). E a peca
## que mais se repete no jogo, entao e nela que uma paleta ruim aparece antes.
func _linha_de_lista() -> Control:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel",
		UI.frame(UI.C_PANEL_HI, Db.el_color("FOGO"), 12, 6))
	p.custom_minimum_size = Vector2(430, 90)
	var linha := UI.box(false, 10)
	p.add_child(linha)
	linha.add_child(Icons.element("FOGO", UI.icon_px(UI.F_H2)))
	var texto := UI.box(true, 2)
	linha.add_child(texto)
	texto.add_child(UI.label("Faúlha", UI.F_H2, UI.TEXT))
	texto.add_child(UI.label("Fogo · Arcano · Meio", UI.F_SMALL, UI.TEXT_DIM))
	var bar := UI.bar("red", 18)
	bar.ratio = 0.78
	bar.custom_minimum_size = Vector2(150, 18)
	texto.add_child(bar)
	linha.add_child(UI.label("120", UI.F_H2, UI.GOLD))
	return p


# --- a mesma conta de contraste do smoke test -------------------------------
#
# WCAG 2.1: c' = c/12.92 se c <= 0.03928, senao ((c+0.055)/1.055)^2.4;
# L = 0.2126R' + 0.7152G' + 0.0722B'; razao = (Lclaro+0.05)/(Lescuro+0.05).
# Repetida aqui de proposito: uma ferramenta que so OLHA nao pode depender de
# uma que so MEDE, e sao dez linhas.

func _canal(v: float) -> float:
	return v / 12.92 if v <= 0.03928 else pow((v + 0.055) / 1.055, 2.4)


func _luminancia(c: Color) -> float:
	return 0.2126 * _canal(c.r) + 0.7152 * _canal(c.g) + 0.0722 * _canal(c.b)


func _contraste(a: Color, b: Color) -> float:
	var la := _luminancia(a)
	var lb := _luminancia(b)
	return (maxf(la, lb) + 0.05) / (minf(la, lb) + 0.05)
