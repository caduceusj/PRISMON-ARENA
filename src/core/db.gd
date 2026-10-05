extends Node
## Banco de dados de conteudo do PRISMON (autoload "Db").
##
## GDD 22.1 -- "dados fora do codigo": todo conteudo e numero de balanceamento
## vive em res://data/*.json. Nenhuma constante de design mora em .gd.

const DATA_DIR := "res://data/"

## A PALETA DE RESERVA -- o unico hex que sobrou no codigo do jogo.
##
## A cor do PRISMON mora em data/paleta.json (GDD 22.1, "dados fora do
## codigo"). Mas uma cor ausente nao pode impedir o jogo de ABRIR: se o arquivo
## sumir, vier quebrado, ou apontar para uma paleta que nao existe, o jogo cai
## aqui, AVISA no log, e continua. Esta e a paleta "vidro" de 16/09, valor por
## valor -- se voce mudar data/paleta.json e quiser que a reserva acompanhe,
## copie os hex para ca; se nao copiar, a reserva vira o "estado conhecido bom"
## anterior, que tambem e uma resposta razoavel.
const PALETA_EMBUTIDA := {
	"nome": "O Vidro do Domador (reserva embutida)",
	"nota": "Padrao de emergencia: data/paleta.json nao pode ser lido.",
	"materia": {
		"mesa": "#0f0d18", "lajota": "#1c1930",
		"lajota_hi": "#262138", "aresta": "#3a3450",
	},
	"materia_aux": { "recuo": "#070610", "aresta_hi": "#4b4468" },
	"recipiente": {
		"fundo": "#0f0d18", "painel": "#191627",
		"painel_hi": "#221e33", "linha": "#2e2942",
	},
	"texto": { "forte": "#e9e6f2", "fraco": "#8f88a8" },
	"estado": {
		"bom": "#5cd6a0", "ruim": "#e0576a", "aviso": "#e8b23a",
		"ouro": "#f0d98a", "acento": "#7d6cf0",
	},
	"salas": {
		"titulo": "#6a5ad8", "iniciais": "#4f8a63", "escolha": "#3f5a8a",
		"preparacao": "#7a6a9e", "sinergias": "#7a6a9e", "combate": "#7a6a9e",
		"vitoria": "#3f8f6a", "derrota": "#8f3f4e", "recruta": "#4a90c8",
		"loja": "#e8a23a", "cozinha": "#e8663a", "poder": "#3ad0e8",
		"acaso": "#8f6ae0", "troca": "#6f9a86", "chefe": "#b0524a",
		"fim_vitoria": "#c9a13f",
	},
	"sala_forca": 0.06,
	"sala_na_materia": 0.0,
}

var elements: Dictionary = {}       # id -> Dictionary
var element_order: Array[String] = []
var slice_elements: Array[String] = []
var aura_to_element: Dictionary = {}  # aura_id -> element_id

var reactions: Dictionary = {}      # id -> Dictionary
var _matrix: Dictionary = {}        # aura_id -> { hit_element -> {reaction, direction} }

var species: Dictionary = {}        # id -> Dictionary
var base_species: Array[String] = []
var roles: Dictionary = {}          # id do papel -> {name, text}

var resonances: Array = []
var resonance_thresholds: Dictionary = {}
var actives: Dictionary = {}
var active_order: Array[String] = []
var relics: Dictionary = {}
var relic_order: Array[String] = []
var items: Dictionary = {}
var item_order: Array[String] = []
var dishes: Dictionary = {}
var dish_order: Array[String] = []
var random_events: Array = []   # eventos de acaso (data/random_events.json)
var themes: Array = []
var arenas_by_id: Dictionary = {}   # id -> arena
var modifiers: Array = []           # modificadores de bando
var arenas: Dictionary = {}
var boss: Dictionary = {}
var tuning: Dictionary = {}
var icons: Dictionary = {}
var rig: Dictionary = {}
var anims: Dictionary = {}

var paletas: Dictionary = {}        # nome -> paleta (data/paleta.json)
var paleta: Dictionary = {}         # a paleta ATIVA, ja resolvida
var paleta_ativa: String = ""       # o nome dela

var loaded := false


func _ready() -> void:
	load_all()


func load_all() -> void:
	elements.clear(); element_order.clear(); slice_elements.clear(); aura_to_element.clear()
	reactions.clear(); _matrix.clear(); species.clear(); base_species.clear()
	actives.clear(); active_order.clear(); relics.clear(); relic_order.clear()
	items.clear(); item_order.clear(); dishes.clear(); dish_order.clear()

	var el_doc := _read("elements.json")
	for e in el_doc.get("elements", []):
		elements[e["id"]] = e
		element_order.append(e["id"])
		if e.get("slice", false):
			slice_elements.append(e["id"])
		if String(e.get("aura_id", "")) != "":
			aura_to_element[e["aura_id"]] = e["id"]

	var rx_doc := _read("reactions.json")
	for r in rx_doc.get("reactions", []):
		reactions[r["id"]] = r
	for m in rx_doc.get("matrix", []):
		var aura: String = m["aura"]
		if not _matrix.has(aura):
			_matrix[aura] = {}
		_matrix[aura][m["hit"]] = { "reaction": m["reaction"], "direction": m.get("direction", "forward") }

	var sp_doc := _read("species.json")
	roles = sp_doc.get("roles", {})
	for s in sp_doc.get("species", []):
		species[s["id"]] = s
		if not s.get("evolved", false):
			base_species.append(s["id"])

	var res_doc := _read("resonances.json")
	resonances = res_doc.get("resonances", [])
	resonance_thresholds = res_doc.get("thresholds", {"eco": 2, "coro": 4, "apice": 6})

	for a in _read("actives.json").get("actives", []):
		actives[a["id"]] = a
		active_order.append(a["id"])
	for r in _read("relics.json").get("relics", []):
		relics[r["id"]] = r
		relic_order.append(r["id"])
	for i in _read("items.json").get("items", []):
		items[i["id"]] = i
		item_order.append(i["id"])
	for d in _read("dishes.json").get("dishes", []):
		dishes[d["id"]] = d
		dish_order.append(d["id"])
	random_events = _read("random_events.json").get("events", [])

	var en_doc := _read("enemies.json")
	themes = en_doc.get("themes", [])
	boss = en_doc.get("boss", {})
	for a in en_doc.get("arenas", []):
		arenas[a["name"]] = a
		arenas_by_id[a["id"]] = a
	modifiers = en_doc.get("modifiers", [])

	tuning = _read("tuning.json")
	icons = _read("icons.json")
	rig = _read("monster_rig.json")
	anims = _read("anims.json")
	_load_paleta()
	loaded = true


## A PALETA, e a entrega dela ao kit de interface.
##
## POR QUE `src/core` chama `src/ui` aqui (a unica vez que isso acontece):
## `UI` e um `class_name` sobre RefCounted, sem `_ready()`, entao ele nao tem
## como ir buscar a paleta sozinho na hora certa -- e um inicializador de
## `static var` que lesse `Db` poderia rodar antes de o autoload existir. A
## ordem que o Godot garante e "todo autoload pronto antes do `_ready()` da
## cena principal", e e por isso que a entrega e um EMPURRAO daqui, explicito,
## e nao uma leitura preguicosa de la. Ver o cabecalho de src/ui/ui.gd.
##
## `PrismaTheme` entra junto porque o `Theme` da raiz ASSA StyleBox prontos com
## as cores de dentro: esquecer a paleta sem esquecer o Theme deixaria metade
## da tela com a cor velha.
func _load_paleta() -> void:
	var doc := _read_opcional("paleta.json")
	paletas = doc.get("paletas", {})
	paleta_ativa = String(doc.get("ativa", ""))
	_juntar_paletas_soltas()
	if paletas.is_empty():
		push_warning("PRISMON: data/paleta.json ausente ou sem paletas — "
			+ "usando a paleta de reserva embutida (Db.PALETA_EMBUTIDA)")
		paletas = { "embutida": PALETA_EMBUTIDA }
		paleta_ativa = "embutida"
	elif not paletas.has(paleta_ativa):
		push_warning("PRISMON: paleta ativa '%s' nao existe em paleta.json — "
			% paleta_ativa + "usando a paleta de reserva embutida")
		paletas["embutida"] = PALETA_EMBUTIDA
		paleta_ativa = "embutida"
	paleta = paletas[paleta_ativa]
	UI.aplicar_paleta(paleta)
	PrismaTheme.esquecer()


## AS PALETAS SOLTAS -- data/paletas/*.json.
##
## Todo arquivo da pasta entra, e nome repetido SOBREPOE o de paleta.json:
## e assim que se troca a cor do jogo sem editar o arquivo do jogo.
##
## A pasta ja existia e ninguem a lia. Um agente desta leva escreveu
## estufa.json ali enquanto a mesma paleta vivia duplicada no arquivo base,
## e o disco nao reclamou -- que e o pior desfecho possivel para uma pasta de
## extensao: quem larga um arquivo nela nao ganha erro, ganha silencio.
##
## `DirAccess.get_files_at` sobre res:// so enxerga o que foi EXPORTADO. Se a
## listagem vier vazia num build, as paletas soltas simplesmente nao existem
## la -- e por isso a paleta do jogo mora no arquivo base, e nao aqui.
func _juntar_paletas_soltas() -> void:
	var dir := DATA_DIR + "paletas"
	var nomes := DirAccess.get_files_at(dir)
	for f in nomes:
		var nome := String(f)
		# num build exportado o arquivo pode vir com .remap no fim
		if nome.ends_with(".remap"):
			nome = nome.trim_suffix(".remap")
		if not nome.ends_with(".json"):
			continue
		var caminho := "%s/%s" % [dir, nome]
		var parsed: Variant = JSON.parse_string(
			FileAccess.get_file_as_string(caminho))
		if typeof(parsed) != TYPE_DICTIONARY:
			push_warning("PRISMON: paleta solta invalida, ignorada: %s" % caminho)
			continue
		var extras: Dictionary = (parsed as Dictionary).get("paletas", {})
		for k in extras:
			paletas[k] = extras[k]


## Como `_read`, mas o arquivo pode faltar sem virar erro: quem chama tem um
## plano B. Usado so pela paleta — o jogo nao pode deixar de abrir por cor.
func _read_opcional(fname: String) -> Dictionary:
	var path := DATA_DIR + fname
	if not FileAccess.file_exists(path):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if typeof(parsed) == TYPE_DICTIONARY else {}


func _read(fname: String) -> Dictionary:
	var path := DATA_DIR + fname
	if not FileAccess.file_exists(path):
		push_error("PRISMON: arquivo de dados ausente: %s" % path)
		return {}
	var txt := FileAccess.get_file_as_string(path)
	var parsed: Variant = JSON.parse_string(txt)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("PRISMON: JSON invalido em %s" % path)
		return {}
	return parsed


# --- consultas -------------------------------------------------------------

func el(id: String) -> Dictionary:
	return elements.get(id, {})

func el_name(id: String) -> String:
	return String(el(id).get("name", id))

func el_color(id: String) -> Color:
	return Color(String(el(id).get("color", "#ffffff")))

func aura_name(aura_id: String) -> String:
	var e: String = aura_to_element.get(aura_id, "")
	return String(el(e).get("aura_name", aura_id))

func aura_color(aura_id: String) -> Color:
	return el_color(aura_to_element.get(aura_id, ""))

func sp(id: String) -> Dictionary:
	return species.get(id, {})

## Nome do papel COM acento. O id continua sem ("Guardiao"), porque ele e
## chave de filtro em enemy_gen e run_state — trocar o id quebraria a
## composicao dos inimigos. O acento vive so aqui, na exibicao.
func role_name(id: String) -> String:
	return String(roles.get(id, {}).get("name", id))


func sp_name(id: String) -> String:
	return String(sp(id).get("name", id))

## Base de uma linha evolutiva (a propria especie, se ja for base).
func sp_base_id(id: String) -> String:
	var s := sp(id)
	return String(s.get("base_form", id)) if s.get("evolved", false) else id

## GDD 6.2 -- lookup O(1) da matriz de reacoes.
## Retorna {} quando nao ha reacao para o par (aura presente, elemento do golpe).
func lookup_reaction(aura_id: String, hit_element: String) -> Dictionary:
	var row: Dictionary = _matrix.get(aura_id, {})
	var hit: Dictionary = row.get(hit_element, {})
	if hit.is_empty():
		return {}
	var rule: Dictionary = reactions.get(hit["reaction"], {})
	if rule.is_empty():
		return {}
	return { "rule": rule, "direction": String(hit["direction"]) }

## Todas as reacoes que um conjunto de elementos consegue produzir entre si.
## Usado pelo grafo de reacoes da tela de preparacao (GDD 21.1).
func reactions_between(els: Array) -> Array:
	var out: Array = []
	var seen := {}
	for a in els:
		var aura_id: String = String(el(a).get("aura_id", ""))
		if aura_id == "":
			continue
		for b in els:
			if a == b:
				continue
			var hit := lookup_reaction(aura_id, b)
			if hit.is_empty():
				continue
			var key: String = "%s|%s|%s" % [a, b, hit["rule"]["id"]]
			if seen.has(key):
				continue
			seen[key] = true
			out.append({ "from": a, "to": b, "reaction": hit["rule"], "direction": hit["direction"] })
	return out

func tune(section: String, key: String, fallback: Variant = 0.0) -> Variant:
	var sec: Dictionary = tuning.get(section, {})
	return sec.get(key, fallback)

func combat(key: String, fallback: Variant = 0.0) -> float:
	return float(tune("combat", key, fallback))

func run_cfg(key: String, fallback: Variant = 0) -> Variant:
	return tune("run", key, fallback)


## Custo de um prato como {element_id: quantidade}, ja resolvido contra a despensa.
## Retorna {} quando o prato usa custo generico (cost_any / cost_distinct).
func dish_cost(dish_id: String) -> Dictionary:
	return Db.dishes.get(dish_id, {}).get("cost", {})

func dish_any(dish_id: String) -> int:
	return int(dishes.get(dish_id, {}).get("cost_any", 0))

func dish_distinct(dish_id: String) -> int:
	return int(dishes.get(dish_id, {}).get("cost_distinct", 0))

func dish_is_nutrition(dish_id: String) -> bool:
	return String(dishes.get(dish_id, {}).get("kind", "")) == "nutricao"
