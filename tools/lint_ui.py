# -*- coding: utf-8 -*-
"""Cerca contra as regressoes de UI que o autor ja apontou mais de uma vez.

Cada regra aqui nasceu de um print. Nenhuma delas da erro no Godot: o jogo
compila, roda e fica visualmente errado em silencio — que e exatamente o tipo
de defeito que precisa de um teste, porque nao aparece em nenhum log.

Roda fora do Godot, chamado por tools/validate_data.py.
"""
import glob
import io
import json
import os
import re

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# Os icones sao 32x32 nativos (sheet da Shikashi). 16, 32 e 48 sao as unicas
# escalas que nao reamostram pixel art em fracao quebrada; qualquer outro valor
# deixa o icone com um tamanho ligeiramente diferente do vizinho na mesma linha
# — era metade do "icones esparsos e nao encaixando" do pedido.
ICON_LIMPOS = {"16", "32", "48", "16.0", "32.0", "48.0"}

# Um nivel de parenteses aninhados e OBRIGATORIO no padrao: a forma mais comum
# no codigo e `Icons.item(String(o["id"]), 34.0)`, e um `[^)\n]*?` para no `)`
# de `String(...)` e nao chega ao numero. A primeira versao desta regra casava
# ZERO ocorrencias e passava verde — um lint que nao morde e pior que nenhum,
# porque dá a impressao de que foi verificado.
_ARGS = r"(?:[^()\n]|\([^()\n]*\))*?"

ICONE = re.compile(
    r"Icons\.(?:element|role|node|item|dish|relic|active|node_type)"
    r"\(" + _ARGS + r",\s*([0-9]+(?:\.[0-9]+)?)\s*[,)]"
)

# set_anchors_preset troca as ancoras e NAO mexe nos offsets: o no fica com o
# tamanho antigo, deslocado dentro do pai. Ja deixou a cozinha fora de centro e
# prendeu overlays num canto da tela.
ANCORA = re.compile(r"(?<!_and_offsets)\bset_anchors_preset\(")

# Um ColorRect girado 45 graus sai da grade de pixels: a rasterizacao passa a
# depender da posicao fracionaria do no, e dois losangos do MESMO tamanho, lado
# a lado, saem com alturas diferentes. Use Gem.make(), que desenha o losango
# como pilha de retangulos de 1 px em coordenada inteira.
GIRADO = re.compile(r"\.rotation\s*=\s*PI")

# Cartao clicavel tem de ser CardButton. Um Button com filhos ancorados ignora
# o content_margin do StyleBox 9-patch e o conteudo vaza a moldura — quebrou a
# cozinha, o seletor de Prismon e os cartoes de recruta, um por vez.
BOTAO_ANCORADO = re.compile(r"\bButton\.new\(\)")

# `FontFile.load_dynamic_font(caminho)` le o .ttf CRU do disco. Funciona no
# editor e falha EM SILENCIO no jogo exportado: o Godot empacota os recursos
# importados (.fontdata), nao os arquivos-fonte, entao no build o caminho nao
# existe, a fonte nao carrega e tudo cai no tipo padrao da engine sem erro
# nenhum. Foi assim que a fonte "sumiu" na exportacao (autor, 03/09).
# Em src/ isso e proibido; em tools/ e permitido, porque ferramenta nunca
# e exportada e o probe de fonte precisa medir o arquivo cru.
FONTE_CRUA = re.compile(r"\bload_dynamic_font\s*\(")

# As texturas assets/ui/bar_*.png tem 18 px de altura. 10, 14 e 20 esticam o
# desenho em 0.55x, 0.77x e 1.11x: o grao da barra vira borrao e cada tela fica
# com uma espessura diferente. Estava assim em quatro lugares ao mesmo tempo.
BARRA = re.compile(r"(?:PrismaBar\.make|UI\.bar)\(" + _ARGS + r",\s*(\d+)\s*[,)]")
BAR_LIMPOS = {"18", "36", "54"}

# --- REGRAS DA REVISAO DE 15/09 -------------------------------------------

# RAIZ 3 DO RELATORIO, virada regra. `StyleBoxTexture.modulate_color` multiplica
# a textura 9-patch INTEIRA — borda e miolo. Com o tint de um elemento em cima,
# o miolo #191627 vira #130a10 e o painel fica a 1,1 de luma do vazio atras
# dele: o jogo inteiro passa a ser uma bisel de 6 px flutuando num campo
# chapado, e onze telas parecem a mesma tela. Nao da erro nenhum no Godot.
# O unico lugar onde a chamada e legitima e ui.gd, que compoe borda e miolo em
# duas camadas e fixa modulate_color = Color.WHITE.
MODULA = re.compile(r"\.modulate_color\s*=")

# `clip_text = true` trava a largura MINIMA do Label em 1 px (medido em
# tools/fit_probe.tscn). Dentro de um HBox sem ninguem esticando, o Label
# encolhe ate sumir: e literalmente o achado "os nomes do elenco nao existem".
# O par obrigatorio e um SIZE_EXPAND_FILL por perto — no proprio Label ou no
# container que o embrulha, que e a forma usada no resto do codigo.
CLIP = re.compile(r"\bclip_text\s*=\s*true")
EXPANDE = re.compile(r"size_flags_horizontal\s*=\s*(?:Control\.)?SIZE_EXPAND_FILL")
# 5 linhas antes: e a distancia real entre `v.size_flags_horizontal` e o
# `nm.clip_text` do PickPanel, que e o padrao correto do repositorio.
CLIP_ANTES = 5
CLIP_DEPOIS = 3

# A grade tipografica e 18 / 26 / 36 / 54. 27 px e PROIBIDO: a m6x11plus tem 18
# px por em, e 27 = 1.5x a grade dobra fileiras alternadas num batimento
# regular — o olho le "fonte quebrada". A const SNAP ja e conferida abaixo;
# esta regra pega o NUMERO CRU nas chamadas, que e por onde 27 voltaria.
FONTE_27 = re.compile(
    r"(?:UI\.fs\(\s*|UI\.icon_px\(\s*|font_size\"\s*,\s*|font_size\s*=\s*"
    r"|UI\.label\(" + _ARGS + r",\s*|UI\.wrap\(" + _ARGS + r",\s*"
    r"|UI\.button\(" + _ARGS + r",\s*|UI\.button_confirmar\(" + _ARGS + r",\s*"
    r"|UI\.button_secundario\(" + _ARGS + r",\s*)(27(?:\.0)?)\b")

# ALTURA DE BOTAO. UI.button ja escreve BTN_H = 58 em custom_minimum_size.y —
# 58 e a altura em que a lajota nova cabe com os 20/13 de respiro e ainda sobra
# a folga de 3 px por onde ela sobe no hover. Uma tela que escreve 42 por cima
# nao "aperta o botao": ela corta a sombra dura e o rotulo desencosta do centro
# da lajota (ver UI.CELL_CENTRO). O alvo de toque tambem cai abaixo do minimo.
BTN_H_MIN = 58
NASCE_BOTAO = re.compile(
    r"(?:var\s+)?([A-Za-z_][A-Za-z0-9_]*)\s*(?::\s*\w+)?\s*:?=\s*"
    r"(?:UI\.button_confirmar|UI\.button_secundario|UI\.button|Button\.new)\b")
ALTURA_VEC = re.compile(
    r"\b([A-Za-z_][A-Za-z0-9_]*)\.custom_minimum_size\s*=\s*Vector2\("
    r"[^,)]*,\s*([0-9]+(?:\.[0-9]+)?)\s*\)")
ALTURA_Y = re.compile(
    r"\b([A-Za-z_][A-Za-z0-9_]*)\.custom_minimum_size\.y\s*=\s*([0-9]+(?:\.[0-9]+)?)")

# As listas paralelas da celula. Um indice a mais ou a menos em qualquer uma
# delas nao aparece em lugar nenhum ate alguem abrir A TELA que usa aquela
# celula — e ai e um erro de indice em tempo de execucao, longe da causa.
LISTAS_DA_CELULA = ["FRAMES", "MASCARAS", "CELL_MARGIN", "CELL_MIOLO_DEGRAU",
                    "CELL_CENTRO"]


# DIVIDA HERDADA (15/09).
#
# Cada entrada abaixo e um achado VERDADEIRO de uma das regras novas, num
# arquivo de outro dono. A regra fica ligada — o que a divida compra e so o
# direito de o lint continuar verde enquanto o pedido nao e atendido, para que
# `validate_data.py` siga sendo um sinal util em vez de um vermelho cronico que
# todo mundo aprende a ignorar.
#
# A lista so pode ENCOLHER. Quando um dono conserta, a entrada fica orfa e o
# lint imprime "divida quitada" pedindo para apaga-la. Isso e AVISO e nao erro
# de proposito: com varios agentes editando o mesmo repo ao mesmo tempo, um
# conserto de outra pessoa nao pode derrubar a suite de quem escreveu a regra.
DIVIDA = {
}


# Amostras que cada regra TEM de pegar, e amostras que ela NAO pode pegar.
# Sem isto uma regra quebrada passa verde para sempre: foi o que aconteceu com
# a primeira versao da regra de icone, que nao atravessava `String(...)`.
_AUTOTESTE = [
    (ICONE, 'row.add_child(Icons.item(String(o["id"]), 34.0))', "34.0"),
    (ICONE, "chip.add_child(Icons.element(e, 22.0))", "22.0"),
    (ICONE, "row.add_child(Icons.relic(id, 32.0))", "32.0"),
    (BARRA, "var bar := PrismaBar.make(_fill(u), 14)", "14"),
    (BARRA, 'UI.bar("red", 10)', "10"),
    (FONTE_27, 'col.add_child(UI.label("A RUN EM NUMEROS", 27))', "27"),
    (FONTE_27, 'l.add_theme_font_size_override("font_size", 27)', "27"),
    (FONTE_27, "var px := UI.fs(27)", "27"),
    (ALTURA_VEC, "b.custom_minimum_size = Vector2(0, 44)", ("b", "44")),
    (ALTURA_Y, "jogar.custom_minimum_size.y = 40", ("jogar", "40")),
    (NASCE_BOTAO, 'var fechar := UI.button_secundario("VOLTAR")', "fechar"),
    (NASCE_BOTAO, 'b = UI.button("  NOVA RUN  ", UI.F_H2)', "b"),
]
_AUTOTESTE_NEG = [
    (ICONE, "Icons.element(el, UI.icon_px(UI.F_SMALL))"),
    (BARRA, 'PrismaBar.make("green", BAR_H)'),
    (FONTE_27, 'UI.label("x", 26)'),
    (FONTE_27, "card.custom_minimum_size = Vector2(27, 8)"),
    (FONTE_27, "for i in range(27):"),
    (ALTURA_VEC, "row.custom_minimum_size = Vector2(BAR_W, altura_da_lista())"),
    (NASCE_BOTAO, "var v := UI.box(true, 6)"),
    (MODULA, "sb.modulate = Color.WHITE"),
]


def autoteste():
    """Falha ALTO se uma regra parou de casar o que devia."""
    for rx, amostra, esperado in _AUTOTESTE:
        achou = rx.findall(amostra)
        assert achou and achou[0] == esperado, (
            "lint_ui: a regra parou de casar %r (achou %r)" % (amostra, achou))
    for rx, amostra in _AUTOTESTE_NEG:
        assert not rx.findall(amostra), (
            "lint_ui: a regra casou o que nao devia: %r" % amostra)
    # a regra do clip_text e um par (achado + janela), entao o autoteste dela
    # exercita a JANELA, que e a parte que ja errou uma vez
    assert _clip_coberto(["v.size_flags_horizontal = Control.SIZE_EXPAND_FILL",
                          "var nm := UI.label(x)", "nm.clip_text = true"], 2)
    assert not _clip_coberto(["var rname := UI.label(u.display_name())",
                              "rname.clip_text = true",
                              "hrow.add_child(rname)"], 1)


def _clip_coberto(linhas, i):
    """Alguem estica a largura na vizinhanca da linha `i` (base 0)?"""
    ini = max(i - CLIP_ANTES, 0)
    return EXPANDE.search("\n".join(linhas[ini:i + CLIP_DEPOIS + 1])) is not None


def _linhas(path):
    """Linhas do arquivo, sem as que sao comentario inteiro."""
    txt = io.open(path, encoding="utf-8").read()
    for n, linha in enumerate(txt.splitlines(), 1):
        if linha.lstrip().startswith("#"):
            continue
        yield n, linha


def _icones_exigidos(load):
    """Todo nome de icone que os DADOS pedem, com quem o pede.

    Um nome que falta nao da erro em lugar nenhum: Icons.tex() devolve null e a
    linha sai sem o icone que as outras linhas tem. Foi assim que a Mao do
    Domador ficou com um buraco na linha do Orvalho, desalinhada das outras
    duas, e que a ficha da preparacao pediu "stomach" sem que nada reclamasse.
    """
    out = []
    for e in load("elements.json")["elements"]:
        out.append(("elem_%s" % e["id"], "elemento %s" % e["name"]))
    for a in load("actives.json")["actives"]:
        out.append(("act_%s" % a["id"], "ativo %s" % a["name"]))
    for i in load("items.json")["items"]:
        out.append(("item_%s" % i["id"], "item %s" % i["name"]))
    for d in load("dishes.json")["dishes"]:
        out.append(("dish_%s" % d["id"], "prato %s" % d["name"]))
    for r in load("relics.json")["relics"]:
        out.append(("relic_%s" % r["id"], "reliquia %s" % r["name"]))
    for r in sorted(load("species.json").get("roles", {}).keys()):
        out.append(("role_%s" % r, "papel %s" % r))
    return out


def _elementos_da_lista(texto, nome):
    """Quantos itens de primeiro nivel tem `const <nome> := [ ... ]`.

    Aceita `static var` tambem: desde que a cor virou dado (17/09), tabela
    da celula que dependa da paleta nao pode mais ser `const`.
    """
    m = re.search(r"(?:const|static\s+var)\s+%s\s*:?=\s*\[" % nome, texto)
    if not m:
        return -1
    i = m.end()
    prof = 1
    n = 1
    vazia = True
    while i < len(texto) and prof > 0:
        c = texto[i]
        if c in "[(":
            prof += 1
        elif c in ")]":
            prof -= 1
            if prof == 0:
                break
        elif c == "," and prof == 1:
            n += 1
        elif not c.isspace():
            vazia = False
        i += 1
    if vazia:
        return 0
    # virgula final ("[a, b,]") nao cria um item
    if texto[m.end():i].rstrip().endswith(","):
        n -= 1
    return n


def run(load, check):
    """Aplica as regras. `load` le um JSON de data/, `check(cond, msg)` acusa."""
    autoteste()
    pendentes = set()

    def acusa(rel, simbolo, msg):
        """Acusa — a nao ser que o achado ja esteja na divida herdada."""
        chave = (os.path.basename(rel), simbolo)
        if chave in DIVIDA:
            pendentes.add(chave)
            return
        check(False, msg)

    ic = load("icons.json")
    have = set(ic["icons"].keys()) | set(ic.get("files", {}).keys())

    # o sheet e 512x867 = 16 colunas x 27 linhas de 32 px
    for name, rc in ic["icons"].items():
        check(0 <= rc[0] < 27 and 0 <= rc[1] < 16,
              "icone %s aponta para fora do sheet (%s)" % (name, rc))

    exigidos = _icones_exigidos(load)
    for nome, quem in exigidos:
        check(nome in have,
              "sem icone para %s (o codigo vai pedir '%s' e receber nada)"
              % (quem, nome))
    print("icones: %d no mapa, %d exigidos pelos dados" % (len(have), len(exigidos)))

    arquivos = sorted(glob.glob(os.path.join(ROOT, "src", "ui", "*.gd")))
    for f in arquivos:
        rel = os.path.relpath(f, ROOT).replace(os.sep, "/")
        # gem.gd É o desenho do losango; card_button.gd É o cartao clicavel
        eh_gem = rel.endswith("/gem.gd")
        eh_card = rel.endswith("/card_button.gd")
        eh_kit = rel.endswith("/ui.gd")
        texto = io.open(f, encoding="utf-8").read()
        # BARRA NAO E PAINEL. A regra do modulate existe porque tingir um
        # 9-patch inteiro apaga o MIOLO junto com a borda — o painel vira
        # contorno, que e a Raiz 3 do relatorio. Uma barra e um 3-slice: as
        # margens de cima e de baixo sao zero, ela nao tem miolo separado da
        # borda, e o preenchimento PRECISA ser tingido em tempo de execucao (a
        # vida vai de verde a vermelho durante o combate, e a de ultimate usa a
        # cor do elemento). Assar uma textura por cor seria uma textura por
        # cor. O teste e estrutural, nao por nome de arquivo: quem declara
        # margem 0 em cima E embaixo esta montando 3-slice.
        eh_barra = ("texture_margin_top = 0" in texto
                    and "texture_margin_bottom = 0" in texto)
        todas = texto.splitlines()
        botoes = set(NASCE_BOTAO.findall(texto))
        for n, linha in _linhas(f):
            for m in ICONE.finditer(linha):
                check(m.group(1) in ICON_LIMPOS,
                      "%s:%d icone em %s px, fora de {16,32,48} — use UI.icon_px()"
                      % (rel, n, m.group(1)))
            check(not ANCORA.search(linha),
                  "%s:%d set_anchors_preset nao ajusta offsets — use "
                  "set_anchors_and_offsets_preset" % (rel, n))
            check(not FONTE_CRUA.search(linha),
                  "%s:%d load_dynamic_font le o .ttf cru e NAO sobrevive a "
                  "exportacao — use preload() do recurso importado" % (rel, n))
            for m in BARRA.finditer(linha):
                check(m.group(1) in BAR_LIMPOS,
                      "%s:%d barra de %s px: as texturas bar_*.png tem 18 px "
                      "de altura, use 18/36/54" % (rel, n, m.group(1)))
            if not eh_gem:
                check(not GIRADO.search(linha),
                      "%s:%d losango/no girado sai da grade de pixels — use Gem.make()"
                      % (rel, n))
            for m in FONTE_27.finditer(linha):
                check(False,
                      "%s:%d corpo de fonte 27 = 1.5x a grade da m6x11plus "
                      "(dobra fileiras alternadas) — use 18, 26, 36 ou 54"
                      % (rel, n))
            if not eh_kit and not eh_barra and MODULA.search(linha):
                acusa(rel, "<arquivo>",
                      "%s:%d modulate_color multiplica a textura 9-patch INTEIRA "
                      "(borda E miolo): e a Raiz 3 do relatorio, e o Godot nao "
                      "reclama. Quem compoe as duas camadas e UI.frame()" % (rel, n))
            if CLIP.search(linha) and not _clip_coberto(todas, n - 1):
                alvo = linha.strip().split(".")[0].strip()
                acusa(rel, alvo,
                      "%s:%d clip_text trava a largura MINIMA em 1 px e ninguem "
                      "estica por perto — o rotulo some dentro do HBox. Falta um "
                      "size_flags_horizontal = Control.SIZE_EXPAND_FILL" % (rel, n))
            for rx in (ALTURA_VEC, ALTURA_Y):
                for m in rx.finditer(linha):
                    alvo, alt = m.group(1), float(m.group(2))
                    if alvo in botoes and 0.0 < alt < BTN_H_MIN:
                        acusa(rel, alvo,
                              "%s:%d botao com %g px de altura: UI.button ja "
                              "escreve %d (UI.BTN_H), e abaixo disso a sombra "
                              "dura e cortada e o rotulo desencosta do centro "
                              "da lajota" % (rel, n, alt, BTN_H_MIN))

    # A escala tipografica nao pode ter degrau a 1.5x da grade da fonte. A
    # m6x11plus tem 18 px por em; um corpo N com N % 18 == 9 (27, 45) dobra
    # fileiras alternadas num batimento regular, e o olho le "fonte quebrada".
    # Medido em tools/fit_probe.tscn — 26 px tem o mesmo tamanho aparente que
    # 27 e traco limpo, por isso a escala e 18 / 26 / 36 / 54.
    ui = io.open(os.path.join(ROOT, "src", "ui", "ui.gd"), encoding="utf-8").read()
    snap = re.search(r"const SNAP := \{(.*?)\}", ui, re.S)
    check(snap is not None, "ui.gd: const SNAP nao encontrado")
    if snap:
        for corpo in re.findall(r":\s*(\d+)", snap.group(1)):
            check(int(corpo) % 18 != 9,
                  "ui.gd: SNAP mapeia para %s px = 1.5x a grade da m6x11plus "
                  "(traco irregular) — use 18, 26, 36 ou 54" % corpo)

    # A COR NAO PODE VOLTAR PARA DENTRO DO .gd (17/09).
    #
    # Ate esta leva as quinze cores do kit eram `const Color("#...")` em
    # ui.gd, e os quatro degraus neutros estavam REPETIDOS em
    # tools/build_ui_sheet.py. Agora vem todas de data/paleta.json. Sem esta
    # cerca a regressao e de uma linha: alguem precisa de "so mais um tom",
    # escreve um hex aqui, e a paleta deixa de mandar naquele pedaco da tela
    # sem nenhum erro aparecer.
    #
    # A reserva embutida (Db.PALETA_EMBUTIDA) e a UNICA excecao, porque ela
    # existe justamente para o caso de o JSON nao poder ser lido.
    for rel in ("src/ui/ui.gd", "src/ui/prisma_theme.gd"):
        texto = io.open(os.path.join(ROOT, *rel.split("/")), encoding="utf-8").read()
        for achado in set(re.findall(r'Color\("(#[0-9a-fA-F]{3,8})"\)', texto)):
            check(False,
                  "%s: a cor %s esta escrita no codigo. Cor de interface mora "
                  "em data/paleta.json desde 17/09 — se e cor nova, ela entra "
                  "em TODAS as paletas de la" % (rel, achado))

    # AS LISTAS PARALELAS DA CELULA tem de andar juntas. Hoje sao cinco tabelas
    # indexadas pelo MESMO enum; uma entrada a mais em qualquer uma delas so
    # aparece como erro de indice em tempo de execucao, na tela que usar aquela
    # celula — que pode ser uma que ninguem abre ha semanas.
    tamanhos = dict((nome, _elementos_da_lista(ui, nome)) for nome in LISTAS_DA_CELULA)
    enum_m = re.search(r"enum \{([^}]*)\}", ui, re.S)
    n_enum = len([x for x in enum_m.group(1).split(",") if x.strip()]) if enum_m else -1
    base = tamanhos["FRAMES"]
    check(base > 0, "ui.gd: nao consegui contar UI.FRAMES")
    for nome, n in tamanhos.items():
        check(n == base,
              "ui.gd: UI.%s tem %d entradas e UI.FRAMES tem %d — as tabelas da "
              "celula sao indexadas pelo mesmo enum" % (nome, n, base))
    check(n_enum == base,
          "ui.gd: o enum das celulas tem %d nomes e as tabelas tem %d" % (n_enum, base))
    print("celulas: %d (FRAMES/MASCARAS/CELL_MARGIN/CELL_MIOLO_DEGRAU/"
          "CELL_CENTRO/enum)" % base)

    # A divida so pode encolher: uma entrada orfa e um pedido ja atendido.
    for chave in sorted(set(DIVIDA) - pendentes):
        print("  divida quitada: apague %s de DIVIDA em tools/lint_ui.py" % (chave,))
    if pendentes:
        print("divida herdada: %d pendencia(s) em arquivo de outro dono" % len(pendentes))
        for chave in sorted(pendentes):
            print("   %-34s %s" % ("%s (%s)" % chave, DIVIDA[chave]))
    print("lint da ui: %d arquivos" % len(arquivos))


if __name__ == "__main__":
    import sys

    estado = {"ok": True}

    def _load(name):
        with open(os.path.join(ROOT, "data", name), encoding="utf-8") as f:
            return json.load(f)

    def _check(cond, msg):
        if not cond:
            estado["ok"] = False
            print("  FAIL:", msg)

    run(_load, _check)
    print("=> %s" % ("OK" if estado["ok"] else "ERROS"))
    sys.exit(0 if estado["ok"] else 1)
