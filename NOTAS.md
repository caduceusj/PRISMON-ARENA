# NOTAS DE IMPLEMENTAÇÃO — PRISMA Vertical Slice

Tudo que o protótipo decidiu por conta própria, e tudo que ele descobriu ao rodar.
Os blocos permanentes são **achados de balanceamento** (§1), **lacunas do GDD que
precisaram de uma decisão** (§2) e **desvios conscientes** (§3); §5 e §6 registram as
duas revisões grandes, e §4 fecha com o que o protótipo **não** responde.

---

## 1. Achados de balanceamento

### 1.1 As estatísticas do §18 e o alvo de ritmo do §17.4 se contradizem

Com as estatísticas do §18 **exatamente como escritas**, as fórmulas do §17.3 exatamente
como escritas, e as unidades **paradas** (como o GDD descreve o autobattler), o simulador
mede:

| Métrica | Alvo §17.4 | Com o GDD literal, sem deslocamento |
|---|---|---|
| Duração de combate (mediana) | 28 s | **9,2 s** |
| Ativos por combate | 1,5–2,5 | **0,83** |
| Taxa de vitória | 35–45% | **15%** |

A aritmética é direta. HP médio das 12 espécies base: **508**. DPS físico efetivo médio
(ATK × VEL, contra DEF 40): **42,5/s**. Um 1×1 médio dura 12 s *sem nenhuma reação*; com
Derretimento constante, **6 s**.

A consequência não é estética — ela **quebrava a pergunta que o slice existe para
responder**. A Energia do Domador acumula a +2/s; um Meteoro custa 40. Num combate de
9 segundos o jogador acumula ~18 de Energia e **nunca lança nada**.

**Duas coisas resolveram isso, e a segunda foi de graça:**

1. Um escalar explícito, `combat.hp_scale` em `tuning.json`, aplicado ao HP máximo
   **dos dois lados**. Escalar HP em vez de reduzir ATK preserva todas as razões que o
   GDD estabelece — entre espécies, entre papéis, e entre dano físico e dano de reação.
   A única distorção é que as fontes **fixas** (Combustão 4/s, `DanoBase(N)`, escudos)
   ficam relativamente mais fracas, na mesma proporção.
2. **O deslocamento na arena** (§3.8). A fase de aproximação vale ~5 s por combate, e
   ela é tempo em que a Energia acumula sem ninguém morrer. Isso permitiu **baixar o
   escalar de 2.0 para 1.4** — ou seja, o protótipo hoje está muito mais perto das
   estatísticas literais do seu documento do que estava antes do movimento.

**A curva medida com deslocamento** (150–250 runs por ponto, `power_last` 1.85):

| `hp_scale` | Vitória | Mediana | Estouro 45 s | Ativos | Reações |
|---|---|---|---|---|---|
| 1.0 *(GDD literal)* | 37% | 14,5 s | **3%** ✅ | 1,06 ❌ | 19,6 |
| 1.2 | 39% | 14,9 s | 4% ✅ | 1,22 ❌ | 23,3 |
| **1.4** | **36%** | **17,6 s** | **7%** | **1,57** ✅ | **28,9** |
| 1.6 | 43% | 17,9 s | 9% | 1,61 ✅ | 31,6 |
| 2.0 | 42% | 21,3 s | 15% ❌ | 2,05 ✅ | 41,5 |

**O que a tabela mostra, e que vale mais que o número escolhido:**

- Com deslocamento, **as estatísticas literais do GDD atingem a meta de estouro (3%)**,
  que era inalcançável antes. O que elas não atingem é o mínimo de Ativos por combate.
- Os 28 s de mediana e os <6% de estouro continuam **não sendo alcançáveis ao mesmo
  tempo**: subir o HP alonga a mediana e engorda a cauda de impasses na mesma medida.

Duas leituras possíveis, e a escolha é de design:

1. **Os 28 s são um alvo do jogo completo**, não do slice. Com Vínculo 12, 6–8 corpos e
   inimigos de índice 2,7–4,2, é natural que o Ato I seja mais rápido.
2. **O ritmo precisa de um mecanismo, não de um número.** Um "sudden death" progressivo
   (dano crescente a partir dos 30 s) resolveria a mediana *e* a taxa de estouro de uma
   vez, em vez de trocar uma pela outra. O GDD hoje só tem o corte seco dos 45 s.

Recomendo a leitura 2 se o alvo de 28 s for pra valer. Não implementei porque seria
inventar uma regra que o documento não tem.

### 1.2 Congelar cobrava um imposto invisível de builds de Gelo

Bug encontrado olhando o combate rodar: a tela mostrava `Congelar ×26` e `IMUNE ×22`
lado a lado.

A imunidade de 5 s do §7.4 impedia o *efeito* do Congelar, mas a reação ainda
**disparava e consumia 2 UA**. Durante os 5 s de imunidade, cada golpe de Água sobre
Gélido queimava aura e não fazia absolutamente nada — nem o controle, nem a aura
sobrando para outra reação.

**Correção:** uma reação catalítica de Controle não acontece contra alvo imune. A aura
fica no alvo e vira combustível para a próxima reação. Implementado em
`reaction_resolver.gd` via `Ctx.target_control_immune`, mantendo o resolvedor puro.

Isso subiu a taxa de vitória de 33% para 37% na medição em que foi isolado.

### 1.3 Times inimigos com 3–4 Guardiões eram a maior fonte de impasse

O gerador escolhia papéis livremente depois de garantir um Guardião e um Arcano.
Sorteios com 3–4 Guardiões produziam times de ~5.000 HP com DPS baixíssimo — a receita
exata de um combate que estoura os 45 s. Não era uma decisão de design, era um acidente
do sorteio. **Teto de 2 Guardiões por time inimigo** em `enemy_gen.gd`.

### 1.4 Atribuição de reação vai para o gatilho, não para o aplicador

No log pós-combate, um Nevascor que aplica Gélido o combate inteiro aparece com **0
reações**, e a Faúlha que dispara o Derretimento leva todas as 34. Está correto pela
definição, e é até didático — mas o "aviso" do §21.3 (que aponta a unidade que menos
contribuiu) pode acusar injustamente um aplicador puro. Hoje o aviso olha dano *e*
cura; talvez devesse olhar também "UA aplicada".

### 1.5 Guardião contra Guardião é matematicamente insolúvel em 45 s

Achado que só apareceu depois do deslocamento, porque agora os tanques **de fato se
encontram** e ficam trocando golpes.

Um Guardião tem 22–30 ATK, 0,8–1,0 VEL e 44–58 DEF. Um batendo no outro faz
`22 × 0,8 × (1 − 44/144) ≈ 12 de dano/s` contra 1.100–1.300 de HP: **~110 segundos**
para matar. Os 45 s do §7.3 nunca chegam lá.

Isso não é um bug — é coerente com o §9.2 ("Guardião: absorve dano e aplica aura por
contato"), ou seja, tanque não é condição de vitória. O abate tem que vir de Lâminas e
de reações. O impasse acontece quando os causadores de dano morrem primeiro e sobram só
os tanques, e o §7.3 resolve por % de HP.

O diagnóstico do `autoplay` confirma: nos combates que estouram, sobram em média
**2,1 unidades suas contra 1,8 inimigas**, e há um Guardião em praticamente todas as
composições travadas. Reduzi o teto de Guardiões em times inimigos pequenos (1 para
times de até 3 corpos, 2 acima disso), o que ajudou pouco — a causa é a matemática do
papel, não a frequência dele.

**Se os <6% de estouro forem inegociáveis, o lugar de mexer é o Guardião**, não o HP
global: ou ele ganha uma fonte de dano que escala, ou o §7.3 ganha o sudden death do
§1.1.

### 1.6 Tirar o upkeep deixou o jogador forte demais

Quando a Manutenção (§12.2) saiu e a Nutrição (§12.3) entrou, a comida virou de imposto
em bônus: acabaram as penalidades de −25%/−50% de ATK e PE, acabou o abandono de
unidades, e os pratos passaram a somar estatísticas permanentes ao longo da run.

A taxa de vitória saltou de **36% para 46%** na hora, e depois para **56%** com o
deslocamento (§1.7). A correção foi na curva de poder do inimigo: `power_last` de
**1.45 (§14.6) para 1.85**. É a mesma curva que o §14.6 descreve, só que reconhecendo
que a curva do *jogador* cresceu.

### 1.7 O deslocamento fortaleceu muito quem ataca à distância

Com movimento, uma unidade de Papel Arcano mantém distância de verdade: ela recua
enquanto o Guardião inimigo caminha. Isso rendeu +14 pontos percentuais de vitória
sozinho (42% → 56%) e é a maior parte do ajuste de `power_last`.

O contrapeso existe e funciona: a Lâmina anda a 148 px/s contra 78 do Arcano, e a
Postura Retaguarda a manda no alvo de menor HP% — ou seja, ela mergulha na retaguarda
inimiga. Dá para ver isso acontecendo nas capturas. **Se em playtest o Arcano parecer
dominante, o botão certo é a velocidade da Lâmina ou o tamanho da arena**
(`movement.arena_half_width`), não o dano.

### 1.8 Números que continuam fora do alvo

- **Estouro de 45 s em 7%** (alvo <6%). Ver §1.1 e §1.5 — é o outro lado da mediana,
  e a causa raiz é o Guardião.
- **Mediana de 17,6 s** contra os 28 s do alvo. Ver §1.1.
- **Taxa de vitória em 36%**, na borda de baixo da faixa. O bot do `autoplay` é
  deliberadamente cru (escolhe nó por heurística simples, nunca reposiciona itens, nunca
  segura Energia para um combo). Um jogador competente deve ficar acima disso — que é
  exatamente o que a faixa de 35–45% para "jogador experiente" pede.

---

## 2. Lacunas do GDD que precisaram de uma decisão

Nenhuma dessas está errada no documento — são coisas que só aparecem quando o sistema
roda. Todas estão isoladas em dados ou num único ponto do código.

| # | Lacuna | Decisão | Onde |
|---|---|---|---|
| 1 | Numa reação, o golpe recebido **deixa a própria aura**? | **Não** — o elemento é consumido pela reação. Regra uniforme; mantém "no máximo 2 auras" com significado. A exceção nomeada do GDD (Eletrocussão *não* consome Encharcado) continua valendo: o alvo mantém o Encharcado e pode eletrocutar de novo | `reaction_resolver.gd` |
| 2 | ~~**Eco de Gelo**: "reduz 10% de VEL de movimento" — não havia movimento~~ | **Resolvido.** Com deslocamento na arena (§3.8) o texto do GDD virou literal e a reinterpretação foi desfeita | `resonances.json` |
| 3 | **Névoa** (de Vaporizar): "−20% de precisão de ultimate" — não existe precisão no modelo | −20% no ganho de Energia de ultimate por 3 s | `reactions.json` |
| 4 | O que uma unidade de **Postura Suporte** faz quando ninguém precisa de cura? | Cura o aliado mais ferido abaixo de 90% de HP; caso contrário ataca. Sem isso a Nadina (Água/Curandeira) nunca aplicaria Encharcado e ficaria fora do sistema de auras | `combat_sim.gd` |
| 5 | **Empurrão** da Detonação: "empurra 1 posição para trás na fila de ação" | Soma 50% do intervalo de ataque do alvo ao cooldown dele | `reactions.json` |
| 6 | O GDD dá estatísticas por espécie mas não **raridade** por espécie | Guardião e Arcano = Comum (3 Éter); Lâmina e Curandeiro = Incomum (5 Éter). Os finalizadores e a cura custam mais | `species.json` |
| 7 | **Crítico** aparece no Eco de Raio (+10% de chance) mas nunca é definido | ×1.5 de dano, chance base 0% | `tuning.json` |
| 8 | Quantos **Ativos** o jogador começa com? | 2 (Chuva Torrencial + Meteoro), com o 3º slot comprável na Feira. Com menos, a intervenção não existiria nos primeiros nós — e é ela que o slice precisa testar | `run_state.gd` |
| 9 | O §12.3 diz que o Estômago limita "bônus permanentes", mas não diz se **Transmutação** conta | Não conta. Guisado Cromático, Prato da Muda e Doce do Esquecimento não somam estatística — são correção de build, e travá-los atrás do Estômago tiraria justamente a função de correção | `dishes.json` |
| 10 | O mesmo prato **duas vezes** na mesma unidade acumula? | Não. Dois Espetos Flamejantes na mesma criatura seriam só +20 ATK gastando dois slots de Estômago; recusar força a diversificar ou a investir em outra unidade | `run_state.gd` |
| 11 | Qual o **alcance** de cada Papel, agora que existe deslocamento? | Guardião 62 px e Lâmina 54 px fecham distância; Arcano 250 px e Curandeiro 290 px mantêm 195 e 250 de folga. A Lâmina anda a 148 px/s contra 96 do Guardião e 78 do Arcano — é ela que mergulha | `tuning.json` (`movement.roles`) |

---

## 3. Desvios conscientes

### 3.1 Santuário entrou na lista de nós

O §24.1 lista os nós do slice como Rinha, Ninho, Jazida, Feira e Incubadora — mas lista
**8 Relíquias** no mesmo escopo. Sem Santuário, nenhuma delas seria alcançável.

Adicionei o Santuário como sexto tipo, aparecendo **exatamente uma vez, no nó 5**, como
uma das duas opções — o mesmo padrão que o §14.3 define para o Altar do Vínculo.

### 3.2 Vínculo sobe de 6 para 8 no nó 5

O §10.5 dá "início da run: 6" e "fim do Ato I: 8". Como o slice é um Ato só, o marco foi
colocado no meio (nó 5). O Altar do Vínculo não entrou — não está no escopo do §24.1 e o
Santuário já ocupa o nó 5. Está em `tuning.json` (`bond_milestone_node`).

### 3.3 Times inimigos de 2 a 5, não de 3 a 6

O jogador começa com **2 corpos** e Vínculo 6. Três inimigos no nó 1 significa estar em
desvantagem numérica na primeira decisão da run, com índice de poder 1.00 — que deveria
ser o encontro mais neutro possível. A escala vai de 2 a 5 ao longo do Ato.

### 3.4 Conteúdo em JSON, não em `.tres`

O §22.1 pede `Resource` / `.tres`. Usei JSON em `res://data/`. O princípio está
respeitado: **nenhum número de balanceamento vive em `.gd`**. A troca é por legibilidade
em diff, edição sem abrir o editor, e validação fora do Godot
(`tools/validate_data.py`). Migrar para `.tres` depois é mecânico: os campos já estão no
formato de um `Resource`.

### 3.5 `ElementalState` é `RefCounted`, não `Node`

O esboço do §22.2 escreve `class_name ElementalState extends Node`. Mas o §22.3 exige
que a simulação seja headless e sem acesso a cena — as duas coisas não convivem. Ficou
`RefCounted`, o que é o que torna 521 combates em 6,8 s possíveis.

### 3.6 Arenas são informativas

O §24.1 exclui Arenas do slice, mas o card do nó (§14.2) promete mostrá-las. Elas
aparecem no card e na tela de combate, **sem efeito mecânico**. Os dados já estão em
`enemies.json` com o texto de cada uma.

### 3.7 A comida virou Nutrição, não Manutenção — a pedido do autor

O §24.1 define, para o slice: *"Comida: só manutenção (sem culinária)"*. Foi o que
implementei primeiro: Provisões, Apetite, upkeep após cada nó, Faminta/Definhando e
abandono da equipe.

O autor pediu o oposto — comida como **refeições que dão bônus permanentes**, na linha
de *How Many Dudes*. Isso é o §12.3 (Nutrição) e o §12.4 (Transmutação) do próprio
documento. Então:

- **Saiu inteiro:** Provisões, Apetite, upkeep, os três estados de fome, o abandono
  após o 3º encontro, e a tela de escolha de quem passa fome.
- **Entrou:** 7 pratos (4 de Nutrição, um por elemento do slice, + 3 de Transmutação),
  o **Estômago** por unidade (3 base / 4 evoluída) como limite de investimento, e o nó
  de **Banquete** (§14.3) como a bancada onde se cozinha.
- **Ingredientes** (§12.5) já existiam como recompensa de combate, com o elemento do
  inimigo derrotado. Só agora o elo do §12.5 fecha de verdade: *a escolha de rota
  alimenta a cozinha, a cozinha alimenta a build, a build determina qual rota é segura.*
- Duas relíquias novas de cozinha (Estômago de Ferro, Livro de Receitas) — daí as 10
  em vez das 8 do §24.1.
- O **Devorador** passou a comer Ingredientes em vez de Provisões. O teste de economia
  do Chefe I continua o mesmo: quem cozinhou tudo e não guardou despensa apanha.

Consequências medidas em §1.6. O sistema deixou de ser um imposto e virou uma decisão
de investimento — mas também deixou de ser uma **pressão**, e a pressão que ele exercia
sobre o tamanho de equipe agora recai inteira sobre o Vínculo.

### 3.8 As unidades se deslocam pela arena

O GDD descreve o combate como estático: três faixas fixas por Postura (§7.2). O autor
pediu movimento, como em *How Many Dudes*.

O que **não** mudou, e é o que importa para o §7.1: o jogador continua sem posicionar
ninguém. A formação inicial continua sendo a das três faixas, na ordem exata de VEL
decrescente — a "formação prevista" da tela de preparação continua verdadeira, e agora
descreve *onde a briga começa*.

O que mudou: a **Postura** decide quem a unidade ataca (regra do §7.2, intacta); o
**Papel** decide como ela se move. Guardião e Lâmina fecham distância; Arcano e
Curandeiro mantêm a sua; Suporte fica perto de quem precisa de cura e longe da briga.
A direção de aproximação sai da posição **inicial** da unidade, não da atual — sem isso
todo mundo que mira o mesmo alvo converge no mesmo vetor e o campo vira uma bola.

Três consequências que valem registro:

1. **Melhorou o ritmo de graça.** A fase de aproximação alongou a mediana de 13,9 s
   para 17,6 s e derrubou o `hp_scale` artificial de 2.0 para 1.4 (§1.1).
2. **Área passou a importar de verdade.** Meteoro e Detonação dependem de como o campo
   se aglomerou, e isso muda a cada combate.
3. **Fortaleceu quem ataca à distância** (§1.7), o que exigiu recalibrar a curva do
   inimigo.

Tudo isso continua determinístico: o passo de movimento é Euler a 10 Hz, a separação
entre corpos desempata por id, e não há RNG em lugar nenhum do deslocamento. A camada
visual interpola as posições a 60 fps — a simulação continua sendo a única fonte de
verdade.

### 3.9 Arte: pacotes da Kenney como placeholder

A UI construída em código (`StyleBoxFlat`) foi substituída pelo **UI Pack · Pixel
Adventure**, e as criaturas — que eram círculos coloridos — passaram a ser montadas com
o **Monster Builder Pack**. Ambos CC0.

Três decisões que valem registro, todas detalhadas em `assets/CREDITOS.md`:

1. **As molduras da Kenney são compostas sobre a paleta do PRISMA** por um script
   versionado (`tools/build_ui_sheet.py`), porque os tiles têm centro transparente e o
   `StyleBoxTexture` do Godot não tem cor de fundo. A moldura é clareada de propósito
   para aceitar `modulate_color` — é assim que um cartão de Fogo ganha borda vermelha
   com uma única textura.
2. **A criatura é montada na hora de desenhar**, não pré-renderizada. Porque a **cor vem
   da Afinidade atual**: um Núcleo Ígneo, um Guisado Cromático ou o Prisma de Reescrita
   mudam a criatura na tela imediatamente. Pré-renderizar exigiria 24 espécies × 6 cores
   de imagens e perderia justamente essa leitura.
3. **O tamanho em tela é proporcional ao custo de Vínculo** (§21.4): base 46 px,
   evoluída 64 px, chefe 112 px.

O que **não** foi resolvido: os dois pacotes têm linguagens visuais diferentes (UI em
pixel art, criaturas vetoriais). É aceitável num protótipo e até ajuda a separar
interface de criatura, mas não é uma direção de arte — é um placeholder.

Ajuste que a arte forçou na simulação: o `movement.separation_radius` e os alcances de
corpo a corpo tiveram que crescer para caber os corpos desenhados. Os alcances de melee
**precisam ser maiores que a separação**, senão a separação empurra os corpos para longe
do ponto em que eles querem atacar e o clinch fica tremendo.

### 3.10 Enxugamento da interface

A tela de preparação tinha virado uma parede: cada unidade mostrava seis
estatísticas, o texto completo da ultimate, contadores de Vínculo, Estômago, UA por
golpe, progresso de Muda, itens e pratos — vezes cinco unidades. O §P3 do GDD pede
"toda build legível em 5 segundos", e não era.

O critério usado para cortar foi o próprio §21.1: **a tela precisa responder cinco
perguntas sem cliques** — Ressonâncias ativas, reações possíveis, formação prevista,
cozinha e Vínculo. Estatística por estatística e texto de ultimate **não são nenhuma
das cinco**. Foram para tooltip; nada se perdeu, mas a tela parou de gritar.

O que mudou concretamente:

| Antes | Agora |
|---|---|
| `HP 100%` escrito | barra fina |
| `Estômago 1/3`, `Muda: 1/2 cópias` | bolinhas preenchidas |
| `ATK 46 · DEF 15 · VEL 1.5 · PE 85 · Vontade 40` | tooltip |
| `⚡ Lança de Chama — Dano alto + 4 UA...` | só o nome da ultimate |
| `1× Glaciarca 1× Nevascor 1× Fríora` | medalhões das criaturas |
| pastilha de elemento + nome em negrito | medalhão com aro tingido pelo elemento |
| cartão de cabeçalho | faixa do pacote da Kenney |
| lista de reações com fórmula | só o nome, cor e tooltip |
| efeito de cada Ressonância por extenso | contadores 2/4/6 + tooltip |

No combate, números de dano abaixo de **3% do HP máximo do alvo** deixaram de aparecer.
Arranhões viravam uma nuvem de dígitos exatamente sobre o clinch e escondiam o número
que o §21.2 diz que importa: o da reação.

Os cartões de nó também deixaram de esticar para preencher a tela — ficavam 70% vazios.

### 3.11 O Theme, e três erros de aplicação de 9-patch

A primeira integração da UI aplicava as molduras nó a nó, com
`add_theme_stylebox_override`. Isso alcança só o que a gente cria à mão — **tudo que a
engine instancia sozinha continuava cinza**: o painel de tooltip, as barras de rolagem, o
`LineEdit`, o `ProgressBar`, os separadores. `src/ui/prisma_theme.gd` monta um `Theme` na
raiz e resolve isso de uma vez.

Três defeitos de aplicação que valem registro, todos encontrados desenhando cada peça em
quatro tamanhos (`tools/ui_probe.tscn`) em vez de aplicar direto:

1. **A faixa estava dobrada.** `43–45` e `56–58` no tilesheet são **duas faixas
   completas**, não a metade de cima e a de baixo de uma só. Compor as duas linhas
   empilhava um laço sobre o outro.
2. **A barra cheia cobria a própria moldura.** O `ProgressBar` do Godot desenha o
   preenchimento a partir de (0,0) sobre todo o retângulo, ignorando as margens do
   fundo. Virou um `Control` próprio (`prisma_bar.gd`) que desenha na ordem certa.
3. **As bordas texturizadas borravam.** O 9-patch esticava o grão da moldura dourada;
   `AXIS_STRETCH_MODE_TILE` repete em vez de esticar e mantém o pixel.

A lição, que vale para as próximas peças do pacote: **desenhar em quatro tamanhos antes
de aplicar**. Um 9-patch parece correto num cartão grande e quebra numa linha de 38 px.

### 3.12 Ícones: um mapa semântico, não nomes de arquivo

Todo item, prato, relíquia, ativo, elemento e tipo de nó tem ícone. O mapa
(`data/icons.json`) liga um **nome semântico** — `dish_espeto_flamejante`,
`node_jazida` — a uma posição no sheet do Shikashi, seguindo o mesmo princípio do
resto do conteúdo: dados fora do código.

Duas decisões que valem registro:

1. **O mapa foi montado a partir de um índice visual do sheet, não da ordem listada no
   README do pacote** — a ordem do README não bate com o layout. `tools/icon_probe.tscn`
   desenha os 68 ícones com o nome ao lado; foi assim que a conferência foi feita, e é
   assim que qualquer ícone novo deve ser conferido.
2. **Ícones de conteúdo não são tingidos.** Os do Shikashi já vêm coloridos e tingi-los
   embaralharia a leitura de elemento. Onde a cor precisa vir do elemento, o mapa aponta
   para as silhuetas brancas do Board Game Icons (`g_*`).

**Ponto de atenção jurídico:** o pacote do Shikashi é o único do projeto que **não é
CC0**. Parte dele deriva de game-icons.net (CC BY 3.0) e **exige atribuição** se o jogo
for publicado. Está destacado em `assets/CREDITOS.md`. Trocar por arte própria depois é
só reescrever `data/icons.json` — o código não muda.

### 3.13 O encaixe das criaturas passou a ser medido

As criaturas montadas estavam quebradas: membros soltos, e aparentemente **um braço só**.
Duas causas, nenhuma delas de gosto:

1. **A posição de encaixe vinha do retângulo do corpo, não da silhueta.** Os corpos do
   pacote vão de 165×165 a 132×250. Uma fração da largura do retângulo acerta no corpo
   quadrado e erra feio no alto e estreito. Agora `tools/build_monster_rig.py` mede, para
   cada corpo, a **meia-largura opaca** na altura da cabeça, do ombro e do quadril, e
   mede a âncora de cada membro pelo centro de massa da faixa de encaixe. O resultado vai
   para `data/monster_rig.json` — dado, não estimativa.
2. **`draw_texture_rect` com largura negativa não espelha de forma confiável.** Ele
   normaliza o retângulo, e o braço esquerdo saía com a massa virada para dentro do
   corpo — daí a impressão de um braço só. O espelho agora é `draw_set_transform` com
   escala −1 no eixo x a partir do ponto de encaixe.

De quebra, o rosto passou a ser dimensionado pela **largura da cabeça** medida, e não
pela largura total do corpo: num corpo alto e estreito o retângulo não diz nada sobre
onde o rosto cabe, e os olhos estouravam a silhueta.

A conferência é visual e tem ferramenta própria: `tools/rig_probe.tscn` desenha os seis
tipos de corpo com os pontos de encaixe marcados por cima, e `tools/arm_probe.tscn`
isola os braços sem o corpo. Foi o probe dos braços que revelou a segunda causa.

### 3.14 Ultimates como listas de operações

As 24 ultimates do §18 não estão em GDScript. Cada uma é uma lista de operações
(`strike`, `heal`, `shield`, `buff`, `taunt`, `control`, `repeat`, `consume_aura`,
`discharge`, `chain`, `delay_action`, `rewrite_affinity`, `cleanse`) interpretada por
`ability_runner.gd`. Uma ultimate nova é um bloco de JSON, não código — e uma operação
desconhecida vira aviso, não crash, então os dados podem andar à frente do código.

---

## 5. Revisão de 30/08/2026 — decisões do autor (Arthur)

Três mudanças de design pedidas por mensagem, todas implementadas. **Este bloco é o
"ajuste do GDD"**: onde contradizem o documento, valem estas decisões.

### 5.1 A escolha é sempre entre DOIS COMBATES

> "as duas opções pro jogador tem que ser 2 combates. Recompensas e eventos são
> automáticos, você não escolhe o caminho deles."

O §14.3 (11 tipos de nó) sai de cena. Cada passo oferece **duas Rinhas** com informação
completa; o eixo é o Risco do §14.4 (o card mais perigoso paga mais — `pair.reward_per_danger`).
Entre combates roda a **esteira de eventos automáticos** (`EventGen` + `ScreenEvents`),
como em How Many Dudes: recruta, relíquia (nós 3 e 6), item (nós 2, 5, 7), cozinha
automática (1 prato/nó quando a despensa banca) e bônus de Éter. Zero escolhas; tudo
determinístico por semente.

### 5.2 Recruta-se a criatura INTEIRA

> "tipo chocar ovo, acho ruim. Acho melhor pegar o pokemon inteiro."

A Incubadora morreu. O recruta automático entrega a criatura completa. Com o elenco de
teste sem linhas evolutivas, **A Muda fica dormente** (o código dela permanece, ativado
por `evolves_to` nos dados — volta quando houver linhas de evolução de novo).

### 5.3 Elenco de teste: 5 criaturas animadas

> "mandei uns pokemon pra vc. Implemente esses 5 e coloca as animações, vamos usar só
> esses por enquanto pra teste."

| Criatura | Elemento | Papel | Quadro de dano |
|---|---|---|---|
| Apollo | Fogo | Lâmina | **13** |
| Coalla | Natureza | Curandeiro | **11** |
| Hipocampo | Água | Arcano | **11** |
| Pinto-Raio | Raio | Arcano | **11** |
| Sheep | Gelo | Guardião | **12** |

Sheets de 160×160 (attack 18 quadros, idle 12, walk 6), medidos por
`tools/build_anim_rig.py` → `data/anims.json`. Blocos de estatística reaproveitados do
§18 (Cinzel, Nadina, Gotarém, Faísco, Nevisco).

**O golpe conecta no quadro pedido.** A animação de ataque estica sobre o intervalo de
ataque inteiro e a simulação agenda o dano para `intervalo × (quadro−1)/18` — o windup.
Testado: o dano do Apollo cai a ~0,40 s do início com VEL 1.9 (quadro 13 ≈ 0,35 s +
resolução de tick). Quem está armando o golpe fica **plantado** (não anda).

O Coalla é *grass* — então **NATUREZA entrou no slice** com as duas reações simples do
§6: **Catalisação** (Raio↔Natureza, devolve 8 de Energia — vira motor de Ativos) e
**Geada Mortal** (Gelo↔Natureza, 1.2× + 4% do HP máx). Esporo implementado (2/s
dobrando a cada 3 s, teto 5×; Eco de Natureza dobra a cada 2 s). As lacunas
(Esporo+Fogo, Esporo+Água) são deliberadas — §6.6.

**O Devorador** virou um Coalla gigante (130 px, tinta própria) — o glutão combina; a
escolta agora é Faísca no Mato (RAIO+NATUREZA) para nunca ser tanque+curandeiro.

### 5.4 Fontes pixel

- **Pixelify Sans** (OFL, Google Fonts) — fonte padrão do Theme. Baixada porque a
  Pixeled **não tem ã/õ/â/ê/ô** ("ração" virava "raç□o").
- **Pixeled** (enviada no zip) — usada onde só há dígitos: os números de dano.

### 5.5 O que a revisão abriu (pendências honestas)

- **Éter perdeu o dreno.** A Feira morreu com os nós de evento; hoje Éter só acumula
  (recompensa/score). Decidir: loja de meta pós-run? eventos pagos? — decisão de design
  do autor.
- **Timeout em ~16%** (alvo <6%): metade é o chefe (testa "raça" e resolve por HP% aos
  45 s — design), metade é o padrão já conhecido "sobra Guardião sem dano" (§1.5),
  agravado pelo elenco de 1 tanque. Mitigado com teto de não-dano em times inimigos
  pequenos; a solução de verdade continua sendo o sudden death recomendado no §1.1.
- **Mediana 13,7 s** (alvo 28 s) — a tensão do §1.1 continua; windup ajudou pouco.
- Vitória **39%** ✅ e Ativos/combate **1,47** (≈ alvo) com `power_last 1.55`,
  `hp_scale 2.0`.
- **Regra dura de movimento**: alcance de melee precisa exceder `separation_radius`
  por ~12 px — a Lâmina em 68 contra separação 70 travava num **deadlock sem nunca
  bater** (corrigido: separação 56, Lâmina 72, +10% de folga no início do ataque).

### 5.6 Revisão 31/08 — iniciais escolhidos e introdução que escala

**Escolha de iniciais.** Nova tela entre o título e o primeiro nó: o jogador monta a
dupla que abre a jornada (`ScreenStarter`). Ao marcar dois, a tela mostra **quais
reações a dupla produz** — a primeira decisão do jogo já é sobre a máquina elemental.
O sorteio antigo (`_roll_starting_team`) fica como reserva para o autoplay.

**A introdução estava invertida.** O histograma "onde as runs morrem" (novo no
autoplay, GDD §23.1) mostrou **26% das runs morrendo no nó 1** e só 74% de vitória no
primeiro combate. Duas causas e duas correções:

1. `power_first` 1.00 → **0.80** (e `power_last` 1.55 → **1.85**, `boss_power` 1.9 →
   **2.1**): a curva inteira inclinou — começa abaixo do jogador e termina acima.
2. **O perigo dos temas não media letalidade.** A "Ninhada Ígnea" (★★) é um bando só
   de Apollos (Lâminas de ATK 66) — o pior massacre do early game. Os perigos foram
   **reclassificados pela letalidade medida** (times com Curandeiro diluem dano e
   valem menos; bandos de puro dano valem mais), e o sorteio ganhou um **cardápio por
   nó** (`pair.danger_max/min_by_node`): o nó 1 só oferece temas leves; do nó 6 em
   diante as duas opções são pesadas.

Resultado medido (250 runs): **vitória no primeiro combate 100%**, zero mortes no nó 1,
mortes escalando do nó 5 ao 8, e todas as 10 duplas iniciais viáveis (55–85% de
vitória; antes: apollo+coalla tinha 5%). Vitória global ~65% — acima do alvo 35–45% do
§17.4 **por decisão do autor** ("o trecho inicial começa já com algumas vitórias e vai
escalando"); o alvo do GDD volta a valer quando houver mais conteúdo tardio.

### 5.7 Revisão 31/08 — escala tipográfica

> "tá tudo meio pequeno nas fontes e não tá tão legível, acho que precisa aumentar
> a fonte no geral"

A Pixelify Sans é uma fonte de pixel: desenha os glifos **menores que o tamanho
nominal**, e 11 pt (o tamanho de metade dos rótulos) simplesmente sumia.

Em vez de caçar os ~30 tamanhos literais espalhados pelas telas, tudo passa a
atravessar **`UI.fs()`** — um funil único em `src/ui/ui.gd`:

```gdscript
const F_SCALE := 1.34   # sobe a escala inteira de uma vez
const F_MIN   := 15     # piso: nada desce abaixo do legível
static func fs(size: int) -> int:
	return maxi(int(round(float(size) * F_SCALE)), F_MIN)
```

`UI.label/wrap/rich/button`, o `Theme` inteiro (botão, tooltip, barra, LineEdit) e
os textos do campo de combate passam por ele. **Para mexer na legibilidade do jogo
inteiro, mexa só ali.**

**Três colisões que a fonte maior expôs** — todas resolvidas com o mesmo princípio
(pista livre *medida*, não adivinhada):

| Sintoma | Causa | Correção |
|---|---|---|
| Avisos de reação empilhados uns sobre os outros | a faixa era ancorada no **y da unidade**, então pistas diferentes caíam no mesmo pixel quando as unidades estavam em alturas diferentes | anúncios agora usam uma **linha fixa da arena** — o x diz onde aconteceu, o y é estável; a pista sobe só quando o texto realmente encostaria em outro |
| Números de dano cobrindo uns aos outros | o leque tinha passo fixo de 24 px, mas a Pixeled desenha bem mais larga | passo = **largura medida** do número; unidades vizinhas (< 46 px) compartilham o índice do leque |
| `CoallaHipocampo` — dois nomes virando um | a altura alternava por `u.id % 3`: duas unidades vizinhas com o mesmo resto colidiam | mesma **pista livre medida**, recalculada a cada quadro |

Hierarquia nova nos anúncios: ultimates e avisos do chefe em `fs(20)`, nomes de
reação (frequentes) em `fs(15)` — o raro é maior que o comum.

### 5.8 Revisão 31/08 (tarde) — o que "automático" queria dizer

Eu tinha entendido errado o "eventos são automáticos". O autor esclareceu:

> "os eventos não são automáticos, eles só são separados de momentos entre escolher
> combates e eventos. Quando é pra brigar o jogador vai ser sempre brigar."

Ou seja: **o jogador não escolhe o CAMINHO** (não existe "ir pra loja ou pro ninho"),
mas **dentro de cada evento sempre há escolha**. A esteira de cartas que só passavam
na tela foi jogada fora.

O jogo agora alterna **momentos**:

| Momento | O que o jogo decide | O que o jogador decide |
|---|---|---|
| **Combate** | quais dois combates aparecem | qual dos **dois combates** enfrentar — sempre dois combates, nunca combate-ou-evento |
| **Recruta** | que duas criaturas aparecem | **qual das duas** entra no elenco (ou nenhuma) |
| **Loja** | o estoque da banca | **o que comprar** com o Éter e com os ingredientes |
| **Acaso** | qual evento apareceu | **entrar ou não** no evento |

O esquema está em `data/tuning.json → momentos.evento_apos_combate`:
`[recruta, acaso, recruta, loja, recruta, acaso, recruta, loja]`.

**A Loja resolveu o buraco do Éter** que eu tinha deixado aberto em §5.5: o Éter
finalmente tem um dreno. Itens e relíquias custam Éter; pratos custam ingredientes —
e cozinhar deixou de ser automático, virou compra. `Run.spend_ether()` é novo.

Eventos de acaso vivem em **`data/random_events.json`** (7 eventos, desfechos com
peso). Recusar nunca custa nada — o preço de recusar é a chance perdida.

### 5.9 A máscara de alcance — o bug dos corpos travados

> "as vezes os bichos se barram, e fica um colidindo no outro e não bate no inimigo
> porque nunca chega no alcance dele"

Diagnóstico: `_separate()` rodava **depois** do movimento e não sabia nada sobre
alcance. A unidade andava até a borda do alcance, o aliado a empurrava para fora,
ela voltava, era empurrada de novo — um ciclo que nunca fechava.

A correção é a "máscara" que o autor descreveu: `_leash_to_target()`, aplicada
**depois** da separação. Os corpos continuam se afastando para não virar sopa, mas
**nenhum empurrão pode tirar uma unidade do alcance do seu alvo** — quem passou do
ponto é puxado de volta para a borda de dentro do próprio alcance. Quem já está
encaixado também recebe só 30% do empurrão (`separation_clinch_scale`), então o
clinch parou de tremer. Determinístico, sem RNG.

Medido em `tools/clinch_probe.tscn` (4×4 só corpo a corpo, 10 combates longos):

| | travado | **no alcance** | duração |
|---|---|---|---|
| sem máscara | 1,6% | **57,4%** | 45,0 s |
| com máscara | 0,0% | **99,7%** | 35,8 s |

As unidades passavam **43% do combate fora do alcance do próprio alvo**. Esse era
o bug — e ele explicava duas métricas que estavam presas havia semanas.

**O balanceamento inteiro precisou ser refeito**, porque de repente todo mundo
passou a lutar de verdade (e os inimigos costumam ser mais numerosos): a vitória
despencou para 5%. Recalibrado com 4 momentos de recruta, `power_first 0.62 →
power_last 1.60` e `hp_scale 3.7`. Resultado em 250 runs:

| Métrica (§17.4) | Alvo | Antes da máscara | Agora |
|---|---|---|---|
| Vitória da run | 35–45% | 65% | 52% |
| Combates > 45 s | < 6% | 16% ❌ | **6% ✅** |
| Ativos por combate | 1,5–2,5 | 1,47 ❌ | **1,55 ✅** |
| Reações por combate | 5–45 | 26 ✅ | **37,6 ✅** |
| Runs que cozinharam | > 70% | 53% ❌ | **89% ✅** |
| Duração (mediana) | 28 s | 13,7 s ❌ | 13,3 s ❌ |

**Quatro dos seis alvos verdes** — o melhor estado do protótipo até aqui. O timeout
e a cozinha, travados desde o começo, foram destravados pela máscara. A mediana de
28 s continua a tensão conhecida do §1.1.

### 5.10 Fonte: Pixel Sans Serif

O autor mandou <https://www.dafont.com/pixel-sans-serif.font>. Testada em
`tools/font_probe.tscn` contra a Pixelify Sans, nos tamanhos reais do jogo:

- **Desenha muito maior e mais nítida** no mesmo tamanho nominal — por isso a
  `F_SCALE` voltou de 1,34 para **1,0** e nada encolheu na tela.
- Tem **todos os acentos** do português (602 glifos).
- **Não tem os símbolos** ★ ⚡ ❄ ◆ → — a Pixelify Sans entra como `fallbacks` da
  FontFile, e o Godot busca nela o glifo que falta.

⚠️ **Licença: "free for personal use".** Serve para protótipo, mas **trava um
lançamento comercial** — é preciso comprar licença ou trocar de fonte antes de
publicar. Registrado em `assets/CREDITOS.md`.

### 5.11 Revisão 31/08 (noite) — layout no formato How Many Dudes

> "priorize colocar a UI na direita e esquerda e em cima e embaixo, mas ao máximo
> livrando o centro, e sendo similar ao How Many Dudes em questão de organização e texto"

Três peças novas, compartilhadas por todas as telas:

| Peça | Onde | O que resolve |
|---|---|---|
| **`RosterRail`** | trilho fixo à **esquerda** | o elenco só existia na tela de preparação; nas outras o jogador decidia às cegas. Escolher combate, recrutar, comprar e aceitar evento são decisões *sobre a equipe* — ela precisa estar à vista enquanto se decide |
| **`RunRibbon`** | fita no **alto** | mostra o Ato inteiro de uma vez: os 8 combates, que evento vem depois de cada um, e onde o jogador está. Substitui o texto "NÓ 3/9", que dizia a posição sem dizer o que vem pela frente |
| Barra de decisão | **rodapé** | as duas opções de combate saíram do miolo: preço, ★ de perigo, botão LUTAR! e a composição inimiga em linhas de texto ("2 Hipocampos"), como o "10 Bebês" do HMD |

**O centro ficou vazio de propósito.** É onde a arena vive; enchê-lo de UI fazia a
tela de decisão e a de combate parecerem dois jogos diferentes.

Consequências no resto:
- **A preparação perdeu sua coluna de elenco** — repetir a mesma lista em duas
  colunas gastava metade da tela com informação já visível. Sobrou espaço para o
  grafo de reações e a coluna de leitura.
- **O trilho recolhe no combate e no log**, onde a largura vale mais: a arena
  precisa do espaço, e o log já lista as unidades na própria tabela.
- **O log virou tabela**, no formato "Pontuações por Cara" do HMD: uma linha por
  Cara, colunas de Nocautes / Reações / Dano Causado / Cura / Dano Sofrido, com
  barra de fundo proporcional ao melhor da coluna. A barra sozinha dizia quem bateu
  mais; a tabela diz também quem curou, quem morreu e quem apanhou — que é o que
  explica uma derrota.
- **A tela de recruta mostra o que cada opção desbloqueia** em reações novas, então
  a escolha é sobre a máquina elemental, não sobre qual bicho é mais bonito.

**Armadilha registrada:** `UI.panel()` devolve um `StyleBoxTexture` 9-patch — ele
desenha a moldura mesmo com fundo transparente. Nas células zeradas do placar isso
virava uma grade de caixinhas vazias. Onde o fundo precisa sumir de verdade, usar
`StyleBoxFlat`.

**Pendente:** o wireframe `PRISMA Wireframes.dc.html` (projeto Claude Design
`771a1977-e52a-4cb6-a4b4-3e84d409656b`) não pôde ser lido — `DesignSync` exige
autorização que só o `/design-login` numa sessão interativa concede. As "escolhas A"
pedidas pelo autor ainda precisam ser conferidas contra este layout.

### 5.12 Revisão 31/08 (madrugada) — arena circular e as bordas ocupadas

Quatro pedidos do autor, todos sobre onde a informação mora.

**1. O Rancho no fundo da escolha** (`RanchView`). O centro estava livre de UI —
correto — mas também vazio. Agora a equipe fica em pé lá, tocando *idle*, em arco
ordenado por Postura: vanguarda à frente, suporte atrás. A "formação prevista" da
preparação passa a se ler no chão, e a decisão ganha peso: você vê quem vai lutar
antes de escolher contra quem.

**2. A arena virou elipse.** Prender a briga num retângulo deixava quatro cantos que
ninguém usava e que o desenho tinha de fingir que existiam. O `_clamp_arena` projeta
para dentro da elipse e o piso é desenhado como anel — centro mais claro, borda
escurecendo — então o olho cai no meio sozinho.

**3. O painel lateral do combate** (`CombatPanel`, 300 px à esquerda). Antes a leitura
da equipe cabia numa barrinha de 5 px sobre a cabeça, disputando espaço com os números
de dano: *quem está morrendo*, *quem carrega qual aura* e *de quem é a ultimate que vai
sair* eram perguntas sem resposta no meio da luta. Cada Cara agora tem ficha larga com
vida em número, carga de ultimate, auras ativas e **o que está fazendo agora** —
"atacando Hipocampo", "armando o golpe", "⚡ Arco Voltaico".

**4. A doca de itens à direita** (`ItemDock`). Relíquias e itens equipados deixaram de
existir como um contador no topo ("RELÍQUIAS 3") e viraram objetos visíveis, cada um
com seu texto no tooltip — como nos wireframes do How Many Dudes.

**Duas colisões que a fonte maior tinha escondido e o layout novo expôs:**

| Sintoma | Causa | Correção |
|---|---|---|
| Ultimates caindo sobre nomes de reação | as duas faixas tinham bases próprias (74 e 114 px) e alturas de pista diferentes (22 e 34 px) — elas se cruzavam | **corredor único**: a faixa decide só o tamanho do texto, e todos disputam as mesmas pistas com altura fixa |
| `CoallaHipocampo` de novo | cada criatura tem altura própria, então a linha de base muda por unidade: "mesma pista" não significava "mesma altura" | a busca compara **o Y que o rótulo vai ocupar de fato**, não o índice da pista |

Ultimates repetidas agora agregam como as reações — "Arco Voltaico ×3" em vez de três
rótulos no mesmo pixel.

**Custo medido:** a elipse mudou o balanceamento de leve (o clamp empurra a briga para
o meio, então os encontros são mais densos): timeout 6% → 7%, cozinha 89% → 79%. Ambos
ainda dentro do aceitável, e três alvos seguem verdes. Não recalibrei — a diferença é
menor que a variação entre execuções.

### 5.13 Revisão 31/08 — a limpeza

> "é preciso fazer uma limpeza de interface pelo amor de deus, para não ficar
> enchendo de informação e transformando o jogo em confuso"

A crítica é justa e o histórico explica: cada revisão ACRESCENTOU (fita, trilho,
doca, painel de combate, placar) sem nunca tirar nada. Esta passada só **remove**.

**O que saiu, e para onde:**

| Saiu | Onde estava | Por quê |
|---|---|---|
| `NÓ 3/9`, `VÍNCULO 2/6`, `RELÍQUIAS 0`, `SEMENTE` | barra do topo | a fita já mostra o nó, o trilho já mostra o Vínculo, a doca já mostra as relíquias. Seis blocos **estouravam a largura em 2544 px** |
| `7 F 2 G 4 Á 1 R 1 N` | Despensa, no topo | cinco números com inicial de elemento, ilegíveis e de largura variável. Virou **um** número; a quebra por elemento foi para o tooltip |
| barra de escudo + barra de ultimate | sob cada unidade na arena | eram três barras empilhadas de 2 a 5 px. Sobrou **uma**: a vida. A ultimate vive no painel da esquerda, que tem espaço |
| nome dos inimigos | arena | oito nomes escritos que o jogador não usa para decidir nada. O inimigo se lê pela silhueta e pela cor da barra |
| rótulos de buff | sob cada unidade | eram uma terceira linha de texto por unidade |
| `HP/ATK/DEF/VEL` + `◆itens ◇pratos` | fichas do trilho | seis coisas por Cara × seis Caras. Sobrou **nome + barra de vida**; os números estão todos no tooltip |
| número de UA nas auras | painel de combate | "6 UA de Encharcado" no relance não ajuda; virou um **ponto colorido** por aura |
| `+29` de cura e escudo | arena | com `hp_scale 3.7`, curar 29 numa unidade de 2886 HP é 1% — ruído verde piscando. Agora seguem a mesma regra do dano: abaixo de 3% do HP máximo, não vira número |
| caixinha "VAZIO" | doca de itens | a doca inteira só aparece quando há o primeiro item |

**Duas mudanças de comportamento:**

- **A barra do topo some no combate.** O caminho da run não ajuda a assistir uma
  briga, e a fita competia com a arena pelo olho.
- **A pausa automática saiu.** O §21.2 do v0.1 pedia pausar no primeiro Ativo
  disponível, para ensinar que o jogador pode intervir. Na prática o jogo parava no
  meio da luta e exigia ESPAÇO — interrompia justamente o momento que se quer
  assistir. O ensino continua sem parar o jogo: o botão do Ativo acende e a barra de
  Energia enche à vista.
- Os painéis laterais do combate ficam **centrados na vertical**, não colados nos
  cantos.

### 5.14 Revisão 31/08 — geometria travada

> "a UI lateral fica aumentando e diminuindo de tamanho de um jeito muito estranho…
> tem que sempre estar alinhada e fixa em um lugar bem estabelecida. Reduza a UI de
> cima e de baixo ao centro, elas não precisam escalar do jeito que escalam"

**Duas causas distintas, os dois sintomas iguais: caixa dimensionada pelo conteúdo.**

**1. O painel lateral pulsava** porque a linha de estado muda o tempo todo —
"procurando alvo" → "atacando Hipocampo" → "⚡ Arco Voltaico". Cada troca de texto
empurrava a ficha, a ficha empurrava o painel, e o painel inteiro respirava de
largura durante o combate. As auras faziam o mesmo ao aparecer e sumir.

Correção: **nada ali dimensiona pelo conteúdo.** Largura reservada para o nome e o
estado (`TEXT_W`, com `clip_text`), espaço reservado para as auras (`AURA_W`, sempre
o mesmo com zero, uma ou duas), altura fixa da ficha (`CARD_H`). O texto é cortado —
nunca faz a caixa crescer.

**2. As barras de cima e de baixo esticavam de ponta a ponta.** Em 1600 px passava;
em 2544 px os espaçadores jogavam o logo num canto e os recursos no outro, e a barra
de Energia atravessava a tela inteira — mais larga, não mais legível.

Correção: o conteúdo das três barras (topo do jogo, topo do combate, rodapé do
combate) tem **largura própria fixa** (`BAR_W = 1180`) e fica **centrado**. O painel
continua sendo o fundo de ponta a ponta; o que mora dentro dele não acompanha mais a
janela.

Os painéis laterais também ganharam margem: colados na borda, a ficha parecia cortada
pela moldura da janela.

**Verificado nas duas resoluções** (1600×900 e 2544×1422, a do relato): nada é
cortado e nada muda de tamanho durante o combate.

### 5.15 Revisão 31/08 — a briga sai da beirada, e as barras encolhem

> "tá tendo uma sobreposição péssima na frente, das barras… essas barras ocupando a
> tela toda não estão dando certo… ao invés dessa barra grande pra representar a
> habilidade dá pra resumir ela de alguma forma"

**A sobreposição tinha uma causa de layout, não de arte.** A faixa mais funda nascia
em `lane_base + 2×lane_gap` = 205 + 310 = **515**, contra um raio de arena de **530**.
A Retaguarda nascia colada na borda e a briga inteira acontecia na beirada da elipse,
com os corpos, as barras de vida e os anéis empilhados num canto. Agora a faixa mais
funda cai em 150 + 180 = **330** — cerca de 62% do raio — e o encontro acontece no
meio, que é onde a câmera olha. `separation_radius` subiu de 56 para 64.

Duas fontes de círculo sobrepostos, as duas contidas:

- **Anéis de aura** cresciam com a carga e passavam de 40 px de sobra; dois lutadores
  colados tinham os anéis cruzando um pelo outro. Agora o anel é limitado a metade do
  espaço de separação: ele diz *qual* aura e *quanto* (pela espessura) sem invadir o
  vizinho.
- **Ondas de reação** ficavam a meia opacidade e cresciam até 77 px. Menores, mais
  discretas, e com **teto de 4 simultâneas** — a mais antiga sai.

**As barras largas foram resumidas.**

| Antes | Agora |
|---|---|
| Barra de Energia de ponta a ponta no rodapé | **chip com o número** + uma barrinha *dentro de cada Ativo* mostrando o quanto falta para **aquele** custo |
| Barra de tempo de ponta a ponta no topo | marcador curto de 190 px ao lado dos controles |

A Energia dizia uma coisa só — "quanto falta para eu poder lançar algo" — e gastava a
largura inteira para isso. A versão nova responde a pergunta *por Ativo*, que é a
forma útil dela, e ocupa um sexto do espaço. As duas barras ganharam margem interna.

O corredor de avisos ficou com **5 pistas e teto de 5 simultâneos**: sem teto, o sexto
anúncio caía numa pista ocupada e voltava a se sobrepor.

**Rastro de barra visível:** o trilho era escuro demais e uma barra quase vazia sumia
contra o painel — o jogador não via que existia barra até ela encher.

**Balanceamento remedido** depois de mexer nas distâncias (200 runs): vitória 51%,
timeout 6%, Ativos 1,57, reações 37,7, cozinha 77% — praticamente idêntico ao de
antes. Mexer no layout de spawn não desequilibrou nada.

### 5.16 Revisão 31/08 — a economia parte em duas, e os itens ganham identidade

**A Feira virou dois momentos.** `loja` vende itens permanentes por Éter; `cozinha`
serve pratos pagos em ingredientes. Antes era uma tela só com nove linhas rolando
para fora do ecrã. A sequência do Ato ficou:
`[recruta, cozinha, recruta, loja, acaso, cozinha, recruta, loja]`.

**Três ofertas por vez, e um botão de renovar que custa Éter** — com preço crescente
dentro do mesmo momento (`renovar_preco + renovar_passo × vezes`), então renovar é
sempre uma escolha, não um botão grátis de rolar até gostar.

**A comida alimenta UM Prismon, escolhido pelo jogador.** Antes o prato ia para quem
tivesse menos pratos — automático, sem decisão. A tela agora tem duas colunas: *o que
cozinhar* e *quem come*. Escolher o prato é meia decisão; a outra metade é para quem,
porque o Estômago é 3 e o bônus é permanente.

*Cuidado de balanceamento:* três sorteios entre sete pratos podiam devolver só os
caros, e o momento virava uma tela sem jogada — a métrica "runs que cozinharam" caiu
de 89% para 67% exatamente assim. **O primeiro prato do cardápio é sempre um que a
despensa banca**, quando existir algum. Voltou a 75%.

#### Três famílias de item novas

| Família | O que faz | Exemplos |
|---|---|---|
| **Poder** | acelera a regeneração da carga que dispara a ultimate (`unit_ult_gain`) | Bateria Óssea (+35%), Coração-Turbina (+70% e −60 HP), Diapasão Vivo (+25% nele, +10% na equipe) |
| **Sinergia** | escala com **uma reação nomeada** — vale muito numa build e nada em outra | Para-Raios (Eletrocussões +45%), Isolante Rachado (Eletrocussões atordoam 1 s, recarga 6 s), Estopim Curto (Detonações +55% e atordoam) |
| **Assinatura** | só o Prismon dono equipa (campo `for`) | Cauda de Brasa (Apollo), Lã Condutora (Sheep), Bico Para-Raio (Pinto-Raio), Sifão das Marés (Hipocampo), Folha Perene (Coalla) |

**A loja não filtra por quem você tem.** Um item de assinatura aparece mesmo sem o
dono na equipe, e a linha diz o motivo na cara — "nenhum Apollo na equipe" — em vez
de só apagar o botão. É deliberado: a banca mostra o que existe no mundo, e ver a
Cauda de Brasa sem ter o Apollo é informação sobre o próximo recruta.

**Motor:** `rx_dmg_add` multiplica o dano de uma reação nomeada; `rx_stun` aplica
Controle com **recarga própria por unidade e por reação**, senão uma equipe que reage
o tempo todo transformaria o item em atordoamento permanente. `unit_ult_gain` entra
nos dois pontos de ganho de ultimate (ataque desferido e golpe recebido).

**Balanceamento remedido** (250 runs). A vitória caiu para 32% com a mudança — um
recruta a menos (3, equipe de 5) e itens que podem não ter dono compatível. Com
`power_last 1.60 → 1.36`: **vitória 39% ✅** (dentro do alvo 35–45% do §17.4 pela
primeira vez), primeiro combate 100%, mortes escalando do nó 3 ao 7, cozinha 75% ✅,
reações 33,7 ✅. Ativos 1,42 (logo abaixo de 1,5) e timeout 7% seguem fora.

### 5.17 Revisão 31/08 — o dano passa a doer, e o Meteoro volta a existir

#### O bug: o Meteoro nunca acertou nada

`aim_area` lia o raio do **op**; o Meteoro declara `radius` no **ativo**. O op não
tinha raio, então `radius = 0.0`, e nenhuma unidade estava a distância zero do ponto
mirado. **O Ativo mais caro do jogo não fazia absolutamente nada** — e o autoplay
nunca pegou porque só media *quantos* Ativos eram lançados, não se surtiam efeito.

Corrigido em dois lugares: o op herda o raio do ativo, e o JSON passou a declará-lo
explicitamente. O validador agora reprova qualquer ativo de área sem raio no op, e o
smoke test exige que cada Ativo de área tenha **efeito** (dano *ou* aura — a Chuva
Torrencial é habilitadora e não bate) em **mais de um alvo**.

#### A economia de sobrevivência

> "faça o dano que os personagens receberem passar para os próximos combates, e os
> personagens nocauteados voltam com 1 de hp"

Não há mais cura de graça entre nós (`heal_between_nodes` só levanta os caídos). Quem
terminou a 30% começa o próximo a 30%. Quem caiu volta com **1 ponto de vida** — o
valor absoluto, não uma porcentagem, então o Sheep de 2886 e o Apollo de 1295 voltam
os dois com um.

Isso obrigou a criar uma fonte de cura, e é o que dá função aos **consumíveis**
(`data/consumables.json`):

| Consumível | Efeito | Base → teto |
|---|---|---|
| Cataplasma de Musgo | 35% num Prismon | 9 → 26 |
| Faísca Vital | levanta um caído a 50% | 14 → 38 |
| Seiva Densa | 75% num Prismon | 17 → 42 |
| Vapor Reconstituinte | 30% na equipe | 22 → 55 |
| Banho de Luz | 60% na equipe e levanta os caídos | 38 → 84 |

O preço é `base + passo × (nó − 1)` **com teto** — encarece junto com o quanto a
equipe apanha, sem nunca virar incomprável. A **Loja sempre oferece dois**: ficar sem
como curar não pode depender de sorte de sorteio. Há ainda ~42% de chance de cair um
no pós-combate. A bolsa se usa na tela de preparação, antes de entrar.

#### Ativos novos

| Ativo | Custo | O que faz |
|---|---|---|
| **Orvalho Curativo** | 30 | cura 22% numa **área** — barato o bastante para sair duas vezes por combate |
| **Círculo de Seiva** | 55 | cura 40% numa área grande e limpa 1 debuff de cada |
| **Improviso** | 20 | **gasta um consumível da bolsa** no meio da luta e cura 45% da equipe |

`aim_area_ally` é novo: cura de área pega os aliados dentro do raio, não a equipe
toda — posicionamento passa a valer para o suporte também. O Orvalho entrou na mão
inicial.

#### Layout

- **A cozinha vazava** porque `set_anchors_preset` ajusta as âncoras mas **não os
  offsets**: o Control mantinha o tamanho anterior e o `CenterContainer` centrava
  dentro de um retângulo errado. Trocado por `set_anchors_and_offsets_preset` em
  todas as telas. Era a mesma causa do painel de escolha nascer preso num quadrado
  no canto.
- **"Quem come" virou painel adjacente** (`PickerOverlay`): antes ocupava metade da
  tela o tempo todo; agora só existe quando há decisão pendente, escurece o fundo e
  sempre tem **Cancelar**. O mesmo painel serve para escolher quem recebe um
  consumível.
- **O LUTAR** deixou de ocupar a largura inteira: 360 px, centrado, com a bolsa ao
  lado.

#### Balanceamento

O dano persistente é a maior mudança de dificuldade da sessão. Com o bot ensinado a
comprar e usar cura, e `power_last 1.36 → 1.26` (250 runs): **vitória 40% ✅**,
**Ativos 1,84 ✅** (o Orvalho barato destravou essa métrica), reações 30,5 ✅,
cozinha 76% ✅ — **quatro alvos verdes**. Primeiro combate 100%, mortes escalando do
nó 3 ao 7. Duração 14,1 s e timeout 7% seguem fora.

### 5.18 Revisão 31/08 — as magias de mira, e por que o teste não pegou

> "novamente Orvalho Curativo e bola de fogo não estão funcionando, faça um fix
> permanente disso pois as magias de escolher alvo não estão funcionando"

**A causa.** O clique no campo era resolvido por um `match` com dois casos escritos
à mão:

```gdscript
match String(a.get("aim", "")):
    "enemy_area": ...
    "enemy_single_pick_element": ...
```

O Orvalho e o Círculo de Seiva são `ally_area`. **Nenhum caso batia**, então o clique
não fazia nada: a magia ficava armada para sempre e nunca saía. Todo Ativo novo com
um modo de mira novo nascia quebrado, e em silêncio.

**A correção não é adicionar `ally_area` à lista** — seria consertar dois Ativos e
deixar a armadilha montada. A mira agora decide pela **forma** do modo: termina em
`_area` → lança no ponto; termina em `_pick_element` → abre o seletor; começa com
`all_` → lança direto; qualquer outro → alvo único. Um modo novo passa a funcionar
sem tocar nesse código.

**Segunda blindagem: o clique chega por dois caminhos.** Ele dependia do
`_unhandled_input`, que só recebe eventos que *nenhum* Control consumiu — bastava um
painel novo no caminho para a mira morrer sem ninguém perceber (e esta sessão
acrescentou três painéis). O FieldView agora emite `clicked` pelo `_gui_input`, que é
entregue ao Control sob o cursor. Os dois caminhos coexistem.

#### Por que o teste anterior passou verde com o jogo quebrado

Ele chamava `AbilityRunner.run()` **direto** — pulava a camada de mira, que era
exatamente onde estava o defeito. Duas vezes seguidas o mesmo tipo de bug escapou
por isso.

O teste novo instancia a **tela de combate de verdade**, aperta o botão do Ativo
(`_arm`) e clica no campo (`aim_at`), como uma pessoa faria. E percorre
**`Db.actives` inteiro**: um Ativo novo com um modo de mira novo é coberto
automaticamente, sem ninguém lembrar de escrever caso de teste. Para cada um exige
que **tenha efeito** (cura, dano, aura ou mudança de afinidade) e que **cobre
Energia**.

Resultado, com os números que o teste imprime:

| Ativo | Mira | Efeito medido |
|---|---|---|
| Meteoro | `enemy_area` | 360 de dano, 12 UA |
| Chuva Torrencial | `all_enemies` | 15 UA |
| Bênção Aurora | `all_allies` | 1147 de cura |
| Prisma de Reescrita | `enemy_single_pick_element` | afinidade trocada |
| Orvalho Curativo | `ally_area` | 1009 de cura |
| Círculo de Seiva | `ally_area` | 1835 de cura |
| Improviso | `all_allies` | 2065 de cura |

**Bônus:** `FieldView.screen_of(u)` é novo — devolve onde a unidade está *desenhada*,
que é o ponto em que `unit_at()` a encontra. O teste clicava em `u.pos` e errava por
causa da interpolação.

**O bot também mirava errado:** `_best_aim` devolvia sempre o centroide inimigo,
então a cura de área era lançada em cima dos inimigos — o Ativo saía, a métrica
contava, e ninguém era curado. Agora respeita o lado, e para cura mira nos três
aliados mais feridos.

**Balanceamento** (200 runs, agora com os Ativos realmente funcionando): vitória
41% ✅, Ativos 1,89 ✅, reações 30,8 ✅, cozinha 77% ✅ — quatro alvos verdes.

### 5.19 Revisão 31/08 — os ícones vazando da Cozinha

> "a UI da loja de comida ainda tá errada e mal calibrada, com os ícones vazando"

**Causa.** Os cartões da Cozinha eram um `Button` com os filhos ancorados no
retângulo dele. Isso quebra de dois jeitos ao mesmo tempo:

1. **Filho ancorado ignora o `content_margin` do StyleBox.** A moldura 9-patch
   reserva 12 px de borda, o conteúdo começava em x=0, e o ícone do prato saía por
   cima da borda — os "ícones vazando".
2. **`Button` não cresce com o conteúdo.** Uma descrição de duas linhas transbordava
   a altura fixa de 84 px.

**Correção: `CardButton`** (`src/ui/card_button.gd`), um cartão clicável que
dimensiona pelo conteúdo *e* respeita a margem. É um `PanelContainer` — container,
logo honra o `content_margin` e mede os filhos — com um `Button` transparente
ancorado por cima, fora do fluxo, só para capturar o clique. Padding de 18/12 em vez
de 12/8: a moldura tem grão nas bordas e 12 px deixava o ícone visualmente colado.

Aplicado na Cozinha e no `PickerOverlay`, que tinham o mesmo padrão. A Loja já usava
`UI.card()` (PanelContainer) e não sofria do problema.

**Detalhe de alinhamento:** o ícone passou de centralizado no cartão para alinhado à
primeira linha. Centralizado, ele "flutuava" para baixo nos pratos de descrição
longa, e a coluna de ícones perdia o alinhamento entre cartões de alturas diferentes.

**Armadilha de construção registrada:** a primeira versão montava o corpo do cartão
no `_ready()`, que só roda ao entrar na árvore — quem chamasse `card.body` antes de
anexar pegava `null`. O `CardButton` sai da fábrica já montado.

### 5.20 Revisão 31/08 — os itens na tela de preparação

> "na tela pré combate deixe mostrando também os itens atuais que o jogador tem,
> mostrando a barra lateral para que ele também as analise"

A doca de itens existia só no combate. Mas é **antes** de entrar que os itens
importam: qual Prismon carrega o quê e quais relíquias estão em jogo fazem parte da
leitura da build tanto quanto a Ressonância e a formação prevista.

A doca ganhou um **modo detalhado** (`detailed`), usado só na preparação. No combate
ela segue uma tira de 74 px de ícones — espaço é caro ali e o jogador só precisa
lembrar do que tem. Na preparação ela abre para 224 px e mostra, por item, o **nome
completo e o retrato do dono**, com o nome dele na cor do elemento.

A diferença importa: "analisar" não é "reconhecer o ícone". Saber que a Presa Rachada
está no Apollo e não no Sheep é o que muda a decisão — e essa resposta não pode
depender de passar o mouse em cada slot.

### 5.21 Revisão 31/08 — a tela de Sinergias

O autor desenhou uma tela e mandou o mockup. O grafo em pentágono foi substituído
por ela, e a troca é de fundo, não de estilo: **o grafo mostrava QUE havia reações
entre os elementos da equipe; nunca o que cada uma FAZ, nem o que falta destravar.**
Quem não decorou o §6 do GDD olhava linhas coloridas.

Três blocos, três perguntas diferentes:

| Bloco | Responde |
|---|---|
| **Matriz de reação** | o mapa: toda dupla possível, o que já sai (losango aceso) e o que existe mas falta energia |
| **Sinergias ativas** | o que ESTA equipe produz agora, com o efeito escrito, o tipo (amplifica/transforma/controle), o multiplicador e o custo de aura |
| **A um passo** | o que destrava com UM elemento a mais — e qual. É o bloco que orienta o próximo recruta |

Os chips de **energias em campo** filtram os cartões ao clique.

**As 8 reações ganharam `text` nos dados.** Antes esse conhecimento só existia no
código e no GDD; agora a tela pode explicá-las, e a explicação é conteúdo editável.

#### Três lições de layout, todas medidas

Esta tela não coube na primeira, nem na segunda tentativa. Em vez de adivinhar,
instrumentei um probe que imprime `get_combined_minimum_size()` de cada nó — e o
culpado era sempre o mesmo mecanismo: **largura mínima subindo pela árvore**.

| Fonte | Mínimo que impunha | Correção |
|---|---|---|
| Chips numa linha só (`HBoxContainer`) | **1541 px** | `HFlowContainer` — quebram linha |
| Label sem autowrap ("consome a aura inteira" ×2 cartões) | **1049 px** | texto curto ("aura toda", "2 UA"); o longo foi para o tooltip |
| `HFlowContainer` dos cartões | decidia 3 colunas no primeiro quadro e cortava o terceiro | `GridContainer` de 2 colunas — o número de colunas é decisão, não consequência |

**A regra que fica:** uma `Label` sem `autowrap_mode` reporta o texto INTEIRO como
largura mínima, e `clip_text` não muda isso. Texto longo dentro de painel lado a
lado é uma armadilha de layout, não um detalhe de escrita.

Mínimo do painel: **1073 → 711 px**. A coluna de referência voltou a caber, com a
matriz no topo e a doca de itens embaixo.

**A Ressonância foi absorvida:** ela dizia o mesmo número que os chips de energia —
quantas unidades de cada elemento a equipe tem. Os pips de Eco/Coro passaram para o
chip, e o bloco duplicado saiu da coluna de leitura.

### 5.22 Revisão 31/08 — dois níveis de leitura

> "essa informação deve ser visualizada de forma opcional, como um botão…
> no geral elas só devem ser representadas por ícones… esses quilos de texto
> ainda estão muito densos"

O painel de Sinergias nasceu fixo na tela de preparação e ficou denso demais:
**oito cartões de texto competindo com a decisão de entrar no combate.** A crítica
está certa e a correção é uma regra, não um ajuste:

> **O que se lê de relance fica na tela; o que se lê com calma abre por botão.**

**Nível 1 — a tira (`SynergyStrip`).** Um par de losangos por reação, os dois
elementos que a produzem, e o nome. Sem parágrafo, sem multiplicador, sem custo de
aura. Oito sinergias cabem em duas linhas curtas. O efeito completo continua no
tooltip de cada chip, para quem passar o mouse.

**Nível 2 — o painel (`SynergyView`).** Virou overlay com véu e FECHAR, aberto pelo
botão *Analisar Sinergias*. Lá dentro cabe tudo com folga: a matriz completa, os
cartões com efeito, tipo, multiplicador e custo, e o "a um passo".

**O espaço liberado virou o Rancho.** A equipe aparece de pé no centro da
preparação, como na tela de escolha — ver quem vai lutar antes de mandar lutar. A
tela deixou de ser um painel de dados e voltou a ser um lugar.

### 5.23 Revisão 02/09 — as criaturas se recuperam sozinhas

> "faz as criaturas sempre regenerarem vida quando acabar batalha e tira as coisas
> que recupera vida fora de batalha que vai ser inútil" — Arthur

**Reverte a economia de sobrevivência de 31/08 (§5.17)**, e a consequência que ele
apontou está certa: com regeneração total, item que cura fora de combate não tem
função nenhuma. Não dava para manter as duas coisas.

O que saiu:

| Saiu | Era |
|---|---|
| `data/consumables.json` | 5 consumíveis de cura |
| Bolsa (`Run.bag`) e a fileira dela na preparação | usar consumível antes de entrar |
| Consumíveis e **Descanso** na Loja | as duas fontes de cura pagas |
| Drop de consumível no pós-combate | ~42% de chance |
| Ativo **Improviso** | gastava um item da bolsa no meio da luta |

O que **fica**: a cura de área dentro do combate (Orvalho, Círculo de Seiva, Bênção
Aurora). Dentro de uma batalha o dano continua importando — só não atravessa mais
para a seguinte.

#### O detalhe que quase se perdeu

A cura passou a acontecer **logo depois do combate e ANTES do momento de evento**.
Se viesse depois (como estava, em `_after_node`), o dano que um evento de acaso
cobra seria apagado junto — e *"a fenda desmorona, equipe perde 22% do HP"* viraria
texto decorativo. Os eventos de risco continuam custando sangue; o combate seguinte
é que começa limpo. Há um teste guardando isso.

#### Balanceamento

Praticamente inalterado (200 runs): vitória **39% ✅**, Ativos **1,89 ✅**, reações
**30,9 ✅**, cozinha **76% ✅** — os mesmos quatro alvos verdes. A explicação é que
o Éter que ia para consumíveis agora vai para itens permanentes, e uma coisa
compensa a outra. Não recalibrei nada.

### 5.24 Revisão 02/09 — teste de fonte: m6x11 e m6x11plus

O autor mandou duas fontes. Testadas contra a atual em três eixos: **cobertura de
glifos**, **nitidez por tamanho** e **licença**.

#### m6x11 está fora

124 glifos e **nenhum acento**: "Coração", "REAÇÕES", "Vínculo" e "Éter" quebram
inteiros. Só funcionaria com fallback, e aí metade das palavras portuguesas sairia
noutra fonte. Descartada.

#### m6x11plus passa — mas com uma condição

236 glifos, **todos os acentos**. A condição é que **fonte de pixel só fica nítida
em múltiplos inteiros do corpo nativo**. A m6x11 é desenhada para 11 px, então os
tamanhos limpos são 11 / 22 / 33 / 44 — e 11 é ilegível. Nos tamanhos que a escala
usava (13, 15, 19, 26) o traço borra visivelmente.

`UI.fs()` ganhou uma tabela de *snap* que trava tudo em múltiplos de 11. Equivalência
medida: **22 px de m6x11plus ≈ 15–19 px da anterior**; 33 ≈ 26; 44 ≈ 44.

**O custo:** sobram **três degraus** de tamanho (22/33/44) contra os cinco da escala
antiga. F_SMALL e F_BODY colapsam ambos para 22. Na prática funcionou — as telas
ficaram até mais limpas, porque a hierarquia passou a se apoiar em cor e peso em vez
de em diferenças de 2 px que ninguém percebia.

#### O achado que decidiu: licença

Lendo o *name table* das próprias fontes (name ID 13):

| Fonte | Licença embutida |
|---|---|
| **m6x11plus** | **"Free to use with attribution"** — Daniel Linssen |
| Pixel Sans Serif (a que estava em uso) | **"FontStruct Non-Commercial License"** |

Isso **confirma e agrava** o alerta de 31/08: a fonte que o jogo usava não é só
"free for personal use" no dafont — a restrição não-comercial está gravada na fonte.
A m6x11plus resolve o problema e ainda é mais nítida. Aplicada.

#### Um erro meu, corrigido

Eu vinha dizendo que a Pixelify Sans era a fonte dos símbolos (★ ⚡ ❄ ◆ →). **Ela
também não os tem** — nenhuma das quatro tem. Eles vêm de um fallback do sistema
operacional, o que significa que podem mudar de aparência entre máquinas. Registrado
em `assets/CREDITOS.md` como risco de consistência visual.

**Para reverter:** `UI.PIXEL_SNAP := false` e trocar o caminho em `prisma_theme.gd`.
Duas linhas.

### 5.25 Revisão 02/09 — o nome, a grade da fonte e o vazamento

**O jogo se chama PRISMON.** Trocado na tela de título, no HUD, no nome da janela
(`project.godot`) e nas mensagens de erro. O Ativo *Prisma de Reescrita* continua com
o nome dele — é outra coisa.

#### A grade da fonte estava errada

Eu tinha assumido que o corpo nativo da m6x11plus era 11 px, pelo nome. **A métrica
diz outra coisa:** `unitsPerEm = 1152` com 64 unidades por pixel da grade, ou seja
**18 px por em**. O "11" do nome é a altura da caixa alta (704 ÷ 64 = 11), não o
corpo.

Com a grade errada, quase tudo ficava preso em 22 px — pequeno demais para leitura
corrida, que foi o que o autor apontou. A escala nova usa múltiplos de 9 (meio pixel
da grade):

| Papel | Antes | Agora |
|---|---|---|
| rótulo | 22 | **18** |
| corpo e pequeno | 22 | **27** |
| título de bloco | 33 | **36** |
| título de tela | 44 | **54** |

Quatro degraus de verdade em vez de três colapsados, e o corpo 23% maior.

#### O vazamento

Os cartões de recruta ainda eram `Button` com filhos ancorados — o padrão que já
tinha causado os ícones vazando na Cozinha (§5.19). Com a fonte maior o defeito
reapareceu: "desbloqueia Supercondução · Congelar" saía pelas bordas do cartão.
Convertidos para `CardButton`, que mede o conteúdo e respeita a moldura; agora o
texto quebra linha em vez de vazar.

**Regra reforçada:** nenhum cartão clicável deve ser um `Button` com filhos
ancorados. É a terceira vez que esse padrão quebra algo.

## 6. Revisão de 15–16/09/2026 — a leva dos 121 achados

Sete frentes trabalharam em paralelo sobre `docs/REVISAO_GERAL.md`, e esta seção fecha a
conta. Segue a regra da casa: **a medição ao lado da decisão**. Todo número abaixo é de
`--runs=1000` salvo onde diz o contrário, com margem de ±3,0 pontos na taxa de vitória.

### 6.1 O placar, antes e depois

| Métrica (§17.4) | Alvo | Antes | Depois |
|---|---|---|---|
| Taxa de vitória da run | 35–45% | 38% | **40%** ✅ |
| Ativos por combate · lutas normais | 1.5–2.5 | 2,21 | **2,05** ✅ |
| Reações por combate · build de reação | 25–45 | — (a faixa não podia falhar) | **32,9** ✅ |
| Relógio · lutas normais | < 6% | 5,6% (misturado com o chefe) | **5,3%** ✅ |
| Runs que cozinharam | > 70% | 85% | **91%** ✅ |
| Duração de combate (mediana) | 28 s ±21% | 12,6 s ❌ | 13,1 s ❌ |

E o que a revisão pediu para medir e ninguém media:

| Pergunta | Antes | Depois |
|---|---|---|
| Vitória nos nós 2 e 4 | 100,0% e 99,5% | **98,0% e 98,0%** |
| Fração das mortes nos 4 primeiros passos | 0,8% | **8,9%** |
| Sobra de Éter ao fim (mediana) | 119 de 258 que entraram | **30 de 196** |
| Recusas por falta de Éter | **0 / 0 / 0** em 364 visitas | **407 itens · 635 relíquias · 43 pratos** |
| Combates sem **nenhum** Ativo disponível | 15% — e **52% no nó 2** | **0,7% — 4,1% no nó 2** |
| Vitória por espécie inicial | sheep 42,0% × coalla 27,25% | **sheep 44,3% × coalla 35,8%** |

Vitória por nó (denominador = quem chegou nele): 100 · 98,0 · 98,5 · 98,0 · 95,9 · 92,3
· **80,5** · 90,7 · 64,8.

### 6.2 As cinco decisões que o autor delegou

**(a) `energy_start` em vez de mexer em `hp_scale`.** O achado era que 15% dos combates
não ofereciam **um Ativo sequer**, e no passo 2 eram 52% — a única agência do jogador
dentro da briga chegava depois de a briga estar decidida (mediana do primeiro Ativo
disponível: 5,8 s numa luta de 12,6 s). O botão óbvio era alongar o combate, e ele é
justamente o que move a vitória em 23 pontos. A decisão foi **mudar a distribuição, não
a média**: `energy_start = 20` adianta ~7,7 s de acúmulo, e `energy_per_second` desceu
de 2,6 para 1,6 para o orçamento total da briga ficar quase igual. Resultado: Ativos por
combate 2,21 → 3,04 → **2,49** (depois 2,05 com o resto da leva), e combates secos de
15% para **0,7%**.

**(b) O Acaso volta ao passo 6, e o Poder passa a dar duas escolhas.** Os 7 eventos de
`random_events.json`, a tela `ScreenChance` e o bloco `momentos.acaso` inteiro eram
**inalcançáveis**: `acaso` não aparecia em `evento_apos_combate`. Conteúdo pronto que
nenhuma run via. Ele tomou o lugar do **segundo** momento de Poder — e aí 1 Ativo
inicial + 1 aprendido parava em 2, com `max_actives = 3` inalcançável. Daí
`momentos.poder.escolhas = 2`: o mesmo momento oferece duas vezes, e a segunda oferta já
vem sem o que o jogador acabou de levar. Os pisos que o smoke test cobra continuam de
pé (3 recrutas nos passos 1/3/7, 2 lojas nos 4/8). O Acaso foi de **0% para 84%** das
runs.

**(c) A economia foi apertada dos DOIS lados.** Entravam 258 de Éter por run e sobravam
119 — 45% de tudo que entrou. Em 4.212 itens, 538 relíquias e 2.622 pratos oferecidos, o
número de compras recusadas por falta de Éter era **zero nas três categorias**. O
gargalo não era preço, era **oferta**: não havia o que comprar. Por isso a correção
cortou a renda *e* abriu o ralo no mesmo movimento — `ether` 20–32 → 13–22, ofertas da
banca 3 → 4, Comum 11 → 15, Raro 24 → 32, relíquia 35% a 38 → 55% a 34. E a lição que se
repete: **mexer na economia é mexer na dificuldade.** Sozinha, ela derrubou a vitória de
38,0% para **20,8%**, e foi preciso recalibrar `power_last` (1,05 → 0,92) e `boss_power`
(4,5 → 3,5) para voltar aos 40%. As 4 ofertas foram medidas à parte: com 3, a sobra
média volta a 41 e as recusas de item caem de 6,8% para 1,3%. O ralo precisa de tamanho,
não só de profundidade.

**(d) Consertar os Coros ANTES de tocar em espécie.** A Coalla vinha 15 pontos abaixo do
resto do elenco, e a tentação era subir a ficha dela. Mas três defeitos estruturais
mascaravam o problema: o item de assinatura do Pinto-Raio entregava metade do texto, o
`team_ult_gain` de item nunca chegava ao combate, e os dois Totens faziam as auras do
**inimigo** durarem mais em cima de quem os equipava — sinal invertido. Consertados
primeiro, o leque caiu sozinho. Só **depois** a Coalla subiu (PE 70 → 88, ATK 20 → 26),
e ainda assim porque a raiz estava medida: a cura escala com ATK e o HP escala com
`hp_scale` 3.7, então o único Papel cujo trabalho é recompor HP devolvia ~30 HP contra
poços de 1500–2900. `support_heal_scale = 1.8` (2,0 estourava o relógio em 6,3%).
Coalla 27,25% → **35,8%**; leque do elenco 14,75 → **8,5 pontos**.

**(e) "O Vidro do Domador".** A direção de arte ganhou nome porque virou regra
verificável: matéria neutra, canto cortado, sombra dura de 3 px, **cor só no feixe da
aresta**. A raiz do problema era mecânica — `modulate_color` num `StyleBoxTexture` tinge
a peça inteira, então 16 chamadas de `UI.panel` **renderizavam nada**. Cada célula passou
a sair em duas camadas (matéria + máscara RGB) e `UI.frame()` as compõe. Miolo do painel
de Fogo: luma 13,4 (1,5 *abaixo* do fundo) → **28,5**; aresta 135,8 → 71,5. Como a regra
é verificável, virou cerca: `tools/lint_ui.py` proíbe `modulate_color` fora de `ui.gd`,
proíbe a fonte 27 e cobra `UI.BTN_H = 58` em todo botão.

### 6.3 O achado novo: os dois alvos do §17.4 se contradizem

A mediana de combate é a única métrica fora do alvo desde que o slice existe, e a
explicação que se dava era "só `hp_scale` move isso". **Mexi.** A mediana de 28 s *é*
alcançável só com dados — `hp_scale` 3.7→7.9, `max_duration` 45→96 (o mesmo fator, senão
o relógio colhe o que a duração plantou), `energy_per_second` 1.6→0.6,
`energy_per_reaction` 1.0→0.5:

| Configuração | Mediana | Vitória | Ativos | Reações | Relógio |
|---|---|---|---|---|---|
| **[A]** atual (1000 runs) | 13,1 s | 40% | 2,05 | **32,9** ✅ | 5,3% |
| **[B]** hp 7.9 · dur 96 · eps 0.6 · epr 0.5 (400) | **26,9 s** ✅ | 32% | 2,24 | **66,3** ❌ | 4,4% |
| **[C]** [B] + `transform_consume_ua` 2.0→3.5 (400) | 27,5 s | 32% | 2,21 | **66,4** ❌ | 4,6% |
| **[D]** [B] + `max_reaction_chain` 3→1 + `aura_cap_ua` 8→4 (300) | 27,8 s | **36%** | 2,29 | **66,5** ❌ | 5,2% |

Em [D] **quatro das cinco métricas fecham ao mesmo tempo** — inclusive a mediana. O que
não fecha é reações. E não há alavanca: a **taxa** é invariante — 2,51/s em [A], 2,46 em
[B], 2,41 em [C], 2,39 em [D]. Três alavancas diferentes de `tuning.json` mexeram **0,2
reação no total**, porque nenhuma delas governa a taxa. Quem governa é o intervalo de
ataque das espécies, o `ua_per_hit` e o tique de aura das arenas — conteúdo, não escalar.

> Um teto de 45 reações equivale a um combate de 45 ÷ 2,45 = **18,4 s**; um piso de 25, a
> **10,2 s**. A faixa 25–45 do §17.4 **descreve um combate de 10 a 18 s**, enquanto a
> mediana de 28 s do mesmo §17.4 pede **69 reações**. Os 13,1 s de hoje caem no meio da
> janela que o alvo de reações permite.

Por isso **[A] ficou de pé**. Escolher a mediana de 28 s é escolher baixar a taxa de
reação em um terço, e isso é decisão de desenho do autor — não de calibragem. A tabela
vive em `tuning.json → targets._duracao_x_reacoes_doc`, ao lado do alvo que ela
qualifica.

### 6.4 O que entrou de sistema

- **Áudio.** Autoload `Som` com API por nome (`Som.tocar("golpe")`), 14 efeitos e 7
  laços de arena, pool de vozes com roubo da mais velha e anti-metralhadora por quadro —
  40 chamadas de `tocar("golpe")` num quadro viram **1 voz**. Os 21 `.wav` são
  **placeholders gerados** por `tools/gerar_sons.py`, só com a biblioteca padrão do
  Python e determinísticos por semente (md5 idêntico em duas execuções). **Headless é
  mudo por construção**: `Som` detecta o `DisplayServer` "headless" e sai no primeiro
  `if`, para ferramenta de lote nunca abrir dispositivo de áudio. Três volumes nas
  Configurações, ligados no mesmo quadro em que são arrastados.
- **Save de run** em `user://run_save.cfg`, gravado ao fim de cada nó e ao sair pela
  pausa; o título oferece **CONTINUAR — PASSO n**. O **par de nós não é salvo de
  propósito**: ele é derivado de semente + índice, e guardá-lo seria guardar um cache que
  pode discordar da fonte.
- **Menu de pausa no ESC** (só dentro da run), com as Configurações abrindo *dentro* do
  véu e devolvendo o jogador onde estava.
- **A auto-pausa do §21.2 foi retirada** e substituída pela **dica de intervenção**: uma
  vez em toda a run, não uma vez por combate. Pausar sozinho interrompia justamente a
  pergunta que o slice existe para responder.
- **A preparação virou três faixas** (cabeçalho / corpo de três colunas / rodapé), com a
  coluna nova **CONTRA ESTE BANDO** ocupando 430 px que antes eram vazio.
- **A tela de fim mostra a semente** num campo copiável, e soma `Run.history`: combates
  vencidos, tempo em briga, reações, dano causado e sofrido, Ativos e o maior golpe com o
  autor.

### 6.5 O que a cerca passou a cobrar

O smoke test foi de 230 asserções com 6 falhas para **257 com 0**. As três cercas novas
merecem registro porque cada uma pegou um defeito real no dia em que foi escrita:

1. **Cobertura de chave.** Toda chave de `mods` (37) e toda folha de `tuning.json` (122)
   precisa aparecer entre aspas em algum `.gd`. Array conta como folha — array morto é
   tão morto quanto número morto. Pegou as 8 chaves de `targets`, que eram decorativas.
2. **Toda peça muda um número.** Para cada um dos 47 itens/relíquias/ressonâncias, monta
   **duas runs idênticas** (3 combates completos + bancada dirigida) e falha **nomeando**
   a peça cuja impressão digital não mudou. Acusou 5 na primeira execução; 3 eram defeito
   do teste e **2 são reais** (ver 6.6).
3. **O kit tinge.** Para cada uma das 10 células, compõe `UI.frame(célula, Fogo)` e
   `UI.frame(célula, Água)` e falha nomeando a que sair com os mesmos bytes.

### 6.6 O que fica em aberto, medido

- **`rx_dmg_add` não vale para reações AMPLIFY.** A Lente de Forja e a Chave de Vapor não
  mudam **número nenhum** do combate — o smoke test as nomeia. A causa: o bônus
  multiplica `res.reaction_damage`, que só é consumido no ramo `TRANSFORM`; o dano de uma
  amplify sai de `res.damage_mult` aplicado dentro de `strike()`, antes de
  `_apply_reaction` rodar. É conserto em `combat_sim.gd` e move balanceamento.
- **`combustao_cap_mult` (Coro de Fogo) e `encharcado_decay_mult` (Eco de Água) caem no
  lado errado.** `begin()` os escreve nas unidades do **próprio** lado: o Coro de Fogo
  faz a Combustão que os inimigos aplicam em **você** empilhar até 16, e o Eco de Água
  faz o Encharcado durar 50% mais **em cima de você**. Mesma classe do sinal invertido
  dos Totens, que já foi consertada.
- **A build de RESSONÂNCIA não tem medição.** O grupo sai com `n = 0` em 7.310 combates:
  o bot recruta maximizando elementos distintos, e a build exige Peso 4 (Coro), ou seja 4
  corpos do mesmo elemento num teto natural de 5. A faixa 5–12 do §17.4 continua sendo um
  travessão, e sair dele exige um bot alternativo (`--build=ressonancia`), não um ajuste.
- ~~**Não dá para jogar uma run sem mouse.**~~ **Resolvido em 16/09** — ver §6.9. Eram
  três pontas, não duas: `focus_mode` no `CardButton`, uma moldura de foco visível no
  Theme (era `StyleBoxEmpty`, ou seja, um botão alcançado pelo teclado não mostrava
  *nada*), e alguém para **receber** o foco quando a tela abre. A terceira ponta é a que
  três agentes não viram, e sem ela as outras duas não servem para nada: o jogador aperta
  a seta e não acontece coisa alguma, porque nenhum controle tem foco para ceder.

---

### 6.9 O fecho: as pendências que sobreviveram ao lote (16/09)

Sete agentes trabalharam em paralelo com **propriedade de arquivo disjunta** — cada um só
podia escrever na própria lista, porque não havia merge e não havia controle de versão.
Funcionou para o que era local e produziu um efeito colateral previsível: **todo defeito
que atravessava dois donos ficou parado**, registrado como pedido e nunca executado. Três
agentes seguidos recusaram o mesmo conserto de teclado, cada um pelo motivo certo.

Quando o lote fechou, ninguém era dono. Estas foram fechadas depois:

| O que | Onde | Por que tinha ficado |
|---|---|---|
| **Eco de Água e Coro de Fogo caíam no lado errado** | `combat_sim.gd` (begin/put_aura), `sim_unit.gd` | Move balanceamento, e o agente já tinha gasto a margem de medição |
| **`rx_dmg_add` não valia para reações AMPLIFY** | `combat_sim.gd` (`_resolve_reaction`) | A regra da tarefa proibia mexer em código durante a calibragem |
| **Navegação por teclado** | `card_button.gd`, `prisma_theme.gd`, `main.gd` | Conserto de três pontas em três donos diferentes |
| **Trilho da barra clareado 1,9×** | `prisma_bar.gd`, `build_ui_sheet.py` | Par acoplado em dois donos |
| **Volume de áudio no teto** | `som.gd`, `gerar_sons.py`, `screen_options.gd` | Reportado pelo autor com o lote ainda rodando |

**As duas ressonâncias de aura.** `combustao_cap_mult` e `encharcado_decay_mult` eram
escritos em `u.aura` do **portador**, dentro de `begin()`. Esse estado pertence a quem
*recebe* a aura — então o Coro de Fogo fazia a Combustão que **os inimigos** jogavam em
você empilhar até 16, e o Eco de Água fazia o Encharcado **deles** durar 50% mais em cima
da sua equipe. Os dois liam como bônus e cobravam como maldição. Os textos não deixam
dúvida sobre a intenção: *"Encharcado dura +50%"* e *"Combustão **de aliados** empilha até
2×"*. É a mesma classe do sinal invertido dos dois Totens, já consertada no lote — e agora
os quatro viajam pelo mesmo caminho, em `src`, para quem **aplica**.

**`rx_dmg_add` e as AMPLIFY.** Era ordem de execução, não dado faltando:

```
653  var res := _resolve_reaction(...)
656  dmg *= res.damage_mult          <- o AMPLIFY é consumido AQUI
667  _apply_reaction(...)            <- o bônus era aplicado AQUI, tarde demais
```

E ele só mexia em `reaction_damage`, que é **zero** numa AMPLIFY (ela multiplica o golpe
em vez de causar dano próprio). Os dois itens do jogo que nomeiam uma reação
amplificadora — Lente de Forja (Derretimento) e Chave de Vapor (Vaporizar) — eram
decoração. A aplicação foi para dentro de `_resolve_reaction`, que é o funil único por
onde os dois call sites passam, e agora atinge os dois campos. **Foi o bloco
`[cobertura de dados]` que acusou os dois pelo nome** — a cerca pegou o que oito revisores
não tinham pegado, que era exatamente o motivo dela existir.

**Áudio.** Os efeitos saíam normalizados entre 0,52 e 0,95 de pico (o crítico a −0,4 dBFS,
encostando no teto do 16 bits) e os três barramentos nasciam em 1,0. Um combate com 33
reações somava vozes já quentes. Entrou um `TRIM` global no gerador, que multiplica
**todos** os picos de uma vez — a proporção entre os sons fica intacta, e só o nível
desce. Pico do banco hoje: **−7,4 dBFS**; com os barramentos, ~13 dB abaixo do que era.

E um defeito que o volume escondia: `_sem_saida()` só checava `--headless`, mas
`tools/screenshots.tscn` e as sondas rodam **com janela** — precisam de janela, é o ponto
delas. Elas passaram a tocar som em cima de quem estivesse usando o computador, em rajada,
sem nada na tela explicando de onde vinha. A regra agora é o **caminho da cena principal**:
qualquer coisa sob `res://tools/` nasce muda, e ferramenta nova entra na regra sozinha.

**A sonda de teclado.** `tools/teclado_probe.tscn`, 13 asserções. Ela empurra
`InputEventAction` pelo `Input` — o caminho do jogador — em vez de chamar `grab_focus` ou
o método na mão, e depois pergunta ao viewport quem está com o foco. E **ela se
auto-verifica**: `_autoteste` monta um `CardButton`, quebra o `focus_mode` dele de
propósito e confere que a checagem reprova. Sem isso uma sonda quebrada diz OK para
sempre — já aconteceu neste projeto, com o probe de tooltip que mentiu sobre um conserto.

O combate fica **de fora** do foco automático, de propósito: lá as teclas são do jogo
(1/2/3, ESPAÇO, TAB) e um botão focado come ESPAÇO e TAB antes de o jogo ver. Era o
defeito relatado ("clicar qualquer botão desliga ESPAÇO e TAB"); dar foco na entrada o
reintroduziria sem nem precisar de clique. A sonda cobra isso numa asserção própria.

**O que a cerca mostra hoje:** `smoke_test` verde com o bloco `[cobertura de dados]` de
lista de dívida **vazia**, `lint_ui` verde sem dívida herdada, `validate_data` verde.

---

### 6.10 O Acaso passa a cobrar o que voce equipou (16/09)

O autor apontou tres coisas na mesma frase: *"quando o personagem cavar por uma reliquia
mostre qual foi a reliquia que o personagem ganhou ali"* e *"isso de a equipe receber dano
e transferir para os proximos combates foi removido, entao nas chances de perder algo
coloque uma chance de perder um item ou uma comida equipada"*.

**O engano que veio antes.** No lote dos 121 achados eu mandei um agente **ligar**
`run.heal_between_nodes_pct`, que estava em `tuning.json` sem ninguem ler. O relatorio
listou a chave como dado morto, e dado morto normalmente e esquecimento. Aqui nao era: a
cura total e **decisao registrada** (secao 5.23, 02/09) e foi ela que derrubou os
consumiveis, a Bolsa, o Descanso da Loja e o Improviso. Uma chave sem leitor e uma regra
que o autor removeu de proposito sao **indistinguiveis de dentro de um grep** — e a cerca
de cobertura de dados, que existe justamente para achar chave sem leitor, nao sabe a
diferenca. Foi ela, alias, que acusou a chave orfa depois que eu a removi.

Revertido: `heal_between_nodes()` volta a curar 100%, a chave saiu do `tuning.json` (e no
lugar dela ficou a explicacao de por que nao existe), e a assercao do `smoke_test` voltou a
ser **numero literal** em vez de formula. Uma formula que le do dado aceita qualquer valor
em silencio; o literal reprova a mudanca e obriga quem a fizer a vir ler a secao 5.23.

**O risco de mentira.** Com cura total, o `damage` do Acaso **nao custava nada** — a equipe
voltava inteira na briga seguinte. A manchete de risco que o lote tinha acabado de criar
media exatamente esse nada, e dizia a verdade literal enquanto enganava. Seis ops `damage`
viraram `perde_equipado`: tira um **item** ou um **prato** ja equipado de alguem, sorteado,
e isso e permanente. Arranhao leve (`pct < 0,18` no dado antigo) tira so prato; tombo pode
tirar item.

**O defeito que a propria correcao criou.** Trocada a op, a previa ficou mentindo em dois
lugares ao mesmo tempo: a manchete passou a dizer *"SEM RISCO — nenhum desfecho custa HP"*
(verdade literal, agora enganosa) e o desfecho ruim ficou **sem etiqueta nenhuma**, porque
`_op_texto` nao conhecia a op nova. Seria **pior** que o defeito original: trocar um risco
falso por um risco invisivel. Hoje le `RISCO 25% de perder um item ou prato equipado`.

**A reliquia.** O nome ja estava na tela — marcador cinza de corpo 15 no meio de uma lista
onde o `+18 Eter` tinha o mesmo peso. A reliquia e a peca mais forte do jogo e 42% das runs
terminam sem nenhuma. O conserto nao foi aumentar a fonte: foi **parar de devolver
string**. `_apply_op` descrevia o ganho em prosa e a tela so sabia repintar a prosa; agora
ele devolve tambem o QUE foi ganho, com tipo e id, e a tela monta um cartao com icone, nome
na cor da peca e **o que a peca faz** — a informacao que decide se aquilo muda a run.

**A sonda que faltava.** `tools/acaso_probe.tscn`. `screenshots.tscn` fotografava o Acaso
**em repouso**, antes da decisao — e os dois momentos interessantes daquela tela vem depois
dela. Foi por isso que o cartao pode nascer errado sem ninguem ver, e foi a primeira
captura da sonda que acusou a previa velha. Na estreia a imagem saiu com a fonte do
sistema e por um instante pareceu defeito da tela: era a sonda sem `PrismaTheme`.

**Medido de novo depois da reversao** (1000 runs): vitoria **40%**, relogio normal 5,2%,
ativos 2,05, reacoes 33,0, cozinhou 89%, mediana 13,1 s (o alvo unico que segue fora, ver
6.3). Sao os mesmos numeros de antes dentro da margem de +-3,0 pontos — a cura parcial
tinha passado sem deixar marca na taxa de vitoria, o que so reforca que ela nao estava
pagando por si mesma.

---

### 6.11 A gaveta que empurrou o rodape para fora da tela (16/09)

Autor, depois do lote de polimento: *"o botao de ver bando inimigo projetando pra baixo
bugou a visualizacao toda, o botao fugiu de alcance e nao foi mais possivel ver nada"*.

**Medido antes de tocar em qualquer coisa.** `tools/gaveta_probe.tscn` monta a tela de
resultado com **5 corpos seus contra 4** e abre a gaveta pelo caminho do jogador. Fechada,
CONTINUAR termina em `y=878`. Aberta, em **`y=963` numa janela de 900** — 63 px abaixo da
borda, fora do alcance do mouse e do olho. O relato do autor era exato.

**A causa nao era a gaveta ser grande.** Era um `BoxContainer` nunca entregar menos que o
minimo do filho: o `_detalhe` era um VBox solto dentro da coluna, entao a coluna ficou
maior que a tela e empurrou o rodape para fora. O comentario da funcao **ja dizia a
intencao certa** — *"a gaveta abre no vazio que ha entre o conteudo e ele"* — e nada no
layout obrigava isso. Intencao que mora no comentario e nao no codigo e a forma mais cara
de errar: ela le como se estivesse resolvida, e ninguem vai conferir.

O conserto tem duas metades, e nenhuma e o sintoma:

1. **A gaveta vive dentro de um `ScrollContainer` com `EXPAND_FILL`.** Com rolagem vertical
   `AUTO` o minimo dele **nao** inclui a altura do filho — ele aceita a folga que existe, e
   o que nao couber rola.
2. **O espacador que empurra o rodape some quando a gaveta abre.** Sem isso os dois
   disputariam a mesma folga e a gaveta ficaria com metade dela.

**Por que nenhuma captura tinha pegado isso.** `screenshots.tscn` fotografa a tela de
resultado com a gaveta **fechada**, que e como ela nasce, e com uma equipe de **dois**. O
estado que quebra e o de depois do clique, numa run avancada. E a mesma cegueira do cartao
do Acaso (6.10), duas vezes na mesma leva: **o que a ferramenta nao fotografa pode nascer
errado e ficar errado.** As duas sondas novas existem por isso, e as duas cobram a mesma
regra, que e a queixa do autor virada asercao: *nenhum botao pode terminar fora da janela*.

**A fissura saiu.** Ela era minha, deste lote: um risco fino atravessando o quadro dentro
de `UI.luz_de_sala`, para a tela nao parecer um `PanelContainer` limpo demais. Nos prints
ela nao le como arte — le como **defeito de renderizacao**: cruza a aresta da fita do topo
na preparacao, corta o canto do painel de consulta, atravessa o rodape do resultado em
diagonal. *"Vazamentos de tela"* e *"sobreposicao do cenario na interface muito indesejado"*
descrevem exatamente essa leitura. Nao ha conserto de grau — clarear e ela some, escurecer
e ela continua sendo um risco atravessado. `UI.fissura()` fica no kit sem chamador: se
voltar, volta recortada **dentro** de um painel, onde a aresta que ela cruza e a do painel.

**Um incidente de ferramenta, que vale mais registrado que esquecido.** Uma barra invertida
de continuacao de linha nao sobreviveu ao caminho *heredoc -> Python -> arquivo* deste
ambiente: chegou em `tools/smoke_test.gd` como os dois caracteres `\` e `n`, e o Godot
recusou o arquivo inteiro. Isso **parou a verificacao obrigatoria dos quatro agentes do
lote de polimento** por quase uma hora; dois deles contornaram rodando uma copia
consertada, e os dois relataram o defeito em `pedidos` sem escrever num arquivo que nao era
deles — que e a disciplina funcionando. O conserto final nao foi reescrever a barra: foi
**nao precisar dela** (`continue` no lugar da continuacao de linha).

**Estado ao fechar:** `smoke_test` **265 asercoes** TUDO OK com a lista de divida vazia,
`teclado_probe` 13/13, `gaveta_probe` e `prep_abas_probe` verdes, `lint_ui` e
`validate_data` OK, build Windows exportada (**PCK 5,50 MB**) subindo com zero erros e zero
avisos.

---

### 6.12 A cor sai do codigo (17/09)

Autor: *"falta muita cor nessa interface (...) faca a UI ser colorida, teste tons de cores
escuras tipo roxo, verde ou azul, para ter cores diferentes nas escolhas e visualizacoes de
sinergias (...) venha com propostas de paletas tambem e faca de uma forma que seja facil
customizar isso."*

**O terceiro pedido decidiu os outros dois.** "Facil de customizar" era impossivel: as cores
eram `const Color("#...")` dentro de `src/ui/ui.gd`, e os MESMOS quatro degraus neutros
estavam repetidos em `tools/build_ui_sheet.py` sob um comentario pedindo *"se mudar um, mude
os dois"*. Um comentario pedindo sincronizacao manual e a definicao de dificil de
customizar. Entao a cor virou dado, com o mesmo estatuto do resto do balanceamento:
`data/paleta.json` para a paleta do jogo, `data/paletas/*.json` para as propostas, e uma
palavra em `ativa` troca a cara do jogo inteiro. O unico hex que sobrou no codigo e a paleta
de reserva do `Db`, que existe para o jogo abrir se o arquivo sumir. O `lint_ui` reprova
`Color("#...")` em `ui.gd` e em `prisma_theme.gd`, para a cor nao voltar.

**"Falta cor" tinha uma causa mensuravel, e a resposta e UM NUMERO.** O sistema de sala ja
existia e ja era chamado por dez telas, cada uma com a sua cor — e nao aparecia, porque a
materia (os quatro degraus) era identica em toda tela e o halo valia 0,04 a 0,075. Medido na
tela de escolha de combate, que foi a do print: com `sala_na_materia = 0.00`, os dois
cartoes saem **byte a byte identicos** (dE2000 = 0,0). Em 0,20 dao dE 7,1; em 0,32, dE 10,7;
em 0,44, dE 13,2. Ficou **0,32**: em 0,44 o miolo do cartao chega a (39,6,26), matiz quase
puro num fundo escuro, que e onde comeca o banding. Varri o contraste de 0 a 0,40 e ele nao
quebra em ponto nenhum.

**Tres propostas, e as tres foram reprovadas pelos criticos — com numero.** Isso e o sistema
funcionando, nao falhando:

| paleta | o que o critico mediu | o que foi feito |
|---|---|---|
| **estufa** (verde) | `aviso` #f0c330 a **dE2000 2,60** do elemento RAIO #e8c53a | `aviso` -> #e0872d (dE 22,6) |
| **brasa** (vinho) | mesmo defeito, dE 2,88 | `aviso` -> #f0781d (dE 28,9) |
| **abisso** (azul) | `aresta_hi` a dE 17,5 do elemento AGUA — o pior par elemento-contra-quina das cinco | `aresta_hi` -> #34736d (dE 30,2) |

Havia ainda **duas paletas azuis**: o agente do sistema improvisou uma (`abismo`) antes de o
agente dedicado entregar a dele (`abisso`). Medidas lado a lado, `abismo` separa 5 das 16
salas e `abisso` separa 14. Saiu a que nao fazia o trabalho.

**E `ativa` tinha ficado em "abisso".** A instrucao era devolver ao valor original; quem
escolhe a paleta e o autor. Voltou para `vidro`.

**Duas cercas novas, e as duas nasceram erradas.**

A primeira mede o contraste do texto contra a materia **tingida**, e nao contra a lajota
crua — nenhuma tela desenha a lajota crua depois desta leva. A segunda cobra que uma cor de
ESTADO nao caia em cima de uma cor de ELEMENTO. Escrevi as duas, rodei o autoteste negativo
reinjetando o defeito da estufa, e **o teste passou verde**. Duas coisas estavam erradas, e
eu tinha escrito as duas em comentario como se fossem verdade:

1. *"CIE76 subestima a distancia entre amarelos"* — e o contrario. O par estufa/RAIO da
   **2,60 em CIEDE2000 e 5,54 em CIE76**: a formula crua SUPERESTIMA justamente na regiao de
   croma alto, que e a regiao que a cerca existe para vigiar, e e por isso que a de 2000 foi
   criada. Com o piso em unidades erradas a cerca nao tinha como disparar. Entrou CIEDE2000
   escrita em GDScript, conferida contra a implementacao em Python nos dois pares.
2. *O piso de 2,3* (o limiar classico de perceptibilidade) tambem **nao pega** o defeito: os
   pares ruins medem 2,60 e 2,88, ou seja, ficam acima dele. O critico chamou de "a mesma
   cor" e a conta nao sustenta isso ao pe da letra. Mas o criterio certo aqui nunca foi "da
   para ver a diferenca se estiverem encostadas": e "da para nao CONFUNDIR uma com a outra
   quando aparecem em cantos diferentes da mesma tela, uma dizendo cuidado e a outra dizendo
   Raio". O piso e **5,0**, e a paleta do jogo fica em 7,22 — com folga, e nao raspando.

Com as duas correcoes o autoteste negativo reprova os dois pares originais pelo nome e pelo
numero. **Uma cerca que nunca reprovou nada ainda nao e uma cerca.**

**E uma cerca que nao tem como reprovar nada hoje, dita por escrito.** A do contraste
tingido nao consegue falhar com a rampa atual: varrendo os tres degraus contra 72 matizes x
21 saturacoes, o pior texto forte possivel e 9,53:1 e o pior fraco e 3,49:1, os dois acima
do piso — consequencia de `materia_da_sala` preservar o **V** do degrau e de os tres degraus
serem escuros. Ela nao e cerca morta: reprova no dia em que existir uma paleta CLARA, ou em
que alguem trocar a formula por uma que nao preserve o V. Mas o comentario tem de dizer
isso, senao ela le como se estivesse protegendo algo agora.

**A pasta que ninguem lia.** `data/paletas/` existia desde o lote — um agente escreveu
`estufa.json` la enquanto a mesma paleta vivia duplicada dentro de `paleta.json` — e o
carregador nao a lia. Pior que nao ter a pasta: quem larga um arquivo nela nao ganha erro,
ganha silencio. Hoje `Db._juntar_paletas_soltas()` junta tudo, com nome repetido sobrepondo
o base, e o `validate_data.py` faz a MESMA juncao — um validador que discorda do carregador
e um validador que mente. Conferido no jogo exportado, e nao so no editor: com
`ativa = "abisso"` (paleta que so existe na pasta) o build sobe limpo, e os tres arquivos
estao dentro do PCK.

**Estado ao fechar:** `smoke_test` **277 asercoes** TUDO OK, `lint_ui` e `validate_data`
verdes, `docs/paletas.png` com as quatro paletas lado a lado, build Windows exportada
(PCK 6,12 MB) subindo com zero erros.

---

## 4. O que o protótipo NÃO responde

- **Legibilidade em 4×** só foi verificada em captura estática, e com deslocamento ela
  ficou mais difícil: no clinch três corpos se encostam. O que já foi feito: agregação
  de reações ("Derretimento ×15"), faixa separada para ultimates, teto de 4 números por
  unidade, nomes em três alturas alternadas, e investida/projétil para que o golpe seja
  visível. Mesmo assim, **isso precisa de olho humano em movimento** — é a coisa que
  mais pede playtest agora.
- **Se o campo vira um amontoado**, os botões são `movement.separation_radius`,
  `movement.arena_half_width` e o `kite` por Papel, todos em `tuning.json`.
- **A cozinha é usada:** 91% das runs cozinham, com média de 1,9 prato (1000 runs).
  A pergunta deixou de ser "o sistema é alcançado?" e passou a ser "a escolha do
  prato importa?", que simulação não responde. Se em playtest a Nutrição parecer
  decorativa, os botões são `momentos.cozinha.ofertas` e o Estômago (`food.estomago_base`).
- **A curva de dificuldade do Ato I** vem de um bot cru. A distribuição de derrotas por
  nó (§23.1) já existe e já foi consertada uma vez — os quatro primeiros passos saíram
  de 0,8% das mortes para 8,9% —, mas ela mede um bot, não um jogador. O nó 7 é hoje o
  vale da curva (80,5%) porque é o único passo em que o jogador entra em minoria; se
  isso é tensão ou injustiça, só playtest diz.
- **Nenhuma build de referência do §19** foi validada — todas dependem de Pactos, Ápice
  ou Afinidade Dupla, que estão fora do slice por decisão do §24.1.
- **R1 do §25** ("o combate é chato de assistir") é *a* pergunta do slice, e ela não se
  responde por simulação. É a única coisa aqui que exige alguém jogando.
