class_name RanchView
extends Control
## O Rancho: sua equipe em pé no meio da tela, tocando idle, enquanto o
## jogador decide o próximo combate.
##
## O centro estava vazio — corretamente livre de UI, mas também sem nada que
## dissesse "este é o SEU time". No How Many Dudes é a multidão parada no
## terreno que dá peso à decisão: você vê quem vai lutar antes de escolher
## contra quem. As criaturas ficam em arco, ordenadas por Postura, para a
## formação prevista já se ler no chão.

const ORDER := {"Vanguarda": 0, "Meio": 1, "Retaguarda": 2, "Suporte": 3}

## PROFUNDIDADE DO ARCO, EM PIXELS (revisão 15/09 — "a fileira de nomes escorrega
## 27 px de amplitude medida").
##
## Era 30,0, e a correção anterior (a de 31/08, logo abaixo, que levou a curva do
## centro do sprite para a linha dos PÉS) resolveu só metade da causa: os pés
## passaram a seguir a curva juntos, mas a curva continuou sendo a mesma de 30 px
## e os NOMES continuaram pendurados em cada pé.
##
## A conta do defeito: `cos(f*PI)` vai de 0 nas pontas a 1 no meio, então o pé do
## meio nascia 30 px abaixo do pé das pontas; somando a sombra, que é `h*0,09` e
## varia com a espécie (9,5 px no Pinto-Raio a 13,8 px na Sheep), a base de cada
## nome variava junto.
##
## MEDIDO com cinco corpos (sonda do agente "peças", 15/09): a base por-pé dava
## 27,8 px de amplitude com o arco de 30 — que é o número de 27 px dos prints —
## e dá 7,2 px com o arco de 9. A linha que de fato é desenhada dá 0,0, porque
## ela é UMA (ver o fim de `_layout`).
##
## 9 px é o mesmo degrau do canto cortado do kit (três degraus de 3). Mantém a
## leitura de "quem está no meio está à frente" e derruba o pior afastamento
## entre um nome e o seu dono para menos de um corpo de texto.
const ARCO := 9.0

## ------------------------------------------------------------------------
## CONSERTO DE 16/09 — OS NOMES SE SOBREPUNHAM NA HORIZONTAL.
##
## Print do autor, com cinco corpos: sai literalmente
## "SheepPinto-RaioHipocampoApollo Coalla". Os dois consertos anteriores (os
## comentários acima) atacaram a ALTURA dos rótulos, que era o defeito de 15/09,
## e a altura está resolvida — hoje a fileira inteira divide UMA base.
##
## A causa do defeito NOVO é outra e está na linha do espaçamento: o passo entre
## dois corpos vizinhos era `span / (n-1)` com `span = min(largura/2, 90 + n*78)`
## — um número tirado do TAMANHO DO SPRITE, que nada sabe do nome que vai
## debaixo dele. Medido nesta fonte (corpo 26): "Hipocampo" ocupa ~110 px e
## "Pinto-Raio" ~120, enquanto o passo do arco com cinco corpos na preparação
## dava 96 px. Dois rótulos vizinhos se encavalavam por construção, sempre, e
## nenhum ajuste de arco ou de base podia resolver isso.
##
## Agora a fileira é medida: cada criatura ocupa uma CAIXA cuja largura é o
## maior entre o sprite desenhado (`MonsterArt.metrics`) e o nome (medido na
## fonte real, no mesmo corpo em que será desenhado), e os vizinhos avançam por
## essa caixa mais uma folga. A sobreposição fica impossível por construção, em
## qualquer elenco e em qualquer largura de caixa.
##
## O AJUSTE quando não cabe tem ordem: encolhe o CORPO primeiro (o nome não
## muda de tamanho; encolher a letra seria trocar um defeito por outro), depois
## aperta a folga até `FOLGA_MIN`, e só num retângulo impossível comprime o
## conjunto proporcionalmente.
##
## E a ESCALA SUBIU de 2,4 para 3,6: o mesmo print mostra "um vazio grande
## embaixo das criaturas". O rancho é o assunto da tela de preparação, e um
## corpo de 105 px no meio de uma caixa de 660 não é assunto de nada.

## Altura de desenho = `size` da espécie × isto. É um TETO, não um valor fixo:
## as duas travas abaixo (altura da caixa e largura da fileira) derrubam a
## escala sozinhas onde a caixa é menor. Medido: 3,6 na preparação em tela
## cheia, ~3,2 na tela de escolha (caixa de 424 px de altura) e ~2,5 na
## preparação dentro da run, onde o trilho do elenco come 288 px de largura.
## As espécies vão de 44 a 64, então o teto desenha entre 158 e 230 px.
const ESCALA := 3.6
const ESCALA_MIN := 1.5

## Folga MÍNIMA entre as CAIXAS de dois vizinhos — não entre os centros deles.
const FOLGA := 30.0
const FOLGA_MIN := 12.0

## Respiro nas duas bordas do rancho: o nome da ponta nunca encosta na moldura.
const BORDA := 20.0

## Onde o bloco (corpos + sombra + linha de nomes) se ancora na altura da caixa.
## 0,5 seria o centro exato; 0,56 empurra o grupo um pouco para baixo, na
## direção do botão que fecha a tela — a folga que sobra vai para CIMA, onde ela
## lê como ar sob o cabeçalho, e não para baixo, onde lia como buraco entre o
## elenco e o LUTAR. Na tela de escolha o valor tem de continuar deixando o
## grupo ACIMA dos dois cartões de combate, e deixa: a trava de altura já
## derruba a escala lá, e o bloco inteiro cabe na faixa que ela reserva.
const ANCORA := 0.56

var _t := 0.0
var _spots: Array = []
## A base ÚNICA dos nomes, calculada no layout. Ver `_layout`.
var _linha_nomes := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	Run.team_changed.connect(_layout)
	resized.connect(_layout)
	set_process(true)
	_layout()


func _process(delta: float) -> void:
	_t += delta
	queue_redraw()


## Arco raso, ordenado por Postura: vanguarda à frente, suporte atrás. A mesma
## leitura da "formação prevista" da preparação, mas no chão.
func _layout() -> void:
	_spots.clear()
	if Run.team.is_empty() or size.x < 10.0:
		return
	var team: Array = Run.team.duplicate()
	team.sort_custom(func(a, b):
		var oa: int = int(ORDER.get(a.stance(), 9))
		var ob: int = int(ORDER.get(b.stance(), 9))
		if oa != ob:
			return oa < ob
		return a.uid < b.uid)

	var n: int = team.size()
	var font: Font = _fonte()
	var sz: int = UI.fs(12)

	# A largura do NOME não depende da escala do corpo: mede-se uma vez.
	var nomes: Array = []
	var maior: float = 1.0
	for u in team:
		nomes.append(font.get_string_size(String(u.display_name()),
			HORIZONTAL_ALIGNMENT_LEFT, -1, sz).x)
		maior = maxf(maior, MonsterArt.size_of(u.species_id))

	# teto de ALTURA: numa caixa baixa (a tela de escolha dá 424 px ao rancho) o
	# corpo inteiro tem de caber junto com a sombra e a linha de nomes.
	var escala: float = clampf((size.y * 0.58 - 40.0) / maior, ESCALA_MIN, ESCALA)
	var folga: float = FOLGA
	var disponivel: float = maxf(size.x - BORDA * 2.0, 120.0)
	var larguras: Array = _larguras(team, nomes, escala)
	var total: float = _total(larguras, folga)

	# 1) encolhe o CORPO — o nome fica no tamanho em que se lê
	while total > disponivel and escala > ESCALA_MIN:
		escala = maxf(escala * 0.94, ESCALA_MIN)
		larguras = _larguras(team, nomes, escala)
		total = _total(larguras, folga)
	# 2) aperta a folga
	while total > disponivel and folga > FOLGA_MIN:
		folga = maxf(folga - 2.0, FOLGA_MIN)
		total = _total(larguras, folga)
	# 3) retângulo impossível: comprime tudo por igual em vez de vazar
	var k: float = 1.0 if total <= disponivel else disponivel / maxf(total, 1.0)
	var largo: float = total * k

	# O BLOCO INTEIRO SE CENTRA, não o pé. A altura útil vai do topo do corpo
	# mais alto até a linha dos nomes; centrar só a linha do chão era o que
	# deixava "um vazio grande embaixo das criaturas" do print.
	var alto: float = maior * escala
	var abaixo: float = alto * 0.09 + font.get_ascent(sz) + 5.0
	var cy: float = (size.y - (alto + ARCO + abaixo)) * ANCORA + alto
	var cx: float = size.x * 0.5

	var x: float = cx - largo * 0.5
	for i in range(n):
		var w: float = float(larguras[i]) * k
		var px: float = x + w * 0.5
		x += w + folga * k
		# `f` sai da posição REAL, e não de um passo uniforme: as caixas têm
		# larguras diferentes, então o índice já não diz onde a criatura está.
		var f: float = 0.0 if n == 1 else clampf((px - cx) / maxf(largo, 1.0), -0.5, 0.5)
		# O arco vai para a linha dos PES, nao para o centro do sprite. As
		# criaturas tem alturas diferentes (o corpo vai de 132 a 250 px de
		# altura no rig), entao aplicar a curva ao centro punha cada pe num
		# y diferente: a fileira de nomes escorregava 26 px e o grupo nao
		# parecia pisar no mesmo terreno. Aqui o pe segue a curva e o corpo
		# sobe a partir dele.
		var chao: float = cy + cos(f * PI) * ARCO
		var h: float = MonsterArt.size_of(team[i].species_id) * escala
		_spots.append({"u": team[i], "pos": Vector2(px, chao - h * 0.5), "chao": chao,
			"h": h, "phase": float(i) * 0.37, "flip": -1.0 if f > 0.02 else 1.0})

	# UMA LINHA SÓ PARA TODOS OS NOMES — é isto que conserta o escorregão.
	#
	# Encolher o arco reduz o padrão; não o apaga, porque a sombra ainda muda de
	# raio com a espécie. Com uma base comum a amplitude vai a ZERO por
	# construção: os nomes deixam de ser uma etiqueta pendurada em cada pé e
	# viram a legenda da fileira, que é o que uma escalação é.
	#
	# A base é a mais baixa de todas (`max`), então nenhum nome sobe por cima de
	# sombra ou de perna — a folga de 31/08 continua valendo para o pior caso.
	var fundo := 0.0
	for s in _spots:
		fundo = maxf(fundo, float(s["chao"]) + float(s["h"]) * 0.09)
	_linha_nomes = fundo + font.get_ascent(sz) + 5.0


## A CAIXA de cada criatura: o maior entre o sprite desenhado e o nome.
##
## É esta função que torna a sobreposição impossível. `MonsterArt.metrics`
## devolve a largura REAL do retângulo desenhado (px_w/px_h do rig × altura),
## que é o mesmo número que `draw_anim` usa — não uma estimativa.
func _larguras(team: Array, nomes: Array, escala: float) -> Array:
	var out: Array = []
	for i in range(team.size()):
		var u: UnitInstance = team[i]
		var h: float = MonsterArt.size_of(u.species_id) * escala
		var m: Dictionary = MonsterArt.metrics(u.species_id, String(u.element()), h)
		out.append(maxf(float(m["w"]), float(nomes[i])))
	return out


static func _total(larguras: Array, folga: float) -> float:
	var t: float = folga * float(maxi(larguras.size() - 1, 0))
	for w in larguras:
		t += float(w)
	return t


## O TERREIRO: o chão em que o grupo pisa.
##
## O print do autor diz "sobra um vazio grande embaixo das criaturas". Metade
## disso era layout (o botão LUTAR flutuava numa faixa própria, longe; hoje ele
## fecha a coluna do palco) e metade era que o elenco pairava num campo chapado,
## sem nada dizendo onde ele está. Uma mancha rasa sob a fileira resolve a
## segunda metade sem acrescentar UMA PALAVRA à tela.
##
## É a mesma forma da sombra de cada criatura, uma escala acima, e a mesma
## matéria do kit (LAJOTA) — não é cenário novo, é a lajota do recipiente
## deitada no chão. Ela engloba também a linha dos nomes, que assim lê como
## legenda gravada no terreno em vez de texto solto no vazio.
func _terreiro() -> void:
	var esq: float = 1.0e9
	var dir: float = -1.0e9
	var chao: float = 0.0
	for s in _spots:
		var meio: float = float(s["pos"].x)
		var raio: float = float(s["h"]) * 0.34
		esq = minf(esq, meio - raio)
		dir = maxf(dir, meio + raio)
		chao = maxf(chao, float(s["chao"]))
	# a mancha respira 54 px além da fileira, MAS não encosta na moldura vizinha:
	# sem a trava ela vazava alguns pixels por baixo do painel de consulta.
	esq = maxf(esq - 54.0, 6.0)
	dir = minf(dir + 54.0, size.x - 6.0)
	var topo: float = chao - 20.0
	var base: float = _linha_nomes + 12.0
	var at := Vector2((esq + dir) * 0.5, (topo + base) * 0.5)
	var rx: float = (dir - esq) * 0.5
	var ry: float = (base - topo) * 0.5
	var pts := PackedVector2Array()
	for i in range(40):
		var a: float = TAU * float(i) / 40.0
		pts.append(at + Vector2(cos(a) * rx, sin(a) * ry))
	draw_colored_polygon(pts, Color(UI.LAJOTA.r, UI.LAJOTA.g, UI.LAJOTA.b, 0.62))


func _draw() -> void:
	if _spots.is_empty():
		return
	_terreiro()
	var frames: int = MonsterArt.frames_of("idle")
	var fps: float = MonsterArt.fps_of("idle")
	for s in _spots:
		var u: UnitInstance = s["u"]
		var p: Vector2 = s["pos"]
		var h: float = float(s["h"])

		# draw_anim ancora no CENTRO do sprite, então os pés ficam meio corpo
		# abaixo — é ali que a sombra e o nome pertencem.
		var feet: float = h * 0.5
		_shadow(p + Vector2(0, feet), h * 0.34, h * 0.09)

		var fr: int = int((_t + float(s["phase"])) * fps) % maxi(frames, 1)
		var tint: Color = MonsterArt.tint_for(u.species_id, u.element())
		# respiro vertical de 2 px: o idle sozinho já mexe, isso só desencontra
		# as criaturas para o grupo não pulsar em uníssono
		var bob: float = sin((_t + float(s["phase"])) * 1.6) * 2.0
		MonsterArt.draw_anim(self, u.species_id, "idle", fr,
			p + Vector2(0, bob), h, float(s["flip"]), tint)

		# nome discreto sob os pés — identifica sem competir com a decisão.
		# A base sai de `_linha_nomes`, que é a MESMA para a fileira inteira: a
		# altura do texto deixou de depender do lugar na curva e da espécie.
		var font: Font = _fonte()
		var sz: int = UI.fs(12)
		var nm := u.display_name()
		var w: float = font.get_string_size(nm, HORIZONTAL_ALIGNMENT_LEFT, -1, sz).x
		draw_string(font, Vector2(p.x - w * 0.5, _linha_nomes), nm,
			HORIZONTAL_ALIGNMENT_LEFT, -1, sz, Color(1, 1, 1, 0.42))


## A fonte do corpo, com o mesmo plano B do resto do projeto. Num lugar só
## porque `_layout` e `_draw` precisam medir a MESMA fonte: a base dos nomes é
## calculada num e desenhada no outro.
static func _fonte() -> Font:
	return PrismaTheme.body_font if PrismaTheme.body_font != null else ThemeDB.fallback_font


func _shadow(at: Vector2, rx: float, ry: float) -> void:
	var pts := PackedVector2Array()
	for i in range(26):
		var a: float = TAU * float(i) / 26.0
		pts.append(at + Vector2(cos(a) * rx, sin(a) * ry))
	draw_colored_polygon(pts, Color(0, 0, 0, 0.28))
