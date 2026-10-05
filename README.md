# PRISMON — Vertical Slice

Protótipo jogável do GDD **PRISMON v0.1** (João Anísio Marinho da Nóbrega, ago/2026),
feito em **Godot 4.7** / GDScript.

> Você não comanda monstros. Você comanda o campo elemental em que eles lutam.

O escopo parte do **Vertical Slice do documento (§24.1)**, revisado em 30/08/2026
pelas decisões do autor (ver [NOTAS.md](NOTAS.md) §5): **escolha sempre entre 2
combates, eventos automáticos entre eles, e um elenco de teste de 5 criaturas
animadas**. A pergunta continua a mesma:

> *"O combate sem posicionamento, com Ativos, é interessante de assistir e de intervir?"*

---

## Como rodar

O projeto abre direto no editor do Godot 4.7 (`project.godot`). Pela linha de comando:

```bash
godot --path . 
```

Ferramentas (todas headless, sem render):

```bash
godot --headless --path . res://tools/smoke_test.tscn
```

```bash
godot --headless --path . res://tools/autoplay.tscn -- --runs=1000 --csv=user://balance.csv
```

```bash
godot --path . --resolution 1600x900 res://tools/screenshots.tscn -- --out=res://shots
```

| Ferramenta | O que faz |
|---|---|
| `tools/smoke_test.tscn` | **277 asserções** sobre dados, matriz de reações, regras de aura, combate, economia, determinismo, o Chefe I, o kit de interface, o som e o fluxo de telas |
| `tools/autoplay.tscn` | Roda runs completas com um bot e mede os alvos do §17.4. ~161 ms por run — **use `--runs=1000`**, ver abaixo |
| `tools/screenshots.tscn` | Captura um PNG de cada tela em `shots/` |
| `tools/bestiary.tscn` | Renderiza as 24 espécies montadas, em todas as Afinidades, numa folha só |
| `tools/rig_probe.tscn` | Os seis tipos de corpo com os pontos de encaixe medidos marcados — se um membro não encosta, aparece aqui |
| `tools/arm_probe.tscn` | Os braços isolados, sem o corpo por cima |
| `tools/build_monster_rig.py` | Mede as peças e gera `data/monster_rig.json` (silhueta do corpo + âncora dos membros) |
| `tools/icon_probe.tscn` | Desenha todos os ícones mapeados com o nome ao lado — é como o mapa foi conferido |
| `tools/teclado_probe.tscn` | **13 asserções** de que dá para jogar sem mouse: empurra `InputEventAction` pelo `Input` (o caminho do jogador, não `grab_focus` na mão) e pergunta ao viewport quem está com o foco. Auto-verificada — reintroduz o defeito e confere que a checagem reprova |
| `tools/acaso_probe.tscn` | Fotografa o Acaso **depois do aceite** — o estado que nenhuma outra ferramenta capturava, e onde o cartao de premio pode nascer errado sem ninguem ver. Aperta o botao pelo caminho do jogador, nao chama `_accept` na mao |
| `tools/gaveta_probe.tscn` | Abre a gaveta "VER DETALHE POR CRIATURA" da tela de resultado com equipe cheia contra bando cheio e mede que **todo botão continua dentro da janela** — o estado de DEPOIS do clique, que nenhuma captura tinha |
| `tools/prep_abas_probe.tscn` | As três abas da preparação (BANDO/EQUIPE/MOCHILA) com a equipe cheia, medindo que nada termina abaixo dos 900 px |
| `tools/paleta_probe.tscn` | Desenha as paletas instaladas lado a lado em `docs/paletas.png` — os quatro degraus, os cinco estados, as 16 salas e peças de verdade montadas com o kit. É a folha que se olha para escolher |
| `tools/ui_probe.tscn` | Desenha cada moldura em 4 tamanhos, a faixa em 3 larguras, as barras, os medalhões, o tooltip e a barra de rolagem — para o 9-patch quebrar aqui e não no jogo |
| `tools/validate_data.py` | Confere os JSON de conteúdo fora do Godot |
| `tools/build_ui_sheet.py` | **Desenha** as 10 células da UI, a faixa e as barras em PIL (ver `assets/CREDITOS.md`) |
| `tools/gerar_sons.py` | Sintetiza os 21 `.wav` de placeholder só com a biblioteca padrão do Python |
| `tools/lint_ui.py` | Cerca as regras do kit: fonte 27 proibida, altura de botão, `modulate_color`, tabelas de célula |

## Controles

| Tecla | Ação |
|---|---|
| `1` `2` `3` | Lançar o Ativo daquele slot |
| clique | Mirar (Meteoro = área; Prisma = inimigo, depois escolher o elemento) |
| `ESC` | Cancelar a mira; sem mira armada, abre o menu de pausa |
| `ESPAÇO` | Pausar / continuar |
| `TAB` | Velocidade 1× / 2× / 4× |
| `F11` | Tela cheia |
| setas · `ENTER` | Navegar e confirmar **fora do combate** — dá para jogar uma run inteira sem mouse (`tools/teclado_probe.tscn` cobra isso) |

`ESC` fora da mira abre o **menu de pausa** (voltar ao jogo, configurações, salvar
e sair da run). As Configurações abrem *dentro* do véu e devolvem você onde estava.

A navegação por teclado vale em **todas as telas menos o combate**, e a exceção é
deliberada: lá as teclas são do jogo, e um botão focado comeria `ESPAÇO` e `TAB`
antes de o jogo ver. A sonda cobra as duas metades — que o foco chegue sozinho
fora do combate, e que ninguém fique com ele dentro dele.

A **auto-pausa do §21.2 foi retirada.** Parar a briga sozinho no primeiro Ativo
disponível interrompia justamente o que o slice existe para responder — se o
combate é bom de *assistir*. O substituto é a **dica de intervenção**
(`screen_combat.gd`): na primeira vez em **toda a run** em que um Ativo fica
pronto, a linha do topo escreve `Meteoro pronto — aperte 1` e o botão daquele
Ativo pulsa uma vez. Some depois de 7 s. Não pausa, não pede tecla, não repete a
cada combate.

---

## O que está dentro (§24.1)

| Sistema | Conteúdo |
|---|---|
| Elementos | 5 — Fogo, Gelo, Água, Raio, Natureza |
| Reações | 8 em 16 pares — as 6 do slice + Catalisação e Geada Mortal (Natureza) |
| Espécies | **5 criaturas de teste animadas** (attack/idle/walk; golpe no quadro exato) |
| Ressonância | Eco (2) e Coro (4), por Peso Elemental |
| Ativos | Meteoro, Chuva Torrencial, Bênção Aurora, Prisma de Reescrita |
| Relíquias | 9 |
| Itens | 28 (armas, núcleos, totens, itens de assinatura) |
| Comida | **Nutrição e Transmutação** (§12.3/§12.4): 7 pratos, bônus permanentes limitados pelo Estômago |
| Momentos | **Combate** (escolhe entre 2) alternado com a sequência fixa **recruta · poder · recruta · loja · cozinha · acaso · recruta · loja** |
| Áudio | autoload `Som`: 14 efeitos e 7 laços de arena, três volumes nas Configurações. **Placeholders gerados** (`tools/gerar_sons.py`) |
| Save | uma run em andamento é gravada em `user://run_save.cfg` ao fim de cada nó; o título oferece **CONTINUAR — PASSO n** |
| Arte | **"O Vidro do Domador"**: recipiente de matéria neutra, canto cortado, sombra dura de 3 px, e a cor **só** no feixe da aresta |
| Run | escolha de **2 iniciais** → 8 combates + Chefe I (introdução leve, escalada medida) |

Os 8 momentos são um **orçamento fechado** e a ordem foi medida. Até 15/09 o
**Acaso era inalcançável**: os 7 eventos de `random_events.json`, a tela inteira e
o bloco `momentos.acaso` existiam, mas `acaso` não aparecia em
`evento_apos_combate` — **nenhuma run via um**. Ele tomou o lugar do segundo
momento de Poder (passo 6), e o Poder que ficou passa a dar **duas escolhas
seguidas**, para o teto de 3 Ativos continuar alcançável. Medido em 1000 runs: o
Acaso passou de 0% para **84%** das runs.

As unidades **se deslocam pela arena** enquanto lutam: o Papel decide como
(Guardião e Lâmina fecham distância, Arcano e Curandeiro mantêm a sua), a Postura
continua decidindo quem elas atacam. A formação inicial é a das três faixas do §7.2 —
é ela que a tela de preparação promete. O jogador continua sem posicionar ninguém.

**Fora do slice, por decisão do GDD:** Afinidade Dupla, Despertar, Terceira Muda,
Pactos, Ápice, o Sindicato, Arenas com efeito mecânico, meta-progressão, os outros
5 elementos e as 14 reações restantes.

O §24.1 dizia "comida: só manutenção (sem culinária)". Isso foi **invertido a pedido
do autor**: o upkeep saiu inteiro e a cozinha entrou. Comida agora é investimento,
não imposto.

---

## Arquitetura

O princípio do §22.1 — **dados fora do código** — é a espinha dorsal. Nenhum número de
balanceamento vive em `.gd`.

```
data/            conteúdo e balanceamento (JSON)
  elements.json      9 elementos (5 no slice), com resistência ao próprio elemento
  reactions.json     8 reações + a matriz de 16 pares ordenados
  species.json       5 formas de teste, com ultimates descritas como listas de operações
  resonances.json    Eco / Coro
  actives.json       A Mão do Domador
  relics.json        as 9 relíquias
  items.json         itens equipáveis
  dishes.json        pratos de Nutrição e Transmutação
  enemies.json       temas de time inimigo, arenas (e o tint de cada uma) e o Chefe I
  tuning.json        TODAS as constantes: fórmulas, preços, curvas, alvos

src/core/db.gd           autoload Db — carrega os JSON, matriz de reações O(1)
src/core/som.gd          autoload Som — 14 efeitos por NOME, laço por arena, mudo em headless
src/sim/                 SIMULAÇÃO HEADLESS (nenhum acesso a cena)
  aura_state.gd            as auras de uma unidade e suas 4 regras (§4.2)
  reaction_resolver.gd     resolvedor PURO e estático (§22.2)
  sim_unit.gd              uma unidade dentro do combate
  combat_sim.gd            o tick de 10 Hz, determinístico por semente (§22.3)
  ability_runner.gd        interpretador das operações de ultimate/ativo/reação
src/run/                 estado persistente da run
  run_state.gd             autoload Run — equipe, recursos, ressonância, comida
  unit_instance.gd         uma criatura sua ao longo da run
  node_gen.gd              gerador da trilha, com os eixos de tensão do §14.4
  enemy_gen.gd             times inimigos e o Chefe I
  combat_builder.gd        a ÚNICA ponte entre run e simulação
src/ui/                  camada visual — apenas um OBSERVADOR da simulação
  prisma_theme.gd          o Theme aplicado na raiz (tooltip, scrollbar, LineEdit...)
  ui.gd                    kit de UI sobre as molduras da Kenney (9-patch)
  prisma_bar.gd            barra de 3 fatias: o ProgressBar cobriria a moldura
  icons.gd                 nome semântico -> região do sheet de ícones
  monster_art.gd           monta a criatura pelo rig MEDIDO (data/monster_rig.json)
  monster_portrait.gd      a mesma criatura, dentro de um Control
assets/                  pacotes da Kenney (CC0) + o que é gerado deles
  ui/                      molduras 9-patch
  monsters/                178 peças de criatura
  icons/                   sheet do Shikashi + glifos do board-game
```

## Arte — "O Vidro do Domador"

A direção de arte tem nome porque ela é uma **regra**, não um humor. Um recipiente do
PRISMON é uma lajota de **matéria neutra** (`MESA #0f0d18` · `LAJOTA #1c1930` ·
`LAJOTA_HI #262138` · `ARESTA #3a3450`), com um **canto cortado** em vez de arredondado,
uma **sombra dura de 3 px** sem desfoque, e **a cor só no feixe da aresta**. O miolo
nunca é tingido.

Isso resolve o defeito que a revisão chamou de Raiz 3: `modulate_color` num 9-patch
tinge a peça **inteira**, o que apagava o corpo do painel e deixava só a borda visível —
16 chamadas de `UI.panel` renderizavam nada. Hoje cada célula sai em duas camadas
(matéria + máscara RGB) e `UI.frame()` as compõe. Medido no painel de Fogo: o miolo saiu
de luma 13,4 (1,5 **abaixo** do fundo) para 28,5, e a aresta de 135,8 para 71,5 —
deixou de ser a única coisa visível da peça.

Três consequências que o kit passou a cobrar sozinho: **botão de avançar é sempre
`UI.button_confirmar`** (verde, dois cantos cortados — duas marcas = *commit*, legível em
escala de cinza), **recuar/pular é sempre `UI.button_secundario`** (roxo), e a **altura
de botão é uma só** (`UI.BTN_H = 58`). `tools/lint_ui.py` mantém as três como cerca.

Cinco pacotes, integrados como placeholder:

- **UI Pack · Pixel Adventure** — todos os painéis, cartões, botões e barras. As
  molduras são compostas sobre a paleta do PRISMON por `tools/build_ui_sheet.py` e
  tingidas em tempo de execução com a cor do elemento.
- **Monster Builder Pack** — as criaturas são montadas peça a peça na hora de desenhar.
  **A forma vem da espécie, a cor vem da Afinidade atual** — então um Núcleo Ígneo muda
  a criatura na tela na hora, que é a leitura que o pilar "elemento é estado, não tipo"
  precisa.
- **UI Pack RPG Expansion** — as barras de HP, Energia e tempo, em 3 fatias.
- **Board Game Icons** — glifos de sistema em silhueta branca, tingíveis pela cor do
  elemento.
- **Shikashi's Fantasy Icons Pack v2** — um ícone para cada item, prato, relíquia,
  ativo, elemento e tipo de nó. **Este é o único pacote que não é CC0**: parte deriva de
  game-icons.net (CC BY 3.0) e exige atribuição se o jogo for publicado. Ver
  [assets/CREDITOS.md](assets/CREDITOS.md).

Do pacote de UI vêm as molduras dos painéis, a **faixa de título**, as **barras** e o
**medalhão** que emoldura cada criatura. As três últimas existem para tirar texto da
tela: a faixa substitui um cartão de cabeçalho, o medalhão substitui pastilha de
elemento mais nome em destaque, e a barra substitui "HP 100%" escrito.

A interface segue o critério do §21.1 — a tela de preparação responde cinco perguntas
sem cliques, e **o que não é uma dessas cinco vive em tooltip**. Ver
[NOTAS.md](NOTAS.md) §3.10.

Detalhes e decisões em [assets/CREDITOS.md](assets/CREDITOS.md).

A separação do §22.3 é levada a sério: `CombatSim` não conhece nenhum `Node` de cena.
Ela emite eventos; `FieldView` os consome. É isso que permite rodar **7.921
combates em 161 segundos** no `autoplay` (1000 runs completas), e é por isso que o
balanceamento é mensurável em vez de opinável.

A UI é construída **em código**, sem `.tscn` — o protótipo inteiro é texto revisável
(as duas únicas cenas são cascas de uma linha).

Uma diferença deliberada em relação ao §22.1: o conteúdo é **JSON**, não `.tres`.
O princípio é o mesmo (dado fora do código, editável sem abrir o editor); a escolha
foi por legibilidade em diff e por poder validar fora do Godot.

---

## Estado atual do balanceamento

**O protocolo é `--runs=1000`, e o número tem uma razão.** A faixa de vitória que o
§17.4 julga tem 10 pontos de largura; a margem de 95% de uma proporção é
`1,96·√(p(1-p)/n)`. Com 200 runs isso dá **±6,7 pontos** — o instrumento não separa "no
alvo" de "fora do alvo", e toda decisão tirada dali é tomada em cima de ruído. Com 1000
runs dá **±3,0 pontos**. O `autoplay` imprime a margem ao lado do número e **avisa**
abaixo de 1000.

Medido em **1000 runs · 7.921 combates** (16/09). Os alvos vêm de
`data/tuning.json → targets`, não de números escritos no `.gd`:

| Métrica (§17.4) | Alvo | Medido |
|---|---|---|
| Taxa de vitória da run | 35–45% | **40%** ✅ |
| Ativos por combate · lutas normais | 1.5–2.5 | **2.05** ✅ |
| Reações por combate · build de reação | 25–45 | **32.9** ✅ |
| Combates que estouram o relógio · lutas normais | < 6% | **5.3%** ✅ |
| Runs que cozinharam ao menos 1 prato | > 70% | **91%** ✅ |
| Duração de combate (mediana) | 28 s ±21% | 13,1 s ❌ |

O chefe é medido **à parte**, porque tem teto de tempo próprio (90 s contra 45 s) e
juntá-lo às lutas de passagem escondia uma distribuição bimodal: relógio **11,1%** e
**7,75** Ativos por combate.

### A única métrica fora do alvo, e por que ela fica

A explicação que se dava era "só `hp_scale` move isso, e mexer nele move a vitória".
Mexi, e o resultado é mais interessante: **a mediana de 28 s é alcançável só com dados**
— `hp_scale` 3.7→7.9, `max_duration` 45→96, `energy_per_second` 1.6→0.6,
`energy_per_reaction` 1.0→0.5 dão **26,9 s** com relógio em 4,4% e Ativos em 2,24, tudo
dentro do alvo. **Mas as reações por combate vão a 66,3**, contra um teto de 45.

E não há alavanca: a **taxa** de reação é invariante — 2,51/s na configuração atual,
2,46/s com o HP dobrado, 2,41/s com `transform_consume_ua` em 3.5, 2,39/s com
`max_reaction_chain` em 1 e `aura_cap_ua` em 4.0. Três alavancas diferentes de
`tuning.json` mexeram **0,2 reação no total**, porque nenhuma delas governa a taxa: quem
governa é o intervalo de ataque das espécies, o `ua_per_hit` e o tique de aura das
arenas.

Daí a conclusão, que é um achado sobre o **GDD** e não sobre o protótipo:

> Um teto de 45 reações equivale a um combate de 45 ÷ 2,45 = **18,4 s**, e um piso de 25
> a **10,2 s**. A faixa 25–45 do §17.4 *descreve* um combate de 10 a 18 s; a mediana de
> 28 s do mesmo §17.4 pede 69 reações. **Os dois alvos se contradizem** na taxa de
> reação que o jogo produz hoje, e os 13,1 s de agora caem no meio da janela que o alvo
> de reações permite.

Escolher a mediana de 28 s significa baixar a taxa de reação em um terço — isso é
**conteúdo** (espécies, itens, arenas), não escalar — ou afrouxar a faixa de reações.
É decisão do autor, não de calibragem. A tabela das quatro medições está em
`tuning.json → targets._duracao_x_reacoes_doc`.

### O que mais foi medido nesta leva

| Pergunta | Antes | Agora |
|---|---|---|
| Vitória nos nós 2 e 4 (onde o jogador tinha +1 corpo) | 100,0% e 99,5% | **98,0% e 98,0%** |
| Fração das mortes nos 4 primeiros passos | 0,8% | **8,9%** |
| Sobra de Éter na bolsa ao fim (mediana) | 119 | **30** |
| Compras recusadas por falta de Éter | 0 / 0 / 0 | **407 itens · 635 relíquias · 43 pratos** |
| Combates sem **nenhum** Ativo disponível | 15% (52% no nó 2) | **0,7% (4,1% no nó 2)** |
| Vitória por espécie inicial (leque) | sheep 42,0% × coalla 27,25% | **sheep 44,3% × coalla 35,8%** |

Vitória por nó, com o denominador sendo quem chegou nele: 100 · 98,0 · 98,5 · 98,0 ·
95,9 · 92,3 · **80,5** · 90,7 · 64,8. O nó 7 é o vale de propósito — é o único passo em
que o jogador entra **em minoria** (4 corpos contra 5), e o nó 8 sobe de novo porque o
recruta do passo 7 cai entre os dois. O chefe mata 35,2% de quem chega nele.

---

## Telas

`tools/screenshots.tscn` captura **25 PNG** em `shots/` — uma por tela e por estado que
vale comparar: título, opções, escolha de iniciais, escolha de combate, preparação,
sinergias (equipe rica e equipe pobre), combate, log, os seis momentos (recruta, loja,
cozinha e a sua escolha, poder, troca, acaso), o chefe, e a tela de fim **nos dois
estados** — vitória e derrota, lado a lado de propósito, porque o cartão "A RUN EM
NÚMEROS" é o mesmo nos dois e só assim dá para julgar se ele responde a pergunta certa.

> A ferramenta precisa de janela: `RenderingServer.frame_post_draw` **nunca retoma a
> corrotina sob `--headless`**, e o processo giraria para sempre sem escrever um PNG.
> As cinco ferramentas de captura agora testam `DisplayServer.get_name()` antes de
> esperar pelo quadro, então rodar uma delas headless falha rápido em vez de travar.
