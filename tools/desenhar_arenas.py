# -*- coding: utf-8 -*-
"""Monta as CENAS das arenas no Aseprite, uma camada por elemento.

O PIPELINE TEM TRES ETAPAS:

  1. tools/retonar_arenas.py  — pega o pacote de parallax CC0 (MatiasVME,
     OpenGameArt), mede a luminancia de cada pixel e remapeia para a rampa de
     cor da arena. Sai uma camada retonada por elemento.

  2. este script — monta a cena: importa cada camada retonada como uma CAMADA
     PROPRIA e desenha os adereços, tambem um por camada.

  3. tools/exportar_arenas.py — reexporta as cenas para PNG e aplica a mascara
     de alfa. E o script que se roda DEPOIS de mexer na cena a mao.

UMA CAMADA POR ELEMENTO (revisao 10/09, autor: "crie cenas separadas pra eu
ajustar visualmente, ha elementos que podem ser encaixados melhor"). Antes a
base era um PNG achatado e todos os adereços dividiam uma camada so: nao havia
o que ajustar. Agora cada poste, cada lapide e cada montanha tem a sua — da
para arrastar, esconder e reordenar no Aseprite.

TODOS OS ELEMENTOS ENTRAM, mesmo os que aquela arena nao usa: eles ficam com a
camada DESLIGADA. Experimentar o sol na Arena Assombrada passa a ser um clique,
em vez de uma ida ao codigo.

ESTE SCRIPT NAO SOBRESCREVE CENA EXISTENTE. Depois que voce mexer no .aseprite,
rodar isto de novo apagaria o seu trabalho — entao ele PULA o que ja existe.
Para refazer do zero, `--refazer`.

Rodar:  python tools/desenhar_arenas.py [--refazer] [id ...]
"""
import io
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import ase  # noqa: E402

RAIZ = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SAIDA = os.path.join(RAIZ, "assets", "arenas")

L, A = 1280, 260
HORIZONTE = 170
FIM_AVENTAL = 236
FUNDO = "#0f0d18"

# nome do arquivo do pacote -> nome da camada na cena, na ordem de tras para a
# frente. O numero na frente e so para a pilha ficar legivel no Aseprite.
PAISAGEM = [
    ("sky", "01 ceu"),
    ("sun", "02 sol"),
    ("clouds", "03 nuvens"),
    ("mountains_3", "04 montanha funda"),
    ("mountains_2", "05 montanha meio"),
    ("mountains_1", "06 montanha perto"),
    ("trees", "07 arvores"),
    ("rocks", "08 pedras"),
]

# o que cada arena mostra de cara. O resto entra desligado.
VISIVEIS = {
    "solo_vulcanico": {"01 ceu", "04 montanha funda", "05 montanha meio",
                       "06 montanha perto", "08 pedras"},
    "chuva_constante": {"01 ceu", "03 nuvens", "04 montanha funda",
                        "05 montanha meio", "06 montanha perto", "08 pedras"},
    "nevasca": {"01 ceu", "03 nuvens", "04 montanha funda", "05 montanha meio",
                "06 montanha perto", "08 pedras"},
    "campo_magnetico": {"01 ceu", "05 montanha meio", "06 montanha perto",
                        "08 pedras"},
    "bosque_vivo": {"01 ceu", "04 montanha funda", "06 montanha perto",
                    "07 arvores", "08 pedras"},
    "arena_assombrada": {"01 ceu", "06 montanha perto", "07 arvores", "08 pedras"},
}


def hexcor(s):
    s = s.lstrip("#")
    return tuple(int(s[i:i + 2], 16) for i in (0, 2, 4))


def hexstr(t):
    return "#%02x%02x%02x" % tuple(max(0, min(255, int(round(v)))) for v in t)


def rampa(tint):
    c = hexcor(tint)
    f = hexcor(FUNDO)
    return [hexstr(tuple(f[i] + (c[i] - f[i]) * k for i in range(3)))
            for k in (0.07, 0.15, 0.30, 0.52, 1.0)]


class Cena(object):
    def __init__(self, arquivo, tint):
        self.arquivo = arquivo
        self.p = rampa(tint)
        self.chamadas = [
            {"tool": "create_canvas",
             "args": {"width": L, "height": A, "filename": arquivo}},
        ]
        self._vistas = set()

    def camada(self, nome, visivel=True):
        self._vistas.add(nome)
        self.chamadas.append({"tool": "add_layer",
                              "args": {"filename": self.arquivo, "layer_name": nome}})
        if not visivel:
            self.chamadas.append({
                "tool": "set_layer_visibility",
                "args": {"filename": self.arquivo, "layer_name": nome,
                         "visible": False}})

    def importar(self, nome, png):
        self._vistas.add(nome)
        self.chamadas.append({
            "tool": "import_image_as_layer",
            "args": {"filename": self.arquivo, "image_path": png,
                     "layer_name": nome, "frame_index": 1}})

    def _add(self, tool, camada, **kw):
        # A CAMADA E CRIADA EXPLICITAMENTE na primeira vez que e usada.
        # `create_if_missing` nao cria camada — cria CEL numa camada que ja
        # exista. Sem este add_layer, todo adereço caia na camada padrao do
        # canvas e o arquivo saia com a paisagem em camadas e os adereços
        # achatados num bloco so, que e o oposto do que se quer aqui.
        if camada not in self._vistas:
            self._vistas.add(camada)
            self.chamadas.append({"tool": "add_layer",
                                  "args": {"filename": self.arquivo,
                                           "layer_name": camada}})
        args = {"filename": self.arquivo, "layer_name": camada, "frame_index": 1,
                "create_if_missing": True}
        args.update(kw)
        self.chamadas.append({"tool": tool, "args": args})

    def ret(self, camada, x, y, w, h, cor, fill=True):
        self._add("draw_rectangle_at", camada, x=int(x), y=int(y),
                  width=int(w), height=int(h), color=cor, fill=fill)

    def elipse(self, camada, cx, cy, rx, ry, cor, fill=True):
        self._add("draw_ellipse_at", camada, center_x=int(cx), center_y=int(cy),
                  radius_x=max(1, int(rx)), radius_y=max(1, int(ry)),
                  color=cor, fill=fill)

    def linha(self, camada, x1, y1, x2, y2, cor, grossura=1):
        self._add("draw_line_at", camada, x1=int(x1), y1=int(y1),
                  x2=int(x2), y2=int(y2), color=cor, thickness=int(grossura))

    def poligono(self, camada, pontos, cor, fill=True):
        self._add("draw_polygon", camada,
                  points=[{"x": int(x), "y": int(y)} for x, y in pontos],
                  color=cor, fill=fill)

    def caminho(self, camada, pontos, cor, grossura=1):
        self._add("draw_path", camada,
                  points=[{"x": int(x), "y": int(y)} for x, y in pontos],
                  color=cor, thickness=int(grossura))

    def degrade(self, camada, x, y, w, h, c0, c1, horizontal=False):
        self._add("apply_dither_gradient", camada, x=int(x), y=int(y),
                  width=int(w), height=int(h), color_start=c0, color_end=c1,
                  horizontal=horizontal)

    def textura(self, camada, x, y, w, h, ca, cb, densidade=0.5):
        self._add("apply_dither_pattern", camada, x=int(x), y=int(y),
                  width=int(w), height=int(h), color_a=ca, color_b=cb,
                  density=densidade)


# --- adereços: UM POR CAMADA, para poderem ser arrastados -----------------

def solo_vulcanico(c):
    for i, x in enumerate([70, 300, 540, 780, 1010, 1200]):
        n = "10 veio %d" % (i + 1)
        c.caminho(n, [(x, HORIZONTE + 4), (x + 14, HORIZONTE + 2),
                      (x + 28, HORIZONTE + 6), (x + 40, HORIZONTE + 3)],
                  c.p[4], 1)
    for i, (x, y) in enumerate([(150, 132), (390, 118), (620, 140),
                                (860, 124), (1090, 136)]):
        n = "11 boca %d" % (i + 1)
        c.linha(n, x, y, x + 18, y + 1, c.p[4], 1)
        c.linha(n, x + 4, y + 2, x + 14, y + 2, c.p[3], 1)


def chuva_constante(c):
    for i, (x, w) in enumerate([(60, 110), (300, 84), (520, 130),
                                (760, 96), (1000, 120)]):
        n = "10 poca %d" % (i + 1)
        c.elipse(n, x + w // 2, HORIZONTE + 16, w // 2, max(4, w // 12), c.p[2])
        c.linha(n, x + 10, HORIZONTE + 14, x + w - 12, HORIZONTE + 14, c.p[3], 1)


def nevasca(c):
    for i, (x, h, w) in enumerate([(120, 26, 8), (330, 20, 7), (560, 30, 9),
                                   (790, 22, 7), (1010, 28, 9), (1190, 18, 6)]):
        n = "10 lasca %d" % (i + 1)
        y = HORIZONTE + 12
        c.poligono(n, [(x, y), (x + w // 2, y - h), (x + w, y)], c.p[3])
        c.linha(n, x + w // 2, y - h + 1, x + w // 2, y - h + 5, c.p[4], 1)


def campo_magnetico(c):
    postes = [(80, 74), (300, 92), (520, 66), (740, 100), (960, 78), (1180, 88)]
    for i, (x, h) in enumerate(postes):
        n = "10 poste %d" % (i + 1)
        topo = HORIZONTE - h
        c.ret(n, x, topo, 12, h + 10, c.p[2])
        c.ret(n, x - 5, topo, 22, 7, c.p[3])
        c.linha(n, x + 10, topo + 7, x + 10, HORIZONTE + 6, c.p[3], 1)
    for i in range(len(postes) - 1):
        x0, h0 = postes[i]
        x1, h1 = postes[i + 1]
        y0, y1 = HORIZONTE - h0 + 3, HORIZONTE - h1 + 3
        meio = (x0 + x1) // 2
        c.caminho("11 arco %d" % (i + 1), [
            (x0 + 6, y0), (x0 + (meio - x0) // 2, y0 + 11),
            (meio, (y0 + y1) // 2 + 5), (meio + (x1 - meio) // 2, y1 + 13),
            (x1 + 6, y1)], c.p[4], 1)


def bosque_vivo(c):
    for i, x in enumerate(range(70, L, 118)):
        n = "10 cogumelo %d" % (i + 1)
        y = HORIZONTE + 14
        c.ret(n, x + 3, y - 6, 3, 6, c.p[3])
        c.elipse(n, x + 4, y - 9, 6, 4, c.p[4])


def arena_assombrada(c):
    for i, (x, w, h) in enumerate([(90, 22, 32), (280, 20, 28), (470, 23, 34),
                                   (660, 19, 26), (850, 22, 32), (1040, 20, 28),
                                   (1210, 21, 30)]):
        n = "10 lapide %d" % (i + 1)
        y = HORIZONTE + 14
        c.ret(n, x, y - h + w // 2, w, h - w // 2, c.p[3])
        c.elipse(n, x + w // 2, y - h + w // 2, w // 2, w // 2, c.p[3])
        c.linha(n, x + w - 1, y - h + w // 2, x + w - 1, y - 1, c.p[2], 1)


def camara_de_estimulos(c):
    """INTERIOR: sem paisagem do pacote, desenhada inteira."""
    c.ret("01 parede", 0, 0, L, HORIZONTE, c.p[0])
    c.textura("01 parede", 0, 0, L, HORIZONTE, c.p[1], FUNDO, 0.26)
    c.degrade("02 chao", 0, HORIZONTE, L, FIM_AVENTAL - HORIZONTE, c.p[1], FUNDO)
    c.textura("02 chao", 0, HORIZONTE, L, 50, c.p[2], FUNDO, 0.22)
    topo = 30
    for i in range(8):
        x = 40 + i * 158
        n = "03 coluna %d" % (i + 1)
        c.ret(n, x, topo, 44, HORIZONTE - topo, c.p[1])
        c.ret(n, x - 6, topo, 56, 14, c.p[2])
        c.ret(n, x - 6, HORIZONTE - 16, 56, 16, c.p[2])
        c.linha(n, x + 41, topo + 14, x + 41, HORIZONTE - 16, c.p[2], 1)
    for j, y in enumerate((70, 108)):
        n = "04 cano %d" % (j + 1)
        c.ret(n, 0, y, L, 8, c.p[2])
        c.linha(n, 0, y + 1, L, y + 1, c.p[3], 1)
        for x in range(0, L, 64):
            c.ret(n, x, y - 4, 10, 16, c.p[3])
    for i, x in enumerate(range(46, L, 132)):
        n = "05 frasco %d" % (i + 1)
        y = HORIZONTE + 18
        c.ret(n, x, y - 18, 13, 18, c.p[3])
        c.ret(n, x + 2, y - 10, 9, 9, c.p[4])


ARENAS = {
    "solo_vulcanico": solo_vulcanico,
    "chuva_constante": chuva_constante,
    "nevasca": nevasca,
    "campo_magnetico": campo_magnetico,
    "bosque_vivo": bosque_vivo,
    "arena_assombrada": arena_assombrada,
    "camara_de_estimulos": camara_de_estimulos,
}
SEM_PAISAGEM = {"camara_de_estimulos"}


def main():
    args = sys.argv[1:]
    refazer = "--refazer" in args
    pedidos = [a for a in args if not a.startswith("--")]
    dados = json.load(io.open(os.path.join(RAIZ, "data", "enemies.json"),
                              encoding="utf-8"))
    for a in dados.get("arenas", []):
        aid = a.get("id")
        if aid not in ARENAS or (pedidos and aid not in pedidos):
            continue
        alvo_ase = os.path.join(SAIDA, "%s.aseprite" % aid).replace("\\", "/")
        if os.path.exists(alvo_ase) and not refazer:
            print("  %-22s ja existe — pulando (use --refazer para recriar)" % aid)
            continue

        c = Cena(alvo_ase, a.get("tint", "#8f88a8"))
        if aid not in SEM_PAISAGEM:
            vis = VISIVEIS.get(aid, set())
            for arq, nome in PAISAGEM:
                png = os.path.join(SAIDA, "_cam_%s_%s.png" % (aid, arq))
                if not os.path.exists(png):
                    continue
                c.importar(nome, png.replace("\\", "/"))
                if nome not in vis:
                    c.chamadas.append({
                        "tool": "set_layer_visibility",
                        "args": {"filename": alvo_ase, "layer_name": nome,
                                 "visible": False}})
        ARENAS[aid](c)
        # a camada padrao do canvas fica vazia e so atrapalha na lista
        c.chamadas.append({"tool": "delete_layer",
                           "args": {"filename": alvo_ase, "layer_name": "Layer 1"}})
        res = ase.executar(c.chamadas, silencioso=True)
        ruins = [(c.chamadas[i]["tool"], r) for i, r in enumerate(res)
                 if r.startswith("ERRO") or r == "SEM RESPOSTA"]
        for t, r in ruins[:4]:
            print("   !! %s -> %s" % (t, r[:130]))
        print("  %-22s cena montada (%d chamadas, %d erros)"
              % (aid, len(c.chamadas), len(ruins)))


if __name__ == "__main__":
    main()
