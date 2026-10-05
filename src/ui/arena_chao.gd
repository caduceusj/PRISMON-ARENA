class_name ArenaChao
extends RefCounted
## MARCAS NO PISO da arena.
##
## A ilustracao de fundo deu lugar as sete arenas, mas o CHAO continuava o mesmo
## em todas: duas elipses concentricas e um veu de cor. Quem assiste ao combate
## olha o chao, nao o horizonte — entao era ali que a arena menos existia. Estas
## marcas resolvem isso: o ladrilho da Camara, os aneis do Campo Magnetico e
## as lajes da Arena Assombrada.
##
## SAO GERADAS UMA VEZ POR COMBATE, com semente fixa. Marca de piso que muda de
## quadro a quadro vira ruido piscando; esta fica onde nasceu ate o fim da briga.
##
## FICAM DENTRO DA ELIPSE. Um ponto so e aceito se cair dentro de 92% do raio do
## piso — assim nenhuma rachadura vaza para o preto em volta, que foi exatamente
## o defeito da primeira tentativa de decorar a arena.
##
## NADA E SORTEIO PURO. Ladrilho sorteado vira entulho espalhado, nao piso: a
## Camara usa uma GRADE de verdade e o Campo Magnetico usa ANEIS concentricos.
## As lajes da Arena Assombrada sao sorteadas de POSICAO mas iguais de tamanho,
## que e o que as faz ler como pedra assentada e nao confete.
##
## As coordenadas sao as do CAMPO. Quem desenha (FieldView) projeta com o mesmo
## achatamento da sombra e do anel de aura, entao as marcas deitam no chao junto
## com todo o resto.

## `op` diz a forma:
##   placa — retangulo achatado (laje, ladrilho)
##   anel  — elipse vazada e achatada (marca de runa, borda de dreno)
## SO O QUE E REGULAR SOBROU (revisao 11/09, autor: "essas pocas ai espalhadas
## estao muito feias").
##
## As `manchas` — elipses sorteadas pelo piso — e os `riscos` sairam. Espalhados
## ao acaso eles nao liam como poca nem como rachadura: liam como manchas de
## sujeira e arranhoes na tela. O que ficou de pe foi justamente o que tem
## ESTRUTURA: o ladrilho em grade da Camara e os aneis concentricos do Campo
## Magnetico, que o olho reconhece como piso construido.
##
## A licao vale para o futuro: no chao da arena, marca sorteada vira ruido. Se
## for para voltar com poca ou rachadura, que venha desenhada e posicionada —
## como os adereços do cenario, que viraram nos arrastaveis no editor.
const PERFIS := {
	"campo_magnetico": {"aneis": 3},
	"arena_assombrada": {"lajes": 9},
	"camara_de_estimulos": {"grade": true, "aneis": 1},
}


const GRADE_PASSO := 96.0     # lado do ladrilho, em unidades de campo


static func gerar(id: String, semente: int, hw: float, hh: float,
		cor: Color) -> Array:
	var perfil: Dictionary = PERFIS.get(id, {})
	if perfil.is_empty():
		return []
	var rng := RandomNumberGenerator.new()
	rng.seed = semente * 7919 + id.hash()
	var marcas: Array = []

	# --- o que e regular ---------------------------------------------------
	if bool(perfil.get("grade", false)):
		marcas.append_array(_grade(hw, hh, cor))
	# OS ANEIS VARREM PARA FORA quando a arena dispara (`pulsa`). Eles estavam
	# parados: a Camara e o Campo Magnetico sao as duas arenas cujo efeito e um
	# ESTIMULO periodico, e nada na tela dizia que ele tinha acontecido a nao
	# ser meio segundo de piso mais claro. Amarrar a marca que ja existe ao
	# `arena_pulse` que ja existe e o melhor retorno por linha do arquivo:
	# quem assiste passa a ver a onda saindo do centro no ritmo do estimulo.
	# Quem desenha e o FieldView, que e quem conhece o pulso.
	for i in int(perfil.get("aneis", 0)):
		var f: float = 0.34 + float(i) * 0.26
		marcas.append({
			"op": "anel", "pos": Vector2.ZERO,
			"r": hw * f,
			"w": 1.5,
			# ALFA DE REPOUSO CORTADO PELA METADE (0,16 -> 0,09). Medido no
			# print: com os aneis brancos do piso fora, estes tres passaram a
			# ser a coisa mais visivel do chao e o Campo Magnetico virou um
			# alvo de dardos — o mesmo defeito, com outra cor. Agora eles sao
			# textura em repouso e so ACENDEM quando o estimulo dispara, que e
			# o momento em que tem algo a dizer.
			"cor": Color(cor.r, cor.g, cor.b, 0.09 - float(i) * 0.02),
			"pulsa": true,
		})

	# LAJES SAO IRMAS. Tamanho quase igual e mesmo eixo: variar demais fazia
	# parecer confete em vez de pedra assentada.
	for i in int(perfil.get("lajes", 0)):
		var p2 := _ponto(rng, hw, hh)
		marcas.append({
			"op": "placa", "pos": p2,
			"tam": Vector2(rng.randf_range(52.0, 66.0), rng.randf_range(78.0, 96.0)),
			"cor": Color(cor.r, cor.g, cor.b, rng.randf_range(0.06, 0.11)),
		})
	return marcas


## Ladrilho de verdade: uma grade alinhada, recortada pela elipse. As juntas
## ficam entre os ladrilhos, e nao desenhadas — e o vao que faz ler como piso.
static func _grade(hw: float, hh: float, cor: Color) -> Array:
	var out: Array = []
	var passo := GRADE_PASSO
	var x := -hw
	while x < hw:
		var y := -hh
		while y < hh:
			var c := Vector2(x + passo * 0.5, y + passo * 0.5)
			if _dentro(c, hw, hh, 0.86):
				# alterna o tom como um tabuleiro, bem de leve
				var par: bool = (int(round(x / passo)) + int(round(y / passo))) % 2 == 0
				out.append({
					"op": "placa", "pos": c,
					"tam": Vector2(passo - 10.0, passo - 10.0),
					"cor": Color(cor.r, cor.g, cor.b, 0.085 if par else 0.045),
				})
			y += passo
		x += passo
	return out


static func _dentro(p: Vector2, hw: float, hh: float, folga: float) -> bool:
	var u := p.x / maxf(hw * folga, 1.0)
	var v := p.y / maxf(hh * folga, 1.0)
	return u * u + v * v <= 1.0


## Um ponto DENTRO da elipse do piso, com folga na borda. Sorteia em disco e
## estica: sortear x e y soltos amontoaria tudo nos cantos do retangulo.
static func _ponto(rng: RandomNumberGenerator, hw: float, hh: float) -> Vector2:
	var a := rng.randf_range(0.0, TAU)
	var r: float = sqrt(rng.randf()) * 0.92
	return Vector2(cos(a) * hw * r, sin(a) * hh * r)
