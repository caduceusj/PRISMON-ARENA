# Ajustar as arenas

Cada arena é uma **cena do Godot**: `assets/arenas/<arena>.tscn`, com um
`Sprite2D` por elemento. Abre no editor, arrasta, salva. Não precisa rodar nada.

```
Cenario (Node2D)
├── 01 ceu
├── 04 montanha funda
├── 06 montanha perto
├── 08 pedras
├── 10 poste 1 … 10 poste 6      ← cada um é um nó
└── 11 arco 1 … 11 arco 5
```

Dá para mover, esconder (o olhinho), reordenar na árvore para mudar a
profundidade, e até duplicar um elemento (Ctrl+D) para ter mais um poste.

## Onde as coisas cabem

A cena tem **1280×260** e é desenhada **1:1**. O jogo ancora o **y=236** dela
8 px acima da borda de cima da elipse — ou seja, a última linha visível do
desenho encosta na arena e **nada entra nela**.

| Linha | y | O que acontece ali |
|---|---|---|
| Topo | 0 | invisível: o céu nasce surgindo |
| Céu cheio | 96 | daqui para baixo aparece inteiro |
| Horizonte | 170 | onde a paisagem encontra o chão do desenho |
| **Rodapé** | **236** | encosta na arena; daqui para baixo some |

O desenho inteiro fica **acima** do piso. Antes o horizonte é que era ancorado
na borda, e o avental caía dentro da elipse — como o piso é translúcido, a
montanha aparecia por baixo dele no meio da arena.

## A curva

O cenário é entortado por um shader (`assets/shaders/cenario_fade.gdshader`):
ele desce nas laterais seguindo o arco da elipse, e a paisagem passa a abraçar
a arena em vez de cruzar por cima dela numa reta.

A curva é **mais rasa que a borda** de propósito — desce 45% do que a elipse
desce. Assim a folga cresce para as pontas e a paisagem nunca toca o piso.

Três números em `src/ui/field_view.gd` controlam a distância entre a paisagem e
a arena, e é por eles que se mexe se ainda encostar:

| Constante | Hoje | O que faz |
|---|---|---|
| `DESCE` | 68 | quanto o campo inteiro desce na tela — abre espaço em cima |
| `CENARIO_FOLGA` | 26 | vão entre o rodapé do desenho e a borda do piso |
| `curvatura` | 45% da meia-altura | o quanto o cenário acompanha o arco |

`DESCE` é a que mais rende: ela desce a arena sem tocar em nada da simulação.
Encolher a elipse **não** é opção — `arena_half_width` e `arena_half_height` são
parâmetros de movimento, e mexer neles muda o espaçamento do combate.

O desvanecimento é calculado pela **posição no mundo antes da curva** — então
arrastar uma peça muda o que ela cobre, não o quanto ela desbota, e o recorte
viaja junto com o arco.

## Se quiser redesenhar a arte (não só mover)

Aí sim o Aseprite entra. `assets/arenas/<arena>.aseprite` tem as mesmas camadas.

```bash
# depois de salvar no Aseprite, regera a cena do Godot:
python tools/exportar_arenas.py nevasca
```

> **Atenção:** isso **reescreve o `.tscn`** e perde as posições que você ajustou
> no editor do Godot. Ajuste fino de posição é para fazer no Godot; o Aseprite
> é para mudar o desenho.

## De onde vem a paisagem

Pacote CC0 de parallax (MatiasVME, OpenGameArt), em `fonte_cc0/`. Ele não entra
como veio: `tools/retonar_arenas.py` mede a luminância de cada pixel e remapeia
para a cor da arena — o desenho do artista fica, a paleta muda. Só precisa rodar
de novo se você mudar o `tint` da arena em `data/enemies.json`.

Para recriar uma cena do Aseprite do zero:

```bash
python tools/desenhar_arenas.py --refazer nevasca
```
