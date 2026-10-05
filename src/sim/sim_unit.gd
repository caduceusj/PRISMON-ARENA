class_name SimUnit
extends RefCounted
## Uma unidade dentro de um combate. Lado-simulacao apenas: sem Node, sem cena.
## O UnitInstance (persistente, da run) e "achatado" para ca antes do combate.

const LANE_VANGUARDA := 0
const LANE_MEIO := 1
const LANE_FUNDO := 2

var id: int = 0
var source_uid: int = -1          # uid da UnitInstance de origem (lado do jogador)
var side: int = 0                # 0 = jogador, 1 = inimigo
var species_id: String = ""
var display_name: String = ""

## MARCA DE DESEMPATE, so para o rotulo no campo (16/09). Fica VAZIA quando a
## criatura e unica no lado dela; vira "II", "III"... quando ha copias.
##
## Nao entra em `display_name` de proposito: aquele campo e a CHAVE DE
## AGRUPAMENTO da tabela do log (que soma "Pinto-Raio x3" numa linha so), do
## CombatPanel, do `stat_biggest_hit` e do CSV do autoplay. Um sufixo ali
## consertaria um rotulo e quebraria quatro agrupamentos.
var marca: String = ""


## O nome como ele aparece NO CAMPO — com a marca, quando houver.
func nome_no_campo() -> String:
	return display_name if marca == "" else "%s %s" % [display_name, marca]
var element: String = "FOGO"     # Afinidade atual (pode ser reescrita em combate)
var base_element: String = "FOGO"
var role: String = "Guardiao"
var stance: String = "Vanguarda"
var evolved: bool = false
var is_boss: bool = false

# --- estatisticas base (ja com itens/evolucao/fome aplicados) ---
var hp_max: float = 100.0
var atk: float = 10.0
var def: float = 0.0
var vel: float = 1.0
var pe: float = 0.0
var vontade: float = 0.0
var ua_per_hit: float = 2.0
var resist: Dictionary = {}      # element -> 0..0.75

# --- estado de combate ---
var hp: float = 100.0
var shield: float = 0.0
var ult_energy: float = 0.0
var attack_cd: float = 0.0
var aura := AuraState.new()
var pos := Vector2.ZERO
var home := Vector2.ZERO         # posicao da formacao inicial (GDD 7.2)
var facing: float = 1.0          # -1 esquerda, +1 direita
var speed_px: float = 90.0       # velocidade de deslocamento
var attack_range: float = 60.0
var kite: float = 0.0            # distancia que tenta manter (0 = corpo a corpo)
var target_id: int = -1
var retarget_cd: float = 0.0
var lane: int = 0
var slot: int = 0
var alive: bool = true

var windup_until: float = -1.0   # armando o golpe: parada, dano agendado
var control_kind: String = ""
var control_until: float = 0.0
var control_immune_until: float = 0.0

var buffs: Array = []            # [{stat, mult, value, until, label, element, stacks, max_stacks}]
var pending: Array = []          # acoes agendadas [{at, ops, source}]
var taunted_by: int = -1
var taunt_until: float = 0.0

# --- modificadores vindos de itens desta unidade ---
var unit_reaction_bonus: float = 0.0
var unit_ult_gain: float = 1.0        # regeneracao de Poder (item)
var unit_healing_out: float = 1.0
var rx_dmg_add: Dictionary = {}       # id da reacao -> bonus de dano
var rx_stun: Dictionary = {}          # id da reacao -> {duration, cooldown}
var rx_stun_ready: Dictionary = {}    # id da reacao -> instante em que recarrega
var unit_double_reaction: float = 0.0
var share_damage: float = 0.0
## Teto de UA que ESTA unidade impoe nos ALVOS dela (Totem do Excesso). 0 = sem
## teto proprio. Nao e o teto das auras que ela recebe — esse mora em aura.cap_ua.
var unit_aura_cap: float = 0.0
## Decaimento das auras que ESTA unidade aplica (Totem da Persistencia, Sifao
## das Mares). < 1 = duram mais. Viaja com quem aplica, nao com quem recebe.
var unit_aura_decay_mult: float = 1.0

## RESSONANCIA DE AURA, POR AURA E POR APLICADOR (16/09).
##
## `unit_aura_cap` e `unit_aura_decay_mult` acima vem de ITEM e valem para
## qualquer aura. Estes dois vem de RESSONANCIA e valem para UMA aura nomeada —
## Coro de Fogo so mexe em COMBUSTAO, Eco de Agua so em ENCHARCADO.
##
## Ate 15/09 os dois eram escritos em `aura.cap_overrides` e `aura.decay_mult`
## DA PROPRIA UNIDADE, dentro de `begin()`. Como esse estado pertence a quem
## RECEBE a aura, o efeito saia ao contrario: o Coro de Fogo deixava a Combustao
## que os inimigos jogavam em voce empilhar ate 16, e o Eco de Agua fazia o
## Encharcado deles durar 50% mais em cima da sua equipe. Os dois liam como
## bonus e cobravam como maldicao.
var aplica_cap_override: Dictionary = {}    # aura_id -> teto imposto nos ALVOS
var aplica_decay_mult: Dictionary = {}      # aura_id -> decaimento nos ALVOS

var ult: Dictionary = {}

# --- telemetria por unidade (GDD 21.3: "dano por unidade") ---
var dmg_dealt: float = 0.0
var dmg_taken: float = 0.0
var healing_done: float = 0.0
var reactions_caused: int = 0
var kills: int = 0


func hp_pct() -> float:
	return hp / maxf(hp_max, 1.0)


func is_controlled(now: float) -> bool:
	return control_until > now


func can_act(now: float) -> bool:
	return alive and not is_controlled(now)


# --- buffs -----------------------------------------------------------------

func add_buff(stat: String, mult: float, value: float, duration: float, now: float,
		label: String = "", element_id: String = "", max_stacks: int = 0) -> void:
	if max_stacks > 0:
		var count := 0
		for b in buffs:
			if b.get("stat", "") == stat:
				count += 1
		if count >= max_stacks:
			# refresca o mais antigo em vez de empilhar
			var oldest: Dictionary = {}
			for b in buffs:
				if b.get("stat", "") == stat:
					if oldest.is_empty() or b["until"] < oldest["until"]:
						oldest = b
			if not oldest.is_empty():
				oldest["until"] = now + duration
				return
	buffs.append({
		"stat": stat, "mult": mult, "value": value, "until": now + duration,
		"label": label, "element": element_id,
	})


func expire_buffs(now: float) -> void:
	for b in buffs.duplicate():
		if b["until"] <= now:
			buffs.erase(b)


func stat_mult(stat: String) -> float:
	var m := 1.0
	for b in buffs:
		if b["stat"] == stat:
			m *= float(b["mult"])
	return m


func stat_sum(stat: String) -> float:
	var v := 0.0
	for b in buffs:
		if b["stat"] == stat:
			v += float(b["value"])
	return v


func has_buff(stat: String) -> bool:
	for b in buffs:
		if b["stat"] == stat:
			return true
	return false


func buff_labels() -> Array:
	var out: Array = []
	for b in buffs:
		var l: String = String(b.get("label", ""))
		if l != "" and not out.has(l):
			out.append(l)
	return out


# --- estatisticas efetivas -------------------------------------------------

## FANTASMA (Arena Assombrada). Quem cai continua em campo aplicando aura,
## mas nao causa dano e nao pode ser alvo nem contado como vivo — senao o
## combate nunca terminaria. `alive` segue true para que ele continue agindo
## e andando; quem decide "esta vivo para efeito de vitoria" e `alive_units`.
var ghost := false


func eff_atk() -> float:
	return maxf(atk * stat_mult("atk"), 0.0)

func eff_def() -> float:
	return maxf(def * stat_mult("def"), 0.0)

func eff_pe() -> float:
	return maxf(pe * stat_mult("pe"), 0.0)

## GDD 4.1 -- Gelido reduz a velocidade de ataque enquanto a aura durar.
func eff_vel(gelido_slow: float) -> float:
	var v := vel * stat_mult("vel")
	if aura.has_aura("GELIDO"):
		v *= (1.0 - gelido_slow)
	return maxf(v, 0.05)

## "atk_speed" e um eixo SEPARADO de "vel" de proposito (revisao 15/09). A arena
## Campo Magnetico promete "todos atacam 12% mais rapido" e escrevia um buff
## `atk_speed` que ninguem lia. Reaproveitar "vel" teria acelerado o
## DESLOCAMENTO junto — `eff_speed` tambem multiplica por "vel" — e a arena
## viraria outra coisa: corrida, e nao cadencia de golpe.
func attack_interval(gelido_slow: float) -> float:
	return 1.0 / maxf(eff_vel(gelido_slow) * stat_mult("atk_speed"), 0.05)


## GDD 5.2 (Eco de Gelo) -- Gelido tambem reduz a velocidade de MOVIMENTO.
func eff_speed(gelido_move_slow: float) -> float:
	var v := speed_px * stat_mult("vel")
	if aura.has_aura("GELIDO"):
		v *= (1.0 - gelido_move_slow)
	return maxf(v, 0.0)


func in_range_of(other: SimUnit) -> bool:
	return other != null and pos.distance_to(other.pos) <= attack_range

func resist_to(element_id: String) -> float:
	return float(resist.get(element_id, 0.0))


## RESISTENCIA ELEMENTAL (revisao 15/09): a Afinidade ATUAL resiste ao proprio
## elemento. A formula do GDD 17.3 e o teto `combat.resist_cap` existiam inteiros
## no simulador e nunca recebiam um numero — `resist` nascia vazio e so era
## reescrito com 0.0. O valor mora em data/elements.json porque e balanceamento,
## e e o que torna verdadeira a ultima frase do Prisma de Reescrita.
static func resist_for(element_id: String) -> Dictionary:
	var v: float = float(Db.el(element_id).get("self_resist", 0.0))
	return {element_id: v} if v > 0.0 else {}

## UA aplicada por golpe, com bonus de equipe (Coro de Agua, Mao do Alquimista, itens).
func applied_ua(team_ua_add: float) -> float:
	return maxf(ua_per_hit + team_ua_add, 0.0)


func snapshot() -> Dictionary:
	return {
		"id": id, "side": side, "name": display_name, "element": element,
		"role": role, "stance": stance, "evolved": evolved, "boss": is_boss,
		"hp": hp, "hp_max": hp_max, "shield": shield, "alive": alive,
		"ult": ult_energy, "ult_max": Db.combat("ultimate_max", 100.0),
		"pos": pos, "lane": lane, "facing": facing, "auras": aura.snapshot(),
		"control": control_kind if control_until > 0.0 else "",
		"buffs": buff_labels(),
	}
