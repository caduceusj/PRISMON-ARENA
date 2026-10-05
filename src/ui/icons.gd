class_name Icons
extends RefCounted
## Ícones do jogo. O mapa semântico vive em data/icons.json — nome → posição no
## sheet — seguindo o mesmo princípio do resto do conteúdo (GDD §22.1: dados
## fora do código).
##
## Duas fontes, por motivos diferentes:
##   * Shikashi (32×32, colorido) — ícones de CONTEÚDO: itens, pratos, relíquias,
##     ativos, tipos de nó. Já vêm coloridos e não devem ser tingidos.
##   * Board Game Icons da Kenney (silhueta branca) — glifos de SISTEMA, usados
##     onde a cor precisa vir do elemento e não do ícone.

static var _atlas: Dictionary = {}     # nome -> AtlasTexture
static var _sheet: Texture2D = null


# --- os glifos que vinham do SISTEMA OPERACIONAL ----------------------------
#
# ACHADO da revisao 15/09: "o glifo mais repetido da interface vem do fallback
# do sistema operacional". assets/CREDITOS.md ja registrava o risco por
# escrito: NENHUMA fonte do projeto contem ★ ⚡ ❄ ◆ ◇ → ✔ ○ — nem a Pixelify,
# que era a suposta dona deles. Quem os desenha e a fonte que o SO empresta,
# entao o mesmo rotulo muda de forma entre maquinas, muda de forma entre
# Windows e Linux, e pode simplesmente sair como caixa vazia numa build.
# Contados no fonte: 26 linhas em 14 arquivos.
#
# Aqui cada glifo aponta para um icone que o projeto JA TEM, e o nome continua
# saindo de data/icons.json (§22.1) -- este mapa nao conhece nenhum caminho de
# arquivo, so nomes. Os escolhidos sao todos silhuetas brancas da Kenney (CC0),
# que e a familia feita justamente para "glifo de sistema".
#
# Duas saidas, porque ha dois destinos:
#   `node(glifo_icone(ch))`  para um Control numa linha de interface
#   `marcar(texto)`          para texto em BBCode (as dicas) -- ver TooltipLayer
const GLIFOS := {
	"⚡": "g_crown",       # a ultimate: o golpe do alto da ficha
	"◆": "g_sword",       # item equipado
	"◇": "g_campfire",    # prato (a Cozinha do jogo e uma panela no fogo)
	"→": "g_arrow",       # "vira", "passa a ser"
	"▲": "g_skull",       # traco de chefe
	"❄": "g_hourglass",   # congelado — a ampulheta diz "parado", que e o efeito
}

## O LOSANGO NAO ENTRA NESTE MAPA de proposito: ★/☆ (perigo) e ◆◆ (o par de
## energias de uma reacao) viraram `Gem`, que desenha o losango pixel a pixel.
## Um icone de 32 px nao cabe numa fileira de cinco pips, e o losango e a
## forma da casa -- o prisma. Ver RunRibbon.perigo() e SynergyStrip.


static func _map() -> Dictionary:
	return Db.icons.get("icons", {})


static func has(name: String) -> bool:
	return _map().has(name) or Db.icons.get("files", {}).has(name)


## O nome de icone que substitui um glifo, ou "" quando nao ha substituto.
## Confere contra os dados: um nome que sumir de icons.json volta a ser texto,
## nunca vira um retangulo vazio.
static func glifo_icone(ch: String) -> String:
	var nome: String = String(GLIFOS.get(ch, ""))
	return nome if nome != "" and has(nome) else ""


## Caminho do PNG de um icone de arquivo (os `g_*` da Kenney). Os do atlas do
## Shikashi devolvem "": eles sao uma REGIAO de um sheet de 16 colunas, e o
## `[img]` do BBCode nao sabe recortar regiao.
static func caminho(name: String) -> String:
	return String(Db.icons.get("files", {}).get(name, ""))


## TROCA OS GLIFOS DE UM TEXTO POR IMAGENS, em BBCode.
##
## Isto existe para as DICAS: elas sao o unico lugar do jogo em que o simbolo
## nao pode virar um `Control` (e uma string, montada por dezenas de telas).
## Chamado de um lugar so -- TooltipLayer.formatar -- entao toda dica do jogo
## para de depender da fonte do sistema sem que nenhuma tela mude uma linha.
##
## PRECISA RODAR DEPOIS DO ESCAPE de colchetes: o proprio TooltipLayer troca
## "[" por "[lb]" para que um texto de dados nao abra marcacao, e as tags que
## esta funcao insere nao podem passar por essa troca.
static func marcar(txt: String, px: int = 14) -> String:
	var out := txt
	for ch in GLIFOS:
		if not out.contains(ch):
			continue
		var p := caminho(glifo_icone(String(ch)))
		if p == "":
			continue
		out = out.replace(String(ch), "[img=%d]%s[/img]" % [px, p])
	return out


## Textura de um ícone. Devolve null quando o nome não existe — quem chama
## decide se cai para texto.
static func tex(name: String) -> Texture2D:
	if _atlas.has(name):
		return _atlas[name]
	var files: Dictionary = Db.icons.get("files", {})
	if files.has(name):
		var t: Texture2D = load(String(files[name]))
		_atlas[name] = t
		return t
	var m := _map()
	if not m.has(name):
		return null
	if _sheet == null:
		var sheet_cfg: Dictionary = Db.icons.get("sheet", {})
		_sheet = load(String(sheet_cfg.get("path", "")))
	var cfg: Dictionary = Db.icons.get("sheet", {})
	var ts: int = int(cfg.get("tile", 32))
	var rc: Array = m[name]
	var a := AtlasTexture.new()
	a.atlas = _sheet
	a.region = Rect2(int(rc[1]) * ts, int(rc[0]) * ts, ts, ts)
	a.filter_clip = true
	_atlas[name] = a
	return a


## TextureRect pronto para entrar num container.
##
## Nome inexistente NAO reserva espaco. A versao anterior devolvia um
## TextureRect vazio com `custom_minimum_size` cheio: a linha ficava com um
## buraco invisivel do tamanho de um icone, e como so alguns nomes faltavam
## ("stomach", "rx_*", os Ativos sem arte) o buraco aparecia numa linha e nao
## na outra — as linhas desalinhavam entre si sem motivo visivel. Era metade
## do "icones esparsos" dos prints do autor.
static func node(name: String, px: float = 24.0, tint: Color = Color.WHITE) -> TextureRect:
	var t := tex(name)
	var r := TextureRect.new()
	r.texture = t
	r.visible = t != null
	r.custom_minimum_size = Vector2(px, px) if t != null else Vector2.ZERO
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	r.modulate = tint
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	# pixel art: nearest, como o resto da UI
	r.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	return r


# --- atalhos por tipo de conteúdo ------------------------------------------

static func element(element_id: String, px: float = 22.0) -> TextureRect:
	return node("elem_" + element_id, px)

static func role(role_id: String, px: float = 20.0) -> TextureRect:
	return node("role_" + role_id, px)

static func node_type(type_id: String, px: float = 28.0) -> TextureRect:
	return node("node_" + type_id, px)

static func item(item_id: String, px: float = 26.0) -> TextureRect:
	return node("item_" + item_id, px)

static func dish(dish_id: String, px: float = 26.0) -> TextureRect:
	return node("dish_" + dish_id, px)

static func relic(relic_id: String, px: float = 26.0) -> TextureRect:
	return node("relic_" + relic_id, px)

static func active(active_id: String, px: float = 24.0) -> TextureRect:
	return node("act_" + active_id, px)


## Ícone + número, o par que aparece o tempo todo no HUD.
static func counter(icon_name: String, text: String, color: Color = UI.TEXT,
		px: float = 20.0, size: int = UI.F_H2) -> Control:
	var row := UI.box(false, 4)
	var ic := node(icon_name, px)
	if ic.texture != null:
		row.add_child(ic)
	row.add_child(UI.label(text, size, color))
	return row
