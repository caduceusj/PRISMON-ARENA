class_name ArenaParticulas
extends RefCounted
## O AMBIENTE EM MOVIMENTO da arena (autor, 09/09: "use particulas tambem").
##
## A ilustracao de fundo e parada; ela diz ONDE a briga acontece. Estas
## particulas dizem que o lugar esta VIVO — chove, brasa sobe, neve cai. Sao a
## unica coisa na tela que se mexe quando ninguem esta atacando, e e isso que
## tira o combate da sensacao de diorama.
##
## TRES REGRAS QUE VALEM PARA TODAS:
##
## * SAO DECORACAO, e a simulacao nunca as ve. Nascem e morrem no relogio da
##   TELA, nao no da briga: acelerar o combate para 4x nao vira tempestade.
##
## * FICAM ATRAS DAS CRIATURAS. Chuva por cima de um Prismon de 44 px o
##   apagaria, e a criatura e a coisa que precisa ser lida.
##
## * ENVOLVEM O CAMPO INTEIRO, e nao so a elipse. Clima que para na borda do
##   piso denuncia que o piso e um desenho.
##
## Cada arena tem um perfil em PERFIS. Arena sem perfil simplesmente nao tem
## particula — nada quebra.
##
## AS FAISCAS DE COMBATE SAO A EXCECAO A PRIMEIRA REGRA, e por isso vivem num
## vetor separado: elas nascem de um EVENTO da simulacao (golpe, reacao,
## morte). Mesmo assim o relogio delas continua sendo o da TELA — quem as
## empurra e o `delta` do `_process`, nao o da briga — entao 4x nao vira chuva
## de faisca, so faz nascerem mais vezes por segundo de relogio de parede.

const MAX := 150

## `op` diz como a particula anda e como e desenhada:
##   cai    — desce reto e rapido, desenhada como risco (chuva)
##   flutua — desce devagar balancando (neve)
##   sobe   — sobe balancando (brasa, esporo, vapor)
##
## O `pisca` SAIU (revisao 15/09). Ele nao tinha caso no `match op` de
## `atualizar`: as 34 particulas do Campo Magnetico literalmente nao andavam, e
## 32 pontinhos de 1 a 3 px piscando PARADOS leem como pixel queimado do
## monitor. Medido, o perfil acendia 0,016% do campo. O Campo Magnetico agora
## sobe rapido e cintila, que e o que uma faisca magnetica faz.
const PERFIS := {
	"solo_vulcanico": {
		"op": "sobe", "n": 70, "vel": 34.0, "balanco": 16.0,
		"tam": [1, 2], "alfa": 0.85, "vida": [1.6, 3.4], "cintila": true,
	},
	"chuva_constante": {
		"op": "cai", "n": 130, "vel": 640.0, "inclinacao": -0.30,
		"risco": [12.0, 26.0], "alfa": 0.5, "vida": [0.5, 1.0],
	},
	"nevasca": {
		"op": "flutua", "n": 120, "vel": 42.0, "balanco": 26.0,
		"tam": [1, 2], "alfa": 0.75, "vida": [3.0, 6.0],
	},
	"campo_magnetico": {
		"op": "sobe", "n": 90, "vel": 96.0, "balanco": 5.0,
		"tam": [1, 2], "alfa": 0.8, "vida": [0.5, 1.2], "cintila": true,
	},
	"bosque_vivo": {
		"op": "sobe", "n": 60, "vel": 15.0, "balanco": 22.0,
		"tam": [1, 3], "alfa": 0.8, "vida": [3.0, 6.0], "cintila": true,
	},
	"arena_assombrada": {
		"op": "sobe", "n": 46, "vel": 13.0, "balanco": 34.0,
		"tam": [2, 4], "alfa": 0.85, "vida": [3.5, 7.0], "cintila": true,
	},
	# alfa 0,45 com 40 particulas era METADE da densidade da nevasca: a Camara
	# era a arena que menos existia na tela. 70 a 0,7 a poe no mesmo peso das
	# outras seis sem mudar o que ela e.
	"camara_de_estimulos": {
		"op": "sobe", "n": 70, "vel": 22.0, "balanco": 12.0,
		"tam": [1, 3], "alfa": 0.7, "vida": [2.0, 4.5],
	},
}

## TETO DAS FAISCAS. O orcamento de quads da tela nao e problema — medido, o
## pior quadro gastava 1.350 quads de GLIFO contra 150 de particula — mas sem
## teto uma cadeia de reacoes encheria a arena de pontinhos e o corpo das
## criaturas sumiria atras deles.
const MAX_FAISCAS := 110

## O ACHATAMENTO DO CHAO, espelhado do FieldView (que o escreve aqui no
## `_ready`). A faisca voa RENTE AO CHAO: o espalhamento em y e achatado pelo
## mesmo fator da sombra e do anel de aura, senao ela sai num circulo perfeito
## e le como adesivo colado na tela, nao como coisa que pulou do piso.
var squash := 0.443

var _perfil: Dictionary = {}
var _cor := Color.WHITE
var _p: Array = []
var _faiscas: Array = []
var _rng := RandomNumberGenerator.new()
var _area := Vector2(1280, 720)


func _init() -> void:
	_rng.randomize()


## Troca de arena. Id sem perfil apaga as particulas.
func trocar(id: String, cor: Color) -> void:
	_p.clear()
	_faiscas.clear()
	_perfil = PERFIS.get(id, {})
	_cor = cor
	if _perfil.is_empty():
		return
	# nascem JA ESPALHADAS: sem isto o combate comeca com a tela limpa e a
	# chuva "liga" depois de um segundo, que denuncia o truque
	for i in mini(int(_perfil.get("n", 40)), MAX):
		_p.append(_nascer(true))


func _nascer(espalhada: bool) -> Dictionary:
	var vida: Array = _perfil.get("vida", [2.0, 4.0])
	var t: float = _rng.randf_range(float(vida[0]), float(vida[1]))
	var op := String(_perfil.get("op", "sobe"))
	var y: float
	if espalhada:
		y = _rng.randf_range(0.0, _area.y)
	elif op == "cai":
		y = -20.0
	elif op == "sobe":
		y = _area.y + 12.0
	else:
		y = _rng.randf_range(0.0, _area.y)
	var tam: Array = _perfil.get("tam", [1, 2])
	return {
		"pos": Vector2(_rng.randf_range(-40.0, _area.x + 40.0), y),
		"vida": t,
		"total": t,
		"fase": _rng.randf_range(0.0, TAU),
		"tam": float(_rng.randi_range(int(tam[0]), int(tam[1]))),
		"risco": _rng.randf_range(
			float(_perfil.get("risco", [8.0, 16.0])[0]),
			float(_perfil.get("risco", [8.0, 16.0])[1])),
		"vel": _rng.randf_range(0.75, 1.3),
	}


## O CAMINHO DE MAO UNICA INVERSO: a tela olhando a simulacao e cuspindo
## faisca. `pos` vem em coordenadas de CAMPO — quem projeta e o FieldView, no
## desenho, com a mesma camera de todo o resto.
##
## `forca` e a velocidade de saida em px/s de campo; `n` quantas. Uma faisca
## por golpe pequeno nao le; oito por reacao lem como estouro.
func faiscar(pos: Vector2, cor: Color, n: int, forca: float) -> void:
	for i in n:
		if _faiscas.size() >= MAX_FAISCAS:
			# o mais VELHO sai: ele ja esta esmaecendo, e o novo e o que tem
			# informacao (acabou de acontecer)
			_faiscas.pop_front()
		var ang: float = _rng.randf_range(0.0, TAU)
		var sp: float = forca * _rng.randf_range(0.45, 1.0)
		var t: float = _rng.randf_range(0.22, 0.52)
		_faiscas.append({
			"pos": pos,
			"vel": Vector2(cos(ang) * sp, sin(ang) * sp * squash),
			"alt": _rng.randf_range(2.0, 10.0),
			"valt": _rng.randf_range(0.30, 1.05) * forca * 0.75,
			"vida": t, "total": t,
			"cor": cor,
			"tam": float(_rng.randi_range(1, 2)),
		})


## GRAVIDADE DAS FAISCAS, em px de tela por segundo ao quadrado. Alta de
## proposito: com gravidade baixa a faisca fica boiando e vira confete. A 520
## ela sobe ~14 px e volta ao chao em ~0,3 s, que e a duracao do golpe.
const FAISCA_GRAV := 520.0


func _atualizar_faiscas(delta: float) -> void:
	var freio: float = 1.0 - exp(-3.4 * delta)
	for f in _faiscas.duplicate():
		f["vida"] = float(f["vida"]) - delta
		if float(f["vida"]) <= 0.0:
			_faiscas.erase(f)
			continue
		f["pos"] = Vector2(f["pos"]) + Vector2(f["vel"]) * delta
		f["vel"] = Vector2(f["vel"]).lerp(Vector2.ZERO, freio)
		f["valt"] = float(f["valt"]) - FAISCA_GRAV * delta
		var alt: float = float(f["alt"]) + float(f["valt"]) * delta
		if alt <= 0.0:
			# quica uma vez, fraco: a segunda batida ja e rasteira e a faisca
			# morre andando no chao, que e o que faz ela pertencer ao piso
			alt = 0.0
			f["valt"] = absf(float(f["valt"])) * 0.32
			f["vel"] = Vector2(f["vel"]) * 0.55
		f["alt"] = alt


func atualizar(delta: float, area: Vector2) -> void:
	_atualizar_faiscas(delta)
	if _perfil.is_empty():
		return
	_area = area
	var op := String(_perfil.get("op", "sobe"))
	var vel: float = float(_perfil.get("vel", 20.0))
	var balanco: float = float(_perfil.get("balanco", 0.0))
	var incl: float = float(_perfil.get("inclinacao", 0.0))
	for i in _p.size():
		var q: Dictionary = _p[i]
		q["vida"] = float(q["vida"]) - delta
		q["fase"] = float(q["fase"]) + delta * 1.7
		var v: float = vel * float(q["vel"])
		match op:
			"cai":
				q["pos"] = Vector2(q["pos"]) + Vector2(v * incl, v) * delta
			"flutua":
				q["pos"] = Vector2(q["pos"]) + Vector2(
					cos(float(q["fase"])) * balanco, v) * delta
			"sobe":
				q["pos"] = Vector2(q["pos"]) + Vector2(
					cos(float(q["fase"])) * balanco, -v) * delta
		var fora: bool = float(q["vida"]) <= 0.0 \
			or Vector2(q["pos"]).y < -40.0 or Vector2(q["pos"]).y > _area.y + 40.0
		if fora:
			_p[i] = _nascer(false)


func desenhar(ci: CanvasItem, deslocamento: Vector2) -> void:
	if _perfil.is_empty():
		return
	var op := String(_perfil.get("op", "sobe"))
	var alfa: float = float(_perfil.get("alfa", 0.6))
	var cintila: bool = bool(_perfil.get("cintila", false))
	for q in _p:
		var t: float = clampf(float(q["vida"]) / maxf(float(q["total"]), 0.01), 0.0, 1.0)
		# some nas duas pontas da vida: nascer e morrer de estalo pisca
		var f: float = clampf(minf(t, 1.0 - t) * 6.0, 0.0, 1.0)
		var c := _cor
		c.a = alfa * f * (0.55 + 0.45 * sin(float(q["fase"]) * 2.0) if cintila else 1.0)
		var p: Vector2 = Vector2(q["pos"]) + deslocamento
		if op == "cai":
			var r: float = float(q["risco"])
			ci.draw_line(p, p + Vector2(r * float(_perfil.get("inclinacao", 0.0)), r),
				c, 1.0)
		else:
			var s: float = float(q["tam"])
			ci.draw_rect(Rect2(p.floor(), Vector2(s, s)), c)


## A PASSADA DEPOIS DOS CORPOS. O clima fica atras das criaturas porque chuva
## por cima de um Prismon de 44 px o apagaria; a faisca e o contrario — ela e o
## retorno do golpe, e golpe que acontece atras do corpo nao aconteceu.
##
## `projetar` e o `to_screen` do FieldView: a faisca vive em coordenadas de
## campo e por isso acompanha a camera, como a criatura de onde ela saiu.
func desenhar_faiscas(ci: CanvasItem, projetar: Callable, deslocamento: Vector2) -> void:
	if _faiscas.is_empty() or not projetar.is_valid():
		return
	for f in _faiscas:
		var t: float = clampf(float(f["vida"]) / maxf(float(f["total"]), 0.01), 0.0, 1.0)
		var c: Color = f["cor"]
		# some no fim, nunca no comeco: o primeiro quadro tem de ser o mais forte
		c.a = clampf(t * 1.6, 0.0, 1.0)
		var p: Vector2 = Vector2(projetar.call(Vector2(f["pos"]))) \
			+ Vector2(0.0, -float(f["alt"])) + deslocamento
		var s: float = float(f["tam"])
		ci.draw_rect(Rect2(p.floor(), Vector2(s, s)), c)
