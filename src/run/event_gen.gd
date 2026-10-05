class_name EventGen
extends RefCounted
## Os MOMENTOS de evento entre combates (revisão 31/08, decisão do autor).
##
## O jogador nunca escolhe o CAMINHO — o jogo decide qual evento acontece, pelo
## esquema em data/tuning.json → momentos.evento_apos_combate. Mas dentro do
## evento a escolha é dele:
##   recruta → escolhe entre DUAS criaturas
##   loja    → escolhe que ITEM comprar (Éter)
##   cozinha → escolhe que PRATO e QUAL Prismon come (em Éter)
##   acaso   → escolhe se entra no evento ou não
##
## Aqui só se MONTA a oferta. Quem aplica é a tela, quando o jogador decide.


## Que tipo de evento vem depois do combate `index`, ou "" se nenhum.
static func kind_after(index: int) -> String:
	var arr: Array = Db.tuning.get("momentos", {}).get("evento_apos_combate", [])
	if arr.is_empty() or index < 1 or index > arr.size():
		return ""
	return String(arr[index - 1])


static func _rng(index: int, salt: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = Run.seed_value * 4243 + index * 7877 + salt
	return rng


# --- recruta ---------------------------------------------------------------

## Duas criaturas para escolher. Prefere espécies com menos cópias na equipe,
## para o elenco não virar cinco Sheep.
static func recruit_offer(index: int) -> Array:
	var rng := _rng(index, 11)
	var count: Dictionary = {}
	for u in Run.team:
		count[u.species_id] = int(count.get(u.species_id, 0)) + 1
	var pool: Array = []
	for id in Db.base_species:
		var sid := String(id)
		if not Run.can_recruit(sid):
			continue
		for i in range(maxi(3 - int(count.get(sid, 0)), 1)):
			pool.append(sid)
	var want: int = int(Db.tuning.get("momentos", {}).get("recruta", {}).get("opcoes", 2))
	var out: Array = []
	var tries := 0
	while out.size() < want and tries < 40:
		tries += 1
		if pool.is_empty():
			break
		var pick: String = pool[rng.randi_range(0, pool.size() - 1)]
		if not out.has(pick):
			out.append(pick)
	return out


# --- loja (itens permanentes, em Éter) --------------------------------------

## O estoque: 3 itens, às vezes uma relíquia, e um descanso. `roll` avança a
## cada renovação, então renovar dá um estoque de verdade diferente.
static func shop_offer(index: int, roll: int = 0) -> Array:
	var rng := _rng(index, 23 + roll * 101)
	var cfg: Dictionary = Db.tuning.get("momentos", {}).get("loja", {})
	var prices: Dictionary = cfg.get("preco_por_raridade", {})
	var out: Array = []

	# A loja NÃO filtra por quem você tem: itens de assinatura aparecem mesmo
	# sem o dono na equipe. É o mundo, não um catálogo montado para você.
	var pool: Array = Db.item_order.duplicate()
	for i in range(int(cfg.get("ofertas", 3))):
		if pool.is_empty():
			break
		var pick := String(pool[rng.randi_range(0, pool.size() - 1)])
		pool.erase(pick)
		var it: Dictionary = Db.items[pick]
		var owner := String(it.get("for", ""))
		out.append({"kind": "item", "id": pick,
			"price": int(prices.get(String(it.get("rarity", "Comum")), 12)),
			"name": String(it["name"]), "text": String(it["text"]),
			# o item de dono ganha o RETRATO dele na tela, nao a frase "só Apollo":
			# a etiqueta aqui fica so com a raridade (ver ScreenShop._row)
			"tag": String(it.get("rarity", "")),
			"owner": owner})

	if rng.randf() < float(cfg.get("reliquia_chance", 0.35)):
		var rel: Array = Db.relic_order.filter(func(r): return not Run.has_relic(String(r)))
		if not rel.is_empty():
			var rid := String(rel[rng.randi_range(0, rel.size() - 1)])
			out.append({"kind": "relic", "id": rid,
				"price": int(cfg.get("reliquia_preco", 38)),
				"name": String(Db.relics[rid]["name"]),
				"text": String(Db.relics[rid]["text"]), "tag": "Relíquia", "owner": ""})

	return out


# --- cozinha (pratos, em Éter) ----------------------------------------------

## 3 pratos por visita, sorteados entre TODOS — não só entre os que o Éter
## banca. Ver um prato caro que você não pode pagar é informação: diz o que
## vale guardar Éter para comprar depois.
static func kitchen_offer(index: int, roll: int = 0) -> Array:
	var rng := _rng(index, 71 + roll * 131)
	var cfg: Dictionary = Db.tuning.get("momentos", {}).get("cozinha", {})
	var pool: Array = Db.dish_order.duplicate()
	var out: Array = []
	# O primeiro prato do cardápio é sempre um que o Éter BANCA, quando
	# existir algum. Sem isso, três sorteios entre sete pratos podiam devolver
	# só os caros e o momento de Cozinha virava uma tela sem jogada — a
	# métrica de "runs que cozinharam" caiu de 89% para 67% exatamente assim.
	var afford: Array = pool.filter(func(x): return Run.can_afford_dish(String(x)))
	var forced := ""
	if not afford.is_empty():
		forced = String(afford[rng.randi_range(0, afford.size() - 1)])
		pool.erase(forced)
	for i in range(int(cfg.get("ofertas", 3))):
		var pick := forced if (i == 0 and forced != "") else ""
		if pick == "":
			if pool.is_empty():
				break
			pick = String(pool[rng.randi_range(0, pool.size() - 1)])
		pool.erase(pick)
		out.append({"kind": "dish", "id": pick,
			"price": int(Db.dishes[pick].get("price", 0)),
			"name": String(Db.dishes[pick]["name"]),
			"text": String(Db.dishes[pick]["text"])})
	return out


# --- troca (o Mercador) -----------------------------------------------------

## O que o Mercador oferece por CADA Prismon da equipe.
##
## Regra do autor (03/09): trocar um Prismon "pelado" é uma troca simples; se
## ele carrega item ou prato, a oferta vem com a MESMA quantidade de itens e
## pratos — "os equivalentes, para que faça valer". Sem isso o Mercador seria
## uma armadilha: você entregaria uma criatura investida e receberia uma nua.
##
## Determinístico pela semente, como toda a trilha: reabrir a tela não muda a
## oferta, e renovar (`roll`) muda de propósito e custa Éter.
static func trade_offer(index: int, roll: int = 0) -> Array:
	var rng := _rng(index, 811 + roll * 173)
	var out: Array = []
	for u in Run.team:
		var pool: Array = Db.base_species.filter(func(x):
			return not _team_has(String(x)))
		if pool.is_empty():
			continue
		var sp := String(pool[rng.randi_range(0, pool.size() - 1)])
		out.append({"uid": u.uid, "species": sp,
			"items": _match_items(sp, u.items.size(), rng),
			"dishes": _match_dishes(sp, u.dishes.size(), rng)})
	return out


static func _team_has(sp_id: String) -> bool:
	for u in Run.team:
		if u.base_id() == sp_id:
			return true
	return false


## Itens que a espécie oferecida PODE usar, na mesma quantidade que o Prismon
## entregue carregava. Respeita a regra de assinatura: um item "só do Apollo"
## nunca aparece numa oferta que não é o Apollo.
static func _match_items(sp_id: String, quantos: int, rng: RandomNumberGenerator) -> Array:
	if quantos <= 0:
		return []
	var pool: Array = Db.item_order.filter(func(x):
		var dono := String(Db.items[String(x)].get("for", ""))
		return dono == "" or dono == sp_id)
	var out: Array = []
	for i in range(quantos):
		if pool.is_empty():
			break
		var pick := String(pool[rng.randi_range(0, pool.size() - 1)])
		pool.erase(pick)
		out.append(pick)
	return out


## Pratos de NUTRIÇÃO, na mesma quantidade. Transmutação fica de fora: ela
## reescreve a criatura em vez de alimentá-la, e "vir com um Guisado" não
## significa nada — o efeito dele já estaria embutido no elemento.
static func _match_dishes(sp_id: String, quantos: int, rng: RandomNumberGenerator) -> Array:
	if quantos <= 0:
		return []
	var pool: Array = Db.dish_order.filter(func(x): return Db.dish_is_nutrition(String(x)))
	var out: Array = []
	for i in range(quantos):
		if pool.is_empty():
			break
		var pick := String(pool[rng.randi_range(0, pool.size() - 1)])
		pool.erase(pick)
		out.append(pick)
	return out


# --- poder (a Mão do Domador cresce) ----------------------------------------

## Quantas ESCOLHAS o momento de Poder entrega de uma vez.
##
## O Acaso voltou à sequência (revisão 15/09) e tomou o lugar de um dos dois
## momentos de Poder. Para `run.max_actives` (3) continuar alcançável com um
## momento só, ele passa a dar DUAS escolhas seguidas: o jogador escolhe um
## poder, e a oferta seguinte já vem sem ele (o `roll` muda a semente e o pool
## filtra o que ele acabou de aprender).
static func power_escolhas() -> int:
	return maxi(int(Db.tuning.get("momentos", {}).get("poder", {}).get("escolhas", 1)), 1)


## Poderes que o jogador AINDA NÃO tem, sorteados. Determinístico por semente,
## como todo o resto da trilha.
static func power_offer(index: int, roll: int = 0) -> Array:
	var rng := _rng(index, 313 + roll * 97)
	var cfg: Dictionary = Db.tuning.get("momentos", {}).get("poder", {})
	var pool: Array = Db.active_order.filter(func(a): return not Run.actives.has(String(a)))
	var out: Array = []
	for i in range(int(cfg.get("ofertas", 3))):
		if pool.is_empty():
			break
		var pick := String(pool[rng.randi_range(0, pool.size() - 1)])
		pool.erase(pick)
		var a: Dictionary = Db.actives[pick]
		out.append({"kind": "active", "id": pick,
			"name": String(a["name"]), "text": String(a["text"]),
			"color": String(a["color"]), "icon": "act_" + pick,
			"cost": int(a["cost"])})
	return out


## Preço de renovar, crescente dentro do mesmo momento: renovar sempre é uma
## escolha real, não um botão grátis de rolar até gostar.
static func reroll_price(kind: String, roll: int) -> int:
	var cfg: Dictionary = Db.tuning.get("momentos", {}).get(kind, {})
	return int(cfg.get("renovar_preco", 6)) + int(cfg.get("renovar_passo", 4)) * roll


# --- acaso -----------------------------------------------------------------

static func chance_offer(index: int) -> Dictionary:
	if Db.random_events.is_empty():
		return {}
	var rng := _rng(index, 37)
	return Db.random_events[rng.randi_range(0, Db.random_events.size() - 1)]


## Sorteia o desfecho de um evento aceito e APLICA. Devolve o que aconteceu.
static func resolve_chance(ev: Dictionary, index: int) -> Dictionary:
	var rng := _rng(index, 59)
	var roll := rng.randf()
	var acc := 0.0
	var chosen: Dictionary = ev["outcomes"][ev["outcomes"].size() - 1]
	for o in ev["outcomes"]:
		acc += float(o["weight"])
		if roll <= acc:
			chosen = o
			break
	var lines: Array = []
	# PENDÊNCIAS: o que o evento concede mas NÃO decide. O modelo não abre
	# tela, então ele devolve o que ficou por escolher e a tela resolve com os
	# mesmos painéis da Feira e da Cozinha. Antes o evento sorteava o item E
	# quem recebia, e podia reescrever a Afinidade de um Prismon qualquer sem
	# avisar (autor, 03/09: "tem um item também que sofre da mesma coisa").
	var pendente: Array = []
	var ganhos: Array = []
	for op in chosen.get("ops", []):
		var line := _apply_op(op, rng, pendente, ganhos)
		if line != "":
			lines.append(line)
	return {"good": bool(chosen.get("good", true)),
		"text": String(chosen.get("text", "")), "lines": lines,
		"ganhos": ganhos, "pendente": pendente}


## `ganhos` recebe o QUE foi ganho, com tipo e id — nao a prosa sobre ele.
## A tela precisa do id para desenhar o icone e ler o texto da peca; com uma
## frase pronta ela so conseguiria repetir a frase.
static func _apply_op(op: Dictionary, rng: RandomNumberGenerator,
		pendente: Array, ganhos: Array = []) -> String:
	match String(op.get("op", "")):
		"ether":
			var n := int(op.get("n", 0))
			Run.add_ether(n)
			return "+%d Éter" % n
		"heal":
			Run.team_hp_delta(float(op.get("pct", 0.3)))
			return "equipe recupera %d%%" % int(float(op.get("pct", 0.3)) * 100.0)
		"damage":
			# MANTIDA SO PARA DADO ANTIGO NAO QUEBRAR. A cura entre nos e
			# TOTAL (NOTAS 5.23), entao perder HP aqui nao custa nada: a
			# equipe volta inteira no no seguinte. Nenhum evento de
			# data/random_events.json usa mais esta op — o risco agora e
			# `perde_equipado`.
			Run.team_hp_delta(-float(op.get("pct", 0.2)))
			return ""
		"perde_equipado":
			# O RISCO DE VERDADE (16/09, autor: "nas chances de perder algo
			# coloque uma chance de perder um item ou uma comida equipada").
			# Permanente, visivel no trilho, e doi — ao contrario do HP, que
			# se recompoe sozinho antes da proxima briga.
			var perdido := Run.perder_equipado(rng, bool(op.get("so_prato", false)))
			return perdido if perdido != "" else "nao havia nada para perder"
		"item":
			# Só itens que ALGUÉM da equipe pode de fato usar. O sorteio antigo
			# saía de `Db.item_order` inteiro contra quem tivesse espaço
			# (`can_equip`), sem olhar o dono: dava para o Sheep receber a
			# Cauda de Brasa, que é só do Apollo — a regra de assinatura era
			# respeitada na loja e furada aqui.
			var possiveis: Array = Db.item_order.filter(func(x):
				return not Run.team.filter(func(u): return u.accepts_item(String(x))).is_empty())
			if possiveis.is_empty():
				return ""
			var it := String(possiveis[rng.randi_range(0, possiveis.size() - 1)])
			pendente.append({"tipo": "item", "id": it})
			return "achou %s" % String(Db.items[it]["name"])
		"relic":
			var pool: Array = Db.relic_order.filter(func(r): return not Run.has_relic(String(r)))
			if pool.is_empty():
				return ""
			var rid := String(pool[rng.randi_range(0, pool.size() - 1)])
			Run.add_relic(rid)
			ganhos.append({"tipo": "reliquia", "id": rid})
			# a prosa fica vazia de proposito: quem desenha isto e o cartao de
			# revelacao da tela, com icone e com o texto da reliquia
			return ""
		"dish_free":
			# Escolhe o PRATO por sorteio entre os que alguém aceita, mas QUEM
			# come fica para a tela perguntar. Antes era o primeiro prato da
			# lista para o primeiro Prismon elegível — sempre o mesmo, e sem
			# decisão nenhuma.
			var pratos: Array = Db.dish_order.filter(func(x):
				return not Run.team.filter(func(u): return Run.unit_accepts(u, String(x))).is_empty())
			if pratos.is_empty():
				return ""
			var pr := String(pratos[rng.randi_range(0, pratos.size() - 1)])
			pendente.append({"tipo": "prato", "id": pr})
			return "o cozinheiro serve %s" % String(Db.dishes[pr]["name"])
	return ""
