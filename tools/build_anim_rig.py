# -*- coding: utf-8 -*-
"""Mede os sheets de animacao das criaturas e gera data/anims.json.

Mesmo principio do monster_rig: MEDIR, nao estimar. Para cada criatura, o
retangulo opaco comum a todos os quadros define a escala e a linha do chao;
sem isso, criaturas de 16px e de 31px sairiam com tamanhos aleatorios na tela.

    py tools/build_anim_rig.py
"""
import json
import os
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "assets", "creatures")
DST = os.path.join(ROOT, "data", "anims.json")

CELL = 160
SHEETS = {
    "attack": {"cols": 4, "frames": 18, "fps": 18},
    "idle":   {"cols": 4, "frames": 12, "fps": 8},
    "walk":   {"cols": 3, "frames": 6,  "fps": 10},
}
# prefixo de arquivo por criatura + quadro em que o golpe conecta (1-indexado),
# passados pelo autor do projeto
CREATURES = {
    "apollo":     {"prefix": "apollo",      "hit_frame": 13},
    "coalla":     {"prefix": "grass-coala", "hit_frame": 11},
    "hipocampo":  {"prefix": "hipocampo",   "hit_frame": 11},
    "pinto_raio": {"prefix": "pinto-raio",  "hit_frame": 11},
    "sheep":      {"prefix": "sheep",       "hit_frame": 12},
}


def union_bbox(prefix, anims=None):
    """Caixa que contem TODOS os quadros das animacoes pedidas.

    A uniao existe para o campo de batalha: se cada quadro usasse a sua propria
    caixa, o sprite mudaria de escala e de posicao a cada quadro e a criatura
    "pularia" ao trocar de animacao.

    Mas para o RETRATO a uniao esta errada. Ela inclui a extensao do ataque —
    e no Pinto-Raio o ataque levanta um topete de raio que o quadro parado nao
    usa. Centrar a uniao punha o passaro na parte de baixo do medalhao, pequeno
    e caido: era o "retrato fica abaixo do centro e desenhado pequeno".
    Por isso se mede TAMBEM a uniao so do idle, e o retrato usa essa.
    """
    union = None
    alvo = SHEETS if anims is None else {k: SHEETS[k] for k in anims}
    for anim, cfg in alvo.items():
        path = os.path.join(SRC, "mon-%s-%s1.png" % (anim, prefix))
        im = Image.open(path).convert("RGBA")
        cols = cfg["cols"]
        for i in range(cfg["frames"]):
            r, c = divmod(i, cols)
            cell = im.crop((c * CELL, r * CELL, c * CELL + CELL, r * CELL + CELL))
            bb = cell.getbbox()
            if bb is None:
                continue
            union = bb if union is None else (
                min(union[0], bb[0]), min(union[1], bb[1]),
                max(union[2], bb[2]), max(union[3], bb[3]))
    return union


def main():
    out = {
        "_doc": "Gerado por tools/build_anim_rig.py — medido dos sheets. Nao editar a mao.",
        "_facing": "Os sprites olham para a ESQUERDA; a view espelha quando a unidade olha para a direita.",
        "cell": CELL,
        "sheets": SHEETS,
        "creatures": {},
    }
    for cid, cfg in CREATURES.items():
        bb = union_bbox(cfg["prefix"])
        bi = union_bbox(cfg["prefix"], ["idle"])
        out["creatures"][cid] = {
            "prefix": cfg["prefix"],
            "hit_frame": cfg["hit_frame"],
            "hit_fraction": round((cfg["hit_frame"] - 1) / float(SHEETS["attack"]["frames"]), 4),
            "bbox": list(bb),
            "px_h": bb[3] - bb[1],
            "px_w": bb[2] - bb[0],
            "baseline": bb[3],
            # so o idle: e o que o retrato enquadra (ver union_bbox)
            "bbox_idle": list(bi),
            "px_h_idle": bi[3] - bi[1],
            "px_w_idle": bi[2] - bi[0],
        }
        sobra = (bb[3] - bb[1]) - (bi[3] - bi[1])
        print("  %-11s bbox=%s  %dx%d px  idle %dx%d (%d px de sobra)  "
              "golpe no quadro %d (%.0f%% do ataque)"
              % (cid, bb, bb[2] - bb[0], bb[3] - bb[1],
                 bi[2] - bi[0], bi[3] - bi[1], sobra, cfg["hit_frame"],
                 out["creatures"][cid]["hit_fraction"] * 100))
    with open(DST, "w", encoding="utf-8") as f:
        json.dump(out, f, ensure_ascii=False, indent=2)
    print("gerado %s" % os.path.relpath(DST, ROOT))


if __name__ == "__main__":
    main()
