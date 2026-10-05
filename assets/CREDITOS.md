# Assets de terceiros

## `creatures/` — os 5 monstrinhos de teste

Sprites enviados pelo autor do projeto (`mons-anims.zip`): apollo, grass-coala,
hipocampo, pinto-raio, sheep — attack/idle/walk em células de 160×160.
`tools/build_anim_rig.py` mede os sheets e gera `data/anims.json` (recorte, linha do
chão e o **quadro de dano** de cada um). Origem/licença a confirmar com o autor antes
de publicar.

## `fonts/`

| Fonte | Licença | Uso |
|---|---|---|
| **m6x11plus** | **"Free to use with attribution"** — Daniel Linssen (managore). Lido dos metadados da própria fonte (name ID 13). **Cobre uso comercial**; exige crédito. | **Fonte principal da UI** desde 02/09. |
| ~~Pixel Sans Serif~~ | ⛔ **"FontStruct Non-Commercial License"** — confirmado nos metadados da fonte, não só na página do dafont. Foi por isso que saiu. | aposentada em 02/09 |
| **Pixelify Sans** | OFL (Google Fonts; licença em `OFL_PixelifySans.txt`) | Declarada como `fallbacks` da fonte principal. |
| **Pixeled** | ver site do autor (OmegaPC777) | Só dígitos: números de dano. |

> **Atribuição obrigatória:** a m6x11plus exige crédito a **Daniel Linssen**. Incluir
> nos créditos do jogo publicado.

> **Nota sobre os símbolos** (★ ⚡ ❄ ◆ ◇ → ✔ ○): **nenhuma** das fontes do projeto
> os contém — nem a Pixelify, que eu supunha ser a fonte deles. Eles vinham de um
> fallback do SISTEMA operacional, e podiam mudar de aparência entre máquinas.
>
> **Resolvido em parte (15/09).** `Icons.GLIFOS` mapeia seis deles para silhuetas
> CC0 da Kenney — ⚡→`g_crown`, ◆→`g_sword`, ◇→`g_campfire`, →→`g_arrow`,
> ▲→`g_skull`, ❄→`g_hourglass` — e `TooltipLayer.formatar` faz a troca em **toda
> dica do jogo**, sem que nenhuma tela mude uma linha. Como são da Kenney, isso
> não acrescenta dependência de licença. `✔`/`○` foram trocados por palavras
> ('ativa' / 'faltam 2'), e ★/☆ viraram `Gem` — o losango desenhado pixel a pixel,
> que é a forma da casa. **O que sobra** são os glifos escritos direto em `Label`
> e em `draw_string` fora de dica (`UI.stars`, `screen_map`, `screen_prep`,
> `field_view`): esses ainda dependem do fallback do sistema.


| Pacote | Licença | Onde é usado |
|---|---|---|
| [Kenney · UI Pack: Pixel Adventure](https://kenney.nl/assets/ui-pack-pixel-adventure) | **CC0** | Painéis, cartões, botões, faixa de título, medalhões. |
| [Kenney · UI Pack: RPG Expansion](https://kenney.nl/assets/ui-pack-rpg-expansion) | **CC0** | Barras de HP, Energia e tempo (3 fatias). |
| [Kenney · Board Game Icons](https://kenney.nl/assets/board-game-icons) | **CC0** | Glifos de sistema em silhueta branca, usados onde a cor precisa vir do elemento. |
| [Kenney · Monster Builder Pack](https://kenney.nl/assets/monster-builder-pack) | **CC0** | As criaturas, montadas peça a peça. **Placeholder.** |
| [MatiasVME · Parallax Background Forest Pixel Art](https://opengameart.org/content/parallax-background-forest-pixel-art) | **CC0** | Base das ilustrações de arena. **Não entra como veio:** `tools/retonar_arenas.py` remapeia a luminância de cada pixel para a rampa de cor da arena, e `tools/desenhar_arenas.py` acrescenta os adereços no Aseprite. Fonte em `assets/arenas/fonte_cc0/`, fora da build. |
| **Shikashi's Fantasy Icons Pack v2** | **atenção — ver abaixo** | Ícones de conteúdo: itens, pratos, relíquias, ativos, elementos, tipos de nó. |

## ⚠ Atenção à licença do pacote do Shikashi

Os quatro pacotes da Kenney são **CC0**: uso livre, sem exigência de atribuição.

O pacote do Shikashi **não é CC0**. O texto que acompanha o pacote diz:

> *"You can use and remix these icons for commercial games and projects. Many of these
> icons were based on the designs over at game-icons.net which are CC BY 3.0."*

Ou seja: uso comercial é permitido, mas parte do material deriva de
[game-icons.net](https://game-icons.net), que é **CC BY 3.0 — exige atribuição**.

**Se este protótipo virar um produto, os créditos precisam citar Shikashi e
game-icons.net.** É a única dependência do projeto com essa exigência. Se isso for
indesejável, o caminho é trocar `data/icons.json` por um mapa apontando para ícones
próprios — o código não muda, só o mapa.

---

## `ui/` — molduras

> **MUDANÇA DE 15/09 — a Kenney saiu daqui.** Até esta data as molduras, a faixa
> de título e as barras eram *compostas* a partir de `kenney_ui_tilemap.png`.
> Hoje `tools/build_ui_sheet.py` **desenha** as dez células em PIL, pixel a pixel,
> na paleta do PRISMON. Do pacote de UI da Kenney sobrou **só o medalhão**
> (`ring.png` / `ring_gold.png`), que é arte de personagem e não de recipiente —
> o tilesheet continua no repositório por causa dele. O histórico abaixo fica
> porque as três armadilhas de 9-patch que ele registra continuam valendo para
> qualquer peça nova, venha ela da Kenney ou do script.

Cada célula sai em **dois** arquivos: `frame_*.png` (matéria neutra, miolo
transparente) e `frame_*_m.png` (máscara RGB — R = miolo, G = feixe, B = mistura
da aresta). É essa separação que permite tingir a **borda** sem tocar no miolo,
que era a Raiz 3 da revisão: um `modulate_color` no 9-patch inteiro apagava o
corpo do painel. `UI.frame()` compõe as duas camadas numa `ImageTexture` com
cache por par (célula, acento, miolo).

O script nasceu por dois motivos concretos, que continuam de pé:

1. **Os tiles de moldura da Kenney têm o centro transparente** e um `StyleBoxTexture`
   do Godot não tem cor de fundo própria. O script compõe cada moldura sobre a cor de
   painel do PRISMA e entrega uma textura já pronta para 9-patch — sem empilhar nós.
2. **A moldura é clareada**, preservando o sombreado relativo, para que o
   `modulate_color` consiga tingi-la com a cor do elemento. O fundo, sendo escuro, quase
   não se altera. É assim que um cartão de Fogo ganha borda vermelha e um de Água borda
   azul, com **uma** textura em vez de uma por elemento.

Além das dez células, o script entrega:

| Peça | Tiles | Para que serve |
|---|---|---|
| `banner.png` + `banner_m.png` | *desenhado* | Faixa de título, 96×64 com pontas de 24 px. **Substitui um cartão de cabeçalho inteiro.** |
| `bar_track.png` + `bar_{green,red,blue,yellow}.png` | *desenhado* | Barras de HP, Energia e tempo, nas cores do PRISMON. |
| `ring.png` / `ring_gold.png` | 48/49/61/62 e 46/47/59/60 | Medalhão em volta do retrato da criatura. **Substitui pastilha de elemento + nome em destaque.** |

> **Armadilha que custou uma rodada inteira:** no tilesheet, `43–45` e `56–58` são
> **duas faixas completas** de 96×32 (uma com pinos no topo, outra com rabos embaixo) —
> não a metade de cima e a de baixo de uma faixa só. O mesmo vale para `69–71` e
> `82–84`, que são duas barras completas. Empilhar as duas linhas produzia uma peça
> dobrada, que foi exatamente o defeito da primeira versão. Cada peça montada usa
> **uma** linha.

Cada uma existe para **tirar texto da tela** — foi o eixo da simplificação da
interface, não só decoração.

O script também mede e imprime a **margem de 9-patch** de cada moldura. Ela precisa
englobar a decoração de canto, não só a borda lisa: com margem menor, a decoração cai na
faixa esticável e vira um risco horizontal atravessando o painel. Os valores medidos
alimentam `CELL_MARGIN` em `src/ui/ui.gd`.

Três detalhes de aplicação que só aparecem quando a peça é esticada, e por isso
`tools/ui_probe.tscn` desenha **cada moldura em quatro tamanhos** (linha baixa, cartão,
botão, quadrado pequeno) antes de qualquer coisa ir para a tela:

1. **`AXIS_STRETCH_MODE_TILE`, não `STRETCH`.** As bordas com textura (a dourada, a do
   slot) têm grão irregular. Esticado, o grão vira um borrão com emendas visíveis;
   repetido, ele se mantém.
2. **A faixa não estica na vertical.** A altura é fixa — esticar destrói a
   silhueta. ✅ **Resolvido em 15/09:** as pontas eram de **64 px** numa peça de
   192×64, então numa faixa estreita as duas pontas ocupavam quase tudo e a peça
   lia como dois laços colados. A peça foi refeita em 96×64 com pontas de **24
   px**, e a ponta deixou de ter desenho próprio: é o mesmo canto cortado de
   qualquer recipiente do kit. Verificado em 520, 300 e 190 px no `ui_probe` — lê
   como UMA placa nas três.
3. **A barra não é um `ProgressBar`.** O `ProgressBar` do Godot desenha o preenchimento a
   partir de (0,0) sobre todo o retângulo, ignorando as margens do fundo: com uma
   moldura 9-patch, a barra cheia cobria a própria moldura. `src/ui/prisma_bar.gd`
   desenha trilho, preenchimento por dentro, na ordem certa.

Um arquivo por moldura, e não um atlas: `StyleBoxTexture.region_rect` apontando para uma
célula de atlas renderiza errado aqui — o 9-patch mede as margens contra a textura
inteira, não contra a região.

## O Theme

`src/ui/prisma_theme.gd` monta um `Theme` aplicado na raiz da árvore.

Isso não é preferência de estilo — é o que faltava. `add_theme_stylebox_override` só
alcança os nós criados à mão. Tudo que **a engine instancia sozinha** continuava com o
cinza padrão do Godot: o painel de **tooltip**, as **barras de rolagem** do
ScrollContainer, o `LineEdit`, o `ProgressBar`, os separadores e qualquer `Button` criado
sem passar por `UI.button()`. Era isso que fazia a interface parecer meio aplicada.

O Theme cobre `Button`, `Label`, `PanelContainer`, `Panel`, `PopupPanel`, `LineEdit`,
`ProgressBar`, `ScrollContainer`, `VScrollBar`/`HScrollBar`, `HSeparator`/`VSeparator`,
**`TooltipPanel`** e **`TooltipLabel`**.

Pastilhas de elemento continuam sendo `StyleBoxFlat`: um
9-patch de 32 px não cabe num badge de 18 px, e uma moldura esticada num preenchimento
parcial lê como "caixa vazia", não como "cheio".

## `audio/` — som próprio, gerado, **placeholder declarado**

Nenhum pacote de terceiros: `tools/gerar_sons.py` **sintetiza** os 21 arquivos
usando só a biblioteca padrão do Python (`wave`, `array`, `math`, `random`).
Determinístico por semente fixa e re-executável — duas execuções seguidas dão
md5 idêntico nos 21 arquivos.

| Pasta | Conteúdo | Tamanho |
|---|---|---|
| `audio/efeitos/` | 14 efeitos: `golpe critico reacao morte ativo cura escudo controle clique hover moeda vitoria derrota recruta` | ~196 kB, de 0,03 s (hover) a 0,90 s (derrota) |
| `audio/ambiente/` | 7 laços, um por id de arena de `data/enemies.json` | 7 × 3,20 s ≈ 990 kB |

**Licença: nossa, sem exigências.** São placeholders para um sound designer
trocar — `assets/audio/LEIA-ME.md` explica como: basta substituir o `.wav`
mantendo o nome, porque `Som` resolve por nome e não por caminho escrito à mão.
Os laços de ambiente fecham por cruzamento de cauda sobre cabeça; são curtos por
orçamento (1,13 MB de 2,00 MB), não por desenho.

## `monsters/` — criaturas

178 peças (corpos, braços, pernas, olhos, bocas, narizes, chifres, antenas, orelhas) em
seis cores. `src/ui/monster_art.gd` monta uma criatura na hora de desenhar, seguindo o
GDD §21.4. **O encaixe é MEDIDO, não estimado**: `tools/build_monster_rig.py` lê cada
peça e gera `data/monster_rig.json` com a silhueta do corpo (meia-largura na altura da
cabeça, do ombro e do quadril) e a âncora de cada membro (o ombro é o centro de massa da
faixa superior do braço; o quadril, o da perna; a base, a do adorno).

Por que medir: os corpos vão de 165×165 a 132×250. Posicionar braço e perna por uma
fração do **retângulo** do corpo funciona no corpo quadrado e desmonta no alto e
estreito — foi o que deixou os primeiros bonecos quebrados.

Seguindo o GDD §21.4:

- **A forma vem da espécie** — um hash estável do `species_id` escolhe corpo, membros,
  olho, boca e adorno. A mesma espécie é sempre a mesma criatura, em qualquer run.
- **A cor vem da Afinidade ATUAL**, não da nativa. Um Núcleo Ígneo ou um Guisado
  Cromático mudam a criatura na tela imediatamente — que é exatamente a leitura que o
  pilar "elemento é estado, não tipo" precisa.
- **O tamanho é proporcional ao custo de Vínculo**: base 46 px, evoluída 64 px,
  chefe 112 px.

As seis cores do pacote cobrem seis dos nove elementos do GDD (Fogo, Gelo, Água, Raio,
Natureza, Trevas). Os três catalisadores reaproveitam cores até haver arte própria.

Três ferramentas de conferência, porque encaixe se confere olhando:

- `tools/bestiary.tscn` — as 24 espécies numa folha só.
- `tools/rig_probe.tscn` — os seis tipos de corpo com os pontos de encaixe medidos
  marcados por cima. Se um membro não estiver encostando, aparece aqui.
- `tools/arm_probe.tscn` — os braços isolados, sem o corpo por cima.

> **Armadilha que custou tempo:** `draw_texture_rect` com **largura negativa** não
> espelha de forma confiável — ele normaliza o retângulo. O braço esquerdo saía com a
> massa virada para DENTRO do corpo e os bonecos pareciam ter um braço só. O espelho
> agora é feito por `draw_set_transform` com escala −1 no eixo x a partir do ponto de
> encaixe, que é inequívoco e ainda dispensa a matemática de inverter a âncora.

## `icons/` — ícones

`src/ui/icons.gd` resolve um **nome semântico** (`dish_espeto_flamejante`,
`node_jazida`, `relic_ampulheta_quebrada`) para uma região do sheet do Shikashi
(32×32, 16 colunas). O mapa vive em `data/icons.json`, seguindo o mesmo princípio do
resto do conteúdo: **dados fora do código** (GDD §22.1).

O mapa foi montado a partir de um **índice visual** do sheet, não da ordem listada no
README do pacote — a ordem do README não bate com o layout. `tools/icon_probe.tscn`
desenha todos os ícones com o nome ao lado, que é como a conferência foi feita e como
qualquer ícone novo deve ser conferido.

Duas fontes, por motivos diferentes:

- **Shikashi** para conteúdo. Já vêm coloridos e **não são tingidos** — a cor faz parte
  do ícone.
- **Board Game Icons** (silhueta branca) para glifos de sistema, onde a cor precisa vir
  do elemento. São os `g_*` no mapa.

## Nota de direção de arte

Os dois pacotes têm linguagens visuais diferentes: a UI é pixel art, as criaturas são
vetoriais com contorno suave. Isso é um **placeholder consciente** — separa visualmente
o que é interface do que é criatura, o que ajuda num protótipo. Quando os spritesheets
próprios existirem, só `src/ui/monster_art.gd` muda.

Por isso o projeto usa filtro **nearest** por padrão (pixel art da UI) e
**linear** apenas onde as criaturas são desenhadas (`FieldView` e `MonsterPortrait`).
