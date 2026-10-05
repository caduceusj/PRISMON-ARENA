class_name Gem
extends Control
## O losango de elemento, desenhado PIXEL A PIXEL.
##
## Era um ColorRect girado 45 graus. Girado, ele deixa de cair na grade de
## pixels: a rasterizacao passa a depender da posicao FRACIONARIA do no na
## linha, entao dois losangos do mesmo tamanho, lado a lado, saiam com alturas
## e bordas diferentes. Foi o que o autor viu na tira de sinergias — "os icones
## estao desalinhados com o texto e ta muito feio".
##
## Aqui o losango e uma pilha de retangulos de 1 px em coordenadas INTEIRAS:
## identico em qualquer posicao da linha, e com o degrau de pixel art do resto
## da interface em vez da diagonal lisa de um quadrado girado.
##
## Ele tambem se centra sozinho na vertical (SHRINK_CENTER), que era a outra
## metade do desalinhamento: o holder antigo esticava com a altura da linha e o
## losango ficava preso perto do topo, acima do meio do texto ao lado.

var color: Color = Color.WHITE
var half: int = 5          # lado a lado o losango tem 2*half + 1 px
## Losango OCO: so o contorno de 1 px. E o "vazio" de um contador de pips —
## a mesma forma, sem materia dentro. Ver o porque em `make`.
var oco := false


## O LOSANGO VAZIO SUBSTITUI O ☆ (revisao 15/09).
##
## Perigo era "★★★☆☆" numa Label, e as duas estrelas vem da fonte que o sistema
## operacional empresta (assets/CREDITOS.md: nenhuma fonte do projeto as tem).
## Trocar por icone de 32 px nao serve: uma fileira de cinco pips de 11 px com
## um sprite de 32 dentro ou reamostra pixel art em fracao quebrada, ou ocupa
## 160 px de largura para dizer um numero de 1 a 5.
##
## O losango ja e a forma da casa — e o prisma, e ele ja rotula elemento na
## tira de sinergias. Cheio = um degrau de perigo; oco = um degrau que falta.
## A leitura sobrevive a escala de cinza, que a cor sozinha nao garantia.
static func make(c: Color, h: int = 5, alpha: float = 1.0, cheio: bool = true) -> Gem:
	var g := Gem.new()
	g.color = Color(c.r, c.g, c.b, alpha)
	g.half = maxi(h, 1)
	g.oco = not cheio
	var s := float(g.half * 2 + 1)
	g.custom_minimum_size = Vector2(s, s)
	g.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	g.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	g.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return g


func _draw() -> void:
	var n := half * 2 + 1
	# ancora em pixel inteiro: e o que garante que dois losangos vizinhos
	# fiquem identicos, mesmo que os pais os coloquem em x fracionarios
	var ox := floorf((size.x - float(n)) * 0.5)
	var oy := floorf((size.y - float(n)) * 0.5)
	for i in range(n):
		var w: int = (half - absi(i - half)) * 2 + 1
		var x0: float = ox + float(half - (w - 1) / 2)
		if not oco or w <= 2:
			draw_rect(Rect2(x0, oy + float(i), float(w), 1.0), color)
			continue
		# oco: so as duas pontas da linha. Sem isto o "vazio" teria de ser uma
		# segunda cor chapada, e um losango cinza-claro cheio le como um degrau
		# de perigo aceso e apagado ao mesmo tempo.
		draw_rect(Rect2(x0, oy + float(i), 1.0, 1.0), color)
		draw_rect(Rect2(x0 + float(w - 1), oy + float(i), 1.0, 1.0), color)
