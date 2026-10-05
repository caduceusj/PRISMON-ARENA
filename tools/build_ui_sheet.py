# -*- coding: utf-8 -*-
"""Gera as pecas de interface do PRISMON -- direcao de arte "O VIDRO DO DOMADOR".

    py tools/build_ui_sheet.py

POR QUE ESTE SCRIPT FOI REESCRITO (revisao 15/09, Raiz 3)
---------------------------------------------------------
A versao anterior compunha molduras da Kenney sobre a cor de painel e as
CLAREAVA, para que o `modulate_color` do StyleBoxTexture conseguisse tinge-las.
O efeito colateral e que `modulate_color` multiplica a textura INTEIRA: borda e
miolo. Medido em shots/07b_loja.png, o miolo do painel ficava em luma 16,0
contra 14,9 do fundo da tela -- 1,1 de diferenca -- enquanto a borda ia a 130,1.
O jogo virou "uma bisel de 6 px flutuando num campo chapado", e era por isso que
onze telas diferentes pareciam a mesma tela.

O conserto nao e uma cor nova: e SEPARAR AS CAMADAS. Cada celula sai daqui em
DOIS arquivos, e quem compoe as duas e o ui.gd, em cache, com modulate BRANCO:

  frame_<nome>.png    MATERIA NEUTRA, ja na cor final -- aresta, realce, pe,
                      sombra dura. O miolo fica TRANSPARENTE aqui.
  frame_<nome>_m.png  MASCARA, um canal por papel (alfa sempre 255):
                        R = cobertura do MIOLO   -> ui.gd pinta solido
                        G = cobertura do FEIXE   -> ui.gd pinta com a cor do elemento
                        B = quanto a materia se mistura ao elemento (0 = neutra)

Com isso o miolo NUNCA e modulado: um painel de Fogo continua com o corpo em
#1c1930 e queima so no corte. Medido no PNG gerado: miolo luma 28,5 contra 14,9
do fundo da tela -- 13,6 de diferenca, doze vezes os 1,1 de antes.

O GESTO QUE SE REPETE: O CANTO CORTADO E O FEIXE
------------------------------------------------
Todo recipiente perde o canto superior esquerdo para uma escada de 45 graus em
9 px -- tres degraus de 3 px, que e a MESMA especificacao de canto que o PDF do
briefing ja da a artista. De dentro do corte sai uma barra de 2 px na cor do
elemento. Luz entra pelo corte, sai colorida.

A sombra e DURA: 3 px, preta, deslocada para baixo-direita, sem nenhum desfoque
(5 px na lajota erguida). E a peca que mais muda a percepcao e ela mora num
lugar so -- aqui.

A GEOMETRIA, e por que cada numero e esse
-----------------------------------------
Celula de 40x40. Nao e arbitrario: e a menor caixa que cabe, na mesma imagem,
a escada de 9 px + o feixe de 2 px (11 px de canto), a lajota, e a sombra de
5 px da lajota erguida sem que nada disso caia na faixa ESTICAVEL do 9-patch.

  TOPO  = 3    folga acima da lajota; e nela que a lajota sobe 2 px no hover
  CAUDA = 6    folga abaixo/a direita; e nela que a sombra dura cabe

  margens do 9-patch: L=14  T=15  R=15  B=15  (B=17 nas celulas de dois cortes)

  L=14 porque o canto cortado + feixe ocupa 11 px e a aresta 1 px -- 14 da
  folga de 2. T=15 porque a lajota AFUNDADA comeca em y=4 e o feixe dela desce
  ate y=14, entao a linha 14 PRECISA estar na faixa de canto (0 a T-1).
  B=17 so nas celulas `confirm`, porque o segundo corte (canto oposto) comeca
  em y=24 na versao erguida.

Se voce mudar CELL, TOPO ou CAUDA, rode o tools/ui_probe.tscn e OLHE o PNG: e
exatamente para o 9-patch quebrar la, e nao na tela do jogo, que ele existe.

O QUE CONTINUA VINDO DA KENNEY
------------------------------
So o medalhao (ring / ring_gold), que e arte de personagem e nao de recipiente.
As molduras, a faixa de titulo e as barras passaram a ser desenhadas aqui.
"""
import json
import os
from collections import deque

from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "assets", "ui", "kenney_ui_tilemap.png")
OUT = os.path.join(ROOT, "assets", "ui")

TS, SP, COLS = 32, 1, 13


# --- os quatro degraus neutros, LIDOS DE data/paleta.json ------------------
#
# "materia e neutra em quatro degraus, sem matiz; estado e saturacao cheia".
# Estes quatro valores sao a materia inteira do jogo.
#
# Ate 16/09 eles estavam escritos DUAS vezes -- aqui e em src/ui/ui.gd -- com
# um comentario pedindo "se mudar um, mude os dois". Nao ha mais duas listas:
# os dois lados leem data/paleta.json, e trocar a cara do jogo e trocar um
# campo de JSON e rodar este script de novo.


def carrega_paleta():
    """A paleta ATIVA de data/paleta.json, como dicionario."""
    with open(os.path.join(ROOT, "data", "paleta.json"), encoding="utf-8") as f:
        doc = json.load(f)
    nome = doc["ativa"]
    if nome not in doc["paletas"]:
        raise SystemExit(
            "data/paleta.json: a paleta ativa '%s' nao existe" % nome)
    return nome, doc["paletas"][nome]


def _rgb(hexs):
    h = hexs.lstrip("#")
    return (int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16))


PALETA_NOME, PALETA = carrega_paleta()
_MATERIA = PALETA["materia"]

MESA = _rgb(_MATERIA["mesa"])
LAJOTA = _rgb(_MATERIA["lajota"])
LAJOTA_HI = _rgb(_MATERIA["lajota_hi"])
ARESTA = _rgb(_MATERIA["aresta"])


# Dois degraus auxiliares: o fundo do RECUO (mais escuro que a mesa) e a
# aresta da lajota ERGUIDA (mais clara que a aresta). Eles vivem num bloco
# proprio da paleta, `materia_aux`, e nao dentro de `materia`, porque nao sao
# degraus da rampa: nunca aparecem como corpo de nada, so como o fundo de um
# buraco e a quina de uma peca levantada.
#
# Tentei DERIVA-LOS dos quatro e nao da: #4b4468 e exatamente 1,30x a ARESTA
# #3a3450 (medido, canal a canal), mas #070610 nao e nenhum multiplo de
# #0f0d18 -- os canais dao 0,467 / 0,462 / 0,667. Foram escolhidos a mao, e
# escrever uma formula que "quase" os reproduz seria trocar dois valores certos
# por dois valores errados com cara de regra.
_AUX = PALETA["materia_aux"]
FUNDO = _rgb(_AUX["recuo"])
ARESTA_HI = _rgb(_AUX["aresta_hi"])

# A rampa, do mais escuro ao mais claro. Os indices sao o vocabulario das
# celulas mais abaixo.
RAMPA = [FUNDO, MESA, LAJOTA, LAJOTA_HI, ARESTA, ARESTA_HI]

# A sombra nao e 100% preta de proposito. Sobre o fundo da tela (#0f0d18,
# luma 14,9) preto puro e 0,88 de preto sao indistinguiveis -- mas sobre a ARTE
# DA ARENA, onde os paineis do combate pousam, preto puro le como um buraco
# recortado em vez de sombra. 0,88 mantem a aresta igualmente dura e deixa
# passar um degrau do cenario.
SOMBRA = (0, 0, 0, 224)

CELL = 40
TOPO = 3
CAUDA = 6
LAJ_W = CELL - CAUDA          # 34
LAJ_H = CELL - TOPO - CAUDA   # 31

DEGRAU = 3       # o degrau da escada, em px -- a especificacao do PDF
CORTE_N = 3      # 3 degraus x 3 px = os 9 px do canto principal
CORTE_BR_N = 2   # o segundo corte (commit) e menor: 6 px

MARGEM = (14, 15, 15, 15)        # L, T, R, B
MARGEM_CONFIRM = (14, 15, 15, 17)


# (nome, elevacao, sombra, cortes, aresta, realce, pe, extra)
#
#   elevacao  +2 = lajota ERGUIDA (hover)   0 = em repouso   -1 = AFUNDADA
#   sombra    px da sombra dura; 0 na afundada (o que afunda nao projeta)
#   cortes    "TL" e o gesto padrao; "TLBR" e o COMMIT -- dois cantos cortados
#             dizem "isto confirma" sem precisar de cor
#   aresta/realce/pe  indices da RAMPA
#   extra     decoracao propria da celula (ver `_extra`)
#
# AS OITO CELULAS PUBLICAS TEM PAPEL, nao so aparencia (a revisao achou quatro
# delas mortas: as decoradas eram usadas em UM lugar do jogo inteiro).
CELULAS = [
    # nome        elev som cortes  ar re pe  extra
    ("panel",       0,  3, "TL",   4, 3, 1, ""),          # recipiente padrao
    ("panel_hi",    2,  5, "TL",   5, 4, 2, ""),          # lajota ERGUIDA: hover, dica, chip
    ("inset",      -1,  0, "TL",   3, 0, 3, "recuo"),     # afundada: apertado, campo, trilho
    ("gold",        2,  5, "TL",   5, 4, 2, "regua_topo"),# destaque: recompensa, chefe
    ("danger",      0,  3, "TL",   4, 3, 1, "regua_pe"),  # perigo: o aviso mora no pe
    ("confirm",     0,  3, "TLBR", 4, 3, 1, ""),          # COMMIT em repouso
    ("focus",       2,  5, "TL",   5, 4, 2, "feixe_esq"), # ESCOLHIDO: o feixe desce inteiro
    ("slot",       -1,  0, "TL",   3, 0, 3, "tracejada"), # vago: aresta tracejada, nada dentro
    ("confirm_hi",  2,  5, "TLBR", 5, 4, 2, ""),          # COMMIT sob o mouse
    ("confirm_in", -1,  0, "TLBR", 3, 0, 3, "recuo"),     # COMMIT apertado
]

# Mistura da ARESTA com a cor do elemento (canal B da mascara).
# Nao e 0: uma aresta 100% neutra faz a cor virar de novo so uma pastilha no
# canto. Nao e 1: a regra dura da direcao e "o saturado nunca acima de 5% da
# tela". 0,35 em cima/a esquerda (por onde a luz entra) e 0,15 embaixo/a direita
# poem o matiz na aresta sem que ela dispute com o feixe.
MIX_LUZ = 0.35
MIX_SOMBRA = 0.15
MIX_REALCE = 0.20
MIX_PE = 0.08


def _corte(lx, ly, n):
    """A escada de 45 graus: `n` degraus de DEGRAU px, cortando o canto."""
    return (lx // DEGRAU) + (ly // DEGRAU) < n


def _vizinhos(x, y):
    return ((x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1))


def celula(spec):
    """Desenha uma celula em duas imagens: materia neutra e mascara."""
    nome, elev, som, cortes, i_ar, i_re, i_pe, extra = spec
    base = Image.new("RGBA", (CELL, CELL), (0, 0, 0, 0))
    mask = Image.new("RGBA", (CELL, CELL), (0, 0, 0, 255))
    bp, mp = base.load(), mask.load()

    # a lajota afundada tambem desliza 1 px para a direita: e o que deixa a
    # PAREDE do buraco (o `recuo`) aparecer nos dois lados e nao so em cima.
    px0 = 1 if elev < 0 else 0
    py0 = TOPO - elev

    dentro = [[False] * CELL for _ in range(CELL)]
    cortado = [[False] * CELL for _ in range(CELL)]
    for lx in range(LAJ_W):
        for ly in range(LAJ_H):
            x, y = px0 + lx, py0 + ly
            fora = _corte(lx, ly, CORTE_N)
            if "BR" in cortes:
                fora = fora or _corte(LAJ_W - 1 - lx, LAJ_H - 1 - ly, CORTE_BR_N)
            if fora:
                cortado[x][y] = True
            else:
                dentro[x][y] = True

    # SOMBRA DURA: a propria lajota deslocada. Herdar o corte e de graca e e o
    # detalhe que faz a sombra parecer projetada por aquela peca, e nao colada.
    if som > 0:
        for x in range(CELL):
            for y in range(CELL):
                if not dentro[x][y]:
                    continue
                sx, sy = x + som, y + som
                if 0 <= sx < CELL and 0 <= sy < CELL and not dentro[sx][sy]:
                    bp[sx, sy] = SOMBRA

    borda = [[False] * CELL for _ in range(CELL)]
    luz = [[False] * CELL for _ in range(CELL)]
    for x in range(CELL):
        for y in range(CELL):
            if not dentro[x][y]:
                continue
            for nx, ny in _vizinhos(x, y):
                if not (0 <= nx < CELL and 0 <= ny < CELL) or not dentro[nx][ny]:
                    borda[x][y] = True
                    # a aresta de cima e a da esquerda recebem a luz
                    if ny < y or nx < x:
                        luz[x][y] = True

    # O FEIXE: a faixa de 2 px que huga a escada por dentro. Dilatacao de
    # Chebyshev em vez de uma reta de 45 graus porque a reta, num pixel de 1:1,
    # sai pontilhada -- e o degrau de 3 px e justamente a forma que o resto da
    # interface repete.
    esp = 3 if extra == "feixe_esq" else 2
    feixe = [[False] * CELL for _ in range(CELL)]
    for x in range(CELL):
        for y in range(CELL):
            if not cortado[x][y]:
                continue
            for dx in range(-esp, esp + 1):
                for dy in range(-esp, esp + 1):
                    nx, ny = x + dx, y + dy
                    if 0 <= nx < CELL and 0 <= ny < CELL and dentro[nx][ny]:
                        feixe[nx][ny] = True

    _extra(extra, dentro, borda, feixe, bp, px0, py0)

    for x in range(CELL):
        for y in range(CELL):
            if not dentro[x][y]:
                continue
            if feixe[x][y]:
                mp[x, y] = (0, 255, 0, 255)          # estado puro
            elif borda[x][y]:
                mix = MIX_LUZ if luz[x][y] else MIX_SOMBRA
                bp[x, y] = RAMPA[i_ar] + (255,)
                mp[x, y] = (0, 0, int(mix * 255), 255)
                if extra == "tracejada" and ((x + y) // 2) % 2 == 0:
                    bp[x, y] = RAMPA[max(i_ar - 2, 0)] + (255,)
                    mp[x, y] = (0, 0, 0, 255)
            elif _anel(dentro, borda, x, y, True):
                bp[x, y] = RAMPA[i_re] + (255,)
                mp[x, y] = (0, 0, int(MIX_REALCE * 255), 255)
            elif _anel(dentro, borda, x, y, False):
                bp[x, y] = RAMPA[i_pe] + (255,)
                mp[x, y] = (0, 0, int(MIX_PE * 255), 255)
            else:
                mp[x, y] = (255, 0, 0, 255)          # MIOLO: cor solida, nunca modulada

    return base, mask


def _anel(dentro, borda, x, y, alto):
    """1 px logo por dentro da aresta. `alto` = o lado por onde a luz entra.

    E este anel que da ESPESSURA a lajota. Sem ele o painel tem um contorno e
    um vazio; com ele tem um chanfro, que e o que o olho le como objeto.
    """
    if alto:
        pares = ((x, y - 1), (x - 1, y))
    else:
        pares = ((x, y + 1), (x + 1, y))
    for nx, ny in pares:
        if 0 <= nx < CELL and 0 <= ny < CELL and borda[nx][ny] and dentro[nx][ny]:
            return True
    return False


def _extra(extra, dentro, borda, feixe, bp, px0, py0):
    """Decoracao propria de cada celula, sempre em faixa que o 9-patch estica bem.

    A regra: acento que precisa sobreviver ao esticamento tem de ser uma FAIXA
    (linha inteira ou coluna inteira). Um adereco solto no meio vira um risco
    atravessando o painel -- foi o defeito da primeira versao deste kit.
    """
    if extra == "feixe_esq":
        # o feixe vertical de 3 px na aresta esquerda: o mesmo sinal da linha de
        # lista, agora na escala do cartao. Como mora na faixa L do 9-patch, ele
        # estica na VERTICAL e acompanha qualquer altura.
        for lx in range(3):
            for y in range(CELL):
                x = px0 + lx
                if dentro[x][y]:
                    feixe[x][y] = True
    elif extra in ("regua_topo", "regua_pe"):
        for x in range(CELL):
            col = [y for y in range(CELL) if dentro[x][y] and not borda[x][y]]
            if not col:
                continue
            alvo = col[:2] if extra == "regua_topo" else col[-2:]
            for y in alvo:
                feixe[x][y] = True
    elif extra == "recuo":
        # o que afunda nao projeta sombra: ele mostra a PAREDE do buraco. Uma
        # linha preta 1 px acima e a esquerda da lajota e a borda desse buraco.
        for x in range(CELL):
            for y in range(CELL):
                if not dentro[x][y]:
                    continue
                for nx, ny in ((x, y - 1), (x - 1, y)):
                    if 0 <= nx < CELL and 0 <= ny < CELL and not dentro[nx][ny]:
                        bp[nx, ny] = (0, 0, 0, 200)


# --- a faixa de titulo ------------------------------------------------------
#
# A peca antiga tinha 192x64 com pontas FIXAS de 64 px. Medidas na revisao, as
# faixas do jogo vao de 688 a 1412 px: com 64 px presos em cada ponta, a parte
# que estica varia de 560 a 1284 px, e as pontas passam a ler como dois adesivos
# colados numa barra. A peca nova tem 96 px com pontas de 24, e as pontas nao
# tem mais desenho proprio -- so o canto cortado, que e o mesmo de todo
# recipiente. Em 688 px ou em 1412 px ela le como UMA placa.
FAIXA_W, FAIXA_H = 96, 64
FAIXA_MARGEM = 24
FAIXA_SOMBRA = 3


def faixa():
    base = Image.new("RGBA", (FAIXA_W, FAIXA_H), (0, 0, 0, 0))
    mask = Image.new("RGBA", (FAIXA_W, FAIXA_H), (0, 0, 0, 255))
    bp, mp = base.load(), mask.load()
    pw, ph = FAIXA_W - FAIXA_SOMBRA, FAIXA_H - FAIXA_SOMBRA

    dentro = [[False] * FAIXA_H for _ in range(FAIXA_W)]
    cortado = [[False] * FAIXA_H for _ in range(FAIXA_W)]
    for x in range(pw):
        for y in range(ph):
            if _corte(x, y, CORTE_N):
                cortado[x][y] = True
            else:
                dentro[x][y] = True

    for x in range(FAIXA_W):
        for y in range(FAIXA_H):
            if not dentro[x][y]:
                continue
            sx, sy = x + FAIXA_SOMBRA, y + FAIXA_SOMBRA
            if sx < FAIXA_W and sy < FAIXA_H and not dentro[sx][sy]:
                bp[sx, sy] = SOMBRA

    borda = [[False] * FAIXA_H for _ in range(FAIXA_W)]
    luz = [[False] * FAIXA_H for _ in range(FAIXA_W)]
    for x in range(FAIXA_W):
        for y in range(FAIXA_H):
            if not dentro[x][y]:
                continue
            for nx, ny in _vizinhos(x, y):
                if not (0 <= nx < FAIXA_W and 0 <= ny < FAIXA_H) or not dentro[nx][ny]:
                    borda[x][y] = True
                    if ny < y or nx < x:
                        luz[x][y] = True

    feixe = [[False] * FAIXA_H for _ in range(FAIXA_W)]
    for x in range(FAIXA_W):
        for y in range(FAIXA_H):
            if not cortado[x][y]:
                continue
            for dx in range(-2, 3):
                for dy in range(-2, 3):
                    nx, ny = x + dx, y + dy
                    if 0 <= nx < FAIXA_W and 0 <= ny < FAIXA_H and dentro[nx][ny]:
                        feixe[nx][ny] = True
    # a regua do pe: e ELA que faz o parametro `tint` da faixa existir. Ate
    # agora a unica superficie grande e opaca do jogo era sempre o mesmo
    # vermelho #e2665b da Kenney, e o `tint` de ui.gd:407 tinha ZERO chamadas.
    for x in range(FAIXA_W):
        col = [y for y in range(FAIXA_H) if dentro[x][y] and not borda[x][y]]
        for y in col[-2:]:
            feixe[x][y] = True

    for x in range(FAIXA_W):
        for y in range(FAIXA_H):
            if not dentro[x][y]:
                continue
            if feixe[x][y]:
                mp[x, y] = (0, 255, 0, 255)
            elif borda[x][y]:
                mix = MIX_LUZ if luz[x][y] else MIX_SOMBRA
                bp[x, y] = ARESTA_HI + (255,)
                mp[x, y] = (0, 0, int(mix * 255), 255)
            elif _anel(dentro, borda, x, y, True):
                bp[x, y] = ARESTA + (255,)
                mp[x, y] = (0, 0, int(MIX_REALCE * 255), 255)
            else:
                mp[x, y] = (255, 0, 0, 255)
    return base, mask


# --- as barras --------------------------------------------------------------
#
# 36x18 com pontas de 9 (9/18/9), que e o que src/ui/prisma_bar.gd fatia.
#
# CANAL DE VIDRO: 1 px escuro em cima, 2 px claros embaixo. E o perfil que faz
# um sulco parecer um sulco -- a luz bate no fundo do canal, nao na boca dele.
#
# O acoplamento com prisma_bar.gd foi DESFEITO (16/09): aquele arquivo passou a
# desenhar o trilho com Color.WHITE, entao as cores daqui valem como escritas e
# o divisor e 1.0. Ele fica no lugar, e nao some, porque e o unico aviso de que
# as duas pontas tem de andar juntas: se alguem voltar a clarear por modulate
# la, e aqui que se compensa.
DIV_TRILHO = 1.0

BAR_W, BAR_H, BAR_PONTA = 36, 18, 9

TRILHO_TOPO = (0x05, 0x04, 0x09)
TRILHO_FUNDO = MESA
TRILHO_LUZ = ARESTA

PREENCHIMENTOS = {
    "green": (0x5C, 0xD6, 0xA0),
    "red": (0xE0, 0x57, 0x6A),
    "blue": (0x3A, 0x7F, 0xE0),
    "yellow": (0xE8, 0xB2, 0x3A),
}


def _div(c, k):
    return tuple(min(int(round(v / k)), 255) for v in c) + (255,)


def _mexe(c, k):
    return tuple(min(max(int(round(v * k)), 0), 255) for v in c) + (255,)


def trilho():
    im = Image.new("RGBA", (BAR_W, BAR_H), (0, 0, 0, 0))
    px = im.load()
    for x in range(BAR_W):
        for y in range(BAR_H):
            if y == 0:
                px[x, y] = _div(TRILHO_TOPO, DIV_TRILHO)
            elif y >= BAR_H - 2:
                px[x, y] = _div(TRILHO_LUZ, DIV_TRILHO)
            else:
                px[x, y] = _div(TRILHO_FUNDO, DIV_TRILHO)
    return im


def preenchimento(cor):
    im = Image.new("RGBA", (BAR_W, BAR_H), (0, 0, 0, 0))
    px = im.load()
    for x in range(BAR_W):
        for y in range(BAR_H):
            if y == 0:
                px[x, y] = _mexe(cor, 1.30)
            elif y == BAR_H - 1:
                px[x, y] = _mexe(cor, 0.62)
            else:
                px[x, y] = cor + (255,)
    # A BARRA BRANCA DE 1 PX NA FRENTE DO PREENCHIMENTO. E o que o olho persegue
    # quando a vida cai: o numero muda, a cor muda pouco, mas uma linha branca
    # andando para a esquerda se ve na visao periferica. Mora na ponta DIREITA
    # da textura (9 px que o 9-patch nunca estica), entao ela fica presa na
    # frente do preenchimento em qualquer largura.
    for y in range(BAR_H):
        px[BAR_W - 2, y] = (255, 255, 255, 255)
        px[BAR_W - 1, y] = _mexe(cor, 0.35)
    return im


# --- o medalhao, que continua sendo arte da Kenney -------------------------

def tile(sheet, i):
    r, c = divmod(i, COLS)
    x, y = c * (TS + SP), r * (TS + SP)
    return sheet.crop((x, y, x + TS, y + TS)).convert("RGBA")


def brighten(img, target=235):
    out = img.copy()
    px = out.load()
    w, h = out.size
    peak = 1
    for x in range(w):
        for y in range(h):
            r, g, b, a = px[x, y]
            if a > 0:
                peak = max(peak, r, g, b)
    k = float(target) / float(peak)
    for x in range(w):
        for y in range(h):
            r, g, b, a = px[x, y]
            if a > 0:
                px[x, y] = (min(int(r * k), 255), min(int(g * k), 255),
                            min(int(b * k), 255), a)
    return out


def interior_mask(img):
    """Pixels transparentes alcancaveis a partir do centro: o miolo da moldura."""
    px = img.load()
    w, h = img.size
    seen = [[False] * h for _ in range(w)]
    start = (w // 2, h // 2)
    if px[start][3] != 0:
        return seen
    q = deque([start])
    seen[start[0]][start[1]] = True
    while q:
        x, y = q.popleft()
        for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            nx, ny = x + dx, y + dy
            if 0 <= nx < w and 0 <= ny < h and not seen[nx][ny] and px[nx, ny][3] == 0:
                seen[nx][ny] = True
                q.append((nx, ny))
    return seen


def compose_group(sheet, rows, fill, light):
    w, h = len(rows[0]) * TS, len(rows) * TS
    im = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    for r, row in enumerate(rows):
        for c, idx in enumerate(row):
            t = tile(sheet, idx)
            im.alpha_composite(brighten(t) if light else t, (c * TS, r * TS))
    if fill is not None:
        px = im.load()
        centre = px[w // 2, h // 2]
        for x in range(w):
            for y in range(h):
                if px[x, y][3] == 0 or px[x, y][:3] == centre[:3]:
                    if 4 < x < w - 5 and 4 < y < h - 5:
                        px[x, y] = fill
    return im


ANEIS = [
    ("ring", [[48, 49], [61, 62]]),
    ("ring_gold", [[46, 47], [59, 60]]),
]


def main():
    print("O VIDRO DO DOMADOR -- celula %dx%d, corte de %d px (%d degraus de %d)"
          % (CELL, CELL, DEGRAU * CORTE_N, CORTE_N, DEGRAU))
    for spec in CELULAS:
        nome = spec[0]
        base, mask = celula(spec)
        base.save(os.path.join(OUT, "frame_%s.png" % nome))
        mask.save(os.path.join(OUT, "frame_%s_m.png" % nome))
        m = MARGEM_CONFIRM if "BR" in spec[3] else MARGEM
        print("  frame_%-12s elev%+d sombra %d px  corte %-4s  margem L%d T%d R%d B%d"
              % (nome, spec[1], spec[2], spec[3], m[0], m[1], m[2], m[3]))

    b, m = faixa()
    b.save(os.path.join(OUT, "banner.png"))
    m.save(os.path.join(OUT, "banner_m.png"))
    print("  banner       %dx%d  pontas de %d px (eram 64 -- viravam adesivo acima de 700 px)"
          % (FAIXA_W, FAIXA_H, FAIXA_MARGEM))

    trilho().save(os.path.join(OUT, "bar_track.png"))
    for nome, cor in sorted(PREENCHIMENTOS.items()):
        preenchimento(cor).save(os.path.join(OUT, "bar_%s.png" % nome))
    print("  bar_track + %d preenchimentos  %dx%d  pontas de %d px"
          % (len(PREENCHIMENTOS), BAR_W, BAR_H, BAR_PONTA))

    sheet = Image.open(SRC).convert("RGBA")
    for nome, spec in ANEIS:
        compose_group(sheet, spec, None, False).save(os.path.join(OUT, "%s.png" % nome))
    print("  ring + ring_gold  (unica peca que continua vindo do tilesheet da Kenney)")


if __name__ == "__main__":
    main()
