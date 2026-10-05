# -*- coding: utf-8 -*-
"""Sintetiza os sons PLACEHOLDER do PRISMON: 14 efeitos + 7 ambientes de arena.

    python tools/gerar_sons.py [nome ...]

=============================================================================
  ISTO É ANDAIME, NÃO É TRILHA. Todo .wav em assets/audio/ nasce daqui, de
  onda quadrada e ruído branco escritos à mão. Nenhum foi tocado por um sound
  designer. Estão aqui porque o PRISMON não tinha UM som — e a pergunta de
  pesquisa do slice é "o combate é interessante de ASSISTIR?", que ninguém
  responde com o som desligado. Um designer troca o conteúdo da pasta pelos
  arquivos de verdade, com os MESMOS NOMES, e não mexe em uma linha de .gd.
=============================================================================

POR QUE SINTETIZAR EM VEZ DE BAIXAR: um pacote CC0 precisa de curadoria,
crédito e download — três coisas que travam. Um script determinístico não
trava ninguém: roda em 3 s, sai igual em qualquer máquina, e o diff de um som
"errado" é uma linha de número, não um binário opaco.

SÓ BIBLIOTECA PADRÃO (wave + array + math + random). Sem numpy de propósito:
o script tem que rodar num clone limpo do repositório, e 21 arquivos curtos a
22050 Hz saem em menos de 3 s em Python puro — não há problema a resolver.

DETERMINÍSTICO: cada som tem a sua semente fixa. Rodar duas vezes escreve
bytes idênticos, então re-executar nunca suja o histórico.

O CARÁTER: quadrada e triangular, envelope de ataque curtíssimo e queda
exponencial, uma pitada de ruído no transiente. É o vocabulário de 8 bits
pela mesma razão que a interface é 9-patch de 1 px — som com cauda de reverb
sobre pixel art de 18 px lê como dois jogos colados.
"""
import array
import math
import os
import random
import struct
import sys
import wave

RAIZ = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PASTA = os.path.join(RAIZ, "assets", "audio")

# 22050 Hz mono 16 bits. Metade da taxa de CD: o conteúdo mais agudo do banco
# é um tique de 3 kHz, bem abaixo do teto de Nyquist de 11 kHz, e a pasta
# inteira cabe em ~1 MB em vez de ~4 MB. Som de menu não paga 44100.
SR = 22050

# Ambiente: 3,2 s de laço com 0,6 s de cruzamento. Medido: abaixo de ~3 s o
# ouvido pega o ciclo e o loop vira batida; 7 ambientes a 3,2 s custam 990 kB,
# que é o grosso do orçamento de 2 MB e ainda cabe.
AMB_DUR = 3.2
AMB_CRUZ = 0.6

# MARGEM DE CABECEIRA (autor, 15/09: "abaixa o som que tá muito alto e os sons
# tão meio altos demais").
#
# Cada som é normalizado para um pico PRÓPRIO — o crítico é mais alto que o
# clique de propósito, e é isso que faz a mixagem ter relevo. O problema não
# era o relevo, era o nível: os picos iam de 0,52 a 0,95, ou seja, quase
# encostando no teto do 16 bits, e os três barramentos nasciam em 1.0. Um
# combate com trinta e seis reações somava vozes já quentes e saturava.
#
# O TRIM multiplica TODOS os picos, então a proporção entre os sons fica
# intacta e só o nível desce: -6,9 dB aqui, mais o que os barramentos tiram
# em src/core/som.gd. Ajuste este número, não os picos individuais.
TRIM = 0.45


# --------------------------------------------------------------------------
# primitivas
# --------------------------------------------------------------------------

def n_de(segundos):
    return max(1, int(round(segundos * SR)))


def _forma(fase, forma, duty):
    if forma == "quadrada":
        return 1.0 if (fase % 1.0) < duty else -1.0
    if forma == "triangular":
        return 4.0 * abs((fase % 1.0) - 0.5) - 1.0
    if forma == "serra":
        return 2.0 * (fase % 1.0) - 1.0
    return math.sin(2.0 * math.pi * fase)


def onda(n, f0, f1=None, forma="quadrada", duty=0.5, vibrato=0.0, vib_hz=0.0):
    """Oscilador com varredura linear de frequência.

    A fase é acumulada em vez de recalculada a cada amostra: com `sin(2πft)` a
    varredura produz um salto de fase a cada quadro e o glissando estala.
    """
    f1 = f0 if f1 is None else f1
    fora = [0.0] * n
    fase = 0.0
    for i in range(n):
        t = i / float(n)
        f = f0 + (f1 - f0) * t
        if vibrato > 0.0:
            f += vibrato * math.sin(2.0 * math.pi * vib_hz * i / SR)
        fase += f / SR
        fora[i] = _forma(fase, forma, duty)
    return fora


def ruido(n, rng):
    return [rng.uniform(-1.0, 1.0) for _ in range(n)]


def env(n, ataque=0.004, curva=3.0):
    """Ataque linear + queda exponencial até zero no fim do buffer.

    O ataque nunca é zero: um corte seco no primeiro sample vira um estalo de
    alto-falante que aparece em todo som e some no meio da mixagem — some para
    quem mixa, não para quem joga oito horas.
    """
    na = min(n - 1, max(1, int(ataque * SR)))
    fora = [0.0] * n
    for i in range(n):
        if i < na:
            fora[i] = i / float(na)
        else:
            t = (i - na) / float(max(1, n - na))
            fora[i] = (1.0 - t) ** curva
    return fora


def passa_baixa(buf, corte):
    a = 1.0 - math.exp(-2.0 * math.pi * corte / SR)
    fora = [0.0] * len(buf)
    y = 0.0
    for i, x in enumerate(buf):
        y += a * (x - y)
        fora[i] = y
    return fora


def passa_alta(buf, corte):
    grave = passa_baixa(buf, corte)
    return [buf[i] - grave[i] for i in range(len(buf))]


def aplicar(buf, envelope):
    return [buf[i] * envelope[i] for i in range(min(len(buf), len(envelope)))]


def misturar(*pares):
    n = max(len(b) for b, _ in pares)
    fora = [0.0] * n
    for buf, ganho in pares:
        for i, v in enumerate(buf):
            fora[i] += v * ganho
    return fora


def somar_em(destino, buf, inicio, ganho=1.0):
    for i, v in enumerate(buf):
        j = inicio + i
        if 0 <= j < len(destino):
            destino[j] += v * ganho
    return destino


def esmagar(buf, niveis):
    """Quantiza a amplitude. O degrau é o que dá o grão de 8 bits ao sustain —
    a quadrada sozinha só resolve o ataque."""
    k = float(niveis - 1)
    return [round(v * k) / k for v in buf]


def normalizar(buf, pico):
    m = max(abs(v) for v in buf) or 1.0
    k = (pico * TRIM) / m
    return [v * k for v in buf]


def loopar(buf, cruzamento=AMB_CRUZ):
    """Cruza a cauda sobre a cabeça: o laço fecha sem clique.

    O buffer entra com `cruzamento` segundos a mais no fim. Esses segundos
    somem por cima do começo, em rampa — a amostra depois da última é a mesma
    que já vinha, então a emenda é contínua por construção e não por sorte.
    """
    nf = n_de(cruzamento)
    n = len(buf) - nf
    fora = buf[:n]
    for i in range(nf):
        k = i / float(nf)
        fora[i] = fora[i] * k + buf[n + i] * (1.0 - k)
    return fora


# --------------------------------------------------------------------------
# os 14 efeitos
# --------------------------------------------------------------------------

def s_golpe(rng):
    n = n_de(0.085)
    corpo = aplicar(onda(n, 430, 150, "quadrada", 0.45), env(n, 0.003, 4.0))
    batida = aplicar(passa_alta(ruido(n, rng), 1800), env(n, 0.001, 11.0))
    return normalizar(misturar((corpo, 0.62), (batida, 0.40)), 0.72)


def s_critico(rng):
    # O crítico é o golpe com uma quinta por cima e o dobro de cauda. Mesma
    # família, não outro som: o jogador tem que ouvir "foi AQUELE golpe, forte".
    n = n_de(0.200)
    base = aplicar(onda(n, 900, 250, "quadrada", 0.30), env(n, 0.002, 3.0))
    quinta = aplicar(onda(n, 1350, 375, "quadrada", 0.22), env(n, 0.002, 4.5))
    faisca = aplicar(passa_alta(ruido(n, rng), 2200), env(n, 0.001, 8.0))
    bruto = misturar((base, 0.55), (quinta, 0.32), (faisca, 0.30))
    return normalizar(esmagar(bruto, 12), 0.95)


def s_reacao(rng):
    n = n_de(0.230)
    sobe = aplicar(onda(n, 240, 980, "triangular"), env(n, 0.006, 2.0))
    oitava = aplicar(onda(n, 480, 1960, "quadrada", 0.35), env(n, 0.006, 3.0))
    brilho = aplicar(passa_alta(ruido(n, rng), 3000), env(n, 0.002, 5.0))
    return normalizar(misturar((sobe, 0.55), (oitava, 0.30), (brilho, 0.22)), 0.84)


def s_morte(rng):
    n = n_de(0.420)
    queda = aplicar(onda(n, 260, 62, "quadrada", 0.5), env(n, 0.004, 1.6))
    fundo = aplicar(onda(n, 130, 31, "serra"), env(n, 0.010, 1.3))
    po = aplicar(passa_baixa(ruido(n, rng), 900), env(n, 0.004, 2.2))
    return normalizar(misturar((queda, 0.55), (fundo, 0.28), (po, 0.18)), 0.74)


def s_ativo(rng):
    # Arpejo ascendente: o Ativo é a única coisa que o JOGADOR faz durante o
    # combate. Precisa subir, e precisa não ser confundível com um golpe.
    n = n_de(0.300)
    fora = [0.0] * n
    for k, f in enumerate([440, 587, 880]):
        nn = n_de(0.075)
        voz = aplicar(onda(nn, f, f * 1.01, "quadrada", 0.28), env(nn, 0.003, 3.0))
        somar_em(fora, voz, n_de(0.055 * k), 0.60)
    cauda = aplicar(onda(n, 1760, 1320, "triangular"), env(n, 0.05, 2.5))
    return normalizar(misturar((fora, 1.0), (cauda, 0.20)), 0.84)


def s_cura(rng):
    # Sem transiente: a cura é a única coisa boa que acontece sozinha, e um
    # ataque percussivo a faria soar como mais um impacto.
    n = n_de(0.340)
    a = aplicar(onda(n_de(0.16), 659, 659, "triangular"), env(n_de(0.16), 0.030, 1.6))
    b = aplicar(onda(n_de(0.24), 880, 880, "triangular"), env(n_de(0.24), 0.035, 1.4))
    fora = [0.0] * n
    somar_em(fora, a, 0, 0.7)
    somar_em(fora, b, n_de(0.10), 0.8)
    return normalizar(fora, 0.62)


def s_escudo(rng):
    n = n_de(0.260)
    pancada = aplicar(passa_baixa(ruido(n, rng), 700), env(n, 0.002, 7.0))
    anel = aplicar(onda(n, 330, 318, "triangular", 0.5, 6.0, 9.0), env(n, 0.008, 2.0))
    return normalizar(misturar((pancada, 0.45), (anel, 0.55)), 0.74)


def s_controle(rng):
    # Vibrato largo e grave: "isto travou". É o único som do banco com
    # oscilação audível de altura — controle tem que soar ERRADO.
    n = n_de(0.260)
    corpo = aplicar(onda(n, 185, 150, "quadrada", 0.5, 42.0, 15.0), env(n, 0.006, 1.8))
    sujeira = aplicar(passa_baixa(ruido(n, rng), 1400), env(n, 0.004, 4.0))
    return normalizar(misturar((corpo, 0.70), (sujeira, 0.18)), 0.70)


def s_clique(rng):
    n = n_de(0.045)
    tique = aplicar(onda(n, 1250, 880, "quadrada", 0.25), env(n, 0.001, 6.0))
    seco = aplicar(passa_alta(ruido(n, rng), 3500), env(n, 0.0005, 14.0))
    return normalizar(misturar((tique, 0.70), (seco, 0.22)), 0.52)


def s_hover(rng):
    # Discreto de propósito: o mouse passa por dezenas de botões por tela. Se
    # o hover tiver o peso do clique, a interface vira uma máquina de escrever.
    n = n_de(0.030)
    return normalizar(aplicar(onda(n, 1900, 1900, "quadrada", 0.18),
                              env(n, 0.001, 8.0)), 0.20)


def s_moeda(rng):
    n = n_de(0.200)
    fora = [0.0] * n
    for k, (f, dur) in enumerate([(1568, 0.055), (2093, 0.145)]):
        nn = n_de(dur)
        voz = aplicar(onda(nn, f, f, "quadrada", 0.30), env(nn, 0.002, 3.2))
        somar_em(fora, voz, n_de(0.048 * k), 0.75)
    return normalizar(fora, 0.60)


def s_vitoria(rng):
    # Arpejo maior de quatro notas, a última segurada. Vitória e derrota são a
    # mesma construção com o acorde trocado — a diferença tem que estar na
    # harmonia, não no volume.
    n = n_de(0.820)
    fora = [0.0] * n
    for k, (f, dur) in enumerate([(523, 0.16), (659, 0.16), (784, 0.16), (1046, 0.40)]):
        nn = n_de(dur)
        voz = aplicar(onda(nn, f, f, "quadrada", 0.40), env(nn, 0.004, 2.0))
        tri = aplicar(onda(nn, f * 2, f * 2, "triangular"), env(nn, 0.004, 3.0))
        somar_em(fora, misturar((voz, 0.75), (tri, 0.25)), n_de(0.135 * k), 0.70)
    return normalizar(fora, 0.82)


def s_derrota(rng):
    n = n_de(0.900)
    fora = [0.0] * n
    for k, (f, dur) in enumerate([(392, 0.20), (311, 0.20), (262, 0.48)]):
        nn = n_de(dur)
        voz = aplicar(onda(nn, f, f * 0.985, "quadrada", 0.5), env(nn, 0.008, 1.7))
        somar_em(fora, voz, n_de(0.185 * k), 0.75)
    fundo = aplicar(onda(n, 131, 124, "serra"), env(n, 0.05, 1.2))
    return normalizar(misturar((fora, 1.0), (fundo, 0.22)), 0.72)


def s_recruta(rng):
    n = n_de(0.440)
    fora = [0.0] * n
    for k, f in enumerate([440, 554, 659]):
        nn = n_de(0.13)
        voz = aplicar(onda(nn, f, f, "quadrada", 0.35), env(nn, 0.004, 2.6))
        somar_em(fora, voz, n_de(0.095 * k), 0.70)
    poeira = aplicar(passa_alta(ruido(n, rng), 2600), env(n, 0.20, 2.0))
    return normalizar(misturar((fora, 1.0), (poeira, 0.16)), 0.76)


EFEITOS = {
    "golpe": (s_golpe, 101),
    "critico": (s_critico, 102),
    "reacao": (s_reacao, 103),
    "morte": (s_morte, 104),
    "ativo": (s_ativo, 105),
    "cura": (s_cura, 106),
    "escudo": (s_escudo, 107),
    "controle": (s_controle, 108),
    "clique": (s_clique, 109),
    "hover": (s_hover, 110),
    "moeda": (s_moeda, 111),
    "vitoria": (s_vitoria, 112),
    "derrota": (s_derrota, 113),
    "recruta": (s_recruta, 114),
}


# --------------------------------------------------------------------------
# os 7 ambientes
# --------------------------------------------------------------------------
# Todos entram no `loopar`, então cada função gera AMB_DUR + AMB_CRUZ segundos.
# Pico baixo (~0,3) de propósito: ambiente que compete com o efeito é ruído.

def _n_amb():
    return n_de(AMB_DUR + AMB_CRUZ)


def modulacao(n, hz, prof, fase=0.0):
    return [1.0 - prof + prof * (0.5 + 0.5 * math.sin(2.0 * math.pi * (hz * i / SR + fase)))
            for i in range(n)]


def a_solo_vulcanico(rng):
    n = _n_amb()
    magma = aplicar(passa_baixa(ruido(n, rng), 160), modulacao(n, 0.37, 0.55))
    pulso = aplicar(onda(n, 43, 41, "seno"), modulacao(n, 0.61, 0.70))
    estalo = passa_baixa(ruido(n, rng), 2400)
    fora = misturar((magma, 0.80), (pulso, 0.35))
    for k in range(4):
        nn = n_de(0.05)
        somar_em(fora, aplicar(estalo[:nn], env(nn, 0.001, 9.0)),
                 int(n * (0.11 + 0.23 * k)), 0.22)
    return normalizar(fora, 0.32)


def a_chuva_constante(rng):
    n = _n_amb()
    gota = passa_baixa(passa_alta(ruido(n, rng), 1100), 6500)
    corpo = passa_baixa(ruido(n, rng), 420)
    fora = misturar((aplicar(gota, modulacao(n, 0.29, 0.22)), 0.85), (corpo, 0.25))
    return normalizar(fora, 0.30)


def a_nevasca(rng):
    # Vento é ruído com corte que ANDA. Com o corte parado sai chuveiro; a
    # rajada é a variação lenta, não a amplitude.
    n = _n_amb()
    base = ruido(n, rng)
    rajada = misturar((passa_baixa(base, 700), 0.6), (passa_baixa(base, 1800), 0.4))
    fora = aplicar(rajada, modulacao(n, 0.23, 0.62))
    sopro = aplicar(passa_alta(base, 2800), modulacao(n, 0.17, 0.80, 0.33))
    return normalizar(misturar((fora, 0.90), (sopro, 0.18)), 0.30)


def a_campo_magnetico(rng):
    n = _n_amb()
    zumbido = onda(n, 62, 62, "triangular")
    harm = onda(n, 186, 186, "quadrada", 0.5)
    agudo = aplicar(onda(n, 3100, 3100, "seno"), modulacao(n, 3.1, 0.90))
    fora = misturar((zumbido, 0.70), (harm, 0.12), (agudo, 0.10))
    return normalizar(fora, 0.27)


def a_bosque_vivo(rng):
    n = _n_amb()
    folhas = aplicar(passa_baixa(passa_alta(ruido(n, rng), 900), 4200),
                     modulacao(n, 0.31, 0.45))
    fora = misturar((folhas, 0.85),)
    for k in range(3):
        nn = n_de(0.06)
        chilro = aplicar(onda(nn, 2400 + 260 * k, 3100 + 260 * k, "triangular"),
                         env(nn, 0.004, 4.0))
        somar_em(fora, chilro, int(n * (0.18 + 0.29 * k)), 0.16)
    return normalizar(fora, 0.29)


def a_arena_assombrada(rng):
    # Duas triangulares desafinadas por 3 Hz: o batimento faz o drone respirar
    # sem que nada na função se mova. É o truque mais barato de "assombrado".
    n = _n_amb()
    a = onda(n, 98, 98, "triangular")
    b = onda(n, 101, 101, "triangular")
    sopro = aplicar(passa_baixa(ruido(n, rng), 380), modulacao(n, 0.19, 0.55))
    return normalizar(misturar((a, 0.45), (b, 0.45), (sopro, 0.35)), 0.28)


def a_camara_de_estimulos(rng):
    n = _n_amb()
    maquina = aplicar(onda(n, 110, 110, "quadrada", 0.5), modulacao(n, 2.0, 0.45))
    ar = passa_baixa(ruido(n, rng), 260)
    fora = misturar((maquina, 0.45), (ar, 0.40))
    for k in range(4):
        nn = n_de(0.02)
        somar_em(fora, aplicar(onda(nn, 1700, 1700, "quadrada", 0.3), env(nn, 0.001, 10.0)),
                 int(n * (0.09 + 0.25 * k)), 0.20)
    return normalizar(fora, 0.27)


AMBIENTES = {
    "solo_vulcanico": (a_solo_vulcanico, 201),
    "chuva_constante": (a_chuva_constante, 202),
    "nevasca": (a_nevasca, 203),
    "campo_magnetico": (a_campo_magnetico, 204),
    "bosque_vivo": (a_bosque_vivo, 205),
    "arena_assombrada": (a_arena_assombrada, 206),
    "camara_de_estimulos": (a_camara_de_estimulos, 207),
}


# --------------------------------------------------------------------------
# escrita
# --------------------------------------------------------------------------

def escrever(caminho, amostras):
    dados = array.array("h")
    for v in amostras:
        v = max(-1.0, min(1.0, v))
        dados.append(int(round(v * 32767.0)))
    if sys.byteorder == "big":
        # WAV é little-endian; sem isto o arquivo sairia diferente num PowerPC
        # e o script deixaria de ser determinístico entre máquinas.
        dados.byteswap()
    os.makedirs(os.path.dirname(caminho), exist_ok=True)
    with wave.open(caminho, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(dados.tobytes())
    return os.path.getsize(caminho)


LEIA_ME = """\
# assets/audio — PLACEHOLDERS

Todo arquivo desta pasta foi **gerado por `tools/gerar_sons.py`**: onda quadrada,
triangular e ruído branco, sintetizados com a biblioteca padrão do Python.
Nenhum passou por um sound designer. Não são finais, não são bonitos, e não
precisam de crédito.

**Para trocar por som de verdade:** substitua os arquivos mantendo os NOMES e a
pasta. O jogo carrega por nome (`Som.tocar("golpe")`, `Som.ambiente("nevasca")`)
e nenhuma linha de `.gd` precisa mudar. Formato esperado: WAV mono. Os
ambientes são LAÇOS — emende a cauda na cabeça ou o loop vai estalar.

Se um arquivo sumir, `Som` vira no-op silencioso naquele nome: o jogo roda
igual, sem erro e sem som. Apagar a pasta inteira é um teste válido.

## Efeitos (`efeitos/`)

%s

## Ambientes de arena (`ambiente/`)

Um por arena, pelo `id` de `data/enemies.json`. Laço de %.1f s.

%s
"""


def main():
    alvos = [a for a in sys.argv[1:] if not a.startswith("-")]
    total = 0
    linhas_ef = []
    linhas_amb = []

    print("=== PRISMON :: gerar sons (placeholders) ===")
    for nome, (fn, semente) in EFEITOS.items():
        buf = fn(random.Random(semente))
        linhas_ef.append("- `%s.wav` — %.2f s" % (nome, len(buf) / float(SR)))
        if alvos and nome not in alvos:
            continue
        b = escrever(os.path.join(PASTA, "efeitos", nome + ".wav"), buf)
        total += b
        print("  efeitos/%-10s %5.2f s  %6d B" % (nome + ".wav", len(buf) / float(SR), b))

    for nome, (fn, semente) in AMBIENTES.items():
        buf = loopar(fn(random.Random(semente)))
        linhas_amb.append("- `%s.wav`" % nome)
        if alvos and nome not in alvos:
            continue
        b = escrever(os.path.join(PASTA, "ambiente", nome + ".wav"), buf)
        total += b
        print("  ambiente/%-22s %5.2f s  %6d B" % (nome + ".wav", len(buf) / float(SR), b))

    if not alvos:
        os.makedirs(PASTA, exist_ok=True)
        with open(os.path.join(PASTA, "LEIA-ME.md"), "w", encoding="utf-8", newline="\n") as f:
            f.write(LEIA_ME % ("\n".join(linhas_ef), AMB_DUR, "\n".join(linhas_amb)))

    print("  total %.2f MB  (orcamento: 2.00 MB)" % (total / 1048576.0))
    return 0 if total < 2 * 1048576 else 1


if __name__ == "__main__":
    sys.exit(main())
