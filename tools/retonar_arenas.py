# -*- coding: utf-8 -*-
"""Monta a BASE das arenas a partir do pacote CC0 de parallax.

O pacote (MatiasVME, CC0, OpenGameArt) e pixel art de verdade: ceu pontilhado,
montanhas com sombreamento, picos nevados, pinheiros. O problema e que ele e
claro e alegre, e o PRISMON e escuro. Jogar aquilo no jogo do jeito que veio
gritaria.

O QUE ESTE SCRIPT FAZ E REMAPEAR VALOR. Para cada pixel opaco ele mede a
LUMINANCIA do original e usa so isso: a cor de saida sai da rampa da arena, na
mesma posicao relativa. O desenho do artista — a silhueta, o sombreado, e
sobretudo o dithering — fica inteiro; o que muda e a paleta.

E por isso que isto vale mais que recolorir por matiz: preservar valor preserva
a LEITURA da imagem. Trocar so o matiz deixaria a paisagem clara demais e ela
continuaria brigando com o fundo do jogo.

Cada arena escolhe QUAIS camadas entram — sem pinheiro no vulcao, sem nuvem na
nevasca — e a faixa vertical que interessa.

UMA SAIDA POR CAMADA, e nao uma base achatada (revisao 10/09, autor: "crie
cenas separadas pra eu ajustar visualmente, ha elementos que podem ser
encaixados melhor"). Com a base achatada nao havia o que ajustar: montanha, ceu
e pedra eram um pixel so. Agora cada camada do pacote sai num arquivo, e a cena
montada no Aseprite tem uma camada por elemento — da para arrastar a montanha,
esconder a nuvem, subir o sol.

O MAPEAMENTO DE VALOR E CALCULADO NO COMPOSITO e aplicado igual a todas as
camadas. Medir camada por camada esticaria cada uma para a rampa inteira, e a
montanha do fundo — que e escura de proposito — sairia tao clara quanto a da
frente: a profundidade que o artista desenhou iria embora.

Rodar: python tools/retonar_arenas.py
Saida: assets/arenas/_cam_<id>_<camada>.png
"""
import io
import json
import os

from PIL import Image

RAIZ = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
# O pacote vive DENTRO do projeto (assets/arenas/fonte_cc0), para a receita ser
# reproduzivel sem baixar nada de novo. TEMP_PACK so serve para apontar para
# outra copia durante um teste.
PACK = os.environ.get("TEMP_PACK") or os.path.join(RAIZ, "assets", "arenas", "fonte_cc0")
SAIDA = os.path.join(RAIZ, "assets", "arenas")

FUNDO = (15, 13, 24)

# A faixa util do pacote. As camadas tem 1280x360; a linha de pedras (o "chao"
# do desenho original) fica embaixo, e e ela que vira o nosso horizonte.
LARG = 1280
ALT = 260
HORIZONTE = 170          # dentro da nossa tela de 260
FIM_AVENTAL = 236
RECORTE_Y = 100          # de onde comeca a fatia do pacote (360 -> 260)

# Quanto do preto ao tint cada arena ocupa, e com que curva.
#
# A primeira tentativa usou (0.05, 0.52) linear, e cada arena virou uma parede
# de cor: o ceu, que e a maior area da imagem, caia no meio da rampa e dominava
# a tela. Com GAMA a conta muda de forma — a maior parte da imagem fica no
# fundo escuro e so os realces (pico nevado, topo de nuvem, aresta iluminada)
# sobem. E o que deixa a paisagem ATRAS do combate em vez de brigando com ele.
FAIXA = (0.03, 0.46)
GAMA = 1.5

# TODAS AS ARENAS RECEBEM TODOS OS ELEMENTOS (revisao 10/09, autor: "adicione
# os elementos do cenario no cenario"). Antes cada arena listava um subconjunto,
# e o que ficava de fora simplesmente nao existia no arquivo — nao dava para
# experimentar. Agora tudo e retonado e entra na cena; o que nao servir fica
# com a camada DESLIGADA, e ligar e um clique.
TODAS = ["sky", "sun", "clouds", "mountains_3", "mountains_2", "mountains_1",
         "trees", "rocks"]
CAMADAS = {
    "solo_vulcanico": TODAS,
    "chuva_constante": TODAS,
    "nevasca": TODAS,
    "campo_magnetico": TODAS,
    "bosque_vivo": TODAS,
    "arena_assombrada": TODAS,
    # a Camara e INTERIOR: nao ha paisagem que sirva, e ela continua desenhada
    # inteira no Aseprite
}


def hexcor(s):
    s = s.lstrip("#")
    return tuple(int(s[i:i + 2], 16) for i in (0, 2, 4))


def carregar(pack, nome):
    cam = os.path.join(pack, "forest_background_%s.png" % nome)
    if not os.path.exists(cam):
        return None
    return Image.open(cam).convert("RGBA").crop(
        (0, RECORTE_Y, LARG, RECORTE_Y + ALT))


def compor(pack, camadas):
    base = Image.new("RGBA", (LARG, ALT), (0, 0, 0, 0))
    for n in camadas:
        im = carregar(pack, n)
        if im is not None:
            base.alpha_composite(im)
    return base


def faixa_de(im):
    """A faixa de luminancia usada pelo COMPOSITO. E ela que rege todas as
    camadas, para a relacao de profundidade entre elas nao se perder."""
    px = im.load()
    vmin, vmax = 1.0, 0.0
    for y in range(im.height):
        for x in range(im.width):
            r, g, b, a = px[x, y]
            if a < 8:
                continue
            L = (0.2126 * r + 0.7152 * g + 0.0722 * b) / 255.0
            vmin = min(vmin, L)
            vmax = max(vmax, L)
    return vmin, max(vmax - vmin, 0.001)


def retonar(im, tint, vmin, span):
    """Luminancia do original -> rampa da arena. O desenho fica, a cor muda."""
    c = hexcor(tint)
    px = im.load()
    lo, hi = FAIXA
    # O TETO DA RAMPA COMPENSA O BRILHO DO PROPRIO TINT. Com o teto fixo, o
    # Campo Magnetico (#e8c23a, luminancia 0.75) virava uma parede amarela
    # luminosa enquanto o Solo Vulcanico (#e8563a, 0.45) ficava no ponto — a
    # mesma fracao de rampa, resultados opostos. Dividindo pelo brilho do tint,
    # os sete chegam com o mesmo PESO na tela.
    lt = (0.2126 * c[0] + 0.7152 * c[1] + 0.0722 * c[2]) / 255.0
    hi *= max(0.55, min(1.25, 0.45 / max(lt, 0.2)))
    for y in range(im.height):
        for x in range(im.width):
            r, g, b, a = px[x, y]
            if a < 8:
                px[x, y] = (0, 0, 0, 0)
                continue
            L = (0.2126 * r + 0.7152 * g + 0.0722 * b) / 255.0
            t = lo + (hi - lo) * (((L - vmin) / span) ** GAMA)
            px[x, y] = (
                int(round(FUNDO[0] + (c[0] - FUNDO[0]) * t)),
                int(round(FUNDO[1] + (c[1] - FUNDO[1]) * t)),
                int(round(FUNDO[2] + (c[2] - FUNDO[2]) * t)),
                a,
            )
    return im


def main():
    pack = PACK
    if not pack or not os.path.isdir(pack):
        print("defina TEMP_PACK apontando para a pasta do pacote extraido")
        return 1
    dados = json.load(io.open(os.path.join(RAIZ, "data", "enemies.json"),
                              encoding="utf-8"))
    for a in dados.get("arenas", []):
        aid = a.get("id")
        if aid not in CAMADAS:
            continue
        tint = a.get("tint", "#8f88a8")
        vmin, span = faixa_de(compor(pack, CAMADAS[aid]))
        feitas = []
        for n in CAMADAS[aid]:
            im = carregar(pack, n)
            if im is None:
                continue
            im = retonar(im, tint, vmin, span)
            im.save(os.path.join(SAIDA, "_cam_%s_%s.png" % (aid, n)))
            feitas.append(n)
        print("  %-22s %d camadas: %s" % (aid, len(feitas), ", ".join(feitas)))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
