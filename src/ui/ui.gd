class_name UI
extends RefCounted
## Kit de UI do PRISMON. Toda a interface e construida em codigo (sem .tscn),
## para manter o protótipo em arquivos de texto revisaveis.
## Direcao de arte: GDD 21.4 -- o ELEMENTO precisa ser lido antes da criatura.
##
## DIRECAO DE ARTE: "O VIDRO DO DOMADOR" (revisao 15/09, Raiz 3).
##
## O prisma nao e o logotipo, e a MATERIA de que a interface e feita. Toda tela
## e uma placa de vidro fume sobre a mesa de campo do Domador, com residuo de
## elemento queimado nela. O gesto que se repete e O CANTO CORTADO E O FEIXE:
## todo recipiente perde o canto superior esquerdo para uma escada de 45 graus
## em 9 px (tres degraus de 3), e de dentro do corte sai uma barra de 2 px na
## cor do elemento. Luz entra pelo corte, sai colorida.
##
## A cor parte em DOIS sistemas que antes nao existiam separados:
##   MATERIA -- neutra, quatro degraus, sem matiz (MESA/LAJOTA/LAJOTA_HI/ARESTA)
##   ESTADO  -- saturacao cheia, sem trava, e so em quatro lugares por tela:
##              o feixe da linha, o corte do painel, o preenchimento da barra e
##              o anel sob a criatura.
## Uma tela de um elemento fica ~96% neutra e ~4% queimando.

## A COR VIRA DADO (revisao 17/09)
## =============================================================================
##
## Ate aqui estas quinze cores eram `const Color("#...")` AQUI, e os quatro
## degraus neutros estavam REPETIDOS em tools/build_ui_sheet.py com um
## comentario pedindo "se mudar um, mude os dois". Trocar a cara do jogo pedia
## editar dois arquivos de codigo em duas linguagens, e esse e o oposto de
## "facil de customizar". Agora toda cor nasce de **data/paleta.json**, e este
## arquivo nao tem mais nenhum hex.
##
## POR QUE `static var` + UMA CHAMADA EXPLICITA, e nao leitura preguicosa
## ---------------------------------------------------------------------
## Ha uma ordem de carga no caminho: `UI` e um `class_name` sobre RefCounted, e
## `Db` e autoload. O SCRIPT de UI pode ser carregado (por `preload` de outro
## script, por exemplo) ANTES de o no do autoload existir -- entao um
## inicializador de `static var` que lesse `Db` correria o risco de rodar com o
## singleton ainda nulo, e a falha apareceria como uma tela preta, longe da
## causa. Leitura preguicosa em cada `UI.LAJOTA` tambem nao serve: os call sites
## leem a VARIAVEL, nao uma funcao, e por decisao desta fase nenhum deles muda.
##
## A ordem que o Godot GARANTE e outra: todo autoload esta pronto antes do
## `_ready()` da cena principal, e nada desenha antes disso. Entao
## `Db.load_all()` chama `UI.aplicar_paleta()` uma vez, e a partir dali ler
## `UI.LAJOTA` e ler um valor ja preenchido. `paleta_aplicada` existe para o
## smoke test COBRAR essa ordem em vez de a gente confiar nela.
##
## Medido em tools/_t (descartado depois): um `static var` usado como valor
## padrao de parametro (`bg: Color = PANEL`) e avaliado NA CHAMADA, nao na
## carga do script -- trocar de paleta muda o padrao junto. Por isso nenhuma
## assinatura precisou mudar e nenhum call site foi tocado.
##
## Os valores iniciais abaixo sao DEGENERADOS de proposito (preto e branco, sem
## matiz): eles nao sao uma paleta de reserva. A paleta de reserva e uma so, e
## mora em `Db.PALETA_EMBUTIDA` -- o unico lugar do codigo onde ainda ha hex.
static var BG        := Color.BLACK
static var PANEL     := Color.BLACK
static var PANEL_HI  := Color.BLACK
static var LINE      := Color.BLACK
static var TEXT      := Color.WHITE
static var TEXT_DIM  := Color.WHITE
static var ACCENT    := Color.WHITE
static var GOOD      := Color.WHITE
static var BAD       := Color.WHITE
static var WARN      := Color.WHITE
static var GOLD      := Color.WHITE

## OS QUATRO DEGRAUS NEUTROS -- a materia inteira do jogo.
##
## Nao ha matiz nenhum aqui de proposito: a cor do elemento entra so pelo feixe
## e pelo corte. Os mesmos quatro valores alimentam tools/build_ui_sheet.py, que
## agora LE O MESMO data/paleta.json -- nao ha mais duas listas para manter.
static var MESA      := Color.BLACK   # o vazio atras de tudo
static var LAJOTA    := Color.BLACK   # o corpo do recipiente padrao
static var LAJOTA_HI := Color.BLACK   # a lajota erguida (hover, dica, destaque)
static var ARESTA    := Color.BLACK   # a quina

## Os quatro degraus na ordem da rampa, para quem precisa indexar.
static var DEGRAUS: Array[Color] = []

## A cor de cada SALA, por nome (data/paleta.json -> paletas.<ativa>.salas).
## Leia por `UI.cor_da_sala("acaso")`, que avisa quando o nome nao existe.
static var SALAS: Dictionary = {}

## Forca padrao do halo de `luz_de_sala()`, e quanto da cor da sala entra na
## materia do recipiente. Os dois vem da paleta; ver `materia_da_sala()`.
static var SALA_FORCA := 0.0
static var SALA_NA_MATERIA := 0.0

## Falso ate `Db.load_all()` chamar `aplicar_paleta()`. Nao e decoracao: o
## smoke test reprova se ele estiver falso, e `frame()` avisa uma vez.
static var paleta_aplicada := false
static var paleta_nome := ""

static var _avisou_sem_paleta := false


## Preenche o kit inteiro a partir de uma paleta ja resolvida (`Db.paleta`).
##
## Chamada UMA vez por `Db.load_all()`. Idempotente: pode ser chamada de novo
## para trocar de paleta em tempo de execucao.
##
## O QUE TEM DE SER ESQUECIDO JUNTO, e por que:
##   `_cache_tex` guarda a textura composta por par (celula, acento, miolo). O
##   miolo vem da paleta -- sem limpar o cache, uma paleta nova desenharia com
##   o miolo da paleta velha e a tela ficaria com a cor antiga, sem erro
##   nenhum. `_cache_cru` NAO e limpo: ele guarda os pixels crus do PNG, que
##   nao dependem de paleta.
##   O `Theme` da raiz (PrismaTheme) ASSA StyleBox prontos; ele tambem precisa
##   ser esquecido, e quem faz isso e `Db`, logo depois desta chamada.
static func aplicar_paleta(p: Dictionary) -> void:
	var materia: Dictionary = p.get("materia", {})
	var recip: Dictionary = p.get("recipiente", {})
	var texto: Dictionary = p.get("texto", {})
	var estado: Dictionary = p.get("estado", {})

	MESA      = _cor(materia, "mesa")
	LAJOTA    = _cor(materia, "lajota")
	LAJOTA_HI = _cor(materia, "lajota_hi")
	ARESTA    = _cor(materia, "aresta")
	DEGRAUS = [MESA, LAJOTA, LAJOTA_HI, ARESTA]

	BG       = _cor(recip, "fundo")
	PANEL    = _cor(recip, "painel")
	PANEL_HI = _cor(recip, "painel_hi")
	LINE     = _cor(recip, "linha")

	TEXT     = _cor(texto, "forte")
	TEXT_DIM = _cor(texto, "fraco")

	GOOD   = _cor(estado, "bom")
	BAD    = _cor(estado, "ruim")
	WARN   = _cor(estado, "aviso")
	GOLD   = _cor(estado, "ouro")
	ACCENT = _cor(estado, "acento")

	SALAS = {}
	for nome in p.get("salas", {}):
		SALAS[String(nome)] = Color(String(p["salas"][nome]))
	SALA_FORCA = float(p.get("sala_forca", 0.06))
	SALA_NA_MATERIA = float(p.get("sala_na_materia", 0.0))

	# a tabela de miolo das celulas e DERIVADA dos degraus (ver CELL_MIOLO)
	CELL_MIOLO = []
	for degrau in CELL_MIOLO_DEGRAU:
		CELL_MIOLO.append(DEGRAUS[int(degrau)])

	_cache_tex.clear()
	sala = BG
	paleta_nome = String(p.get("nome", ""))
	paleta_aplicada = true
	_avisou_sem_paleta = false


static func _cor(bloco: Dictionary, chave: String) -> Color:
	var s := String(bloco.get(chave, ""))
	if s == "":
		push_error("PRISMON: paleta sem a cor '%s'" % chave)
		return Color.MAGENTA
	return Color(s)


## A cor de uma sala pelo nome. Nome desconhecido e ERRO, nao silencio: um
## `SALAS.get(nome, BG)` transformaria um erro de digitacao numa tela sem cor,
## que e exatamente o defeito que esta fase existe para tirar do jogo.
static func cor_da_sala(nome: String) -> Color:
	if not SALAS.has(nome):
		push_error("PRISMON: sala desconhecida na paleta: '%s'" % nome)
		return BG
	return SALAS[nome]


## O DEGRAU NEUTRO, JA PUXADO PARA A COR DA SALA.
##
## O pedido do autor tem tres metades, e esta funcao e a terceira: "cores
## diferentes por tela". A materia continua sendo quatro degraus sem matiz --
## `sala_na_materia` diz quanto da cor do lugar entra neles, preservando a
## LUMINANCIA do degrau (so matiz e saturacao viajam). Em 0.0, que e o valor da
## paleta "vidro", ela e a identidade: `materia_da_sala(LAJOTA) == LAJOTA`.
##
## Nenhuma tela chama isto ainda. A fase que pinta as telas e a proxima; o que
## esta fase entrega e o botao, ligado e medido, para ela girar.
static func materia_da_sala(degrau: Color, cor: Color = sala,
		forca: float = -1.0) -> Color:
	var f: float = SALA_NA_MATERIA if forca < 0.0 else forca
	if f <= 0.0:
		return degrau
	var s: float = clampf(cor.s * f * 2.0, 0.0, 0.85)
	return Color.from_hsv(cor.h, s, degrau.v, degrau.a)


## A cor da sala em que a interface esta agora.
##
## Quem a define e `luz_de_sala()`: a peca que pinta a atmosfera e a MESMA que
## registra qual e a sala, entao a sombra dura dos titulos (36 e 54) sai na cor
## do lugar sem que cada tela precise repetir a cor duas vezes. Fora de uma sala
## o padrao e o fundo -- sombra preta, que e o caso seguro.
static var sala := Color.BLACK

# --- escala tipografica ----------------------------------------------------
#
# Revisao 31/08 (pedido do autor: "aumentar a fonte no geral"). Em vez de
# caçar os ~30 tamanhos literais espalhados pelas telas, TODO tamanho passa
# por UI.fs(): F_SCALE sobe a escala inteira de uma vez e F_MIN impede que
# qualquer rotulo desça abaixo do legivel. A Pixelify Sans e uma fonte de
# pixel — ela desenha os glifos menores do que o tamanho nominal sugere, e
# era por isso que 11 pt sumia na tela.
#
# Para mexer na legibilidade do jogo inteiro, mexa AQUI. So aqui.

const F_SCALE := 1.00
const F_MIN   := 13

const F_TITLE := 44
const F_H1    := 26
const F_H2    := 19
const F_BODY  := 15
const F_SMALL := 13


## Tamanho de fonte final. Todo texto do jogo passa por aqui.
##
## ESCALA DA m6x11plus, medida em tools/fit_probe.tscn — nao chutada.
## A fonte tem unitsPerEm = 1152 com 64 unidades por pixel da grade: o "em"
## vale **18 px**, e o "11" do nome e a altura da caixa alta (704/64).
##
## Os corpos PERFEITOS sao os multiplos de 18 (18 / 36 / 54): cada pixel do
## desenho vira um numero inteiro de pixels da tela. Fora deles o rasterizador
## precisa dobrar algumas fileiras e nao outras, e o traco fica irregular.
##
## O ponto que custou caro: **1.5x e o PIOR caso possivel**. Em 27 px (27/18 =
## 1.5) a fileira dobrada alterna de dois em dois, um batimento regular que o
## olho le como "fonte quebrada" — foi exatamente o que o autor apontou nos
## prints. Em 26 px (1.444) o erro se espalha de forma irregular e o traco
## fica limpo, no MESMO tamanho aparente. Por isso a escala e:
##
##   18  rotulo, legenda, texto de consulta      (na grade, perfeito)
##   26  corpo — a leitura principal             (fora da grade, mas limpo)
##   36  nome, numero em destaque, cabecalho     (na grade, perfeito)
##   54  titulo de tela                          (na grade, perfeito)
##
## Se um dia o corpo puder crescer, 36 e o proximo degrau HONESTO. 27 e 30 nao
## sao — ja foram testados e reprovados no probe.
const SNAP := {10: 18, 11: 18, 12: 26, 13: 26, 14: 26, 15: 26,
	17: 26, 19: 26, 20: 36, 21: 36, 22: 36, 26: 36, 34: 54, 44: 54}


## Corpo mais proximo que NAO cai em 1.5x da grade da fonte.
static func snap_size(size: int) -> int:
	var n: int = maxi(int(round(float(size) / 9.0)) * 9, 18)
	return n - 1 if n % 18 == 9 else n


static func fs(size: int) -> int:
	if PIXEL_SNAP:
		return int(SNAP.get(size, snap_size(size)))
	return maxi(int(round(float(size) * F_SCALE)), F_MIN)


## Liga/desliga o alinhamento à grade da fonte de pixel. Uma linha para voltar.
const PIXEL_SNAP := true


## Acima deste corpo o titulo ganha a SOMBRA DURA de 1 px na cor da sala.
##
## Por que so 36 e 54: a sombra dura e um deslocamento de UM pixel. Em 18 e 26
## esse pixel vale 1/18 e 1/26 da altura do glifo e engorda o traco -- a fonte
## le como negrito borrado, que e o defeito oposto ao que se quer. Em 36 e 54
## ele vale 1/36 e 1/54, some dentro do desenho do glifo e so deixa a letra
## descolada do fundo. Medido em shots/15_corpo.png.
const F_SOMBRA_MIN := 36


## Tamanho de icone que ACOMPANHA um corpo de texto.
##
## Metade do "esparso" dos prints vinha daqui: o texto foi para 26 px e os
## icones continuaram em 18-22, entao cada linha tinha um icone pequeno demais
## flutuando ao lado de uma palavra grande, com sobra em cima e embaixo.
##
## Os icones sao 32x32 nativos (Shikashi) e as escalas limpas de 32 sao 16, 32
## e 48 — qualquer valor no meio reamostra pixel art em fracao quebrada. Entao
## sao tres degraus, escolhidos pelo corpo do texto que o icone acompanha.
static func icon_px(size: int) -> float:
	var f: int = fs(size)
	if f <= 20:
		return 16.0
	if f <= 40:
		return 32.0
	return 48.0


## Icone alinhado a PRIMEIRA LINHA de um bloco de texto, nao ao centro do bloco.
##
## Icons.node() centra o icone na vertical, que e o certo numa linha unica. Num
## cartao de tres linhas — nome, descricao, motivo de bloqueio — esse centro cai
## na DESCRICAO: o icone fica orfao no meio do bloco e o nome, que e a manchete,
## comeca sem nada a esquerda. Era o que se via na Feira de Passagem.
##
## Aqui o icone recebe uma caixa da altura de UMA linha do corpo `size` e se
## centra dentro dela; o resto da coluna e folga. O icone continua sendo uma
## coluna de largura fixa, entao as linhas do cartao seguem alinhadas entre si.
static func icon_head(icon: Control, size: int = F_H2) -> Control:
	var col := box(true, 0)
	var slot := CenterContainer.new()
	slot.custom_minimum_size = Vector2(0, float(fs(size)) + 9.0)
	slot.add_child(icon)
	col.add_child(slot)
	col.add_child(spacer(0.0, true))
	return col


## AS REGRAS DESTA BRIGA, em chips: a arena e os modificadores do bando.
##
## Um combate que muda de regra sem avisar e injusto, nao dificil — por isso
## isto aparece na ESCOLHA (antes de aceitar) e na PREPARACAO (antes de entrar),
## e nao so no meio do combate. O nome vai escrito e o efeito no tooltip.
static func rules_strip(payload: Dictionary, size: int = F_SMALL) -> Control:
	var row := HFlowContainer.new()
	row.add_theme_constant_override("h_separation", 6)
	row.add_theme_constant_override("v_separation", 4)
	var arena: Dictionary = Db.arenas.get(String(payload.get("arena", "")), {})
	if not arena.is_empty():
		row.add_child(_rule_chip(String(arena.get("name", "")),
			String(arena.get("text", "")),
			Color(String(arena.get("tint", "#8f88a8"))), "", size))
	for mid in payload.get("mods", []):
		for m in Db.modifiers:
			if String(m["id"]) != String(mid):
				continue
			row.add_child(_rule_chip(String(m["name"]), String(m["text"]),
				Color(String(m.get("color", "#e0576a"))),
				String(m.get("icon", "")), size))
	return row


static func _rule_chip(nome: String, texto: String, cor: Color,
		icone: String, size: int) -> Control:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", frame(C_PANEL_HI, cor, 10, 6))
	p.tooltip_text = "%s — %s" % [nome, texto]
	p.mouse_filter = Control.MOUSE_FILTER_STOP
	var row := box(false, 5)
	p.add_child(row)
	if icone != "":
		row.add_child(Icons.node(icone, icon_px(size), cor))
	var l := label(nome, size, cor.lightened(0.25))
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(l)
	return p


static func el_color(element_id: String) -> Color:
	return Db.el_color(element_id)


# --- as celulas do kit ------------------------------------------------------
#
# Cada celula sai de tools/build_ui_sheet.py em DOIS arquivos, e e este arquivo
# que compoe os dois. Ver o cabecalho do script para a geometria; o que importa
# aqui e o CONTRATO das camadas:
#
#   frame_<nome>.png     MATERIA NEUTRA ja na cor final (aresta, realce, pe,
#                        sombra dura). O miolo esta TRANSPARENTE.
#   frame_<nome>_m.png   MASCARA:  R = cobertura do miolo
#                                  G = cobertura do feixe (a cor do elemento)
#                                  B = quanto a materia se mistura ao elemento
#
# POR QUE ISTO EXISTE (revisao 15/09, o achado ALTO da identidade visual):
# a versao anterior passava a cor do elemento em `sb.modulate_color`, que
# multiplica a textura INTEIRA. Medido em shots/07b_loja.png, o miolo do painel
# ficava em luma 16,0 contra 14,9 do fundo da tela -- 1,1 de diferenca -- e a
# borda em 130,1. O corpo do painel nao existia: o jogo era uma bisel de 6 px
# flutuando num campo chapado, e era por isso que onze telas pareciam a mesma.
# Agora o miolo e pintado SOLIDO e `modulate_color` fica BRANCO.
# Medido no PNG novo: miolo #1c1930 = luma 28,5 contra 14,9 do fundo -- 13,6 de
# diferenca, doze vezes a de antes.

const FRAMES := [
	preload("res://assets/ui/frame_panel.png"),
	preload("res://assets/ui/frame_panel_hi.png"),
	preload("res://assets/ui/frame_inset.png"),
	preload("res://assets/ui/frame_gold.png"),
	preload("res://assets/ui/frame_danger.png"),
	preload("res://assets/ui/frame_confirm.png"),
	preload("res://assets/ui/frame_focus.png"),
	preload("res://assets/ui/frame_slot.png"),
	preload("res://assets/ui/frame_confirm_hi.png"),
	preload("res://assets/ui/frame_confirm_in.png"),
]

const MASCARAS := [
	preload("res://assets/ui/frame_panel_m.png"),
	preload("res://assets/ui/frame_panel_hi_m.png"),
	preload("res://assets/ui/frame_inset_m.png"),
	preload("res://assets/ui/frame_gold_m.png"),
	preload("res://assets/ui/frame_danger_m.png"),
	preload("res://assets/ui/frame_confirm_m.png"),
	preload("res://assets/ui/frame_focus_m.png"),
	preload("res://assets/ui/frame_slot_m.png"),
	preload("res://assets/ui/frame_confirm_hi_m.png"),
	preload("res://assets/ui/frame_confirm_in_m.png"),
]

## AS CELULAS TEM PAPEL, nao so aparencia. A revisao achou quatro delas mortas
## (as decoradas eram usadas em UM lugar do jogo inteiro); agora cada uma e o
## unico jeito de dizer uma coisa:
##
##   C_PANEL       recipiente em repouso                  lajota, sombra de 3 px
##   C_PANEL_HI    ERGUIDA: sob o mouse, dica, chip        sobe 2 px, sombra de 5
##   C_INSET       AFUNDADA: apertado, campo, trilho       sem sombra, parede do buraco
##   C_GOLD        destaque: recompensa, chefe             regua de acento no topo
##   C_DANGER      perigo                                  regua de acento no pe
##   C_CONFIRM     COMMIT: dois cantos cortados            (ver button_confirmar)
##   C_FOCUS       ESCOLHIDO: o feixe desce a aresta toda
##   C_SLOT        vago                                    aresta tracejada
##   C_CONFIRM_HI / C_CONFIRM_IN  os outros dois estados do commit
enum { C_PANEL, C_PANEL_HI, C_INSET, C_GOLD, C_DANGER, C_CONFIRM, C_FOCUS,
	C_SLOT, C_CONFIRM_HI, C_CONFIRM_IN }

## Margens do 9-patch, por celula: [esquerda, cima, direita, baixo].
##
## Nao sao iguais nos quatro lados porque o desenho nao e simetrico: o canto
## cortado de 9 px mais o feixe de 2 px ocupam 11 px em cima e a esquerda, e a
## sombra dura ocupa 5 px embaixo e a direita. As celulas de dois cortes
## precisam de 17 embaixo porque o segundo corte comeca em y=24 na versao
## erguida. Os valores saem impressos por tools/build_ui_sheet.py -- se mudar a
## geometria la, copie daqui.
const CELL_MARGIN := [
	[14, 15, 15, 15], [14, 15, 15, 15], [14, 15, 15, 15], [14, 15, 15, 15],
	[14, 15, 15, 15], [14, 15, 15, 17], [14, 15, 15, 15], [14, 15, 15, 15],
	[14, 15, 15, 17], [14, 15, 15, 17],
]

## O degrau neutro que cada celula usa quando ninguem pede outro, como INDICE
## em `DEGRAUS` (0 = MESA, 1 = LAJOTA, 2 = LAJOTA_HI, 3 = ARESTA).
##
## Era uma lista das proprias cores, e deixou de poder ser: `const` nao pode
## referenciar `static var`. O indice tambem diz melhor o que a tabela e --
## "que degrau da rampa", nao "que cor" -- e continua sendo uma das tabelas
## paralelas da celula que tools/lint_ui.py conta.
const CELL_MIOLO_DEGRAU := [1, 2, 0, 2, 1, 2, 2, 0, 2, 1]

## A mesma tabela ja resolvida em cores. Preenchida por `aplicar_paleta()`.
static var CELL_MIOLO: Array = []

## Quanto o CENTRO DA LAJOTA esta acima do centro da caixa do Control, em px.
##
## A lajota nao ocupa a celula inteira: sobra a folga de cima (por onde ela sobe
## no hover) e a sombra dura embaixo. Medido na celula em repouso com um Control
## de altura H: a aresta de cima da lajota cai na linha 3 e a de baixo na linha
## H-7, logo o centro da lajota esta em H/2 - 2 -- dois pixels acima do centro
## da caixa. A conta NAO depende de H, porque as duas faixas de canto do 9-patch
## sao fixas; o que estica e so o meio.
##
## Sem esta correcao o rotulo de todo botao fica 2 px abaixo do centro do
## proprio botao (4 na lajota erguida), e o texto parece "escorregado" -- que e
## exatamente o defeito que ja tinha aparecido na faixa de titulo.
##
## E ela tambem entrega de graca o gesto do hover: a lajota erguida esta 2 px
## mais alta, o rotulo sobe junto, e o botao inteiro SOBE 2 PX sem tween nenhum.
const CELL_CENTRO := [-2, -4, -1, -4, -2, -2, -4, -1, -4, -1]

# Cache de textura composta, por par (celula, acento, miolo). A composicao
# custa 1600 pixels; o jogo inteiro usa algumas dezenas de pares, entao o custo
# total fica na casa de um quadro. Sem o cache seria um laco de 1600 pixels por
# StyleBox criado -- e um botao cria quatro.
static var _cache_tex: Dictionary = {}
static var _cache_cru: Dictionary = {}


static func _cru(t: Texture2D) -> Array:
	## [bytes RGBA8, largura, altura] de uma textura, decodificada uma vez so.
	var chave := t.resource_path
	if _cache_cru.has(chave):
		return _cache_cru[chave]
	var im: Image = t.get_image()
	var dados: Array = []
	if im != null:
		if im.get_format() != Image.FORMAT_RGBA8:
			im.convert(Image.FORMAT_RGBA8)
		dados = [im.get_data(), im.get_width(), im.get_height()]
	_cache_cru[chave] = dados
	return dados


## Compoe materia + miolo + feixe numa textura so, com alfa direto (nao
## pre-multiplicado, que e o que o StyleBoxTexture espera).
static func _compor(base: Texture2D, mascara: Texture2D,
		acento: Color, miolo: Color) -> Texture2D:
	var b := _cru(base)
	var m := _cru(mascara)
	if b.is_empty() or m.is_empty():
		return base          # sem acesso aos pixels (driver sem imagem): nao quebra a tela
	var bytes: PackedByteArray = b[0]
	var mbytes: PackedByteArray = m[0]
	var w: int = b[1]
	var h: int = b[2]
	var out := PackedByteArray()
	out.resize(w * h * 4)
	for i in range(w * h):
		var o: int = i * 4
		# camada 1 -- MIOLO solido (nunca modulado: e o achado inteiro)
		var am: float = float(mbytes[o]) / 255.0
		var r: float = miolo.r * am
		var g: float = miolo.g * am
		var bl: float = miolo.b * am
		var a: float = am
		# camada 2 -- MATERIA neutra, com um sopro do elemento na aresta
		var ab: float = float(bytes[o + 3]) / 255.0
		if ab > 0.0:
			var k: float = float(mbytes[o + 2]) / 255.0
			var cr: float = lerpf(float(bytes[o]) / 255.0, acento.r, k)
			var cg: float = lerpf(float(bytes[o + 1]) / 255.0, acento.g, k)
			var cb: float = lerpf(float(bytes[o + 2]) / 255.0, acento.b, k)
			r = cr * ab + r * (1.0 - ab)
			g = cg * ab + g * (1.0 - ab)
			bl = cb * ab + bl * (1.0 - ab)
			a = ab + a * (1.0 - ab)
		# camada 3 -- FEIXE: o estado, em saturacao cheia
		var af: float = float(mbytes[o + 1]) / 255.0
		if af > 0.0:
			r = acento.r * af + r * (1.0 - af)
			g = acento.g * af + g * (1.0 - af)
			bl = acento.b * af + bl * (1.0 - af)
			a = af + a * (1.0 - af)
		if a > 0.0039:
			out[o] = int(round(clampf(r / a, 0.0, 1.0) * 255.0))
			out[o + 1] = int(round(clampf(g / a, 0.0, 1.0) * 255.0))
			out[o + 2] = int(round(clampf(bl / a, 0.0, 1.0) * 255.0))
			out[o + 3] = int(round(clampf(a, 0.0, 1.0) * 255.0))
	return ImageTexture.create_from_image(
		Image.create_from_data(w, h, false, Image.FORMAT_RGBA8, out))


static func _textura(cell: int, acento: Color, miolo: Color) -> Texture2D:
	return _em_cache("%d" % cell, FRAMES[cell], MASCARAS[cell], acento, miolo)


static func _em_cache(quem: String, base: Texture2D, mascara: Texture2D,
		acento: Color, miolo: Color) -> Texture2D:
	var chave := "%s|%d|%d" % [quem, acento.to_rgba32(), miolo.to_rgba32()]
	if not _cache_tex.has(chave):
		_cache_tex[chave] = _compor(base, mascara, acento, miolo)
	return _cache_tex[chave]


## StyleBox de uma celula. `tint` pinta SO o feixe e o corte -- nunca o miolo.
## `miolo` transparente (o padrao) significa "o degrau neutro desta celula".
static func frame(cell: int, tint: Color = Color.WHITE,
		pad_h: int = 12, pad_v: int = 8,
		miolo: Color = Color(0, 0, 0, 0)) -> StyleBoxTexture:
	if not paleta_aplicada and not _avisou_sem_paleta:
		# A ordem de carga quebrou: alguem montou interface antes de
		# `Db.load_all()`. A tela sairia preta e sem erro nenhum.
		_avisou_sem_paleta = true
		push_warning("PRISMON: UI.frame() antes de UI.aplicar_paleta() -- "
			+ "a paleta de data/paleta.json ainda nao foi lida")
	var mi: Color = CELL_MIOLO[cell] if miolo.a < 0.5 else Color(miolo.r, miolo.g, miolo.b)
	var sb := StyleBoxTexture.new()
	sb.texture = _textura(cell, _acento(tint), mi)
	var m: Array = CELL_MARGIN[cell]
	sb.texture_margin_left = m[0]
	sb.texture_margin_top = m[1]
	sb.texture_margin_right = m[2]
	sb.texture_margin_bottom = m[3]
	sb.content_margin_left = pad_h
	sb.content_margin_right = pad_h
	# o conteudo se centra na LAJOTA, nao na caixa do Control (ver CELL_CENTRO).
	# A soma continua sendo 2 * pad_v, entao a altura minima nao muda.
	var topo: int = maxi(pad_v + CELL_CENTRO[cell], 0)
	sb.content_margin_top = topo
	sb.content_margin_bottom = pad_v * 2 - topo
	# TILE em vez de STRETCH: a celula `slot` tem aresta TRACEJADA, e esticar um
	# tracejado o transforma num traco continuo. Nas arestas lisas das outras
	# nove celulas nao faz diferenca nenhuma.
	sb.axis_stretch_horizontal = StyleBoxTexture.AXIS_STRETCH_MODE_TILE
	sb.axis_stretch_vertical = StyleBoxTexture.AXIS_STRETCH_MODE_TILE
	# BRANCO. Este e o conserto da Raiz 3: a cor ja esta dentro da textura.
	sb.modulate_color = Color.WHITE
	return sb


## A cor do FEIXE. Queima sempre: o estado nao tem trava.
##
## A `tint_of()` antiga capava S em 0,55 e travava V em 0,78 para toda borda do
## jogo. Fogo #e8563a saia #c6796a e Raio #e8c53a saia #c6b46a -- mesmo brilho,
## mesmo canal maximo 0xc6: a cor virava chave de consulta e nunca clima. Aqui
## Fogo sai #e5684b (S 0,67 V 0,90) e Raio sai #e5d04b.
##
## Isto roda DENTRO de frame(), entao alcanca tambem os ~12 call sites que
## passam `UI.tint_of(cor)` ja capado -- eles nao precisam mudar uma linha.
##
## O teste de "e neutro?" e por CROMA ABSOLUTO (maior canal menos menor), nao
## por saturacao. Saturacao e uma razao: `UI.LINE` (#2e2942) tem S = 0,30 e
## `Color(0.30,0.30,0.36)` (o botao desabilitado) tem S = 0,17 -- os dois
## passariam por "colorido" num teste de S e sairiam daqui como roxo berrante.
## Medido nesta paleta: os neutros ficam todos em croma <= 0,12 e as cores de
## elemento em croma >= 0,27, mesmo depois de passarem pela tint_of capada.
## 0,18 fica no meio do vao.
static func _acento(c: Color) -> Color:
	var croma: float = maxf(c.r, maxf(c.g, c.b)) - minf(c.r, minf(c.g, c.b))
	if croma < 0.18:
		return Color(0.80, 0.82, 0.90)
	return Color.from_hsv(c.h, clampf(maxf(c.s, 0.62), 0.0, 1.0), maxf(c.v, 0.88))


## Traduz uma cor em tinta de moldura.
##
## `forte = false` mantem a trava historica: dentro do FieldView o anel de aura
## ja faz a leitura forte do elemento, e a moldura ali precisa SUGERIR sem
## disputar (GDD 21.4). Fora do combate use `forte = true` -- ou, melhor ainda,
## passe a cor crua para `frame()`, que ja queima sozinho.
static func tint_of(c: Color, forte: bool = false) -> Color:
	if c.is_equal_approx(LINE) or c.s < 0.08:
		return Color(0.80, 0.82, 0.90) if forte else Color(0.62, 0.64, 0.74)
	if forte:
		return Color.from_hsv(c.h, clampf(c.s * 0.9, 0.0, 1.0), 0.9)
	# matiz do elemento, mas dessaturado: a moldura sugere o elemento, nao grita.
	# A leitura forte do elemento fica no anel de aura e na pastilha (GDD 21.4).
	return Color.from_hsv(c.h, clampf(c.s * 0.62, 0.0, 0.55), 0.78)


## Painel de sala. A assinatura e a antiga; o que mudou e que `bg` VOLTOU A
## EXISTIR -- ele agora e o miolo solido da lajota.
##
## Eram sete cores de sala escritas nas telas (#2a1220 no trilho do elenco,
## #4a1526 no cabecalho dele, #181425 no painel de combate, #15121f na moldura
## da run...) e ZERO renderizadas: a versao antiga desta funcao jogava o `bg`
## fora, e o comentario admitia. `radius` continua ignorado -- o recipiente
## deste jogo nao arredonda, ele CORTA o canto.
static func panel(bg: Color = PANEL, radius: int = 8, border: Color = LINE) -> StyleBoxTexture:
	var cell: int = C_PANEL_HI if bg.is_equal_approx(PANEL_HI) else C_PANEL
	return frame(cell, border, 12, 8, Color(bg.r, bg.g, bg.b, 1.0))


## Preenchimento de barra: chapado de proposito. Uma moldura de 9-patch
## esticada num preenchimento parcial le como "caixa vazia", nao como "cheio".
static func bar_fill(c: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = c
	sb.set_corner_radius_all(0)
	sb.content_margin_left = 0
	sb.content_margin_right = 0
	sb.content_margin_top = 0
	sb.content_margin_bottom = 0
	return sb


static func flat(bg: Color, radius: int = 4, border: Color = LINE) -> StyleBoxFlat:
	# usada so nas pastilhas pequenas: um 9-patch de 40px nao cabe num badge de 18px
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_corner_radius_all(radius)
	sb.set_border_width_all(1)
	sb.border_color = border
	sb.content_margin_left = 7
	sb.content_margin_right = 7
	sb.content_margin_top = 1
	sb.content_margin_bottom = 1
	return sb


## A sombra dura dos titulos: a cor da sala, sempre escura.
##
## Forcar V <= 0,12 e o que impede uma sala clara (o verde do Bosque, por
## exemplo) de virar um contorno luminoso em volta da letra. O matiz sobrevive,
## e e ele que amarra o titulo ao lugar.
static func sombra_da_sala() -> Color:
	return Color.from_hsv(sala.h, sala.s, minf(sala.v, 0.12))


static var _fonte_gravada: FontVariation = null


## +1 de espacamento entre glifos, so nos rotulos em CAIXA ALTA.
##
## Uma palavra toda maiuscula numa fonte de pixel de em=18 tem todas as letras
## na mesma altura e sem descida: sem folga extra elas colam e o rotulo vira uma
## mancha. Com +1 ele vira GRAVACAO NA MESA, que e o que a direcao pede.
## FontVariation e o unico caminho no Godot 4 -- Label nao tem constante de
## espacamento entre glifos.
static func _fonte_maiuscula() -> FontVariation:
	if _fonte_gravada == null:
		_fonte_gravada = FontVariation.new()
		var base := PrismaTheme.fonte_corpo()
		_fonte_gravada.base_font = base
		# FontVariation nao herda a cadeia de fallback do `base_font`: sem esta
		# linha, ★ ⚡ ❄ ◆ e → sumiriam de todo rotulo maiusculo.
		if base != null:
			_fonte_gravada.fallbacks = base.fallbacks
		_fonte_gravada.spacing_glyph = 1
	return _fonte_gravada


static func _e_maiuscula(t: String) -> bool:
	return t.length() >= 2 and t == t.to_upper() and t != t.to_lower()


static func label(text: String, size: int = F_BODY, color: Color = TEXT,
		align: int = HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var l := Label.new()
	l.text = text
	var corpo: int = fs(size)
	l.add_theme_font_size_override("font_size", corpo)
	l.add_theme_color_override("font_color", color)
	l.horizontal_alignment = align
	if corpo >= F_SOMBRA_MIN:
		l.add_theme_color_override("font_shadow_color", sombra_da_sala())
		l.add_theme_constant_override("shadow_offset_x", 1)
		l.add_theme_constant_override("shadow_offset_y", 1)
		l.add_theme_constant_override("shadow_outline_size", 0)
	if _e_maiuscula(text):
		l.add_theme_font_override("font", _fonte_maiuscula())
	# sem autowrap por padrao: dentro de um HBoxContainer o label seria espremido
	# ate uma letra por linha. Use wrap() para textos longos em coluna.
	return l


## Label que quebra linha. So use dentro de um VBoxContainer (tem largura definida).
static func wrap(text: String, size: int = F_BODY, color: Color = TEXT) -> Label:
	var l := label(text, size, color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.custom_minimum_size = Vector2(120, 0)
	return l


static func rich(text: String, size: int = F_BODY) -> RichTextLabel:
	var r := RichTextLabel.new()
	r.bbcode_enabled = true
	r.fit_content = true
	r.scroll_active = false
	r.text = text
	r.add_theme_font_size_override("normal_font_size", fs(size))
	r.add_theme_font_size_override("bold_font_size", fs(size))
	r.add_theme_color_override("default_color", TEXT)
	return r


# --- audio ------------------------------------------------------------------
#
# CONSUMIDOR do contrato do agente de audio: `Som.tocar(nome, pitch, volume_db)`.
#
# A busca e por NO e nao pelo identificador global `Som` de proposito: o
# autoload nasce em paralelo, e uma referencia direta a um autoload que ainda
# nao esta em project.godot e ERRO DE PARSE -- derrubaria o jogo inteiro, nao
# so o som. Assim, enquanto o autoload nao existe, tocar um som e um no-op.

static var _som_no: Node = null
static var _som_procurado := false


static func som(nome: String) -> void:
	if not _som_procurado:
		_som_procurado = true
		var laco := Engine.get_main_loop()
		if laco is SceneTree:
			var raiz: Node = (laco as SceneTree).root
			if raiz != null and raiz.has_node("Som"):
				_som_no = raiz.get_node("Som")
	if _som_no != null and is_instance_valid(_som_no):
		_som_no.call("tocar", nome)


# --- botoes -----------------------------------------------------------------
#
# ALTURA DE 58 PX, aqui e nao nas telas. A revisao mediu tres alturas de botao
# convivendo e o padrao de 58 quebrado justamente na peca mais reusada. Como
# TODO botao do jogo passa por esta funcao, o minimo vive aqui.
#
# RESPIRO 20/13 (autor, 03/09: "os botões estão muito apertados").
#
# PREENCHIMENTO EM VEZ DE CONTORNO, e o estado vem da ELEVACAO, nao da cor:
#   repouso  C_PANEL     lajota em repouso, sombra dura de 3 px
#   hover    C_PANEL_HI  a lajota SOBE 2 px e a sombra vai a 5
#   apertado C_INSET     a lajota AFUNDA: some a sombra, aparece a parede do buraco
#
# Por que nada disso move o NO: um Control dentro de Container tem a `position`
# reescrita pelo pai a cada ordenacao, entao um deslocamento animado sobrevive
# ate a primeira reordenacao e depois fica alguns px fora do lugar para sempre.
# O subir e o afundar sao DESENHO (a lajota mora mais alta ou mais baixa dentro
# da propria textura) mais `content_margin` (o rotulo acompanha). A caixa do no
# nao muda um pixel, e o layout nem fica sabendo.
#
# BTN_AFUNDA e o que FALTA para os 3 px: a celula afundada ja desce 1 px
# sozinha (ver CELL_CENTRO: -1 contra os -2 do repouso), entao mais 2 aqui
# fecham o gesto. Do hover (-4) ao apertado (+1) dao os 5 px de curso que a
# mao sente.
const BTN_H := 58
const BTN_PAD_H := 20
const BTN_PAD_V := 13
const BTN_AFUNDA := 2


static func button(text: String, size: int = F_BODY, col: Color = LINE) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_size_override("font_size", fs(size))
	b.add_theme_color_override("font_color", TEXT)
	b.add_theme_color_override("font_hover_color", Color.WHITE)
	b.add_theme_color_override("font_pressed_color", Color.WHITE)
	b.add_theme_color_override("font_disabled_color", TEXT_DIM.darkened(0.35))
	b.custom_minimum_size = Vector2(0, BTN_H)
	_vestir(b, col, C_PANEL, C_PANEL_HI, C_INSET)
	# JUICE: a lajota clareia sob o mouse. O SUBIR e o AFUNDAR moram na arte
	# (nas celulas acima), nao num tween -- ver a nota de layout logo acima.
	Juice.make_reactive(b, b)
	b.pressed.connect(func() -> void: som("clique"))
	b.mouse_entered.connect(func() -> void: som("hover"))
	return b


static func _vestir(b: Button, col: Color, repouso: int, alto: int, fundo: int) -> void:
	b.add_theme_stylebox_override("normal",
		frame(repouso, col, BTN_PAD_H, BTN_PAD_V, LAJOTA_HI))
	b.add_theme_stylebox_override("hover",
		frame(alto, col, BTN_PAD_H, BTN_PAD_V, ARESTA))
	var ap := frame(fundo, col, BTN_PAD_H, BTN_PAD_V, LAJOTA)
	ap.content_margin_top += BTN_AFUNDA
	ap.content_margin_bottom -= BTN_AFUNDA
	b.add_theme_stylebox_override("pressed", ap)
	b.add_theme_stylebox_override("disabled",
		frame(C_PANEL, Color(0.30, 0.30, 0.36), BTN_PAD_H, BTN_PAD_V, MESA))
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())


## O botao que COMETE: avancar, comprar, lutar, confirmar.
##
## Ele se distingue por FORMA, nao so por cor: um SEGUNDO canto cortado, no
## canto oposto. Dois cantos cortados significam commit, e isso sobrevive a
## daltonismo, a monitor mal calibrado e a print em escala de cinza.
##
## A cor e sempre GOOD, sem excecao. A revisao mediu QUATRO cores de confirmar
## em quatro telas -- prep LUTAR vermelho, ScreenMap LUTAR! dourado/ambar/
## vermelho conforme o perigo, PickPanel com a cor da oferta selecionada, que
## muda a cada clique -- e nenhuma delas era a que docs/pecas/botoes.png, gerada
## do proprio codigo, define como "confirmar".
static func button_confirmar(text: String, size: int = F_BODY) -> Button:
	var b := button(text, size, GOOD)
	_vestir(b, GOOD, C_CONFIRM, C_CONFIRM_HI, C_CONFIRM_IN)
	return b


## O botao que RECUA ou PULA: cancelar, dispensar, voltar, seguir sem.
##
## Sempre ACCENT, e um corte so. Hoje o mesmo roxo serve para recuar (DISPENSAR,
## CANCELAR, SEGUIR SEM RECRUTAR) e para avancar (CONTINUAR, NOVA RUN) -- o par
## desta funcao com `button_confirmar` e o que desfaz essa ambiguidade.
static func button_secundario(text: String, size: int = F_BODY) -> Button:
	return button(text, size, ACCENT)


static func box(vertical: bool = true, sep: int = 8) -> BoxContainer:
	var b: BoxContainer = VBoxContainer.new() if vertical else HBoxContainer.new()
	b.add_theme_constant_override("separation", sep)
	return b


static func card(bg: Color = PANEL, border: Color = LINE) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel",
		frame(C_PANEL, border, 12, 8, Color(bg.r, bg.g, bg.b, 1.0)))
	return p


## Cartao com a celula de destaque: usado onde o GDD pede recompensa ou chefe.
## O acento vai em GOLD -- e o unico lugar do kit em que a cor nao vem de fora.
static func card_gold() -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", frame(C_GOLD, GOLD))
	return p


## Encaixe VAZIO: item que falta, vaga de estomago livre, slot sem nada.
## Aresta tracejada e miolo na cor da mesa -- le como buraco, nao como objeto.
static func slot() -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", frame(C_SLOT, LINE))
	return p


## Cartao de PERIGO: a regua de acento mora no pe, onde o olho termina a leitura.
static func card_danger(cor: Color = BAD) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", frame(C_DANGER, cor))
	return p


static func spacer(min_size: float = 0.0, expand: bool = true) -> Control:
	var c := Control.new()
	if expand:
		c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		c.size_flags_vertical = Control.SIZE_EXPAND_FILL
	if min_size > 0.0:
		c.custom_minimum_size = Vector2(min_size, min_size)
	return c


static func hsep() -> HSeparator:
	var s := HSeparator.new()
	var sb := StyleBoxLine.new()
	sb.color = LINE
	s.add_theme_stylebox_override("separator", sb)
	return s


## Pastilha colorida com o nome do elemento -- a camada de leitura #2 do GDD 21.4.
static func element_chip(element_id: String, size: int = F_SMALL) -> PanelContainer:
	var c := el_color(element_id)
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", flat(c.darkened(0.62), 4, c))
	var row := box(false, 4)
	var ic := Icons.element(element_id, icon_px(size))
	if ic.texture != null:
		row.add_child(ic)
	row.add_child(label(Db.el_name(element_id).to_upper(), size, c.lightened(0.35)))
	p.add_child(row)
	p.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	return p


static func stars(n: int, total: int = 5) -> String:
	return "★".repeat(clampi(n, 0, total)) + "☆".repeat(maxi(total - n, 0))


## Nome do tipo de dano em portugues. Os ids sao internos (`physical`,
## `elemental`, `reaction`, `true`) e vinham CRUS para a tela do log — "MAIOR
## GOLPE: Apollo -> 71 em Pinto-Raio (physical)".
static func damage_name(dtype: String) -> String:
	match dtype:
		"physical": return "físico"
		"reaction": return "reação"
		"true": return "puro"
		"elemental": return "elemental"
	return dtype


static func damage_color(dtype: String, element_id: String) -> Color:
	match dtype:
		"physical": return Color.WHITE
		"reaction":
			var c := el_color(element_id)
			return c.lightened(0.35)
		"true": return GOLD
		_: return el_color(element_id)


# --- pecas maiores do pacote ------------------------------------------------
#
# Cada uma existe para TIRAR TEXTO da tela: a faixa substitui um cartao de
# cabecalho inteiro, o medalhao substitui pastilha + nome em destaque, e a barra
# substitui "HP 100%" escrito.

const TEX_BANNER := preload("res://assets/ui/banner.png")
const TEX_BANNER_M := preload("res://assets/ui/banner_m.png")
const TEX_RING := preload("res://assets/ui/ring.png")
const TEX_RING_GOLD := preload("res://assets/ui/ring_gold.png")

const BANNER_H := 64

## As pontas da faixa. Eram 64 px de uma peca de 192, e a revisao mediu SEIS
## larguras de faixa no jogo (688 a 1412 px): com 64 px presos em cada ponta, a
## ponta passa a ler como um adesivo colado numa barra, e o efeito piora quanto
## mais larga a faixa. A peca nova tem 96 px com pontas de 24, e a ponta nao tem
## mais desenho proprio: e o mesmo canto cortado de qualquer recipiente.
const BANNER_MARGEM := 24

## A LARGURA DE CASA da faixa. A peca nova aguenta qualquer largura, mas seis
## larguras diferentes continuam sendo seis telas diferentes: a faixa e o unico
## elemento que aparece em TODAS elas, e e ela que diz "isto e o mesmo jogo".
## 1180 nao e um numero novo -- e o mesmo `BAR_W` que o combate ja usa como
## largura util, entao a faixa passa a se alinhar com a barra de tempo.
##
## Nao e aplicada aqui de proposito: forcar 1180 numa faixa que hoje vive numa
## coluna de 688 px faria a peca transbordar o painel. Quem decide a largura e
## a tela -- ver o pedido de convergencia no retorno do agente `kit`.
const BANNER_W := 1180


## Faixa de titulo. Substitui o cartao de cabecalho das telas.
##
## `tint` AGORA FAZ ALGUMA COISA. Ele tinha zero chamadas, e a faixa era a unica
## superficie grande e opaca do jogo inteiro -- sempre no mesmo #e2665b da
## Kenney. Agora a placa e materia neutra e o `tint` pinta o corte e a regua do
## pe: a faixa passa a dizer em que sala voce esta.
static func banner(text: String, tint: Color = Color.WHITE, size: int = F_H1) -> Control:
	var p := PanelContainer.new()
	var sb := StyleBoxTexture.new()
	sb.texture = _em_cache("faixa", TEX_BANNER, TEX_BANNER_M, _acento(tint), LAJOTA_HI)
	sb.texture_margin_left = BANNER_MARGEM
	sb.texture_margin_right = BANNER_MARGEM
	sb.texture_margin_top = 0
	sb.texture_margin_bottom = 0
	sb.content_margin_left = 26
	sb.content_margin_right = 26
	# A placa ocupa 61 px de uma peca de 64 (os 3 de baixo sao a sombra dura),
	# logo o centro visual esta em 30,5 e nao em 32. Margens de 8/11 poem o
	# centro da caixa de texto exatamente ali. Com 8/8 a frase subia 1,5 px --
	# a mesma classe de erro que ja tinha encostado o acento de "ESTA" na borda.
	sb.content_margin_top = 8
	sb.content_margin_bottom = 11
	sb.axis_stretch_horizontal = StyleBoxTexture.AXIS_STRETCH_MODE_STRETCH
	sb.axis_stretch_vertical = StyleBoxTexture.AXIS_STRETCH_MODE_STRETCH
	sb.modulate_color = Color.WHITE
	p.add_theme_stylebox_override("panel", sb)
	p.custom_minimum_size = Vector2(0, BANNER_H)
	var row := box(false, 12)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	p.add_child(row)
	var l := label(text, size, Color(1, 1, 1), HORIZONTAL_ALIGNMENT_CENTER)
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(l)
	return p


## Barra de 3 fatias do UI Pack RPG. `color_name`: green | red | blue | yellow.
static func bar(color_name: String, height: int = 18,
		tint: Color = Color.WHITE) -> PrismaBar:
	return PrismaBar.make(color_name, height, tint)


# --- a atmosfera da sala ----------------------------------------------------

static var _halo_tex: GradientTexture2D = null


## A LUZ DA SALA. Quatro telas do jogo sao o MESMO retangulo ao pixel (loja e
## cozinha: 954x604 em (323,148), identico), e e por isso que "A PANELA ESTA NO
## FOGO" e "FEIRA DE PASSAGEM" leem como a mesma tela com as palavras trocadas.
##
## Esta peca e a diferenca mais barata possivel: um halo ADITIVO na cor do
## lugar, entrando pelo alto a esquerda -- de onde a luz entra em todo
## recipiente deste kit, pelo corte.
##
## Por que aditivo e nao um veu por cima: um veu escurece o que ja esta escuro e
## achata mais ainda; somar 6% da cor da sala num fundo #0f0d18 sobe o canal em
## ~15 e a sala aparece SEM tirar contraste de nada.
##
## Por que a textura e 64x36 com filtro NEAREST: em 1600x900 o degrau sai com
## ~25 px. Um degrau grosso E a gramatica certa aqui -- um halo liso ao lado de
## pixel art 1:1 denuncia que veio de outro jogo. Um gradiente suave de 6% ainda
## por cima faria bandas de ~60 px, que e o pior dos dois mundos.
##
## Efeito colateral de proposito: registra `UI.sala`, que e de onde a sombra
## dura dos titulos 36/54 tira a cor.
##
## `forca` negativa (o padrao) significa "a forca da paleta ativa"
## (`sala_forca` em data/paleta.json). O sentinela existe porque a intensidade
## do halo e um numero de APARENCIA, e numero de aparencia nao mora em .gd --
## mas as dez telas que ja passam a sua propria forca (0.04 a 0.075) continuam
## mandando nela.
static func luz_de_sala(cor: Color, forca: float = -1.0) -> Control:
	if forca < 0.0:
		forca = SALA_FORCA
	sala = cor
	var raiz := Control.new()
	raiz.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	raiz.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var tr := TextureRect.new()
	tr.texture = _halo()
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_SCALE
	tr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	tr.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tr.modulate = Color(cor.r, cor.g, cor.b, clampf(forca, 0.0, 1.0))
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	tr.material = mat
	raiz.add_child(tr)
	# A FISSURA SAIU DAQUI (16/09). Ela cruzava a tela inteira em diagonal,
	# por cima de molduras, e o autor leu isso como "vazamento de tela".
	# Decoracao que o jogador le como defeito falhou no trabalho dela.
	# `fissura()` continua no kit: se voltar, volta recortada DENTRO de um
	# painel, onde a aresta que ela cruza e a do proprio painel.
	return raiz


static func _halo() -> GradientTexture2D:
	if _halo_tex == null:
		var g := Gradient.new()
		g.offsets = PackedFloat32Array([0.0, 1.0])
		g.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0)])
		_halo_tex = GradientTexture2D.new()
		_halo_tex.gradient = g
		_halo_tex.width = 64
		_halo_tex.height = 36
		_halo_tex.fill = GradientTexture2D.FILL_RADIAL
		# nao centrado: a luz entra pelo alto a esquerda, como no corte
		_halo_tex.fill_from = Vector2(0.30, 0.16)
		_halo_tex.fill_to = Vector2(1.15, 1.0)
	return _halo_tex


## A FISSURA -- um risco de cabelo de 1 px, um por tela.
##
## E a quinta assinatura da direcao e a unica coisa do jogo que nao sai de uma
## regra: nunca centrada, nunca simetrica, sempre cruzando um canto. Na versao
## final ela e DESENHADA A MAO pela artista, uma por tela, e e justamente por
## nao ser gerada que ela funciona.
##
## ISTO AQUI E UM PLACEHOLDER. A versao definitiva e um PNG por tela em
## assets/ui/fissura_*.png. Ate la, uma poligonal determinada pela cor da sala:
## a mesma sala da sempre a mesma fissura (entao os prints sao comparaveis) e
## salas diferentes dao fissuras diferentes.
static func fissura(cor: Color, tamanho: Vector2 = Vector2(1600, 900)) -> Control:
	var c := Control.new()
	c.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var rng := RandomNumberGenerator.new()
	rng.seed = int(cor.to_rgba32())
	var canto: int = rng.randi() % 4
	# fracoes sempre longe de 0,5: a fissura nunca corta o quadro ao meio
	var a: float = rng.randf_range(0.08, 0.36)
	var b: float = rng.randf_range(0.10, 0.44)
	var meio: float = rng.randf_range(0.30, 0.46)
	var w: float = tamanho.x
	var h: float = tamanho.y
	var p0: Vector2
	var p1: Vector2
	match canto:
		0: p0 = Vector2(w * a, 0.0); p1 = Vector2(0.0, h * b)
		1: p0 = Vector2(w * (1.0 - a), 0.0); p1 = Vector2(w, h * b)
		2: p0 = Vector2(w * a, h); p1 = Vector2(0.0, h * (1.0 - b))
		_: p0 = Vector2(w * (1.0 - a), h); p1 = Vector2(w, h * (1.0 - b))
	var l := Line2D.new()
	l.width = 1.0
	l.antialiased = false
	l.default_color = Color(cor.r, cor.g, cor.b, 0.22).lightened(0.55)
	# o ponto do meio sai da reta: uma fissura reta le como risco de regua
	var d := p1 - p0
	var quebra := p0 + d * meio + Vector2(-d.y, d.x).normalized() * (w * 0.012)
	l.points = PackedVector2Array([p0, quebra, p1])
	c.add_child(l)
	return c
