extends Node
## Estado persistente de uma run (autoload "Run").
## GDD 3.1 -- o loop macro: escolha de no -> preparacao -> combate -> recompensa -> upkeep.

signal team_changed
signal resources_changed

var seed_value: int = 0
var rng := RandomNumberGenerator.new()

var node_index: int = 0            # 0 = ainda nao comecou; 1..8 = nos; 9 = chefe
var team: Array = []               # Array[UnitInstance]
var bench_copies: Dictionary = {}  # base_species_id -> copias soltas (nunca usado: a copia entra na equipe)
var ether: int = 0
var relics: Array = []
var actives: Array = []            # Array[String], teto em run.max_actives (GDD 8.1)
var incubator_uses: int = 0
var reroll_count: int = 0

var defeated: bool = false
var victory: bool = false
var history: Array = []            # log de nos visitados

const MAX_ACTIVES := 3


func total_nodes() -> int:
	return int(Db.run_cfg("nodes_per_act", 8)) + 1   # +1 = chefe


func is_boss_node() -> bool:
	return node_index > int(Db.run_cfg("nodes_per_act", 8))


func start_run(p_seed: int = 0) -> void:
	seed_value = p_seed if p_seed != 0 else randi()
	rng.seed = seed_value
	node_index = 0
	team.clear()
	relics.clear()
	history.clear()
	incubator_uses = 0
	reroll_count = 0
	defeated = false
	victory = false
	ether = int(Db.run_cfg("start_ether", 10))
	# A Mao do Domador comeca com UM poder (dados, nao codigo). Os outros dois
	# se ganham no momento de Poder — ver Db.run_cfg("max_actives").
	actives.clear()
	for a in Db.run_cfg("start_actives", ["meteoro"]):
		actives.append(String(a))
	_roll_starting_team()
	team_changed.emit()
	resources_changed.emit()


## GDD 9.2 -- "uma equipe funcional precisa de 1 aplicador de alta frequencia
## (Arcano) e 1 gatilho". A equipe inicial ensina isso sem tutorial.
func _roll_starting_team() -> void:
	var arcanos: Array = []
	var guardioes: Array = []
	for id in Db.base_species:
		var s := Db.sp(id)
		if String(s.get("rarity", "")) != "Comum":
			continue
		match String(s.get("role", "")):
			"Arcano": arcanos.append(id)
			"Guardiao": guardioes.append(id)
	arcanos.sort()
	guardioes.sort()
	var a: String = arcanos[rng.randi_range(0, arcanos.size() - 1)]
	var a_el := String(Db.sp(a).get("element", ""))
	var others: Array = guardioes.filter(func(g): return String(Db.sp(g).get("element", "")) != a_el)
	if others.is_empty():
		others = guardioes
	var g: String = others[rng.randi_range(0, others.size() - 1)]
	team.append(UnitInstance.create(a))
	team.append(UnitInstance.create(g))


## Substitui a equipe inicial pela dupla ESCOLHIDA pelo jogador (tela de
## iniciais). Mantém _roll_starting_team como reserva para quem não escolher.
func set_starting_team(ids: Array) -> void:
	team.clear()
	for id in ids:
		team.append(UnitInstance.create(String(id)))
	team_changed.emit()


# --- recursos --------------------------------------------------------------

## Gasta Eter. Devolve false (sem cobrar) se nao houver saldo — a Loja e o
## unico dreno de Eter do jogo (revisao 31/08).
func spend_ether(n: int) -> bool:
	if ether < n:
		return false
	ether -= n
	resources_changed.emit()
	return true


## Dano/cura em toda a equipe, em fracao do HP maximo. Usado pelos eventos de
## acaso, que cobram em sangue.
func team_hp_delta(pct: float) -> void:
	for u in team:
		u.hp_ratio = clampf(u.hp_ratio + pct, 0.12, 1.0)
	team_changed.emit()


func add_ether(n: int) -> void:
	ether = maxi(ether + n, 0)
	resources_changed.emit()

func spend(n: int) -> bool:
	if ether < n:
		return false
	ether -= n
	resources_changed.emit()
	return true


# --- equipe ----------------------------------------------------------------

func bond_used() -> int:
	var t := 0
	for u in team:
		t += u.bond_cost()
	return t


## GDD 10.5 -- Vinculo disponivel cresce em marcos e por Reliquia.
func bond_total() -> int:
	var base: int = int(Db.run_cfg("start_bond", 6))
	if node_index >= int(Db.run_cfg("bond_milestone_node", 5)):
		base = int(Db.run_cfg("bond_milestone_value", 8))
	base += int(mods().get("bond_add", 0.0))
	return mini(base, int(Db.run_cfg("bond_hard_cap", 14)))


func bond_free() -> int:
	return bond_total() - bond_used()


func field_full() -> bool:
	return team.size() >= int(Db.run_cfg("field_cap", 8))


func can_recruit(sp_id: String) -> bool:
	var cost: int = _bond_cost_of(sp_id)
	return not field_full() and bond_free() >= cost


func _bond_cost_of(sp_id: String) -> int:
	var ev: Dictionary = Db.tuning.get("evolution", {})
	return int(ev.get("bond_cost_evolved", 2)) if Db.sp(sp_id).get("evolved", false) \
		else int(ev.get("bond_cost_base", 1))


## Recruta. Espécies SEM linha evolutiva (o elenco de teste) entram sempre como
## uma criatura inteira nova — "melhor pegar o pokemon inteiro". A Muda só
## existe para espécies com evolves_to.
func recruit(sp_id: String) -> String:
	var base := Db.sp_base_id(sp_id)
	if String(Db.sp(base).get("evolves_to", "")) != "":
		for u in team:
			if u.base_id() == base and not u.is_evolved():
				u.copies += 1
				if u.try_evolve():
					team_changed.emit()
					return "evolved"
				team_changed.emit()
				return "copy"
	if not can_recruit(sp_id):
		return "denied"
	team.append(UnitInstance.create(sp_id))
	team_changed.emit()
	return "added"


func remove_unit(u: UnitInstance) -> void:
	team.erase(u)
	team_changed.emit()


func find_by_uid(uid: int) -> UnitInstance:
	for u in team:
		if u.uid == uid:
			return u
	return null


# --- ressonancia e modificadores agregados ---------------------------------

## GDD 5.1 -- a contagem e feita sobre o PESO ELEMENTAL, nao sobre corpos.
func elemental_weight() -> Dictionary:
	var w: Dictionary = {}
	for u in team:
		var e: String = u.element()
		w[e] = int(w.get(e, 0)) + u.weight()
	return w


## Ressonancias ativas: [{element, tier, name, text, mods}]
func active_resonances() -> Array:
	var w := elemental_weight()
	var th: Dictionary = Db.resonance_thresholds
	var out: Array = []
	for r in Db.resonances:
		var el := String(r["element"])
		var count: int = int(w.get(el, 0))
		var need: int = int(th.get(String(r["tier"]), 99))
		if count >= need:
			out.append(r)
	return out


## Proximo limiar de cada elemento presente -- alimenta a barra lateral (GDD 21.1).
func resonance_progress() -> Array:
	var w := elemental_weight()
	var th: Dictionary = Db.resonance_thresholds
	var out: Array = []
	for el in Db.slice_elements:
		var c: int = int(w.get(el, 0))
		if c <= 0:
			continue
		var next_at: int = 0
		for t in ["eco", "coro", "apice"]:
			if c < int(th.get(t, 99)):
				next_at = int(th.get(t, 99))
				break
		out.append({"element": el, "count": c, "next": next_at,
			"eco": c >= int(th.get("eco", 2)), "coro": c >= int(th.get("coro", 4))})
	out.sort_custom(func(a, b): return a["count"] > b["count"])
	return out


## Soma de TUDO que altera as regras: ressonancias + reliquias.
func mods() -> Dictionary:
	var m: Dictionary = {}
	for r in active_resonances():
		_merge(m, r.get("mods", {}))
	for rid in relics:
		_merge(m, Db.relics.get(rid, {}).get("mods", {}))
	return m


func _merge(into: Dictionary, src: Dictionary) -> void:
	for k in src.keys():
		var v: Variant = src[k]
		if typeof(v) != TYPE_FLOAT and typeof(v) != TYPE_INT:
			into[k] = v
			continue
		match String(k):
			# multiplicativos
			"encharcado_decay_mult", "carga_ua_mult", "combustao_cap_mult", \
			"energy_mult", "team_hp_mult", "reward_mult":
				into[k] = float(into.get(k, 1.0)) * float(v)
			# substituicao (o menor valor manda: Ampulheta Quebrada encurta o combate)
			"combat_duration":
				into[k] = minf(float(into.get(k, 9999.0)), float(v))
			_:
				into[k] = float(into.get(k, 0.0)) + float(v)


func has_relic(id: String) -> bool:
	return relics.has(id)


func add_relic(id: String) -> void:
	if not has_relic(id) and relics.size() < int(Db.run_cfg("max_relics", 12)):
		relics.append(id)
		team_changed.emit()


# --- culinaria (GDD 12.3 / 12.4) ------------------------------------------

## Reliquia Livro de Receitas: cozinhar deixa de exigir um Banquete.
## Quantos poderes ainda cabem na Mão do Domador.
func active_slots_free() -> int:
	return maxi(int(Db.run_cfg("max_actives", 3)) - actives.size(), 0)


## Aprende um poder novo. Recusa o repetido e recusa quando a mão está cheia —
## as duas coisas que o momento de Poder precisa perguntar antes de oferecer.
func learn_active(active_id: String) -> bool:
	if not Db.actives.has(active_id) or actives.has(active_id):
		return false
	if active_slots_free() <= 0:
		return false
	actives.append(active_id)
	resources_changed.emit()
	return true


## O MERCADOR DE TROCAS: sai um Prismon, entra outro já com o que veio junto.
##
## A criatura que sai leva o que carregava — os itens e pratos dela NÃO ficam
## para trás e não vão para a nova. A que entra traz os seus, que o Mercador
## montou em quantidade equivalente (ver EventGen.trade_offer). É isso que faz
## a troca ser troca e não uma forma de lavar item de uma criatura para outra.
func trade(u: UnitInstance, species_id: String, itens: Array, pratos: Array) -> bool:
	var i := team.find(u)
	if i < 0 or not Db.species.has(species_id):
		return false
	var novo := UnitInstance.create(species_id)
	for it in itens:
		novo.items.append(String(it))
	for d in pratos:
		novo.dishes.append(String(d))
	# entra inteiro: a criatura é nova, não herda o dano da que saiu
	novo.hp_ratio = 1.0
	team[i] = novo
	team_changed.emit()
	return true


## O LIVRO DE RECEITAS SAIU (revisao 15/09). A reliquia prometia "pratos podem ser
## cozinhados em qualquer no, nao so em Banquetes" — e o no de Banquete deixou de
## existir quando a Feira foi partida em loja e cozinha (31/08). Sobrava um
## `can_cook_anywhere()` que nenhuma tela chamava, em cima de uma chave que nenhum
## dado consultava: uma reliquia que ocupava uma vaga do sorteio e nao fazia nada.
## Apagada de data/relics.json em vez de implementada, porque a regra que ela
## reescrevia nao existe mais.


## MOEDA UNICA (revisao 03/09, autor: "junta tudo pra ser comprado via eter").
## A despensa era uma segunda moeda que so servia para comprar comida: o
## jogador guardava ingrediente de Fogo para um prato de Fogo que talvez nao
## aparecesse no cardapio, e a tela do topo carregava um contador que ninguem
## sabia ler. Com uma moeda so, comida e item disputam o mesmo bolso — e essa
## disputa e uma decisao visivel, que a outra nunca foi.
func dish_price(dish_id: String) -> int:
	return int(Db.dishes.get(dish_id, {}).get("price", 0))


func can_afford_dish(dish_id: String) -> bool:
	if not Db.dishes.has(dish_id):
		return false
	return ether >= dish_price(dish_id)


## Esta unidade aceita este prato? Nutricao respeita o Estomago; Transmutacao nao.
func unit_accepts(u: UnitInstance, dish_id: String) -> bool:
	# O GUISADO CROMATICO cai na MESMA regra do segundo Nucleo (revisao 15/09):
	# `UnitInstance.element()` devolve o item com `set_element` ANTES de olhar
	# `forced_element`, entao cozinhar o Guisado numa criatura que ja usa Nucleo
	# cobrava o Eter, dizia na tela que a Afinidade mudou — e nao mudava nada.
	if String(Db.dishes.get(dish_id, {}).get("effect", "")) == "set_element" and u.has_core():
		return false
	if not Db.dish_is_nutrition(dish_id):
		return true
	if u.dishes.has(dish_id):
		return false   # o mesmo prato duas vezes na mesma unidade nao acumula
	return u.stomach_free() > 0


## Cobra o prato e devolve quanto custou — o numero volta para o Doce do
## Esquecimento, que reembolsa metade do que a unidade ja comeu.
func _pay_dish(dish_id: String) -> int:
	var custo := dish_price(dish_id)
	spend_ether(custo)
	return custo


## GDD 12.3 / 12.4 -- cozinha um prato numa unidade. `pick` so importa para o
## Guisado Cromatico (elemento de destino). Retorna a mensagem para a UI.
## Prato de graça (Cozinheiro Errante): mesmo efeito, sem cobrar a despensa.
func cook_free(dish_id: String, u: UnitInstance, pick: String = "") -> String:
	return cook(dish_id, u, pick, true)


func cook(dish_id: String, u: UnitInstance, pick: String = "", free: bool = false) -> String:
	if u == null or not unit_accepts(u, dish_id):
		return ""
	if not free and not can_afford_dish(dish_id):
		return ""
	var d: Dictionary = Db.dishes[dish_id]
	var paid: int = 0 if free else _pay_dish(dish_id)
	var name := String(d.get("name", dish_id))

	match String(d.get("effect", "")):
		"set_element":
			u.forced_element = pick if pick != "" else u.element()
			team_changed.emit()
			return "%s agora tem Afinidade de %s." % [u.display_name(), Db.el_name(u.forced_element)]
		"evolve_discount":
			u.muda_discount += 1
			u.try_evolve()
			team_changed.emit()
			return "%s: a próxima Muda exige %d cópia(s)." % [u.display_name(), u.copies_needed()]
		"clear_stomach":
			var refund: float = float(Db.tuning.get("food", {}).get("refund_ratio", 0.5))
			var volta: int = int(floor(float(u.spent_ether) * refund))
			ether += volta
			u.dishes.clear()
			u.spent_ether = 0
			team_changed.emit()
			resources_changed.emit()
			return "%s esqueceu tudo. Estômago vazio, %d de Éter de volta." % [
				u.display_name(), volta]
		_:
			u.dishes.append(dish_id)
			u.spent_ether += paid
			team_changed.emit()
			return "%s comeu %s. %s" % [u.display_name(), name, String(d.get("text", ""))]


## Reliquia Casulo / Prato da Muda: desconto global de copias na evolucao.
func evolve_discount() -> int:
	return 1 if has_relic("casulo") else 0


# --- recuperacao entre nos -------------------------------------------------

## Revisão 02/09 (Arthur): as criaturas se recuperam entre batalhas — é o que
## reverteu a economia de sobrevivência de 31/08 e aposentou os consumíveis.
##
## Só que a recuperação era de 100% INCONDICIONAL, e `run.heal_between_nodes_pct`
## (0.35) estava no arquivo sem ninguém ler. Com cura total, o eixo de Risco da
## escolha de nó não carregava custo nenhum para a frente: entrar na luta brava,
## sair com 12% de HP e chegar inteiro no passo seguinte é a mesma coisa que
## passear. Agora a chave vale, e o dano ATRAVESSA — em fração do HP máximo.
##
## A cura acontece logo DEPOIS do combate e ANTES do momento de evento, para que
## o dano que um evento de acaso cobra ainda entre no próximo combate.
## A CURA ENTRE NOS E TOTAL, e isso e uma decisao do autor (NOTAS 5.23, 02/09):
## "faz as criaturas sempre regenerarem vida quando acabar batalha e tira as
## coisas que recupera vida fora de batalha que vai ser inutil".
##
## Nao e descuido nem falta de ajuste. E o que derrubou os consumiveis, a Bolsa,
## o Descanso da Loja e o Ativo Improviso — com regeneracao total, cura fora de
## combate nao tem funcao. Dentro de uma batalha o dano continua importando; ele
## so nao atravessa para a proxima.
##
## Em 16/09 isto foi ligado a uma fracao (`heal_between_nodes_pct`) por engano
## meu, com uma justificativa que contrariava a 5.23. Revertido. Se o custo entre
## nos tiver de voltar algum dia, ele NAO volta como HP: volta como o que voce
## equipou — ver a op `perde_equipado` em src/run/event_gen.gd.
func heal_between_nodes() -> void:
	for u in team:
		u.hp_ratio = 1.0
	team_changed.emit()


## Tira um ITEM ou um PRATO ja equipado de alguem da equipe, sorteado. Devolve
## uma descricao do que saiu, ou "" quando nao havia nada para perder.
##
## E o custo que o Acaso cobra desde 16/09. Perder HP nao custava nada (a cura
## entre nos e total, ver acima); perder um item e permanente e aparece no trilho.
func perder_equipado(rng: RandomNumberGenerator, so_prato: bool = false) -> String:
	var candidatos: Array = []
	for u in team:
		if not so_prato:
			for it in u.items:
				candidatos.append({"u": u, "tipo": "item", "id": String(it)})
		for d in u.dishes:
			# O BANQUETE DO DILUVIO E UM SLOT DE ITEM (mods.item_slot). Tirar ele
			# com a vaga ocupada deixaria a ficha em "itens 2/1" — estado que
			# `accepts_item` nunca permite pela porta da frente. Tirar o item
			# junto cobraria dois precos numa previa que prometeu um; entao ele
			# so entra no sorteio quando sobra vaga sem ele.
			var slot: int = int(Db.dishes.get(String(d), {}).get("mods", {}).get("item_slot", 0))
			if slot > 0 and u.items.size() > u.item_slots() - slot:
				continue
			candidatos.append({"u": u, "tipo": "prato", "id": String(d)})
	if candidatos.is_empty():
		return ""
	var c: Dictionary = candidatos[rng.randi_range(0, candidatos.size() - 1)]
	var u: UnitInstance = c["u"]
	var id := String(c["id"])
	var nome := ""
	if String(c["tipo"]) == "item":
		u.items.erase(id)
		nome = String(Db.items[id].get("name", id))
	else:
		# O PRATO SAI COM O BONUS JUNTO. `dishes` e a lista que alimenta os
		# bonus permanentes da Nutricao (12.3) e o Estomago — tirar o id sem
		# desfazer o bonus deixaria a estatistica fantasma na ficha.
		# Nao ha bonus em cache para desfazer: `item_slots`, `dishes_eaten` e
		# `stat_bonus` leem a lista `dishes` na hora. Tirar o id ja desfaz tudo.
		u.dishes.erase(id)
		nome = String(Db.dishes[id].get("name", id))
	team_changed.emit()
	return "%s perdeu %s" % [u.display_name(), nome]


# --- equipe ----------------------------------------------------------------


# --- ressonancia e modificadores agregados ---------------------------------


# --- culinaria (GDD 12.3 / 12.4) ------------------------------------------


# --- recuperacao entre nos -------------------------------------------------


## Cura por consumível, em fração do HP máximo. Devolve o quanto curou de fato.
func summary() -> String:
	return "No %d/%d  |  %d Eter  |  Vinculo %d/%d" % [
		node_index, total_nodes(), ether, bond_used(), bond_total()]
