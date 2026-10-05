extends Node
## Som do PRISMON (autoload "Som").
##
## O projeto não tinha UM som — nem arquivo, nem AudioStream, nem controle de
## volume, nem uma linha sobre o assunto em 1283 de NOTAS.md. Não era escopo
## cortado, era assunto nunca levantado. E a pergunta de pesquisa do slice é
## "o combate é interessante de ASSISTIR e de intervir?", que ninguém responde
## com metade dos sentidos desligada.
##
## TODA a interface pública é por NOME, nunca por recurso: `tocar("golpe")`.
## Quem chama não conhece arquivo, barramento nem voz. Isso é o que permite um
## sound designer trocar assets/audio/ inteiro sem tocar em .gd — e é o que
## permite a pasta SUMIR sem quebrar nada (ver `_fluxo`, que devolve null e
## faz `tocar` virar no-op silencioso).
##
## Os arquivos de hoje são PLACEHOLDERS sintetizados por tools/gerar_sons.py.

## Altura (pitch) e volume em dB são parâmetros de CHAMADA, não de dado: quem
## toca sabe se o golpe foi no gigante ou no filhote. O banco é neutro.
const DIR_EFEITOS := "res://assets/audio/efeitos/"
const DIR_AMBIENTE := "res://assets/audio/ambiente/"

## Os 14 nomes válidos. Qualquer outro é no-op SILENCIOSO — um erro de digitação
## num call site de UI não pode derrubar o jogo, e um `push_error` por quadro
## num combate com 36 reações seria pior que o silêncio.
const EFEITOS: Array[String] = [
	"golpe", "critico", "reacao", "morte", "ativo", "cura", "escudo", "controle",
	"clique", "hover", "moeda", "vitoria", "derrota", "recruta",
]

const BARRAMENTOS: Array[String] = ["Efeitos", "Ambiente"]
const CANAIS := {"master": "Master", "efeitos": "Efeitos", "ambiente": "Ambiente"}

## Teto de vozes. O combate medido no autoplay emite 36,1 reações (REVISÃO §
## "Reações por combate") mais um golpe por ataque de cada uma das 12 unidades;
## um AudioStreamPlayer por evento seriam centenas de nós criados e destruídos
## em 12 s de briga. E o teto REAL de disparos num quadro é conhecido: o
## anti-metralhadora abaixo deixa passar no máximo UM por nome, e nomes são 14.
## 16 vozes cobrem o pior quadro possível por construção, não por estimativa.
const VOZES := 16

## ±4,5% de altura a cada disparo. Sem isso a repetição do MESMO arquivo soa
## como máquina; com mais que isso o golpe começa a mudar de identidade.
const VARIACAO := 0.045

## Entrada e saída do ambiente. Bem MAIOR que a entrada de tela (Juice.ENTRADA
## = 0,13 s) de propósito: imagem pode cortar, som de sala não. Um laço de vento
## que começa cheio no primeiro quadro é ouvido como estouro, não como arena.
const FADE := 0.45
const SILENCIO := -40.0

## Quando não há saída de áudio (ferramentas headless), TUDO vira no-op no
## primeiro `if` de cada função pública. O autoplay roda 1000 runs e não pode
## abrir dispositivo nenhum.
var mudo := false

var _pool: Array[AudioStreamPlayer] = []
var _quando: Array[int] = []
var _amb: AudioStreamPlayer = null
var _amb_id := ""
var _amb_tween: Tween = null

var _cache: Dictionary = {}          # caminho -> AudioStream (null = não existe)
var _neste_quadro: Dictionary = {}   # nome -> disparos no quadro atual
## NÍVEL DE PARTIDA, antes de ScreenOptions aplicar o que está salvo (autor,
## 15/09: "abaixa o som que tá muito alto"). Nascia 1.0/1.0/1.0 — sem margem
## nenhuma, e o primeiro som de um jogo recém-aberto saía no teto. O ambiente
## é um laço contínuo e some primeiro, porque ele é a cama e não a figura.
var _volumes := {"master": 0.6, "efeitos": 0.55, "ambiente": 0.32}

## RNG próprio: a variação de altura NÃO PODE sair do RNG global, senão o som
## empurraria a sequência aleatória e dois combates com a mesma semente
## deixariam de ser iguais. O determinismo do sim é a base de tudo aqui.
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	# o som continua na pausa: o combate pausado ainda tem interface, e um
	# clique mudo no menu de pausa parece um botão quebrado
	process_mode = Node.PROCESS_MODE_ALWAYS
	mudo = _sem_saida()
	if mudo:
		set_process(false)
		return
	_rng.randomize()
	_garantir_barramentos()
	for i in VOZES:
		var p := AudioStreamPlayer.new()
		p.bus = "Efeitos"
		add_child(p)
		_pool.append(p)
		_quando.append(0)
	_amb = AudioStreamPlayer.new()
	_amb.bus = "Ambiente"
	add_child(_amb)
	# aquece os 14 efeitos (196 kB somados, medido): a primeira leitura de disco
	# de um .wav no meio da primeira reação é o quadro que não pode pular
	for nome in EFEITOS:
		_carregar(DIR_EFEITOS + nome + ".wav")


## O balde de "já tocou neste quadro" zera aqui, e só aqui.
func _process(_delta: float) -> void:
	if not _neste_quadro.is_empty():
		_neste_quadro.clear()


# --------------------------------------------------------------------------
# API
# --------------------------------------------------------------------------

## Toca um dos 14 efeitos. Nome inválido, arquivo ausente ou saída de áudio
## ausente: não faz nada, não avisa, não quebra.
func tocar(nome: String, pitch: float = 1.0, volume_db: float = 0.0) -> void:
	if mudo:
		return
	var fluxo := _fluxo(nome)
	if fluxo == null:
		return
	# ANTI-METRALHADORA. Uma cadeia de Eletrocussão resolve as 7 reações dela no
	# MESMO quadro; sete cópias do mesmo arquivo no mesmo instante somam em fase
	# e viram um estalo de +17 dB, não sete sons. O segundo disparo do mesmo
	# nome no mesmo quadro é contado e descartado.
	if _neste_quadro.has(nome):
		_neste_quadro[nome] = int(_neste_quadro[nome]) + 1
		return
	_neste_quadro[nome] = 1
	var i := _voz()
	var p := _pool[i]
	p.stream = fluxo
	p.pitch_scale = maxf(0.05, pitch * (1.0 + _rng.randf_range(-VARIACAO, VARIACAO)))
	p.volume_db = volume_db
	p.play()
	_quando[i] = Time.get_ticks_msec()


## Laço de ambiente da arena, pelo `id` de data/enemies.json. `""` desliga.
## Um id sem arquivo também desliga: a arena mudou, e deixar o laço anterior
## tocando por cima da arena nova seria pior que o silêncio.
func ambiente(id: String) -> void:
	if mudo or id == _amb_id:
		return
	if id == "":
		parar_ambiente()
		return
	var fluxo := _fluxo_ambiente(id)
	if fluxo == null:
		parar_ambiente()
		return
	_amb_id = id
	if _amb_tween != null and _amb_tween.is_valid():
		_amb_tween.kill()
	_amb_tween = create_tween()
	if _amb.playing:
		_amb_tween.tween_property(_amb, "volume_db", SILENCIO, FADE)
	_amb_tween.tween_callback(_entrar_ambiente.bind(fluxo))
	_amb_tween.tween_property(_amb, "volume_db", 0.0, FADE)


func parar_ambiente() -> void:
	if mudo:
		return
	_amb_id = ""
	if _amb_tween != null and _amb_tween.is_valid():
		_amb_tween.kill()
	if not _amb.playing:
		return
	_amb_tween = create_tween()
	_amb_tween.tween_property(_amb, "volume_db", SILENCIO, FADE)
	_amb_tween.tween_callback(_amb.stop)


## `canal`: "master" | "efeitos" | "ambiente". `linear` em 0..1.
## O valor fica guardado mesmo no modo mudo — a tela de Configurações lê daqui,
## e ela não pode mentir sobre o próprio estado só porque a máquina não tem
## placa de som.
func set_volume(canal: String, linear: float) -> void:
	if not CANAIS.has(canal):
		return
	linear = clampf(linear, 0.0, 1.0)
	_volumes[canal] = linear
	if mudo:
		return
	var i: int = AudioServer.get_bus_index(CANAIS[canal])
	if i < 0:
		return
	# mute explícito no zero: `linear_to_db(0)` é -inf e alguns drivers
	# devolvem NaN no caminho de volta
	AudioServer.set_bus_mute(i, linear <= 0.0)
	AudioServer.set_bus_volume_db(i, linear_to_db(maxf(linear, 0.001)))


func volume(canal: String) -> float:
	return float(_volumes.get(canal, 1.0))


# --------------------------------------------------------------------------
# interno
# --------------------------------------------------------------------------

## `--headless` liga o driver de vídeo "headless" E o de áudio "Dummy" de uma
## vez só — é por isso que uma checagem de DisplayServer decide sobre áudio.
## Os argumentos de linha de comando cobrem quem pede o driver Dummy sozinho.
##
## FERRAMENTA NÃO FAZ BARULHO (autor, 15/09: "abaixa o som que tá muito alto").
## `--headless` não cobria o caso que de fato incomodou: `tools/screenshots.tscn`,
## `tools/ui_probe.tscn`, `tools/bestiary.tscn` e as sondas rodam COM janela —
## precisam de janela, é o ponto delas — e passaram a tocar som em cima de quem
## estivesse usando o computador. Pior: elas abrem e fecham sozinhas várias
## vezes seguidas quando alguém está iterando, então o barulho vem em rajada e
## sem nada na tela explicando de onde veio.
##
## A regra é o CAMINHO DA CENA PRINCIPAL, não uma lista de nomes: qualquer coisa
## sob `res://tools/` é instrumento de medida e nasce muda. Ferramenta nova entra
## na regra sozinha, sem ninguém lembrar de cadastrá-la.
func _sem_saida() -> bool:
	if DisplayServer.get_name() == "headless":
		return true
	var args := OS.get_cmdline_args()
	if args.has("--headless") or args.has("Dummy"):
		return true
	var cena := String(ProjectSettings.get_setting("application/run/main_scene", ""))
	for a in args:
		if a.begins_with("res://") and a.ends_with(".tscn"):
			cena = a
			break
	return cena.begins_with("res://tools/")


## Master (índice 0) sempre existe. Efeitos e Ambiente são criados aqui em vez
## de virem de um default_bus_layout.tres: o .tres é um arquivo a mais para o
## exportador esquecer, e o dia em que ele faltasse o jogo perderia os dois
## controles de volume sem uma mensagem de erro.
func _garantir_barramentos() -> void:
	for nome in BARRAMENTOS:
		if AudioServer.get_bus_index(nome) != -1:
			continue
		var i := AudioServer.bus_count
		AudioServer.add_bus(i)
		AudioServer.set_bus_name(i, nome)
		AudioServer.set_bus_send(i, "Master")


## Uma voz parada, se houver; senão a que começou há mais tempo cede o lugar.
## Roubar a mais velha é o comportamento certo num autobattler: o som que está
## acabando é o do golpe anterior, e o que importa é o de agora.
func _voz() -> int:
	var velha := 0
	for i in _pool.size():
		if not _pool[i].playing:
			return i
		if _quando[i] < _quando[velha]:
			velha = i
	return velha


func _fluxo(nome: String) -> AudioStream:
	if not EFEITOS.has(nome):
		return null
	return _carregar(DIR_EFEITOS + nome + ".wav")


func _fluxo_ambiente(id: String) -> AudioStream:
	var fluxo := _carregar(DIR_AMBIENTE + id + ".wav")
	var w := fluxo as AudioStreamWAV
	if w != null and w.loop_mode != AudioStreamWAV.LOOP_FORWARD:
		# o laço é ligado AQUI e não no .import porque o .import é gerado pelo
		# editor: quem trocar o arquivo por um som de verdade não precisa saber
		# que existe uma caixinha "Loop" escondida na aba de importação
		w.loop_begin = 0
		w.loop_end = int(w.get_length() * float(w.mix_rate))
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
	return fluxo


func _entrar_ambiente(fluxo: AudioStream) -> void:
	_amb.stream = fluxo
	_amb.volume_db = SILENCIO
	_amb.play()


## O null fica no cache junto com os acertos: um arquivo que falta falha UMA
## vez, não a cada golpe.
func _carregar(caminho: String) -> AudioStream:
	if _cache.has(caminho):
		return _cache[caminho]
	var fluxo: AudioStream = null
	if ResourceLoader.exists(caminho):
		fluxo = ResourceLoader.load(caminho) as AudioStream
	if fluxo == null:
		fluxo = _ler_wav(caminho)
	_cache[caminho] = fluxo
	return fluxo


## Plano B: ler o RIFF na mão.
## `.godot/` está no .gitignore, então num clone novo os .import existem mas os
## .sample importados não — e o jogo ficaria mudo até alguém abrir o editor.
## São 25 linhas para que "clonou, rodou, ouviu" seja verdade.
func _ler_wav(caminho: String) -> AudioStream:
	if not FileAccess.file_exists(caminho):
		return null
	var f := FileAccess.open(caminho, FileAccess.READ)
	if f == null:
		return null
	var b := f.get_buffer(f.get_length())
	f.close()
	if b.size() < 44 or b.slice(0, 4).get_string_from_ascii() != "RIFF":
		return null
	var canais := 1
	var taxa := 22050
	var bits := 0
	var pcm := PackedByteArray()
	var i := 12
	while i + 8 <= b.size():
		var id := b.slice(i, i + 4).get_string_from_ascii()
		var tam := int(b.decode_u32(i + 4))
		var corpo := i + 8
		if id == "fmt " and corpo + 16 <= b.size():
			canais = b.decode_u16(corpo + 2)
			taxa = int(b.decode_u32(corpo + 4))
			bits = b.decode_u16(corpo + 14)
		elif id == "data":
			pcm = b.slice(corpo, mini(corpo + tam, b.size()))
		i = corpo + tam + (tam & 1)
	if bits != 16 or pcm.is_empty():
		return null
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = taxa
	w.stereo = canais == 2
	w.data = pcm
	return w
