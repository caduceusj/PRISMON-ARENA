class_name NodeGen
extends RefCounted
## Gerador da trilha — VERSÃO 2 COMBATES (decisão do autor, 30/08/2026):
## "as duas opções pro jogador tem que ser 2 combates. Recompensas e eventos
## são automáticos, você não escolhe o caminho deles."
##
## Cada passo oferece DOIS COMBATES com informação completa (GDD §14.2). O eixo
## de tensão é o Risco do §14.4: a opção mais perigosa paga mais — e ela é
## SEMPRE a da direita, para a regra ser aprendida sem texto. Os antigos
## nós de evento viraram a sequência automática de EventGen, como em
## How Many Dudes.


## Gera o par de opções do nó `index` (1-based). Determinístico por semente.
static func generate_pair(index: int) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = Run.seed_value * 7919 + index * 104729
	var nodes_per_act: int = int(Db.run_cfg("nodes_per_act", 8))

	if index > nodes_per_act:
		return [_make_boss()]

	# Cardápio gradual (revisão 30/08): o nó define a faixa de perigo permitida.
	# Nó 1 só sorteia temas leves — o jogador COMEÇA vencendo; do nó 6 em diante
	# as duas opções são pesadas. Dentro da faixa, o contraste continua: a opção
	# A vem da metade mansa, a B da metade brava.
	var dmax: int = _sched("danger_max_by_node", index, 5)
	var dmin: int = _sched("danger_min_by_node", index, 1)
	var themes: Array = Db.themes.filter(func(t):
		return int(t["danger"]) >= dmin and int(t["danger"]) <= dmax)
	if themes.size() < 2:
		themes = Db.themes.duplicate()
	themes.sort_custom(func(a, b): return int(a["danger"]) < int(b["danger"]))
	var half: int = maxi(themes.size() / 2, 1)
	var low: Dictionary = themes[rng.randi_range(0, half - 1)]
	var high: Dictionary = themes[rng.randi_range(half, themes.size() - 1)]
	if String(low["id"]) == String(high["id"]):
		high = themes[themes.size() - 1]

	# A DA DIREITA NUNCA É MAIS FÁCIL (revisão 03/09, autor: "só colocar como
	# padrão o da direita ser levemente mais difícil, como algo subentendido").
	# A tela deixou de escrever "o mais perigoso paga mais"; sem a frase, a
	# regra só se aprende se ela valer SEMPRE. Sortear da metade mansa e da
	# metade brava quase garantia isso, mas as duas metades podem cair no mesmo
	# valor de perigo — aqui a ordem passa a ser explícita.
	if int(low["danger"]) > int(high["danger"]):
		var troca: Dictionary = low
		low = high
		high = troca
	return [_make_rinha(low, index, rng), _make_rinha(high, index, rng)]


## Modificadores do bando: SÓ NA RETA FINAL (autor, 03/09 — "para o jogador
## escalar bem, ir em algumas lojas e ficar mais forte").
##
## Até o passo 5 a briga é limpa. É o trecho em que a equipe se monta: três
## recrutas, dois poderes, uma Feira e a Cozinha. Do 6 em diante entra um
## modificador; nos dois últimos, dois. A dificuldade extra concentrada no fim
## deixou a curva de poder voltar a subir (power_last 1.02 → 1.20), então o
## meio do Ato ficou mais generoso em vez de mais raso.
static func _modifiers_for(index: int, rng: RandomNumberGenerator) -> Array:
	var reta: int = int(Db.tune("difficulty", "reta_final_a_partir_de", 6))
	var quantos := 0
	if index >= reta + 2:
		quantos = 2
	elif index >= reta:
		quantos = 1
	if quantos <= 0 or Db.modifiers.is_empty():
		return []
	var pool: Array = Db.modifiers.duplicate()
	var out: Array = []
	for i in range(mini(quantos, pool.size())):
		var pick: Dictionary = pool[rng.randi_range(0, pool.size() - 1)]
		pool.erase(pick)
		out.append(String(pick["id"]))
	return out


## A arena do tema, ou uma das que MUDAM A REGRA se já estamos na reta final.
##
## As arenas marcadas com `late` em enemies.json (Assombrada, Câmara de
## Estímulos) não pertencem a tema nenhum — sem esta escolha elas nunca
## apareceriam no jogo. E é no fim do Ato que elas cabem: até lá a arena só
## banha o campo de aura, o que ajuda a combar em vez de punir.
static func _arena_for(theme: Dictionary, index: int, rng: RandomNumberGenerator) -> String:
	var reta: int = int(Db.tune("difficulty", "reta_final_a_partir_de", 6))
	var tema_arena := String(theme.get("arena", ""))
	if index < reta:
		return tema_arena
	var especiais: Array = Db.arenas.values().filter(func(a): return bool(a.get("late", false)))
	if especiais.is_empty() or rng.randf() > 0.5:
		return tema_arena
	return String(especiais[rng.randi_range(0, especiais.size() - 1)]["name"])


static func _sched(key: String, index: int, fallback: int) -> int:
	var arr: Array = Db.tuning.get("pair", {}).get(key, [])
	if arr.is_empty():
		return fallback
	return int(arr[clampi(index - 1, 0, arr.size() - 1)])


static func _make_rinha(theme: Dictionary, index: int, rng: RandomNumberGenerator) -> Dictionary:
	var count := enemy_count_for(index)
	var power := power_for(index)
	var seed_e: int = rng.randi()
	var danger: int = int(theme.get("danger", 2))
	# GDD 14.4, eixo Risco: perigo maior paga mais
	var mult: float = 1.0 + float(Db.tune("pair", "reward_per_danger", 0.18)) * float(danger - 1)
	# So Eter. Os ingredientes que caiam aqui foram absorvidos pelo proprio
	# Eter (ether_min/max subiram em tuning.json), entao o poder de compra por
	# vitoria continua o mesmo — com uma moeda em vez de duas.
	var ether: int = int(round(_ether_reward(index, rng) * mult))
	var mods := _modifiers_for(index, rng)
	return {
		"type": "rinha", "label": "RINHA", "axis": "Risco", "index": index,
		"title": String(theme["name"]), "danger": danger,
		"preview": EnemyGen.preview(theme, count, seed_e),
		"lines": ["Arena: " + String(theme.get("arena", "—"))],
		"payload": {"theme": theme["id"], "count": count, "power": power,
			"enemy_seed": seed_e, "arena": _arena_for(theme, index, rng),
			"mods": mods},
		"rewards": {"ether": ether},
	}


static func _make_boss() -> Dictionary:
	var b: Dictionary = Db.boss
	var lines: Array = [String(b.get("title", "")), String(b.get("text", ""))]
	for t in b.get("traits", []):
		lines.append("▲ %s — %s" % [String(t.get("name", "")), String(t.get("text", ""))])
	var esc: Dictionary = b.get("escort", {})
	if not esc.is_empty():
		lines.append("Escolta: %d unidades." % int(esc.get("count", 0)))
	return {
		"type": "chefe", "label": "CHEFE", "axis": "Prova final",
		"index": Run.node_index, "danger": 5,
		"title": String(b.get("name", "Chefe")),
		"lines": lines,
		"rewards": {"ether": 30},
		"payload": {"boss": true},
	}


static func power_for(index: int) -> float:
	var d: Dictionary = Db.tuning.get("difficulty", {})
	var n: int = int(Db.run_cfg("nodes_per_act", 8))
	if index > n:
		return float(d.get("boss_power", 1.9))
	var t: float = float(index - 1) / maxf(float(n - 1), 1.0)
	return lerpf(float(d.get("power_first", 1.0)), float(d.get("power_last", 1.45)), t)


## CONTAGEM DE CORPOS POR PASSO, EXPLÍCITA (revisão 15/09).
##
## Era uma interpolação de `enemy_count_first` a `enemy_count_last`, e o
## arredondamento produzia 2,2,3,3,4,4,5,5. Contra o crescimento da equipe
## (2 corpos e recrutas nos passos 1, 3 e 7 → 2,3,3,4,4,4,4,5) isso dava dois
## passos inteiros com o jogador em VANTAGEM NUMÉRICA — e eram exatamente os dois
## picos da vitória por nó (100% e 99,5%). Meia run sem aposta nenhuma.
##
## Com um array por nó a curva é escrita à mão e conferível: nenhum passo entrega
## +1 corpo de graça. Ver `difficulty._count_doc` em data/tuning.json.
static func enemy_count_for(index: int) -> int:
	var arr: Array = Db.tuning.get("difficulty", {}).get("enemy_count_by_node", [])
	if arr.is_empty():
		return 3
	return int(arr[clampi(index - 1, 0, arr.size() - 1)])


static func _ether_reward(index: int, rng: RandomNumberGenerator) -> int:
	var lo: int = int(Db.run_cfg("ether_min", 8))
	var hi: int = int(Db.run_cfg("ether_max", 20))
	var n: int = int(Db.run_cfg("nodes_per_act", 8))
	var t: float = float(index - 1) / maxf(float(n - 1), 1.0)
	var mid: float = lerpf(float(lo), float(hi), t)
	return int(round(mid * float(Run.mods().get("reward_mult", 1.0)))) + rng.randi_range(-1, 2)
