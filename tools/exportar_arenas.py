# -*- coding: utf-8 -*-
"""Transforma as cenas do Aseprite em CENAS DO GODOT, editaveis no editor.

O PEDIDO (autor, 10/09): "eu queria editar dentro do Godot mesmo, mexer algumas
posicoes, ao inves de deixar tudo solto". Antes o cenario era um PNG achatado —
para mover uma lapide era preciso abrir o Aseprite, arrastar, exportar e rodar
um script. Agora cada elemento e um `Sprite2D` numa cena `.tscn`: abre no editor
do Godot, arrasta, salva, e acabou.

COMO FUNCIONA:

  1. O Aseprite exporta CADA CAMADA como um PNG (export_layers).

  2. Cada PNG e RECORTADO na caixa do que ele desenha, e a posicao do recorte
     vira a posicao do Sprite2D. Sem isso cada peca seria uma imagem de
     1280x260 quase toda vazia, e "mover a lapide" seria mover uma folha
     gigante — a posicao dela estaria assada no pixel, nao no no.

  3. Sai um `<arena>.tscn` com um Sprite2D por elemento, na ordem de
     profundidade, com os nomes que a cena do Aseprite usava.

O DISSOLVE DAS BORDAS DEIXOU DE SER ASSADO NO PNG. Com as pecas soltas, uma
mascara assada andaria junto com a peca — a lapide levaria o proprio desbotado
para onde fosse arrastada. Ele virou um shader que calcula o corte pela POSICAO
NO MUNDO, num material compartilhado por todos os sprites da cena (ver
cenario_fade.gdshader).

Rodar:  python tools/exportar_arenas.py [id ...]
"""
import io
import json
import os
import shutil
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import ase  # noqa: E402

from PIL import Image

RAIZ = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ARENAS = os.path.join(RAIZ, "assets", "arenas")
PECAS = os.path.join(ARENAS, "pecas")

L, A = 1280, 260
HORIZONTE = 170
TOPO_FIM = 96
RODAPE_FIM = 236
LATERAL = 210.0


def exportar_camadas(aid, ase_f, tmp):
    if os.path.isdir(tmp):
        shutil.rmtree(tmp)
    os.makedirs(tmp)
    r = ase.executar([
        {"tool": "export_layers",
         "args": {"filename": ase_f, "output_directory": tmp.replace("\\", "/"),
                  "include_hidden": False}},
        {"tool": "get_sprite_info", "args": {"filename": ase_f}},
    ], silencioso=True)
    if r[0].startswith("ERRO") or r[0] == "SEM RESPOSTA":
        print("  %-22s FALHOU ao exportar camadas: %s" % (aid, r[0][:110]))
        return None
    try:
        info = json.loads(r[1])
    except Exception:
        return None
    # so as VISIVEIS, e na ordem de baixo para cima (a ordem de desenho)
    return [c["name"] for c in info["layers"] if c.get("visible", True)]


def recortar(origem, destino):
    """Recorta na caixa do desenho. Devolve (x, y, largura, altura) ou None."""
    im = Image.open(origem).convert("RGBA")
    caixa = im.getbbox()
    if caixa is None:
        return None
    corte = im.crop(caixa)
    corte.save(destino)
    return caixa[0], caixa[1], corte.width, corte.height


def escapar(s):
    return s.replace('"', '\\"')


def montar_tscn(aid, pecas):
    """Monta o .tscn na mao: e um formato de texto simples, e gerar assim evita
    depender do editor aberto."""
    res = []
    nos = []
    for i, (nome, arq, x, y, w, h) in enumerate(pecas):
        idr = "t%d" % (i + 1)
        # sem `uid`: o Godot atribui o dele na primeira importacao, e um uid
        # vazio escrito a mao so gera aviso
        res.append('[ext_resource type="Texture2D" path="res://assets/arenas/pecas/%s/%s" id="%s"]'
                   % (aid, arq, idr))
        # o Sprite2D e centrado: a posicao e o CENTRO do recorte
        # O MATERIAL E O MESMO OBJETO em todos os sprites: uma SubResource
        # compartilhada. Assim o FieldView atualiza `origem` uma vez por quadro
        # e o cenario inteiro acompanha, em vez de um material por no.
        nos.append(
            '[node name="%s" type="Sprite2D" parent="."]\n'
            'texture_filter = 1\n'
            'material = SubResource("mat")\n'
            'position = Vector2(%d, %d)\n'
            'texture = ExtResource("%s")\n'
            % (escapar(nome), x + w // 2, y + h // 2, idr))

    cab = ('[gd_scene load_steps=%d format=3]\n\n' % (len(res) + 3))
    mat = ('[ext_resource type="Shader" path="res://assets/shaders/cenario_fade.gdshader" id="sh"]\n')
    sub = ('\n[sub_resource type="ShaderMaterial" id="mat"]\n'
           'shader = ExtResource("sh")\n'
           'shader_parameter/origem = Vector2(0, 0)\n'
           'shader_parameter/tamanho = Vector2(%d, %d)\n'
           'shader_parameter/topo_fim = %.4f\n'
           'shader_parameter/horizonte = %.4f\n'
           'shader_parameter/rodape_fim = %.4f\n'
           'shader_parameter/lateral = %.4f\n'
           % (L, A, TOPO_FIM / float(A), HORIZONTE / float(A),
              RODAPE_FIM / float(A), LATERAL / float(L)))
    # RAIZ SIMPLES. A primeira versao usava um CanvasGroup para achatar os
    # filhos e cortar o conjunto — mas o buffer dele nao chegava ao shader
    # (nem por COLOR, nem por texture(TEXTURE, UV)) e o cenario saia branco.
    # O corte passou para o material de cada sprite, calculado pela posicao no
    # mundo, e a raiz voltou a ser um Node2D comum.
    raiz = ('\n[node name="Cenario" type="Node2D"]\n\n')
    return cab + mat + "\n".join(res) + "\n" + sub + raiz + "\n".join(nos)


def main():
    pedidos = sys.argv[1:]
    dados = json.load(io.open(os.path.join(RAIZ, "data", "enemies.json"),
                              encoding="utf-8"))
    tmp_raiz = os.path.join(RAIZ, "docs", "_camadas_tmp")
    for a in dados.get("arenas", []):
        aid = a.get("id")
        if pedidos and aid not in pedidos:
            continue
        ase_f = os.path.join(ARENAS, "%s.aseprite" % aid).replace("\\", "/")
        if not os.path.exists(ase_f):
            print("  %-22s sem cena (.aseprite)" % aid)
            continue

        tmp = os.path.join(tmp_raiz, aid)
        ordem = exportar_camadas(aid, ase_f, tmp)
        if not ordem:
            continue

        destino = os.path.join(PECAS, aid)
        if os.path.isdir(destino):
            shutil.rmtree(destino)
        os.makedirs(destino)

        pecas = []
        for nome in ordem:
            origem = os.path.join(tmp, "%s.png" % nome)
            if not os.path.exists(origem):
                continue
            arq = "%s.png" % nome.replace(" ", "_")
            r = recortar(origem, os.path.join(destino, arq))
            if r is None:      # camada vazia nao vira no
                continue
            x, y, w, h = r
            pecas.append((nome, arq, x, y, w, h))

        if not pecas:
            print("  %-22s nenhuma camada com desenho" % aid)
            continue
        alvo = os.path.join(ARENAS, "%s.tscn" % aid)
        io.open(alvo, "w", encoding="utf-8", newline="\n").write(
            montar_tscn(aid, pecas))
        print("  %-22s %2d nos -> %s" % (aid, len(pecas), os.path.basename(alvo)))
    if os.path.isdir(tmp_raiz):
        shutil.rmtree(tmp_raiz)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
