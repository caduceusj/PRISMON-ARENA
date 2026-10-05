class_name MonsterPortrait
extends Control
## Retrato de uma criatura dentro da UI. Usa o mesmo montador do campo de
## batalha, entao o que voce ve no Ninho e exatamente o que entra em campo.

var species_id: String = ""
var element: String = "FOGO"
var body_height: float = 46.0
var show_ground: bool = true
var ring: Texture2D = null      # medalhao circular do pacote da Kenney
var ring_tint := Color.WHITE


## ATENCAO — largura DEPENDENTE DA ESPECIE.
##
## `h` e a altura do CORPO, e a largura minima sai das metricas da arte
## (`m["wide"] * 1.08`). Cada criatura tem uma silhueta diferente, entao cada
## retrato tem uma largura diferente. Numa LISTA isso e um defeito: o texto ao
## lado comeca num x distinto em cada linha e a coluna fica serrilhada — foi o
## que se via nas linhas "3 Apollos / 3 Pinto-Raios" da escolha de combate e
## nos nomes do painel de combate.
##
## Regra: quando o retrato ENCABECA uma linha de texto numa lista, use
## `medallion()`, que e um quadrado de lado fixo (e ainda traz o aro na cor do
## elemento, a camada 1 de leitura do GDD 21.4). `make()` e para retrato
## solitario e centrado — e desde 15/09 ele tambem tem CAIXA FIXA (ver abaixo).
##
## CAIXA FIXA POR PADRAO (revisao 15/09: "make dimensiona a caixa pela silhueta
## da especie, o que desalinha as telas de comparacao lado a lado").
##
## A caixa antiga saia de `m["wide"] * 1,08`, e `wide` e a largura REAL do
## sprite. Medido em h = 84 (o tamanho do cartao de recruta), a caixa ia de
## 75,6 px (Coalla) a 113,4 px (Hipocampo) — 37,8 px de diferenca entre dois
## cartoes que existem para ser COMPARADOS um ao lado do outro. Tudo o que
## vem depois do retrato dentro do cartao herda esse deslocamento.
##
## `LARGURA_CAIXA` e a razao da especie mais larga (Hipocampo, 30/24 = 1,25)
## vezes a mesma folga de 1,08 — ou seja, a caixa nova e exatamente a caixa que
## o pior caso ja ocupava hoje. Nenhuma tela fica mais larga do que ja estava; o
## que muda e que todas ficam iguais. O SPRITE nao muda de tamanho: quem manda
## no desenho e `body_height`, e nao a caixa.
##
## `caixa_fixa = false` volta a caixa justa, para quem quiser um retrato
## solitario colado no texto.
const LARGURA_CAIXA := 1.35

static func make(sp_id: String, el: String, h: float = 46.0,
		caixa_fixa: bool = true) -> MonsterPortrait:
	var p := MonsterPortrait.new()
	p.species_id = sp_id
	p.element = el
	p.body_height = h
	var m: Dictionary = MonsterArt.metrics(sp_id, el, h)
	var larg: float = h * LARGURA_CAIXA if caixa_fixa \
		else maxf(float(m["wide"]) * 1.08, h * 0.9)
	p.custom_minimum_size = Vector2(larg, float(m["total_h"]) + 4.0)
	# IGNORE, e sem dica: os dois usos de `make` vivem dentro de um CardButton,
	# cujo botao invisivel cobre o cartao inteiro e e sempre ele o alvo do
	# cursor. Uma dica aqui seria letra morta — o mesmo defeito que a revisao
	# achou no medalhao do dono da Feira. Quem encabeca a leitura e o cartao.
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# as pecas da Kenney sao vetoriais: nearest (o padrao do projeto) serrilha
	p.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	return p


## Retrato em medalhao: a criatura dentro de uma moldura circular do pacote.
## Substitui "pastilha de elemento + nome em negrito" por uma imagem so.
static func medallion(sp_id: String, el: String, diameter: float = 58.0,
		gold: bool = false) -> MonsterPortrait:
	var p := MonsterPortrait.new()
	p.species_id = sp_id
	p.element = el
	# ENCAIXE PELA MAIOR DIMENSAO. Antes era `diameter * 0.62` seco, sem
	# olhar a proporcao do sprite: uma criatura larga (Pinto-Raio, 47x46)
	# ficava desenhada com 62% da altura e sobrava aro vazio em volta, e
	# uma estreita (Coalla, 26x34) ficava do mesmo tamanho aparente que
	# uma grande. Agora a MAIOR dimensao do sprite e que ocupa 86% do
	# diametro, entao todo bicho preenche o medalhao da mesma forma.
	var m0: Dictionary = MonsterArt.metrics(sp_id, el, 100.0, true)
	var aspecto: float = maxf(float(m0["w"]) / 100.0, 1.0)
	p.body_height = diameter * 0.86 / aspecto
	p.show_ground = false
	p.ring = UI.TEX_RING_GOLD if gold else UI.TEX_RING
	p.ring_tint = Db.el_color(el).lightened(0.15) if not gold else Color.WHITE
	p.custom_minimum_size = Vector2(diameter, diameter)
	p.mouse_filter = Control.MOUSE_FILTER_PASS
	# A DICA QUE NAO EXISTIA (revisao 15/09, achado da composicao dos menus).
	#
	# "as cinco estrelas e os tres patos do canto da preparacao nao tem
	# explicacao, e nao e que ela esteja escondida, e que ela NAO EXISTE":
	# `medallion` era chamado em onze lugares e nunca definia `tooltip_text`,
	# entao os tres medalhoes de inimigo do cabecalho da preparacao eram tres
	# bichos anonimos — a unica tela em que o jogador ainda pode montar a
	# equipe sabendo o que o espera.
	#
	# A ficha vem do medalhao, e nao das telas, porque ele e a unica peca que
	# SEMPRE sabe de qual especie esta falando. Quem ja tem uma dica melhor (o
	# trilho, o painel de combate, a doca) continua ganhando: essas telas poem
	# `mouse_filter = IGNORE` no medalhao de proposito, e ai o alvo do cursor e
	# o pai, com a dica dele.
	p.tooltip_text = ficha(sp_id, el)
	p.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	return p


## A FICHA DE UMA ESPECIE, no mesmo formato das outras dicas do jogo: manchete
## na primeira linha, o resto numa linha so separada por `·` (TooltipLayer).
##
## E de ESPECIE e nao de instancia de proposito: o medalhao aparece tanto para
## um Cara do elenco quanto para um inimigo que ainda nao existe como unidade.
## Quem tem instancia na mao (itens, pratos, HP de agora) escreve a dica dele no
## pai, que e onde esse detalhe cabe.
static func ficha(sp_id: String, el: String) -> String:
	var d: Dictionary = Db.sp(sp_id)
	var nome := Db.sp_name(sp_id)
	# o chefe nao esta em species.json: a ficha dele vive em enemies.json, e o
	# id que as telas passam e o do chefe, nao o do sprite emprestado.
	if d.is_empty() and sp_id == String(Db.boss.get("id", "")):
		d = Db.boss
		nome = String(Db.boss.get("name", nome))
	if d.is_empty():
		return nome
	var linhas: Array = ["%s — %s · %s · %s" % [nome, Db.el_name(el),
		Db.role_name(String(d.get("role", ""))), String(d.get("stance", ""))]]
	linhas.append("HP %d · ATK %d · DEF %d · VEL %.1f · PE %d" % [
		int(d.get("hp", 0)), int(d.get("atk", 0)), int(d.get("def", 0)),
		float(d.get("vel", 1.0)), int(d.get("pe", 0))])
	var ult: Dictionary = d.get("ult", {})
	if not ult.is_empty():
		linhas.append("⚡ %s — %s" % [String(ult.get("name", "")),
			String(ult.get("text", ""))])
	return "\n".join(linhas)


func refresh(sp_id: String, el: String) -> void:
	species_id = sp_id
	element = el
	queue_redraw()


func _draw() -> void:
	if species_id == "":
		return
	# `ring != null` quer dizer medalhao, e medalhao enquadra pelo idle
	var m: Dictionary = MonsterArt.metrics(species_id, element, body_height,
		ring != null)
	var feet: float = float(m["feet"])
	var at := Vector2(size.x * 0.5, size.y - feet - 2.0)
	if size.y < float(m["total_h"]):
		at.y = size.y * 0.5 - float(m["centre_off"])
	if ring != null:
		var d: float = minf(size.x, size.y)
		var o := (size - Vector2(d, d)) * 0.5
		# fundo do medalhao, depois a criatura, depois o aro por cima
		draw_circle(size * 0.5, d * 0.43, Color(0, 0, 0, 0.45))
		# centra pela extensão REAL da arte: o centro visual não é o centro do
		# corpo, porque perna e adorno não são simétricos
		at = Vector2(size.x * 0.5, size.y * 0.5 - float(m["centre_off"]))
		MonsterArt.draw_unit(self, species_id, element, at, body_height,
			1.0, Color.WHITE, true)
		draw_texture_rect(ring, Rect2(o, Vector2(d, d)), false, ring_tint)
		return
	if show_ground:
		var w: float = float(m["w"]) * 0.5
		var pts := PackedVector2Array()
		for i in range(25):
			var a: float = TAU * float(i) / 24.0
			pts.append(Vector2(at.x + cos(a) * w, at.y + feet + sin(a) * w * 0.3))
		draw_colored_polygon(pts, Color(0, 0, 0, 0.28))
	MonsterArt.draw_unit(self, species_id, element, at, body_height)
