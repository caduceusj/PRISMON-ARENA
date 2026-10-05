# -*- coding: utf-8 -*-
"""Mede as peças do Monster Builder Pack e gera data/monster_rig.json.

Por que medir em vez de chutar: os corpos vão de 165x165 a 132x250. Posicionar
braços e pernas por uma fração do RETÂNGULO do corpo funciona no corpo quadrado
e desmonta no alto e estreito — foi o que deixou os bonecos quebrados. Aqui a
posição de encaixe vem da SILHUETA real: para cada corpo, mede-se a meia-largura
opaca na altura do ombro, do quadril e da cabeça, e o membro é encostado ali.

As âncoras dos membros também são medidas: o ombro é o centro de massa da faixa
superior do braço, o quadril o da faixa superior da perna, e a base do adorno o
centro de massa da faixa inferior.

    py tools/build_monster_rig.py
"""
import json
import os
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "assets", "monsters")
DST = os.path.join(ROOT, "data", "monster_rig.json")

REF = "blue"                      # a geometria e a mesma em todas as cores
BODIES = list("ABCDEF")
LIMBS = list("ABCDE")
DETAILS = ["horn_large", "horn_small", "antenna_large", "antenna_small",
           "ear", "ear_round"]

# alturas de interesse, em fração da altura do corpo a partir do TOPO
Y_HEAD = 0.16
Y_SHOULDER = 0.42
Y_HIP = 0.86


def alpha(im):
    return im.convert("RGBA").split()[3].load()


def half_width_at(im, fy):
    """Meia-largura opaca do corpo na altura `fy` (0 = topo, 1 = base),
    em fração da largura da imagem. É onde o membro deve encostar."""
    w, h = im.size
    px = alpha(im)
    y = min(max(int(round(fy * (h - 1))), 0), h - 1)
    xs = [x for x in range(w) if px[x, y] > 8]
    if not xs:
        return 0.0
    return (max(xs) - min(xs) + 1) / 2.0 / float(w)


def centre_x_at(im, fy):
    w, h = im.size
    px = alpha(im)
    y = min(max(int(round(fy * (h - 1))), 0), h - 1)
    xs = [x for x in range(w) if px[x, y] > 8]
    if not xs:
        return 0.5
    return ((max(xs) + min(xs)) / 2.0) / float(w)


def band_centroid(im, top_frac, bottom_frac):
    """Centro de massa dos pixels opacos numa faixa horizontal da imagem,
    em fração do tamanho. É assim que se acha o ombro e o quadril."""
    w, h = im.size
    px = alpha(im)
    y0 = int(top_frac * h)
    y1 = max(int(bottom_frac * h), y0 + 1)
    sx = sy = n = 0
    for y in range(y0, min(y1, h)):
        for x in range(w):
            if px[x, y] > 8:
                sx += x
                sy += y
                n += 1
    if n == 0:
        return [0.5, (top_frac + bottom_frac) * 0.5]
    return [round(sx / float(n) / w, 4), round(sy / float(n) / h, 4)]


def load(name):
    return Image.open(os.path.join(SRC, name + ".png")).convert("RGBA")


def main():
    rig = {
        "_doc": "Gerado por tools/build_monster_rig.py — MEDIDO das peças, não estimado. "
                "Não editar à mão: rodar o script.",
        "_frac": "Todas as medidas são frações do tamanho da própria imagem.",
        "bodies": {}, "arms": {}, "legs": {}, "details": {},
    }

    for b in BODIES:
        im = load("body_%s%s" % (REF, b))
        w, h = im.size
        rig["bodies"][b] = {
            "w": w, "h": h,
            "aspect": round(w / float(h), 4),
            "head_half_w": round(half_width_at(im, Y_HEAD), 4),
            "shoulder_half_w": round(half_width_at(im, Y_SHOULDER), 4),
            "hip_half_w": round(half_width_at(im, Y_HIP), 4),
            "head_cx": round(centre_x_at(im, Y_HEAD), 4),
            "shoulder_cx": round(centre_x_at(im, Y_SHOULDER), 4),
            "hip_cx": round(centre_x_at(im, Y_HIP), 4),
        }

    for a in LIMBS:
        im = load("arm_%s%s" % (REF, a))
        rig["arms"][a] = {"w": im.size[0], "h": im.size[1],
                          "anchor": band_centroid(im, 0.0, 0.13)}
        im2 = load("leg_%s%s" % (REF, a))
        rig["legs"][a] = {"w": im2.size[0], "h": im2.size[1],
                          "anchor": band_centroid(im2, 0.0, 0.16)}

    for d in DETAILS:
        im = load("detail_%s_%s" % (REF, d))
        rig["details"][d] = {"w": im.size[0], "h": im.size[1],
                             "anchor": band_centroid(im, 0.80, 1.0)}

    with open(DST, "w", encoding="utf-8") as f:
        json.dump(rig, f, ensure_ascii=False, indent=2)

    print("corpos:")
    for k, v in rig["bodies"].items():
        print("  %s  %3dx%3d  proporcao %.2f   meia-largura  cabeca %.2f  ombro %.2f  quadril %.2f"
              % (k, v["w"], v["h"], v["aspect"], v["head_half_w"],
                 v["shoulder_half_w"], v["hip_half_w"]))
    print("bracos (ancora = ombro):")
    for k, v in rig["arms"].items():
        print("  %s  %3dx%3d  ancora %.2f, %.2f" % (k, v["w"], v["h"], v["anchor"][0], v["anchor"][1]))
    print("pernas (ancora = quadril):")
    for k, v in rig["legs"].items():
        print("  %s  %3dx%3d  ancora %.2f, %.2f" % (k, v["w"], v["h"], v["anchor"][0], v["anchor"][1]))
    print("adornos (ancora = base):")
    for k, v in rig["details"].items():
        print("  %-14s %3dx%3d  ancora %.2f, %.2f" % (k, v["w"], v["h"], v["anchor"][0], v["anchor"][1]))
    print("\ngerado %s" % os.path.relpath(DST, ROOT))


if __name__ == "__main__":
    main()
