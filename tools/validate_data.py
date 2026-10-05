# -*- coding: utf-8 -*-
"""Sanity-check dos JSON de conteudo do PRISMA (roda fora do Godot)."""
import json, os, re, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

def load(name):
    with open(os.path.join(ROOT, "data", name), encoding="utf-8") as f:
        return json.load(f)

ok = True
def check(cond, msg):
    global ok
    if not cond:
        ok = False
        print("  FAIL:", msg)

el = load("elements.json")["elements"]
el_ids = set(e["id"] for e in el)
aura_ids = set(e["aura_id"] for e in el if e["aura_id"])
slice_els = set(e["id"] for e in el if e["slice"])
print("elements: %d (slice: %s)" % (len(el), sorted(slice_els)))
check(len(el) == 9, "esperado 9 elementos")
check(len(slice_els) == 5, "esperado 5 elementos no slice (com NATUREZA)")

rx = load("reactions.json")
rx_ids = set(r["id"] for r in rx["reactions"])
print("reactions: %d | matrix: %d pares" % (len(rx["reactions"]), len(rx["matrix"])))
check(len(rx["reactions"]) == 8, "esperado 8 reacoes")
check(len(rx["matrix"]) == 16, "esperado 16 pares ordenados")
for m in rx["matrix"]:
    check(m["aura"] in aura_ids, "aura desconhecida %s" % m["aura"])
    check(m["hit"] in el_ids, "elemento desconhecido %s" % m["hit"])
    check(m["reaction"] in rx_ids, "reacao desconhecida %s" % m["reaction"])
# GDD 6.6: lacunas sao deliberadas — nao se exige cobertura completa.

sp = load("species.json")["species"]
ids = set(s["id"] for s in sp)
print("species: %d (elenco de teste, sem evolucoes)" % len(sp))
check(len(sp) == 5, "esperado 5 especies de teste")
for b in sp:
    check(b["element"] in slice_els, "%s: elemento fora do slice" % b["id"])
    for k in ("hp", "atk", "def", "vel", "pe", "vontade", "ua_per_hit", "size"):
        check(k in b, "%s: falta %s" % (b["id"], k))
    check("evolves_to" not in b, "%s: elenco de teste nao tem evolucao" % b["id"])

anims = load("anims.json")
print("anims: %d criaturas" % len(anims.get("creatures", {})))
check(set(anims.get("creatures", {}).keys()) == ids,
      "anims.json e species.json devem ter os mesmos ids")
HIT = {"apollo": 13, "coalla": 11, "hipocampo": 11, "pinto_raio": 11, "sheep": 12}
for cid, cfg in anims.get("creatures", {}).items():
    check(cfg.get("hit_frame") == HIT.get(cid),
          "%s: quadro de dano deveria ser %s" % (cid, HIT.get(cid)))
    p = os.path.join(ROOT, "assets", "creatures",
                     "mon-attack-%s1.png" % cfg["prefix"])
    check(os.path.exists(p), "sheet ausente: %s" % p)

en = load("enemies.json")
for t in en["themes"]:
    for e in t["elements"]:
        n = len([s for s in sp if s["element"] == e])
        check(n >= 1, "tema %s: elemento %s sem especie" % (t["id"], e))
check(en["boss"].get("sprite") in [s["id"] for s in sp], "chefe sem sprite valido")

acts = load("actives.json")["actives"]
for a in acts:
    if a.get("radius"):
        for op in a.get("ops", []):
            if str(op.get("target","")).startswith("aim_area"):
                check("radius" in op, "ativo %s: op de area sem raio (o bug do Meteoro)" % a["id"])

for extra in ("resonances.json", "actives.json", "relics.json", "items.json",
              "dishes.json", "icons.json", "tuning.json"):
    load(extra)
    print("%s: OK" % extra)
tn = load("tuning.json")
check("momentos" in tn and "pair" in tn, "tuning: faltam secoes momentos/pair")

# ALVOS DO GDD 17.4. Ate 15/09 este bloco era DECORATIVO: os limiares que o
# medidor de fato usava estavam escritos a mao em tools/autoplay.gd:332-355,
# exatamente o que o README diz que nao existe neste projeto. Agora o autoplay
# le daqui — entao apagar uma destas chaves silenciaria o julgamento em vez de
# quebrar, e e por isso que a forma delas e conferida aqui.
tg = tn.get("targets", {})
for k in ("median_combat_duration", "timeout_rate_max", "winrate_experienced_min",
          "winrate_experienced_max", "actives_per_combat_min", "actives_per_combat_max"):
    check(isinstance(tg.get(k), (int, float)),
          "tuning.targets: falta o escalar %s (tools/autoplay.gd julga por ele)" % k)
for k in ("reactions_per_combat_reaction_build", "reactions_per_combat_resonance_build"):
    faixa = tg.get(k)
    check(isinstance(faixa, list) and len(faixa) == 2 and faixa[0] < faixa[1],
          "tuning.targets: %s tem de ser [min, max]" % k)
check(float(tg.get("winrate_experienced_min", 1)) < float(tg.get("winrate_experienced_max", 0)),
      "tuning.targets: a faixa de vitoria esta invertida")
# A PALETA (data/paleta.json). Desde 17/09 nenhuma cor de interface e `const`
# dentro de um .gd: `Db` le este arquivo e empurra para `UI`. As duas falhas
# possiveis sao de FORMA — uma paleta com chave faltando cai em `Color.MAGENTA`
# dentro de `UI._cor()`, e uma paleta `ativa` que nao existe derruba o jogo na
# reserva embutida sem ninguem perceber. As duas sao baratas de conferir aqui.
#
# O CONTRASTE nao e conferido aqui, e de proposito: ele precisa da mesma conta
# de luminancia que o jogo usa para julgar, e vive em tools/smoke_test.gd
# ([paleta] -> contraste), onde a medida e feita com a Color do Godot.
HEX = re.compile(r"^#[0-9a-fA-F]{6}$")
BLOCOS = {
    "materia": ["mesa", "lajota", "lajota_hi", "aresta"],
    "materia_aux": ["recuo", "aresta_hi"],
    "recipiente": ["fundo", "painel", "painel_hi", "linha"],
    "texto": ["forte", "fraco"],
    "estado": ["bom", "ruim", "aviso", "ouro", "acento"],
}
SALAS = ["titulo", "iniciais", "escolha", "preparacao", "sinergias", "combate",
         "vitoria", "derrota", "recruta", "loja", "cozinha", "poder", "acaso",
         "troca", "chefe", "fim_vitoria"]

pal = load("paleta.json")
paletas = dict(pal.get("paletas", {}))
# A PASTA CONTA. `Db._juntar_paletas_soltas` junta data/paletas/*.json na carga,
# com nome repetido sobrepondo o base. Se este validador nao fizesse o mesmo,
# ele reprovaria um `ativa` que o jogo carrega sem problema -- um validador que
# discorda do carregador e um validador que mente.
_pasta = os.path.join(ROOT, "data", "paletas")
if os.path.isdir(_pasta):
    for _f in sorted(os.listdir(_pasta)):
        if not _f.endswith(".json"):
            continue
        _d = json.loads(open(os.path.join(_pasta, _f), encoding="utf-8").read())
        for _k, _v in _d.get("paletas", {}).items():
            paletas[_k] = _v
ativa = pal.get("ativa", "")
print("paletas: %d (ativa: %s)" % (len(paletas), ativa))
check(len(paletas) >= 1, "paleta.json: nenhuma paleta instalada")
check(ativa in paletas,
      "paleta.json: a paleta ativa '%s' nao existe em `paletas`" % ativa)
for nome, p in sorted(paletas.items()):
    for campo in ("nome", "nota"):
        check(isinstance(p.get(campo), str) and p[campo].strip() != "",
              "paleta %s: falta o texto `%s`" % (nome, campo))
    for bloco, chaves in BLOCOS.items():
        tem = p.get(bloco)
        check(isinstance(tem, dict), "paleta %s: falta o bloco `%s`" % (nome, bloco))
        if not isinstance(tem, dict):
            continue
        check(sorted(tem.keys()) == sorted(chaves),
              "paleta %s.%s: chaves %s, esperado %s"
              % (nome, bloco, sorted(tem.keys()), sorted(chaves)))
        for k, v in sorted(tem.items()):
            check(isinstance(v, str) and HEX.match(v),
                  "paleta %s.%s.%s: '%s' nao e hex #rrggbb" % (nome, bloco, k, v))
    salas = p.get("salas", {})
    check(isinstance(salas, dict) and sorted(salas.keys()) == sorted(SALAS),
          "paleta %s.salas: chaves %s, esperado %s"
          % (nome, sorted(salas.keys()) if isinstance(salas, dict) else salas,
             sorted(SALAS)))
    if isinstance(salas, dict):
        for k, v in sorted(salas.items()):
            check(isinstance(v, str) and HEX.match(v),
                  "paleta %s.salas.%s: '%s' nao e hex #rrggbb" % (nome, k, v))
    for campo, teto in (("sala_forca", 1.0), ("sala_na_materia", 1.0)):
        v = p.get(campo)
        check(isinstance(v, (int, float)) and 0.0 <= float(v) <= teto,
              "paleta %s: `%s` tem de ser um numero de 0 a %g (veio %r)"
              % (nome, campo, teto, v))

ev = load("random_events.json")["events"]
print("random_events: %d" % len(ev))
check(len(ev) >= 5, "poucos eventos de acaso")
for e in ev:
    for k in ("id", "title", "text", "accept_label", "outcomes"):
        check(k in e, "evento %s: falta %s" % (e.get("id", "?"), k))
    tot = sum(float(o["weight"]) for o in e["outcomes"])
    check(abs(tot - 1.0) < 0.001, "evento %s: pesos somam %.2f" % (e["id"], tot))

# Cerca de UI: cobertura dos icones e as regressoes visuais que ja voltaram.
# Vive em tools/lint_ui.py porque e leitura de CODIGO, nao de dados — mas roda
# junto, para que uma so chamada continue sendo a porta de entrada.
import lint_ui
lint_ui.run(load, check)

print("\n=> %s" % ("TUDO OK" if ok else "ERROS ENCONTRADOS"))
sys.exit(0 if ok else 1)
