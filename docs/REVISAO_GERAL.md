# Revisão geral do PRISMON — 15/09/2026

Revisão em oito frentes independentes (mecânica, run/economia, balanceamento medido,
comportamento de interface, composição do combate, composição dos menus, efeitos/shaders,
identidade visual), com uma passada adversarial em cima das alegações técnicas e um
crítico de completude no fim.

**121 achados** — 44 altos. Da verificação: 37 confirmados, 16 parciais, **1 refutado por
contradição interna** (está registrado abaixo, porque saber que uma medição estava errada
vale mais que o achado original).

Tudo aqui foi medido ou lido no arquivo. Onde há número, ele foi produzido nesta revisão,
não copiado do README — que, aliás, está desatualizado nas seis linhas da tabela de
balanceamento.

---

## Sumário executivo — as três raízes

Os 121 achados não são 121 problemas. A maioria desce para **três causas** e mais **três
ausências**. Consertar as raízes apaga dezenas de sintomas de uma vez.

### Raiz 1 — "declarado nos dados, nunca lido pelo código"

O princípio do §22.1 — dado fora do código — é a espinha dorsal do projeto e é
genuinamente bem executado. Só que **não há cerca nenhuma**: nada impede o JSON de andar
à frente do `.gd`, e o dado morto não faz barulho, só some.

Auditoria das 438 chaves não-`_doc` de `data/*.json` contra todo o fonte: **~35 chaves que
nenhum `.gd` cita**. Onze achados em cinco frentes diferentes são esse mesmo defeito com
nomes diferentes. Os piores:

| Peça | O que promete | O que faz |
|---|---|---|
| **Coro de Gelo** (`dmg_vs_gelido`) | +15% de dano contra Gélido | nada — zero ocorrências em `.gd` |
| **Coro de Natureza** (`dmg_vs_esporo`) | +15% de dano contra Esporo | nada — zero ocorrências em `.gd` |
| **Totem do Excesso** (`unit_aura_cap`) | teto de UA 8 → 12 | aplicado em `combat_builder.gd:118` e sobrescrito em `combat_sim.gd:102` |
| **Bico Para-Raio** (`unit_ua_add`) | +2 UA por golpe | escrito em `unit_instance.gd:151`, nunca lido por `_sim_unit_from` |
| **Diapasão Vivo** (`team_ult_gain`) | +10% de carga de ultimate | ninguém lê |
| **Coração Instável** (`enemy_aura_backlash`) | o lado ruim da relíquia | ninguém lê — a relíquia é puro bônus |
| **Arena Campo Magnético** (`atk_speed`) | acelera o ataque | `stat_mult("atk_speed")` não existe; o simulador lê `"vel"` |
| **Totem da Persistência / Sifão das Marés** | suas auras duram mais | **sinal invertido**: as auras do *inimigo* é que duram mais em quem os equipa |
| **bloco `targets`** (8 constantes) | os alvos do §17.4 | decorativo — os limiares reais estão *hardcoded* em `autoplay.gd:332-355` |
| **bloco `prices`** (inteiro) | preços da run | ninguém lê |
| **`heal_between_nodes_pct`** (0.35) | cura parcial entre nós | `run_state.gd:413` cura 100% incondicionalmente |
| **`UI.panel(bg, ...)`** | 7 cores de sala escritas nas telas | `ui.gd:223` descarta o `bg` — 16 call sites, 0 renderizados |

O **Coro** é o caso mais caro: é o topo do eixo de construção de time, exige Peso
Elemental 4, e para dois dos cinco elementos ele não faz nada. Quem monta Gelo até o Coro
paga o custo inteiro e recebe zero.

> **A mudança única.** Não é consertar os doze. É uma asserção de cobertura em
> `tools/smoke_test.gd`, e o molde **já existe e já roda verde** no bloco
> `[arena e modificadores]` (`:717-824`), que prova com simulação real que cada uma das 7
> arenas "tem efeito de verdade" e que "Ferozes deixa o inimigo mais forte (66 → 73)".
> Repetir esse padrão para cada item, relíquia e ressonância — monta dois combates
> idênticos, um com a peça e um sem, e falha **nomeando a peça que não mudou nenhum
> número**. Isso teria pego sozinho todas as linhas da tabela acima.

### Raiz 2 — no combate, nada é ancorado em quem causou

O borrão de números que aparece em `shots/05_combate.png` não é falta de agregação — a
agregação existe. É que **ela agrega por lugar, não por vítima**.

- `_push_floater` (`field_view.gd:342-384`) recebe só `pos`. Tanto a soma quanto o teto
  `MAX_FLOATERS_PER_UNIT` só contam floaters a menos de 10 px do ponto novo. A janela de
  agregação é 0,30 s; a criatura **mais lenta do jogo** (Arcano, 78 px/s) cruza 10 px em
  0,13 s. Para qualquer alvo em movimento a agregação é impossível em 57% da própria
  janela, e o teto "por unidade" nunca dispara. O evento já carrega `dst`
  (`combat_sim.gd:801`) — só não é passado adiante.
- As faixas de reação moram numa **linha fixa do céu** (`y3 = 68.0 + pista * …`), a até
  580 px de onde a reação aconteceu.
- O nome cede espaço para outros nomes e para os corpos, mas **não para os números** — que
  são muito mais numerosos. Daí "Apollo" virar `5giono` e "Sheep" virar `Shœ31`.

### Raiz 3 — não existem painéis no PRISMON, existem contornos

Esta é a causa técnica do "parece IA", e é **uma linha**.

`ui.gd:208` aplica o tint como `sb.modulate_color`, que multiplica a textura 9-patch
**inteira** — borda e miolo. O miolo de `frame_panel.png` é `#191627`; multiplicado pelos
tints reais vira `#130a10` (Fogo), `#0a0c1e` (Água), `#0f0e1c` (neutro).

Medido agora em `shots/07b_loja.png`:

| | RGB | luma |
|---|---|---|
| fundo da tela | (15, 13, 24) | **14,9** |
| miolo do painel | (15, 14, 29) | **16,0** |
| borda do painel | (108, 133, 173) | **130,1** |

O corpo do painel está a **1,1 de luma** do vazio atrás dele. A borda está a 130. Ou seja:
o jogo inteiro é **uma bisel de 6 px flutuando num campo chapado** — e é por isso que onze
telas diferentes parecem a mesma tela.

Em cima disso, dois amplificadores: `tint_of()` (`ui.gd:214-219`) trava V em 0,78 e capa S
em 0,55 para **toda** borda do jogo, então Fogo `#e8563a` vira `#c6796a` e Raio `#e8c53a`
vira `#c6b46a` — mesmo brilho, mesmo canal máximo `0xc6`; a cor virou chave de consulta e
nunca clima. E o grep fecha: `rotation`/`skew` em Controls = **0**; `shadow` em painel =
**0**. Nada está torto, nada tem peso, nada existe porque alguém quis.

### As três ausências

1. **Zero áudio.** `grep -rn "AudioStream|AudioServer" src/ tools/` → 0. Zero arquivos de
   som. Zero controle de volume nas Configurações. E — o que importa — **zero ocorrências
   de "áudio/som/música" em 1283 linhas de NOTAS.md e no README**. Não é corte de escopo
   documentado; é um assunto que nunca foi levantado. Num projeto cuja pergunta de
   pesquisa é literalmente *"o combate é interessante de **assistir**?"*, metade da
   resposta está sendo medida com o som desligado.
2. **Zero save de run.** `user://config.cfg` guarda só as 4 opções. Fechar o jogo no meio
   de uma run de 8 combates perde tudo. Também não há "sair da run", e as Configurações
   ficam trancadas fora dela.
3. **Zero onboarding.** `_check_auto_pause()` (`screen_combat.gd:241`) é literalmente
   `pass` — removido a seu pedido em 31/08, com razão registrada. Mas o **README:64-65
   ainda promete o mecanismo**, e nada o substituiu. A única instrução do jogo inteiro é
   uma linha de 11 px na tela de título, escrita antes de a palavra "Ativo" ter qualquer
   significado.

---

## 1. Mecânica — o que está implementado de verdade

### O que está sólido (não mexer)

- **A separação do §22.3 é real, não declarada.** `grep -n "Node\|scene\|get_node"
  src/sim/*.gd` não encontra nada em 1969 linhas. É isso que permite rodar 1000 runs e ter
  este relatório medido em vez de opinado.
- **Determinismo levado ao detalhe irritante.** Todos os desempates por `id`/`species_id`;
  `_separate` desempata dois corpos no mesmo pixel por id, sem sorteio; o embaralhamento
  usa o RNG semeado do sim.
- **`max_reaction_chain`** fecha a recursão Eletrocussão → chain → strike **por
  construção**, não por sorte de recurso.
- **A imunidade a Controle dentro do resolvedor** (`reaction_resolver.gd:93-97`) usa
  `continue` e não `return` — a próxima aura ainda pode reagir. É a forma certa, e quase
  ninguém acha isso.
- **A fadiga de cura** mata a forma dominante de impasse sem tocar em dano, e o `_doc`
  registra o compromisso nos dois sentidos.

### Os defeitos que contaminam qualquer medição futura

**1. Todo Controle dura o dobro do que o dado diz.** `attack_cd` só é decrementado dentro
do laço guardado por `can_act`, e `can_act` é `alive and not is_controlled`. Enquanto a
unidade está controlada o cooldown **não anda** — e `apply_control` (`combat_sim.gd:901`)
ainda faz `dst.attack_cd = maxf(dst.attack_cd, real)` por cima. Congelar de 1,5 s custa
3,0 s de inação. Atordoamento de 1 s vira 2 s. Não há comentário sobre isso em lugar
nenhum. *Conserto: apagar a linha 901 — `can_act` já impede a ação durante o controle.*

**2. Os Ativos do jogador rodam "sem lado".** `cast_active` chama `AbilityRunner.run(self,
null, ...)`, e todo o resto do combate descobre o time do golpe por `src.side`:

```gdscript
var mods := team_mods[src.side] if src != null else {}    # :583 e :648
ctx.attacker_pe = src.eff_pe() if src != null else 0.0    # :651
```

Com `src == null`: `reaction_bonus` = 0 (Eco de Fogo, Coração Instável, Totem do Fole),
`attacker_pe` = 0 (a curva de PE vale até 2×), `crit_add` = 0, `reverse_full_mult` = false,
`second_reaction_chance` = 0. **A Mão do Domador é a única coisa no jogo que não recebe
relíquia, ressonância nem PE.** E como os dois portões de Energia por reação exigem
`src != null`, a Catalisação disparada por um Ativo devolve nada — apesar de o texto dela
em `reactions.json` a chamar de "o motor dos Ativos".

Isto é o mais grave da revisão: **o sistema inteiro de build converge para o combate por um
cano que passa ao largo da única agência do jogador.**

**3. Coleira Compartilhada aplica dano cru fora do `_deal`.** `combat_sim.gd:760-769` faz
`m.hp -= each` e para aí: não chama `_kill`, não passa por escudo, não emite evento, não
entra na telemetria. Um aliado pode ficar com HP **negativo** e continuar atacando —
`alive` segue true, e `hp_pct()` negativo envenena `enemy_lowest_hp` e `_most_hurt_ally`. E
o dano some inteiro quando o portador é o último vivo, virando redução pura de dano na
hora mais crítica. *Conserto: `_deal(dst, m, each, "shared", "", false, true)`.*

**4. Em 8 dos 10 temas, é a arena que escolhe a reação — não a sua equipe.** A maré da
arena ocupa permanentemente um dos dois espaços de aura de todo mundo e, por zerar `age` a
cada pulso, é sempre a aura mais nova — a primeira que o resolvedor testa. O log do print
mostra um combate inteiro com exatamente um tipo de reação: `Detonação ×19`.

### O loop de intervenção: hoje é um botão de dano

Três motivos somados, todos medidos:

- **A mão não tem três Ativos na maior parte da run**: 1 nos combates 1-2, 2 nos 3-6, 3 só
  do 7 em diante — que **51% das runs não alcançam**.
- **Não há recarga por Ativo**, só Energia. Com 2,6/s numa briga de 12,5 s de mediana, o
  orçamento dá para um lançamento, quase sempre o mesmo.
- **Não existe decisão de QUANDO.** Guardar Energia não rende nada (teto de 100, a briga
  acaba antes), e a pausa se desfaz sozinha no instante em que você lança
  (`screen_combat.gd:337`). Dá para pensar antes de um Ativo, nunca para armar dois.

E **15% dos combates não oferecem um Ativo sequer** — no nó 2 são **52%**. Mediana do
primeiro Ativo disponível: 5,8 s, numa luta de 12,5 s.

> A alavanca mais barata para criar profundidade é a do defeito #2: se a reação causada
> por um Ativo devolver Energia, Chuva Torrencial (35) passa a pagar parte do Meteoro (40)
> e nasce um combo de duas peças com ordem certa. Adicionar `combat.energy_start` (~20)
> resolve a janela vazia do começo sem tocar em `hp_scale`.

---

## 2. Balanceamento — os números de hoje

Medidos agora com `autoplay --runs=400` e `--runs=1000`. **A tabela do README está errada
nas seis linhas.**

| Métrica (§17.4) | Alvo | README diz | Medido hoje |
|---|---|---|---|
| Vitória da run | 35–45% | 41% | **34–37%** ✅ |
| Ativos por combate | 1,5–2,5 | 1,56 | **2,21** ✅ |
| Reações por combate | 5–45 | 30,3 | **36,1** ✅ |
| Runs que cozinharam | > 70% | 77% | **~90%** ✅ |
| Duração mediana | 28 s | 17,4 s | **12,5 s** ❌ |
| Estouro de relógio | < 6% | 7% | **5,6%** ✅ |

### `hp_scale` é hoje o maior botão de dificuldade do jogo — e o `_doc` dele fala de outro valor

O valor no arquivo é **3.7**. O `_hp_scale_doc` logo acima diz *"permitiu baixar este
escalar de 2.0 para 1.4"* e afirma que ele *"preserva todas as razões"*. Medido, 250 runs
por ponto:

| `hp_scale` | vitória | mediana | relógio | ativos | reações |
|---|---|---|---|---|---|
| 1.4 | 22% | 5,3 s | 0,5% | 0,67 | 13,6 |
| 2.0 | 28% | 7,1 s | 1,0% | 1,05 | 19,6 |
| **3.7 (atual)** | **36%** | **12,5 s** | **5,6%** | **2,21** | **36,1** |
| 5.5 | 40% | 18,4 s | 10,9% | 3,35 | 52,2 |
| 8.0 | 45% | 25,7 s | 20,2% | 4,72 | 72,4 |

Ele move a vitória em **23 pontos percentuais** no intervalo — logo **não** preserva a
razão que importa. Um `_doc` que descreve outro valor é pior que `_doc` nenhum, porque o
próximo ajuste parte dele.

### Éter não é moeda, é placar

- Entra **272 Éter/run**. Sai 149 — e 30 disso é o Devorador comendo, que não é escolha.
- Gasto **escolhido** pelo jogador: 119/run. **Sobra: mediana 121 = 45% de tudo que entrou.**
- Em **364 visitas de loja, 1059 itens e 145 relíquias, o número de compras recusadas por
  falta de Éter foi ZERO.** Na cozinha, **675 de 675** pratos oferecidos foram comprados.

O gargalo **não é preço, é oferta**. Consequência: o prêmio de perigo não compra nada, e a
escolha entre dois combates só tem um eixo de verdade. Teste: zerar `reward_per_danger`
**subiu** a vitória de 36% para 38%.

### Nenhum dos três limites declarados aperta

| Limite | Disponível | Usado (mediana, 250 runs) | Recusas |
|---|---|---|---|
| Vínculo | 6 → 8 | **5** (máximo observado: 5) | 0 recrutas negados |
| Estômago | 3–4 por bicho | 12 vagas **livres** no fim | 0 pratos recusados |
| Slots de item | 3–4 por bicho | 10 livres no fim | — |

A razão é aritmética: 3 recrutas + 2 iniciais = teto natural de 5 corpos a 1 de Vínculo
cada.

### A curva de dificuldade é um dente de serra de contagem de corpos

Os tamanhos de time são **determinísticos**, idênticos em todas as 400 runs:
2×2, 3×2, 3×3, 4×3, 4×4, 4×4, 4×5, 5×5, chefe 5×3. A vitória por nó acompanha exatamente:

`100% · 100% · 96,8% · 99,2% · 93,0% · 86,6% · 76,1% · 84,7% · 73,4%`

Os dois nós em que o jogador tem +1 corpo (2 e 4) são os dois picos; o único em que está em
minoria (7) é a luta normal mais difícil; e o nó 8 é **mais fácil** que o 7. **Os quatro
primeiros nós carregam 0,8% das mortes** — metade da run que todo jogador vê toda vez não
tem aposta nenhuma. E o primeiro combate de **toda** run é o mesmo: Cardume Profundo, 2
Hipocampos, 20 Éter, 1 estrela.

### CONTRADIÇÃO — e a medição que venceu

A frente de números afirmou, com severidade alta, que *"FOGO (apollo) decide a run; ÁGUA
(hipocampo) é negativo"*. **Isso foi refutado.**

O crítico rodou `autoplay --runs=1000`, onde o bot atribui a dupla por
`DUOS[seed % 10]` com seed = `1000 + i*17` — 17 e 10 são coprimos, então os 10 pares
recebem exatamente 100 runs cada. É um **A/B balanceado**, não uma correlação de time
final. Agregado por espécie (n=400 cada), contra linha de base de 34%:

`sheep 42,0% · hipocampo 35,25% · pinto_raio 33,25% · apollo 32,75% · coalla 27,25%`

**Apollo está abaixo da média; hipocampo acima.** O eixo real é **sheep (Gelo) × coalla
(Natureza): 42,0% contra 27,25%, z ≈ 4,4.** O erro da primeira medição foi medir presença
nas composições *vencedoras* — o time final diz o que sobrou, não o que causou.

O alvo é a **Coalla**: 15 pontos de desvantagem numa escolha feita na *segunda tela do
jogo*, sem informação nenhuma. E a primeira hipótese a testar é de graça: o **Coro de
Natureza é um dos dois mods mortos**, então metade do payoff elemental dela literalmente
não roda. Consertar aquilo e remedir **antes** de tocar em qualquer stat.

> **Protocolo:** o README manda `--runs=200`. 200 runs dão ±4 pontos numa faixa julgada de
> 10. O mínimo tem de ser **1000**.

### `--csv` nunca produziu um número

`autoplay.gd:474` tem **12 especificadores e 11 argumentos**, então o `%` do GDScript
devolve o formato sem substituir nada. As 400 linhas do arquivo saem literalmente
`%d,%s,%d,%d,%d,%d,%s,%s,%d,%d,%d,%d`. O README:32 anuncia isso como a ferramenta de
balanceamento. *Conserto: tirar o `,%d` final.*

---

## 3. Interface — comportamento

- **O quarto tooltip grudado.** O tween de entrada de `_assentar` nunca é morto, e o
  `REENGATE` garante que ele alcance a dica seguinte (`tooltip_layer.gd:154-179`).
- **No combate, clicar qualquer botão com o mouse desliga ESPAÇO e TAB** — o foco vai para
  o botão e come as teclas.
- **Não dá para jogar com teclado.** As listas não navegam por seta.
- **Na Feira o COMPRAR morre em silêncio** quando falta Éter; na Cozinha a mesma situação é
  escrita na cara do jogador. Duas telas gêmeas, dois comportamentos.
- **Dois "LUTAR" para o mesmo ato**, e no chefe são duas confirmações seguidas sem decisão
  no meio.
- **O log de derrota só tem o seu lado** — não dá para descobrir o que o inimigo fez, que é
  exatamente a pergunta de quem perdeu.
- **Jargão de engine na tela do jogador**: "limite de ticks", "aniquilação mútua".
- **A tela de fim de run nunca foi revisada por ninguém** — `tools/screenshots.gd` não a
  captura (por isso não tem print), e `grep -in "screen_end"` em NOTAS.md → 0 ocorrências
  em 1283 linhas. Ela **nunca mostra a semente**, apesar de a tela de título ter um campo
  para digitá-la; e chama de "A RUN EM NÚMEROS" um cartão sem um único número de combate.

---

## 4. Visual — o combate

### A briga acontece na casa do inimigo, e a arena não está no meio da tela

Medido pelos pixels exatos das barras de vida em três combates: **nove unidades, nove com
x > 0**, entre +50 e +244, numa arena de ±530. A mediana, **+167**, bate com a conta: o
inimigo de Postura Meio nasce em `lane_base + lane_gap` = +240, e o Guardião para
`melee_hold × range` = 68 px antes → +172.

A causa é uma **fuga sem âncora**: o kiter quer `t.pos + (home - t.pos).normalized() *
kite` e o perseguidor quer o mesmo com `hold`. Cada troca empurra o par `kite - hold` px na
direção da casa do kiter, e só `_clamp_arena` freia. Com 3 das 5 espécies tendo kite e a
dupla inicial sendo melee, **a deriva é sempre para +x**.

E o layout piora de graça: o HBox dá 364 px à esquerda e 102 à direita, então o centro da
elipse já nasce em x = 966 contra 800 do centro da tela. **O centróide da ação fica a 310
px do centro do quadro.**

*NOTAS.md §5.15 declara que "o encontro acontece no meio, que é onde a câmera olha". A
medição diz que não — a correção de 31/08 mexeu no spawn, não no que produz a deriva.*

**Dois consertos, escolha um:**
1. Coleira de casa no kiter: `desired = u.home + (desired - u.home).limit_length(u.kite)`.
   Uma linha, mas toca a simulação — remedir o §17.4 depois.
2. Câmera: `to_screen` é o funil único do FieldView. `size*0.5 + (p - _cam) * SCALE +
   Vector2(0, DESCE)`, com `_cam` = centróide dos vivos suavizado. **Cinco linhas, zero
   risco de balanceamento.**

### O tint de cada arena é o hex exato do elemento que luta nela

Quatro colisões **exatas**:

| Arena | tint | colide com |
|---|---|---|
| Solo Vulcânico | `#e8563a` | FOGO `#e8563a` |
| Chuva Constante | `#3a7fe0` | ÁGUA `#3a7fe0` |
| Bosque Vivo | `#5cd6a0` | **`UI.GOOD` — a cor da sua barra de vida** |
| Arena Assombrada | `#a86fe0` | a cor do aviso de fantasma |

Não é acaso: em `enemies.json` cada tema prende a sua arena, então **a arena é sempre
pintada na cor das criaturas que brigam nela**. Medido: 96,8% dos pixels saturados de
`05_combate.png` cabem numa fatia de 60° de matiz. Na mesma fileira de criaturas em
`04_preparacao.png`, a distribuição se espalha por 8 faixas.

*Correção de uma leitura minha: a culpa não é do véu — `arena_tint` tem alfa 0,030 e só
pinta o polígono do piso. É a arte de fundo, cujas peças estão em saturação 0,50–0,60.*

**Contrato de cor proposto:** arena em S ≤ 0,30 e V ≤ 0,40; criaturas e anúncios donos da
banda clara e saturada; e o tint de cada arena **girado para longe** do elemento que luta
nela. Corolário obrigatório: `bosque_vivo` não pode usar `#5cd6a0`.

### Outros

- **O piso é só contorno.** 14/255 de contraste entre piso e vazio, contra 22/255 do anel
  branco sobre o piso: **a linha aparece mais que o chão**. Seis elipses concêntricas
  depois, é um alvo de radar.
- **O degrau do disco interno é mensurável**: em `11b_run_combate.png`, na linha y=522, a
  cor salta de (36,38,50) para (43,47,61) em x=588 e volta em x=1350 — exatamente
  `0,72 × 530` do centro.
- **`SQUASH` é 0,34; o achatamento real da elipse é 0,443.** Toda sombra, aura e onda está
  achatada demais para o chão em que pousa.
- **Barra de vida de 4 px**, com largura de referência que **muda por espécie** — então
  comprimento não significa porcentagem.
- **Duas criaturas com o mesmo nome** e nenhuma marca de lado.
- **Três grades diferentes na mesma tela**: nada se alinha com nada.

---

## 5. Visual — as telas fora do combate

> Este não é um projeto com problema de gosto. É um projeto com problema de **cumprimento**:
> a direção está decidida, escrita e desenhada em `docs/pecas/`, e as telas divergem da
> própria norma em pontos pequenos e visíveis. O lint checa escala pixel-limpa e sintaxe,
> não significado.

### O conserto mais barato do relatório inteiro

**Os nomes do seu elenco não aparecem no trilho da esquerda.** Sobra um traço de 2 px.

`roster_rail.gd:79` liga `clip_text = true` — que trava a largura mínima do Label em 1 px,
fato já medido e escrito em dois outros arquivos do projeto — **sem** o
`SIZE_EXPAND_FILL` que o acompanha nos outros seis usos; e a linha 82 ainda acrescenta um
`UI.spacer()` que come toda a folga. **Uma linha.** Hoje a peça que existe para manter a
equipe à vista durante a run inteira (288 × 864 px de moldura permanente) mostra dois
medalhões e dois riscos.

### O botão de confirmar tem quatro cores, e nenhuma é a da folha de peças

`docs/pecas/botoes.png`, gerada do próprio código, define "confirmar" = **verde** e
"secundário" = roxo. Na tela: prep LUTAR é **vermelho**; ScreenMap LUTAR! é
**dourado/âmbar/vermelho** conforme o perigo; PickPanel COMPRAR/COZINHAR/APRENDER recebe a
cor da **oferta selecionada**, então muda a cada clique. Só ScreenChance bate com a folha.

Pior: o roxo `ACCENT` serve ao mesmo tempo para **recuar** (DISPENSAR, CANCELAR, SEGUIR SEM
RECRUTAR) e para **avançar** (CONTINUAR, NOVA RUN).

### Quatro telas são o mesmo retângulo, ao pixel

| Tela | caixa do conteúdo | posição |
|---|---|---|
| `07b_loja` | 954 × 604 | (323, 148) |
| `07d_cozinha` | 954 × 604 | (323, 148) — **idêntico** |
| `07f_poder` | 954 × 594 | (323, 153) |
| `07g_troca` | 954 × 650 | (323, 125) |

"A PANELA ESTÁ NO FOGO" e "FEIRA DE PASSAGEM" são a mesma tela com palavras trocadas. Não
há cenografia, não há fogo, não há banca, não há mercador.

### Preparação: o painel mais largo tem o menor conteúdo, e o mais estreito é o que corta

- Painel central: **1230 px de largura × 181 de altura**, para nove chips que cabem em duas
  linhas.
- Coluna de consulta: **320 px**, correndo 660 px na vertical e **cortada no rodapé** — o
  cartão "Presa Rachada / Coalla" é fatiado no meio dos glifos.
- O retângulo abaixo do painel central — **579.040 px², 40% da tela inteira** — tem **5,3%
  de pixels com tinta**.

Suas cinco observações sobre essa tela se confirmam todas. Os nomes em alturas diferentes:
**27 px de amplitude medidos**, e a correção registrada em `ranch_view.gd:55-59` resolveu a
parte centro-versus-pé mas deixou intacto o `cos(f*PI)*30.0` da linha 60, que é o que
produz o padrão. As estrelas e os três patos: `MonsterPortrait.medallion` **não define
tooltip em lugar nenhum do projeto** — não é que a explicação esteja escondida, é que ela
não existe.

Há uma ironia registrada: `screen_map.gd:138-139` defende **por escrito** mostrar inimigos
como texto agrupado ("3 Apollos") em vez de imagem repetida — e a tela seguinte desenha
três medalhões idênticos sem contagem nem nome.

### Recruta: as duas opções não ficam na mesma linha, e a própria tela prova que dá

`screen_recruit.gd:91-98` só acrescenta o bloco "desbloqueia" quando há reação nova, e a
linha 64 centraliza — então um cartão com bloco a mais **re-centra todo o conteúdo**. Em
`07a_recruta.png` nada nos dois cartões se alinha; para comparar "Gelo·Guardião" com
"Raio·Arcano" o olho anda na diagonal. A **mesma tela** em `13_run_evento.png`, onde os
dois cartões têm o bloco, bate **ao pixel nas cinco linhas**.

*Conserto: sempre acrescentar o bloco, escrevendo "nenhuma reação nova" quando vazio.*

### Outros

- A **moeda de Éter** sai com 10 px de tinta na loja e 23 px no HUD — metade do tamanho
  justo onde se gasta dinheiro.
- A **faixa de título** tem **seis larguras** medidas, de 688 a 1412 px, e é a aritmética
  das pontas fixas de 64 px que produz as "pontas coladas".
- Na cozinha, a **barra verde grande é HP**; o número que decide (Estômago) é cinza e
  pequeno.
- Perigo e inimigos aparecem em **dois alfabetos diferentes em telas consecutivas**.
- A **barra de rolagem roxa** aparece cheia e berrante onde não há nada para rolar.
- O contador **RODADA é 1,5× maior que o título da tela**.
- O **maior controle da tela de recruta é o botão de não fazer nada**.

---

## 6. Partículas, efeitos e shaders

### O inventário

**O combate do PRISMON não tem nenhum shader.** Existem nove `ShaderMaterial` no projeto:
oito são o mesmo `cenario_fade` (um por arena) e o nono é o `pixelize` do logotipo. Tudo o
que acontece na arena é desenho imediato. **O único lugar do jogo onde a luz existe é o
horizonte.**

| | Peça | Estado |
|---|---|---|
| ✅ | Curva do cenário tirada da própria elipse | boa, e inteligente |
| ✅ | `SQUASH` único compartilhado por sombra/aura/mira/onda | boa (mas com o valor errado — ver §4) |
| ✅ | Anéis de aura com espessura = UA | boa |
| ✅ | Chuva e nevasca (n=130 e 120) | boas |
| ✅ | Hitstop por reação vindo do JSON | boa |
| ⚠️ | Flash de tela | teto de **0,072 de alfa** = 7% de mistura |
| ⚠️ | Tremor | máximo 2,75 px por 0,125 s |
| ⚠️ | Anel de reação | **54 px fixos**, ignorando que Detonação explode em 140 |
| ⚠️ | Partículas do Campo Magnético | **0,016% do campo aceso** — e não se movem |
| ⚠️ | Partículas da Câmara | alfa 0,45, metade da densidade da neve |
| ❌ | Segundo disco do piso | **atrapalha** — é o degrau de alvo de dardos |
| ❌ | **Hit-flash** | não existe. A criatura atingida não muda um pixel |
| ❌ | **Efeito de morte** | não existe — o evento `death` é emitido e **ninguém o consome** |

Sobre o `pisca` do Campo Magnético: ele **não tem caso no `match op` de `atualizar`** —
essas partículas literalmente não andam. 32 pontinhos de 1 a 3 px que piscam parados leem
como pixel queimado do monitor.

Sobre a morte: `combat_sim.gd:828` emite `{"kind": "death", "id", "pos", "name"}` — com
tudo pronto. `grep '"death"' src/ui/` → **zero ocorrências**. O momento mais importante da
briga é um corte seco de cor.

### O orçamento não é problema — e o culpado é o texto

`_outlined` faz **cinco `draw_string` por rótulo**. O pior quadro do combate gasta
`5 × (10 nomes × 10 glifos + 30 floaters × 3 + 5 pops × 16) = 1.350 quads de glifo`, contra
**150** quads de partícula no teto. **O texto custa nove vezes o clima.** Trocar por
`draw_string_outline` libera mais orçamento do que todas as propostas abaixo consomem
somadas. **Não há razão de desempenho para segurar nenhuma delas.**

### As propostas, por retorno

#### 1. Hit-flash — a maior lacuna do jogo (≈60 linhas + shader de 3)

Tecnicamente um tint branco é **impossível** hoje: `draw_texture_rect_region` só aceita
modulate multiplicativo, e branco × cor = cor. E no Godot 4 o material é do `CanvasItem`,
não do comando de desenho. A saída é uma **camada de silhueta**: um `Control` filho do
FieldView, com material próprio, que redesenha em branco chapado quem acabou de apanhar.

```glsl
// assets/shaders/silhueta.gdshader
shader_type canvas_item;
render_mode blend_mix;
// COLOR entra como textura * modulate DO COMANDO. Passando Color(1,1,1,forca)
// no modulate, COLOR.a ja e alfa_da_textura * forca -- a mascara exata da
// silhueta. O rgb da textura e descartado e a cor vem do uniform.
uniform vec4 cor : source_color = vec4(1.0);
void fragment() {
	COLOR = vec4(cor.rgb, COLOR.a);
}
```

A mesma camada serve para contorno por elemento e para o item 2.

#### 2. Dissolve elemental na morte — reaproveita a camada acima

```glsl
// assets/shaders/dissolve.gdshader
shader_type canvas_item;
render_mode blend_mix;
// DESMANCHE EM BLOCO. Nada de textura de ruido: o limiar sai de um hash da
// coordenada de TELA quantizada, entao o grao tem o tamanho do pixel do jogo
// e nao borra em 1600x900 sem escala.
uniform float bloco : hint_range(1.0, 8.0) = 2.0;
uniform vec4 cor_saida : source_color = vec4(1.0);

float hash21(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123);
}

void fragment() {
	vec4 t = texture(TEXTURE, UV);
	// com NEAREST o alfa da arte e 0 ou 1, entao COLOR.a DENTRO da silhueta e
	// exatamente o alfa do modulate -- e por ele que o progresso viaja
	float prog = COLOR.a;
	float h = hash21(floor(FRAGCOORD.xy / max(bloco, 1.0)));
	COLOR = vec4(mix(t.rgb, cor_saida.rgb, prog * 0.85), t.a * step(prog, h));
}
```

#### 3. O anel de reação com o raio real — duas linhas

`reactions.json` dá `radius: 140` à Detonação e `120` à Supercondução, e
`combat_sim.gd:709` **usa esse raio de verdade** para causar dano. Mas o evento não carrega
`radius`, e a view usa 54 fixo para toda e qualquer reação — então Detonação (área 140) e
Eletrocussão (alvo único) desenham **o mesmo círculo**. O jogador não tem como aprender
quais reações são em área. *O Ativo já faz certo: `field_view.gd:310` usa o raio do evento.*

#### 4. O piso como superfície, com dither ordenado

Trocar os dois discos por uma queda contínua num shader — um quad de tela cheia no lugar de
dois polígonos de 72 vértices. O dither 4×4 de Bayer é obrigatório: sem ele, um alfa que
cai de 0,055 a 0,012 ao longo de 380 px muda ~11 níveis e faz **faixas de ~35 px**.

#### 5. Faíscas de combate — as partículas hoje só conhecem clima

A API da classe é `trocar / atualizar / desenhar`: **não existe nenhuma entrada de
combate**, e o único ponto de desenho é *antes* do laço de criaturas, então tudo fica atrás
dos corpos por construção. Falta o caminho de mão única inverso — a tela olhando a
simulação e cuspindo faísca, com cor **por partícula** e uma passada de desenho **depois**
dos corpos, achatada pelo mesmo `SQUASH` para a faísca sair rente ao chão.

#### 6. Ar quente no Solo Vulcânico — dentro do shader que já existe

Distorcer a **UV da própria peça**, não a tela. Isso dispensa `BackBufferCopy` e
`hint_screen_texture` inteiramente, e o filtro NEAREST faz o deslocamento cair em texels
inteiros: **o tremor anda em pixels**, como o resto do jogo, em vez de borrar. A
infraestrutura de escrever uniform todo quadro já existe (`field_view.gd:902-917`), e a
arena já tem as peças certas (`10_veio_1..6`, `11_boca_1..5`). `calor = 0` nas outras seis
arenas, então o shader continua idêntico para elas.

#### 7. Bloom — sem shader, sem backbuffer

Uma camada aditiva: um `Control` com `CanvasItemMaterial` em `BLEND_MODE_ADD` e um halo
radial gerado em código (`GradientTexture2D`, 32×32, NEAREST). Esticado para 120 px ele sai
em **degraus grossos** — que é a gramática certa aqui: um halo liso ao lado de pixel art
1:1 denuncia que veio de outro jogo.

#### 8. Reperfilar as duas arenas invisíveis

```gdscript
"campo_magnetico": {
	"op": "sobe", "n": 90, "vel": 96.0, "balanco": 5.0,
	"tam": [1, 2], "alfa": 0.8, "vida": [0.5, 1.2], "cintila": true,
},
"camara_de_estimulos": { "n": 70, "alfa": 0.7 },
```

E o melhor retorno por linha: amarrar os três anéis de `ArenaChao` ao `arena_pulse` que já
existe, fazendo a marca parada **varrer para fora** quando o estímulo dispara.

---

## 7. Identidade — por que parece IA, e uma direção

O diagnóstico está na **Raiz 3** acima: não existem painéis, existem contornos. Somando os
amplificadores:

- `UI.panel()` descarta o `bg`: **7 cores de sala escritas, 0 renderizadas**.
- `tint_of()` achata toda cor de borda para o mesmo brilho: **a cor virou chave de
  consulta, nunca clima**.
- `rotation`/`skew`/`shadow` em painel: **zero**. Nada está torto, nada tem peso.
- Vazio chapado: `08_chefe` tem **2,0%** de pixels não-fundo; `07c_acaso` **4,3%**;
  `06_log` **5,0%**.
- O **logotipo é a única coisa com mão no jogo inteiro** — e não sai da primeira tela.
- O glifo mais repetido da interface (o `◆◆` que rotula toda reação) vem do **fallback do
  sistema operacional**.
- A tira de 9 cores no topo do título é resíduo de mockup.

### A direção proposta: **O VIDRO DO DOMADOR**

Ela nasce do único objeto que o tema já entrega: **o prisma não é o logo, é a matéria de
que a interface é feita.** Toda tela é uma placa de vidro fumê sobre a mesa de campo do
Domador, com resíduo de elemento queimado nela.

**O gesto que se repete: o canto cortado e o feixe.** Todo recipiente perde o canto
superior esquerdo para uma escada de 45° em 9 px (três degraus de 3 px — *a mesma
especificação de canto que o PDF já dá à artista*), e de dentro do corte sai uma barra de
2 px na cor do elemento. **Luz entra pelo corte, sai colorida.**

| Peça | O que muda | O que **não** muda |
|---|---|---|
| Painel | lajota **sólida** em 4 degraus neutros (`#0f0d18` mesa / `#1c1930` lajota / `#262138` erguida / `#3a3450` aresta), sombra **dura** de 3 px, nunca desfocada | 9-patch, margem 12/8 |
| Botão | preenchimento em vez de contorno; sobe 2 px no hover, afunda 3 px ao apertar; **confirmar = um segundo corte no canto oposto** (dois cantos = commit, sem precisar de cor) | 58 px de altura, respiro 20/13 |
| Barra | canal de vidro (1 px escuro em cima, 2 px claro embaixo) + barra branca de 1 px na frente do preenchimento — é o que o olho persegue quando a vida cai | 18 px, 9-patch, pontas de 9 |
| Linha de lista | **perde a caixa por completo** em repouso: a identidade é um feixe vertical de 3 px na aresta esquerda, que engorda para 6 px no hover e abre o corte quando selecionada — três estados com uma forma só | 430 × 90, folga 6, quatro visíveis |
| Ícone | uma **passada**, não um redesenho: contorno escuro de 1 px só embaixo-direita, faceta clara de 1 px em cima-esquerda — é o que faz o Shikashi e o Board Game pertencerem à mesma mão | 32 nativo, usado em 16/32/48 |
| Tipografia | sombra dura de 1 px na cor da sala **exclusiva** para 36 e 54; +1 de espaçamento nos rótulos maiúsculos, que viram gravação na mesa | a escada 18/26/36/54 |

**A cor parte em dois sistemas que hoje não existem separados:** *matéria* é neutra em
quatro degraus, sem matiz; *estado* é saturação cheia, sem trava, e só aparece em **quatro
lugares por tela** — o feixe da linha, o corte do painel, o preenchimento da barra e o anel
sob a criatura. Uma tela de um elemento fica **96% neutra e 4% queimando**.

**As cinco assinaturas:**

1. o canto cortado com o feixe dentro;
2. o feixe de 3 px à esquerda — o mesmo sinal em toda escala (3 px numa linha, 6 num
   cartão, 12 no painel de equipe da arena);
3. a sombra dura de 3 px, nunca desfocada;
4. **a fissura** — um risco de cabelo de 1 px, *desenhado à mão*, um por tela, nunca
   centrado, nunca simétrico, sempre cruzando um canto. É o único elemento do jogo que não
   sai de uma regra. Custa à artista uma tarde para as seis;
5. a franja cromática de 1 px nos números grandes: ciano na borda esquerda do glifo,
   vermelho quente na direita — como se visto pelo vidro.

**Das referências que você citou:** do Balatro aprende-se **peso**, não arredondamento — o
que ele faz é preenchimento sólido + sombra dura + "isto é um objeto que dá para pegar"; o
canto arredondado é consequência, e copiá-lo faria o PRISMON parecer um clone com cartas
piores, enquanto **o corte faz o mesmo serviço dizendo prisma**. Do Demonschool aprende-se
que **lista não precisa de caixa** — hierarquia por tipo, alinhamento e uma barra de
acento, zero recipientes; o projeto já teve esse insight em `card_button.gd:81-84` e só o
aplicou pela metade. Não copiar o preto-e-vermelho dele: o charme do PRISMON tem de vir das
criaturas.

### O briefing da artista precisa de uma página ZERO

`docs/PRISMON_pecas_de_interface.pdf` dá as medidas com precisão exemplar — e **as palavras
prisma, refração, Domador, elemento-como-estado e criatura não aparecem em nenhuma das 7
páginas**. As cinco referências são todas sobre **forma** e nenhuma sobre **assunto**. Uma
artista que executar este briefing com perfeição entrega um kit de UI pixel art competente
e genérico — que é o problema atual, redesenhado.

*Acrescentar uma página zero com três coisas: (1) o que o jogo é numa frase — "você não
comanda monstros, você comanda o campo elemental em que eles lutam"; (2) o gesto que se
repete, com desenho; (3) as três palavras que a arte tem de dizer — vidro, corte, feixe.*
E trocar o "as cores ficam a seu critério" por uma regra dura: matéria neutra, estado
saturado, e o saturado nunca acima de 5% da tela.

### E a ficção está trancada atrás de um bug

A **única prosa com voz do projeto inteiro** está em `data/random_events.json`. As 5
espécies têm **0 campos `text`**; os temas inimigos têm `text` vazio; os 28 itens são
"+12 ATK". E os 7 eventos de Acaso são **inalcançáveis**: `evento_apos_combate` não contém
`"acaso"`, então `ScreenChance`, `EventGen.chance_offer/resolve_chance/_apply_op`,
`Run.cook_free` e o bloco `momentos.acaso` estão todos mortos — enquanto o README e o
NOTAS continuam anunciando o momento.

**100% da ficção do PRISMON está trancada atrás desse bug.**

---

## 8. O que fazer, em ordem

### Agora — uma linha cada, impacto desproporcional

1. `roster_rail.gd:79` — `size_flags_horizontal = SIZE_EXPAND_FILL` e apagar o `spacer()`.
   **Os nomes do elenco voltam a existir.**
2. `combat_sim.gd:901` — apagar. **Controle para de durar o dobro.**
3. `autoplay.gd:474` — tirar o `,%d` final. **O CSV volta a produzir números.**
4. `README.md:64-65` — apagar a promessa da auto-pausa deletada; `README:188-202` — refazer
   a tabela com os números medidos.
5. `data/tuning.json` — reescrever `_hp_scale_doc` com o valor que está no arquivo.

### Esta semana — a cerca, antes de qualquer rebalanceamento

6. **Bloco `[cobertura de dados]` no `smoke_test`**, no molde do `[arena e modificadores]`
   que já roda verde. É a mudança única que apaga metade do mapa.
7. Consertar o que ele acusar — começando pelos **dois Coros**, porque o balanceamento da
   Coalla depende disso.
8. **Dar lado ao Domador** (`team_mods[src.side if src != null else 0]`) e afrouxar os dois
   portões de Energia. É o que transforma o Ativo de botão em peça de build.
9. `combat_sim.gd:760-769` — trocar o laço da Coleira por `_deal`.
10. Remedir tudo com `--runs=1000`.

### Depois — o que muda a percepção

11. **`ui.gd:208`**: parar de modular o miolo. Cache de `ImageTexture` por par (célula,
    cor) — `build_ui_sheet.py` já compõe borda e miolo separadamente e sabe quais pixels
    são quais. **Sozinho, dá corpo a todo painel do jogo.**
12. `UI.panel()` honrar o `bg` — uma linha, e sete salas aparecem onde hoje há uma.
13. **Sombra dura de 3 px** em toda lajota, num lugar só. A mudança mais barata da lista e
    a que mais muda a percepção.
14. **Câmera no centróide** (5 linhas em `to_screen`) — a briga volta para o meio da tela.
15. **Agregação de floater por `dst`** — o borrão de números acaba.
16. **Hit-flash + dissolve na morte** (a camada de silhueta) — o combate passa a reagir.
17. **Áudio.** Seis sons pendurados em eventos que o `CombatSim` já emite e o `FieldView`
    já consome: `hit`, `reaction` (tingido pelo `color` do JSON), `death`, `active_cast`,
    um loop de ambiente por arena, e um clique de UI. Mais duas chaves em
    `ScreenOptions.PADRAO` — a tela é montada a partir do mapa, então o layout não muda.
18. **Save de run** e a semente na tela de fim.

### Decisões que são suas, não minhas

- **A duração de combate.** 12,5 s contra o alvo de 28 s do §17.4. A contradição
  §18-vs-§17.4 está documentada, mas hoje o efeito colateral é concreto e medido: **15% dos
  combates não oferecem um Ativo sequer** (52% no nó 2). Ou o alvo muda, ou `energy_start`
  entra.
- **O Acaso volta ou sai?** Se volta, o preço é o terceiro slot da Mão. Se sai, precisa
  estar escrito, e README/NOTAS precisam parar de anunciá-lo.
- **A economia.** Cortar renda derruba a vitória; abrir ralo (mais ofertas, preços × 1,6)
  derruba mais ainda. Não dá para consertar por um lado só — é uma decisão de desenho.

---

## Apêndice — os 121 achados

Um por linha, agrupados por frente e ordenados por severidade. A coluna *verif.* só existe nas quatro frentes técnicas, que passaram pela checagem adversarial; as de visual e identidade não são alegações de fato verificáveis por refutação.


### Simulação e mecânicas (13)

| sev. | esforço | verif. | achado | onde |
|---|---|---|---|---|
| **ALTO** | medio | ✅ confirmado | Os Ativos do jogador rodam "sem lado": nenhuma relíquia, ressonância ou PE chega neles | `src/sim/combat_sim.gd:925 (cast_active), :583 e :648 (mods), :651 (attacker_pe), :698 (energia por reação), src/sim/ability_runner.gd:152` |
| **ALTO** | pequeno | ✅ confirmado | Todo Controle dura o dobro do que o dado diz | `src/sim/combat_sim.gd:288-291 (laço de ação) e :901 (apply_control)` |
| **ALTO** | pequeno | ✅ confirmado | Coleira Compartilhada: o dano repartido não mata, não aparece na tela e evapora quando você fica sozinho | `src/sim/combat_sim.gd:760-769` |
| **ALTO** | pequeno | ✅ confirmado | Quatro chaves de item/relíquia que ninguém lê, e dois totens com o sinal invertido | `src/run/combat_builder.gd:118-122, src/sim/combat_sim.gd:102, src/run/unit_instance.gd:151, data/items.json, data/relics.json` |
| **ALTO** | pequeno | ✅ confirmado | A arena Campo Magnético não faz absolutamente nada — e anuncia na tela que fez | `src/sim/combat_sim.gd:168 e :175, src/sim/sim_unit.gd:174-181, data/enemies.json (campo_magnetico), shots/05_combate.png` |
| médio | pequeno | ⚠️ parcial | Com hp_scale 3.7, as passivas elementais viraram ruído — e a justificativa escrita do escalar está vencida duas vezes | `data/tuning.json:27-28 (_hp_scale_doc e hp_scale), data/elements.json (passive_value), src/sim/combat_sim.gd:360-388` |
| médio | pequeno | ✅ confirmado | O Prisma cobra 50 de Energia por nada se o alvo morrer enquanto você escolhe o elemento | `src/ui/screen_combat.gd:373-386 e :332-338, src/sim/combat_sim.gd:920 e :930-931, src/sim/ability_runner.gd:189-191` |
| médio | medio | ✅ confirmado | Em 8 dos 10 temas é a arena que escolhe a reação, não a sua equipe | `src/sim/combat_sim.gd:153-159 (mare_elemental), src/sim/aura_state.gd:83 e :87-92, src/sim/reaction_resolver.gd:65-66, data/enemies.json (themes/ar…` |
| médio | medio | ⚠️ parcial | A Mão do Domador tem escolha de QUAL, nunca de QUANDO — e nos dois primeiros combates nem isso | `data/tuning.json (run.start_actives, momentos.evento_apos_combate), src/sim/combat_sim.gd:907-926 (can_cast/cast_active), medido em tools/autoplay.…` |
| médio | pequeno | ✅ confirmado | O CSV do autoplay sai com o formato literal em todas as linhas — a trilha de evidência do balanceamento está quebrada | `tools/autoplay.gd:474` |
| médio | medio | ✅ confirmado | O smoke_test prova arena e modificador de bando com simulação real, e nunca faz o mesmo com item, relíquia ou ressonância | `tools/smoke_test.gd:92-100 ([matriz de reacoes]) e :717-824 ([arena e modificadores])` |
| baixo | pequeno | ✅ confirmado | O texto da Vaporizar mente na tela de Sinergias | `data/reactions.json:32-38, shots/04b_sinergias.png (cartão superior direito)` |
| baixo | pequeno | ✅ confirmado | Resistência Elemental é fachada completa, e tuning.json tem duas seções inteiras que ninguém lê | `src/sim/sim_unit.gd:30 e :195-196, src/sim/combat_sim.gd:202 e :934, src/sim/reaction_resolver.gd:16 e :52, data/tuning.json (prices, targets, comb…` |

### Run, economia e decisões (15)

| sev. | esforço | verif. | achado | onde |
|---|---|---|---|---|
| **ALTO** | medio | ✅ confirmado | O Éter não é escasso em momento nenhum: 45% de tudo que entra morre na bolsa | `data/tuning.json:106-107 (ether_min/max), src/run/node_gen.gd:161-167, data/tuning.json:224-235 (momentos.loja)` |
| **ALTO** | pequeno | ✅ confirmado | Os 7 eventos de acaso, a tela ScreenChance e o bloco momentos.acaso são inalcançáveis numa run | `data/tuning.json:210-219 (evento_apos_combate), data/random_events.json (7 eventos), src/ui/screen_chance.gd, src/ui/main.gd:307-315, src/run/event…` |
| **ALTO** | medio | ✅ confirmado | Nenhum dos três limites declarados da run aperta — Vínculo, Estômago e slots de item ficam todos folgados | `src/run/run_state.gd:131-150 (bond), src/run/unit_instance.gd:79-104 (slots/estômago), data/tuning.json:100-104 e 116-121` |
| **ALTO** | pequeno | ✅ confirmado | O CSV do autoplay sai com 400 linhas de '%d,%s,%d,...' — o único export de dados da run está quebrado | `tools/autoplay.gd:474` |
| **ALTO** | pequeno | ✅ confirmado | Um segundo Núcleo é silenciosamente inerte — e a tela promete a troca de Afinidade que não vai acontecer | `src/run/unit_instance.gd:53-60, src/ui/screen_shop.gd:142-146, src/run/run_state.gd:371-374` |
| médio | medio | ⚠️ parcial | A progressão por cópias (a Muda) é 100% inerte, e arrasta metade do bloco 'evolution' junto | `data/species.json (nenhum evolves_to), src/run/run_state.gd:162-177 e 397-399, src/run/unit_instance.gd:180-197, src/run/enemy_gen.gd:46-55, data/t…` |
| médio | pequeno | ✅ confirmado | O primeiro combate de TODA run é o mesmo: Cardume Profundo, 2 Hipocampos, 20 Éter, 1 estrela | `src/run/node_gen.gd:28-39 + data/tuning.json:169-188 (danger_max/min_by_node) + data/enemies.json:13-20` |
| médio | pequeno | ⚠️ parcial | A sequência fixa não precisa ser esta: 'recruta,poder,recruta,loja,cozinha,recruta,poder,loja' mede 42% de vitória contra os 38% da atual | `data/tuning.json:209-219 (_loja_duas_vezes + evento_apos_combate), src/run/event_gen.gd:17-21` |
| médio | pequeno | ⚠️ parcial | O eixo de Risco paga 4 a 12 Éter numa economia que sobra 121 — a única decisão por nó não custa nada | `src/run/node_gen.gd:108-113, data/tuning.json:168 (reward_per_danger 0.18), shots/10_run_escolha.png (canto inferior, os dois cartões)` |
| médio | pequeno | ⚠️ parcial | A relíquia é a peça mais forte do jogo e entra por uma porta só — 42% das runs terminam sem nenhuma | `src/run/event_gen.gd:87-95, data/tuning.json:231-232 (reliquia_chance 0.35, reliquia_preco 38)` |
| médio | pequeno | ⚠️ parcial | hp_scale 3.7 multiplica o +HP de itens e pratos, mas não o ATK/DEF — o número no cartão não é o número na briga | `src/run/combat_builder.gd:101, src/run/unit_instance.gd:111-137, data/tuning.json:27-28 (_hp_scale_doc)` |
| médio | pequeno | ✅ confirmado | A Cozinha e a Loja não são escolhas: 675 de 675 pratos e 0 de 364 visitas sem compra | `src/run/event_gen.gd:104-129 (kitchen_offer), data/tuning.json:241-246, src/ui/screen_kitchen.gd` |
| médio | medio | ✅ confirmado | Coração Instável não tem o lado ruim, e Livro de Receitas não faz nada | `data/relics.json:4-6 e 40-42, src/run/run_state.gd:317-318` |
| médio | grande | — | Metade do catálogo é '+X número' — e o problema não é a proporção, é que o jogador leva todos | `data/items.json (28 itens), data/dishes.json (7 pratos), data/relics.json (10 relíquias)` |
| baixo | pequeno | ✅ confirmado | Dados mortos em tuning.json: o bloco 'prices' inteiro e mais quatro chaves nunca lidas | `data/tuning.json:133-150 (prices), :98 (acts), :105 (start_team_size), :109 (heal_between_nodes_pct)` |

### Balanceamento medido (16)

| sev. | esforço | verif. | achado | onde |
|---|---|---|---|---|
| **ALTO** | pequeno | ⚠️ parcial | A curva de dificuldade e um dente de serra de contagem de corpos, nao uma curva | `src/run/node_gen.gd:156-158 (enemy_count_for) + data/tuning.json:158-160 e 226-235 (eve…` |
| **ALTO** | medio | ⚠️ parcial | FOGO (apollo) decide a run; AGUA (hipocampo) e negativo | `data/species.json (5 especies) + data/enemies.json (chefe)` |
| **ALTO** | pequeno | ✅ confirmado | Ressonancia e, na pratica, um sistema do INIMIGO | `src/run/combat_builder.gd:68-86 (_enemy_mods) + data/enemies.json (temas) + …` |
| **ALTO** | pequeno | ⚠️ parcial | 15% dos combates nao oferecem UM Ativo; no no 2 sao 52% | `data/tuning.json:5 (energy_per_second 2.6) + data/actives.json (meteoro custa 40) + C:/…` |
| **ALTO** | pequeno | ⚠️ parcial | Nao existe atrito entre nos: heal_between_nodes cura 100% e heal_between_nodes_pct e ignorado | `src/run/run_state.gd:413-416; chamado em src/ui/main.gd:277; chave em …` |
| **ALTO** | pequeno | ✅ confirmado | O medidor nao falseia: o bloco targets e dado morto e os limiares estao hardcoded no .gd | `data/tuning.json:190-205 contra tools/autoplay.gd:332-355` |
| **ALTO** | pequeno | ✅ confirmado | O --csv do autoplay grava um arquivo com zero dados | `tools/autoplay.gd:474-477` |
| **ALTO** | pequeno | ✅ confirmado | hp_scale e hoje o maior botao de dificuldade do jogo, e o _doc dele diz o contrario | `data/tuning.json:27-28 (e 155-157 para power_last); tabela em NOTAS.md:45-51` |
| **ALTO** | medio | ✅ confirmado | Eter nao e moeda, e placar - e isso mata o eixo Risco | `data/tuning.json:106-107 (ether_min/max), 168 (reward_per_danger), 216-222 (loja)` |
| médio | pequeno | ✅ confirmado | O chefe nao e dificil, e comprido - e a razao escrita para boss_duration 90 nao se reproduz mais | `data/tuning.json:37-38 (boss_duration e _boss_duration_doc), 162 (boss_power)` |
| médio | pequeno | — | A tabela de balanceamento do README esta errada nas seis linhas | `README.md:188-202` |
| médio | pequeno | ✅ confirmado | O relatorio de composicoes vencedoras nao consegue ver a build dominante - ele fragmenta por permutacao | `tools/autoplay.gd:96-99 (monta 'els' na ordem do time) e 363-372 (imprime)` |
| médio | pequeno | ⚠️ parcial | Vinte e quatro chaves de tuning.json nao fazem diferenca nenhuma | `data/tuning.json (linhas 29, 55, 56, 78, 83, 100-105, 108-109, 119, 122-131, 134-142, 161, 190-205, 236-240)` |
| médio | pequeno | ✅ confirmado | A fadiga de cura mira numa faixa da distribuicao que quase nao existe | `data/tuning.json:39-42` |
| médio | pequeno | ⚠️ parcial | O protocolo de medicao do README (--runs=200) nao resolve a faixa de 10 pontos que ele julga | `README.md:32 e 188; tools/autoplay.gd:11 (runs := 60)` |
| baixo | pequeno | ✅ confirmado | Vinculo nunca aperta em nenhuma run | `data/tuning.json:100-105` |

### Comportamento da interface (13)

| sev. | esforço | verif. | achado | onde |
|---|---|---|---|---|
| **ALTO** | pequeno | ✅ confirmado | O trilho do elenco não mostra nome nenhum: o rótulo é cortado para 1 px | `src/ui/roster_rail.gd:78-82 (visível em shots/11_run_preparacao.png e shots/13_run_evento.png, coluna esquerda, y≈130-290)` |
| **ALTO** | pequeno | ✅ confirmado | A fita da run desenha os dois momentos de Poder como se fossem combate — e o tooltip mente | `src/ui/run_ribbon.gd:52-58, 82-89 e 92-99 (visível no topo de shots/12_run_log.png, células 4 e 12 da esquerda para a direita)` |
| **ALTO** | medio | ✅ confirmado | Não dá para jogar uma run sem mouse: o bloqueio é a SEGUNDA tela | `src/ui/card_button.gd:50; src/ui/screen_starter.gd:33-36,50-54; src/ui/ui.gd:306; src/ui/prisma_theme.gd:106` |
| médio | pequeno | ⚠️ parcial | No combate, clicar qualquer botão com o mouse desliga ESPAÇO e TAB | `src/ui/screen_combat.gd:120-127, 166-174 e 353-369` |
| médio | pequeno | ✅ confirmado | O quarto tooltip grudado: o tween de entrada nunca é morto, e o REENGATE garante que ele bata na dica seguinte | `src/ui/tooltip_layer.gd:154-171 (_assentar), 173-179 (_esconder), 104-109 (_atraso), 31 (REENGATE)` |
| médio | pequeno | ✅ confirmado | Na Feira o COMPRAR morre em silêncio quando falta Éter; na Cozinha a mesma situação é escrita na cara | `src/ui/screen_shop.gd:80-91 contra src/ui/screen_kitchen.gd:79-85; src/ui/pick_panel.gd:281` |
| médio | medio | ✅ confirmado | Não existe save, não existe sair da run, e as Configurações ficam trancadas fora dela | `src/ui/main.gd:201-217 e 341-346; src/ui/screen_options.gd:9-14` |
| médio | pequeno | ⚠️ parcial | Dois botões "LUTAR" para o mesmo ato, e no chefe são duas confirmações seguidas sem decisão | `src/ui/screen_map.gd:37-38 e 107-110; src/ui/screen_prep.gd:51-54; tools/smoke_test.gd (asserção "no 9 e o chefe (opcao unica)")` |
| médio | pequeno | — | O momento "Acaso" está inteiro no projeto e é inalcançável — README e NOTAS ainda o anunciam | `data/tuning.json → momentos.evento_apos_combate; src/run/event_gen.gd:17-21; src/ui/screen_chance.gd (182 linhas); README.md:81; NOTAS.md:577,580` |
| médio | medio | ✅ confirmado | O log de derrota só tem o SEU lado: não dá para descobrir o que o inimigo fez | `src/sim/combat_sim.gd:950-984; src/ui/screen_result.gd:29-45 e 147-201` |
| baixo | pequeno | — | O hover dos botões de Ativo no combate é sobrescrito 60 vezes por segundo | `src/ui/screen_combat.gd:245-256 (linha 255) contra src/ui/ui.gd:310 e src/ui/juice.gd:97-104` |
| baixo | pequeno | ✅ confirmado | Dica morta: o medalhão do dono na Feira tem tooltip que nunca aparece | `src/ui/pick_panel.gd:291-297; src/ui/tooltip_layer.gd:115-136` |
| baixo | pequeno | ⚠️ parcial | Jargão de engine na tela do jogador: "limite de ticks" e "aniquilacao mutua" | `src/sim/combat_sim.gd:306 e 320; src/ui/screen_result.gd:31-32` |

### Composição do combate (12)

| sev. | esforço | achado | onde |
|---|---|---|---|
| **ALTO** | medio | A briga acontece na casa do inimigo, nunca no centro da elipse — e o centro da elipse já não é o centro da tela | `src/sim/combat_sim.gd:1083-1107 (_desired_position) e :1204-1210 (_clamp_arena); src/ui/screen_combat.gd:60-86` |
| **ALTO** | pequeno | A agregação de dano e o teto de números por unidade são calculados num disco de 10 px, não pelo alvo — nenhum dos dois funciona com o alvo andando | `src/ui/field_view.gd:342-384 (linhas 360, 362, 372) e :266-268` |
| **ALTO** | pequeno | O nome da criatura é destruído pelos números de dano — a reserva de espaço ignora justamente o elemento mais numeroso da tela | `src/ui/field_view.gd:483-559 (_resolver_nomes, a lista `ocupado` e a lista `corpos`)` |
| **ALTO** | medio | O tint de cada arena é o hex exato do elemento que luta nela — figura e fundo com a mesma cor, por construção | `data/enemies.json (arenas[].tint) x data/elements.json (color); src/ui/field_view.gd:23-26, 240-242; assets/arenas/pecas/*` |
| médio | pequeno | O alocador de pistas das faixas de reação libera a pista aos 0.6 s, mas o desenho ainda pinta o rótulo até 1.1 s a 100% de alfa | `src/ui/field_view.gd:425 contra :456 e :722` |
| médio | medio | Os anúncios de reação moram numa linha fixa do céu, a até 580 px de onde a reação aconteceu | `src/ui/field_view.gd:719-735 (y3 = 68.0 + lane*(UI.fs(20)+9)) e a justificativa em :723-728 / NOTAS.md §5.7` |
| médio | medio | O piso é só contorno: seis elipses concêntricas com mais contraste que a própria superfície | `src/ui/field_view.gd:651-665; src/ui/arena_chao.gd:42-46 e :64-71` |
| médio | pequeno | O achatamento das marcas de chão (SQUASH 0.34) não bate com o achatamento real do piso (0.443) | `src/ui/field_view.gd:127-139 (const SQUASH := 0.34), usado em :800, :813, :830, :869, :875, :877, :882, :933-942` |
| médio | pequeno | A barra de vida da criatura tem 4 px, largura de referência que muda por espécie, e trilho preto sem moldura | `src/ui/field_view.gd:850-855` |
| médio | pequeno | Duas criaturas com o mesmo nome e nenhuma marca de lado — e o rótulo é duas vezes mais largo que a criatura | `src/run/enemy_gen.gd:88 e src/run/combat_builder.gd:95 (display_name = nome da espécie); src/ui/field_view.gd:755-763 e :488` |
| médio | medio | Três grades diferentes na mesma tela: nada se alinha com nada | `src/ui/screen_combat.gd:19 (const BAR_W := 1180.0), :99-103 e :139-142 (CenterContainer), contra :60-86 (a linha do meio)` |
| baixo | pequeno | shots/05_combate.png mente: o painel da equipe está congelado no quadro zero | `tools/screenshots.gd:150-158 (compare com :283-285)` |

### Composição dos menus (16)

| sev. | esforço | achado | onde |
|---|---|---|---|
| **ALTO** | pequeno | Os nomes do elenco somem no trilho da esquerda — sobra um pixel de texto | `src/ui/roster_rail.gd:78-82` |
| **ALTO** | pequeno | O botão de confirmar contradiz a folha de peças do próprio projeto, e tem quatro cores | `docs/pecas/botoes.png · src/ui/pick_panel.gd:235,279 · screen_prep.gd:51 · screen_map.gd:83,107` |
| **ALTO** | grande | Preparação: o painel mais largo tem o menor conteúdo e o mais estreito é o que corta | `src/ui/screen_prep.gd:28-40,296-333 · shots/04_preparacao.png` |
| **ALTO** | pequeno | Recruta: as duas opções não ficam na mesma linha, e a própria tela prova que dá para alinhar | `src/ui/screen_recruit.gd:64,91-98 · shots/07a_recruta.png vs shots/13_run_evento.png` |
| médio | pequeno | A fileira de nomes do Rancho escorrega 27 px — a correção registrada resolveu metade da causa | `src/ui/ranch_view.gd:55-62,98 · shots/04_preparacao.png, shots/03_escolha_de_combate.png` |
| médio | pequeno | A moeda de Éter aparece com metade do tamanho justamente onde se gasta dinheiro | `src/ui/pick_panel.gd:191 · docs/pecas/icones.png · shots/07b_loja.png, 07d_cozinha.png` |
| médio | medio | Na cozinha, a barra verde grande é HP; o número que decide é cinza e pequeno | `src/ui/picker_overlay.gd:87-95 · src/ui/screen_kitchen.gd:104-110 · shots/07e_cozinha_escolha.png` |
| médio | medio | Perigo e inimigos são mostrados em dois alfabetos diferentes em telas consecutivas | `src/ui/screen_map.gd:83,102,128-139 vs src/ui/screen_prep.gd:64-73 · ui.gd:366` |
| médio | pequeno | A barra de rolagem roxa aparece cheia e berrante onde não há nada para rolar | `src/ui/synergy_view.gd:314 · src/ui/screen_prep.gd:300 · prisma_theme.gd:153-174 · shots/04c_sinergias_pobre.png, 11_run_preparacao.png` |
| médio | pequeno | A faixa de título tem seis larguras diferentes; nas maiores as pontas viram adesivos | `src/ui/ui.gd:407-435 · todas as telas com banner` |
| médio | pequeno | A preparação é a única faixa em caixa mista — e é a tela mais visitada da run | `src/ui/screen_prep.gd:59 vs screen_chance.gd:34 e os títulos de PickPanel` |
| médio | medio | O log de combate pula 144 px para o lado e deixa 451 das 900 linhas vazias | `src/ui/main.gd:195 · src/ui/screen_result.gd:23,29,42 · shots/12_run_log.png` |
| médio | medio | O Acaso ocupa 11,8% da tela e esconde os números que já estão nos dados | `src/ui/screen_chance.gd:31-58 · data/random_events.json · shots/07c_acaso.png` |
| baixo | pequeno | O contador RODADA é 1,5x maior que o título da tela de escolha | `src/ui/screen_map.gd:38-39,74 · shots/03_escolha_de_combate.png, 10_run_escolha.png` |
| baixo | pequeno | O maior controle da tela de recruta é o botão de não fazer nada | `src/ui/screen_recruit.gd:39-41,54 · shots/07a_recruta.png` |
| baixo | pequeno | Três alturas de botão convivem; o padrão de 58 é quebrado justo na peça mais reusada | `src/ui/screen_prep.gd:50-51 · src/ui/pick_panel.gd:149,236,280 · ui.gd:302` |

### Partículas, efeitos e shaders (10)

| sev. | esforço | achado | onde |
|---|---|---|---|
| **ALTO** | pequeno | A criatura atingida não reage: não existe hit-flash — nem nada — no corpo | `src/ui/field_view.gd:259-268 (case "damage"), src/ui/monster_art.gd:204, src/ui/field_view.gd:787-855 (_draw_unit)` |
| **ALTO** | medio | Morrer não produz efeito algum — o evento `death` existe e ninguém o consome | `src/sim/combat_sim.gd:828 (emite) x src/ui/field_view.gd:213-323 (o match do feed, sem o caso)` |
| médio | medio | O piso são dois discos empilhados, e o degrau do disco interno é visível e mensurável | `src/ui/field_view.gd:651-660` |
| médio | pequeno | O anel de reação usa 54 px fixos e ignora o raio real que a reação causou | `src/ui/field_view.gd:276 e src/sim/combat_sim.gd:701-705` |
| médio | medio | As partículas ignoram completamente o combate — só existe clima | `src/ui/arena_particulas.gd (classe inteira); src/ui/field_view.gd:704` |
| médio | pequeno | Dois dos sete perfis de partícula são invisíveis — medi 0,016% do campo aceso no Campo Magnético | `src/ui/arena_particulas.gd:44-46 (campo_magnetico) e 55-58 (camara_de_estimulos); o `match` de atualizar em 125-133` |
| médio | pequeno | Ar quente no Solo Vulcânico dentro do shader que já existe — sem BackBufferCopy e sem CanvasGroup | `assets/shaders/cenario_fade.gdshader:72-87; src/ui/field_view.gd:892-917` |
| médio | pequeno | O brilho que o autor chamou de bloom: aditivo, sem backbuffer e sem shader nenhum | `src/ui/field_view.gd:672-677 (anéis), 737-739 (flash de tela)` |
| baixo | pequeno | O orçamento de desenho do combate está no TEXTO, não nas partículas — 9 para 1 | `src/ui/field_view.gd:742-746 (_outlined)` |
| baixo | medio | O perfil VISUAL de cada arena mora em .gd, não em data/enemies.json — adicionar uma arena hoje toca quatro arquivos | `src/ui/arena_particulas.gd:31-59 e src/ui/arena_chao.gd:169-173, contra data/enemies.json (bloco "arenas")` |

### Identidade visual (14)

| sev. | esforço | achado | onde |
|---|---|---|---|
| **ALTO** | medio | Não existe painel no PRISMON — existe contorno. O `modulate_color` do 9-patch apaga o corpo até o fundo da tela | `src/ui/ui.gd:193-208 (`frame()`, linha 208 `sb.modulate_color = tint`); prova na tela em shots/07b_loja.png, corte horizontal em y=400` |
| **ALTO** | pequeno | Sete cores de sala pedidas no código, zero renderizadas: `UI.panel()` joga o `bg` fora | `src/ui/ui.gd:223-226 (comentário literal: "`bg` deixou de ser usada"); 16 chamadas afetadas, entre elas src/ui/roster_rail.gd:21,68,89 · src/ui/com…` |
| **ALTO** | pequeno | A cor só é código, nunca atmosfera: `tint_of()` trava V em 0.78 e capa S em 0.55 para TODA borda do jogo | `src/ui/ui.gd:214-219 (`return Color.from_hsv(c.h, clampf(c.s * 0.62, 0.0, 0.55), 0.78)`); prova em shots/04b_sinergias.png, os 8 chips de reação na…` |
| **ALTO** | pequeno | Zero rotação, zero inclinação, zero sombra: toda a interface é retângulo alinhado ao eixo | `src/ui/ — busca por `rotation`, `skew`, `corner_radius` e `shadow` em todos os 40 arquivos` |
| **ALTO** | pequeno | Quatro telas diferentes são o mesmo retângulo, pixel a pixel — a cozinha não é uma cozinha | `shots/07b_loja.png, shots/07d_cozinha.png, shots/07f_poder.png, shots/07g_troca.png — caixa envolvente do conteúdo, medida` |
| **ALTO** | pequeno | O briefing da artista descreve caixas com precisão e não diz o que é o jogo | `docs/PRISMON_pecas_de_interface.pdf, 7 páginas — caixa de destaque da pág. 1 e seção "Referências" das págs. 6-7` |
| médio | pequeno | Fora do combate o jogo é 95–98% de vazio chapado, e a justificativa escrita não cobre as telas onde isso acontece | `shots/08_chefe.png, shots/07c_acaso.png, shots/06_log_de_combate.png, shots/01b_opcoes.png — fração de pixels diferentes do fundo #0f0d18` |
| médio | medio | As sete arenas — a única identidade visual real do projeto — param num contorno de 1px e nunca saem do combate | `assets/arenas/ (7 arenas × 8 camadas de parallax + .aseprite com adereços colocados à mão); prova em shots/05_combate.png e shots/11b_run_combate.png` |
| médio | pequeno | O glifo mais repetido da interface vem do fallback do sistema operacional | `assets/CREDITOS.md, seção "Nota sobre os símbolos"; ocorrências contadas em src/; prova em shots/04b_sinergias.png (os 8 chips "◆◆") e shots/03_esc…` |
| médio | pequeno | O trilho do elenco — a moldura permanente da run, 288×864 px — não mostra nome nenhum | `src/ui/roster_rail.gd:79 (`rname.clip_text = true`) e :82 (`hrow.add_child(UI.spacer())`); visível em shots/09_hud_e_escolha.png, shots/11_run_prep…` |
| médio | medio | Os números de dano se empilham em ilegibilidade: o corredor de pistas existe e não foi aplicado a eles | `src/ui/field_view.gd:342 (`_push_floater`, sem pista) contra :395 (`_push_pop`, com a busca de pista das linhas 410-440); prova na região x=1140..1…` |
| médio | pequeno | O kit de molduras tem oito peças; quatro são decoradas e o jogo usa as decoradas em UM lugar | `src/ui/ui.gd:178-190 (as 8 células) contra a contagem de uso em src/; única chamada decorada em src/ui/card_button.gd:95` |
| médio | medio | O logotipo é a única coisa com mão no jogo inteiro, e ele não sai da primeira tela | `shots/01_titulo.png (letreiro entre x=470..1130, y=150..405) contra shots/02_iniciais.png, a tela imediatamente seguinte` |
| baixo | pequeno | A tira de 9 cores no topo do título lê como paleta de mockup — é o elemento mais "gerado" da primeira tela | `src/ui/screen_title.gd:33-43; visível em shots/01_titulo.png na faixa y=110..124, x=440..1160` |

### Crítico de completude (12)

| sev. | esforço | achado | onde |
|---|---|---|---|
| **ALTO** | medio | PRISMON não tem um som. Zero áudio no projeto e zero menção em 1283 linhas de NOTAS. | `projeto inteiro; src/ui/screen_options.gd:19-24 (as 4 opções, nenhuma de volume); NOTAS.md (1283 linhas); README.md` |
| **ALTO** | pequeno | A auto-pausa que o README promete como o onboarding do jogo é um `pass` — e uma frente citou ela como viva. | `src/ui/screen_combat.gd:241-242 (corpo `pass`), :25 (`_auto_paused` morto), :231 (chamada inerte); README.md:64-65` |
| **ALTO** | pequeno | Os Coros de Gelo e de Natureza não fazem absolutamente nada — 2 das 10 ressonâncias são mods que nenhum .gd lê. | `data/resonances.json (GELO coro → `dmg_vs_gelido` 0.15; NATUREZA coro → `dmg_vs_esporo` 0.15); src/sim/ e src/run/ inteiros` |
| **ALTO** | pequeno | Ninguém revisou a tela de fim de run porque a ferramenta de prints não a captura — e ela é a única tela do jogo que nunca foi discutida. | `tools/screenshots.gd:66-252 (16 telas capturadas, ScreenEnd ausente); src/ui/screen_end.gd (66 linhas); shots/ (26 PNG); NOTAS.md` |
| **ALTO** | medio | CONTRADIÇÃO: a dupla inicial que decide a run não é a que a frente `numeros` disse — apollo está ABAIXO da média e hipocampo acima, medido em 1000 runs. | `contradiz o achado [alto/balanceamento] da frente numeros ('FOGO (apollo) decide a run; AGUA (hipocampo) e negativo'); tools/autoplay.gd:55-60 (con…` |
| **ALTO** | medio | A CLASSE que ninguém nomeou: 'declarado nos dados, nunca lido pelo código'. Oito frentes acharam pedaços; a mudança única é uma asserção de cobertura no smoke_test. | `tools/smoke_test.gd (a asserção que falta); atravessa data/tuning.json, items.json, relics.json, resonances.json, elements.json, enemies.json, spec…` |
| médio | pequeno | O único bloco de cor opaca do jogo inteiro é sempre o MESMO vermelho, e o parâmetro que existe para mudá-lo tem zero chamadas. | `src/ui/ui.gd:407 (assinatura) e :426 (`sb.modulate_color = tint`); os 6 call sites: pick_panel.gd:87, screen_chance.gd:34, screen_options.gd:67, sc…` |
| médio | pequeno | A única prosa do jogo está no único arquivo que o jogador nunca alcança — o resto do catálogo é ficha técnica. | `data/random_events.json (7 eventos) x data/species.json, data/items.json, data/dishes.json, data/enemies.json` |
| médio | pequeno | A metade 'aura sozinha' do combate nunca é explicada — e a frase que explicaria já está escrita nos dados, intocada. | `data/elements.json (campos `passive` e `passive_text` dos 5 elementos do slice); src/ui/synergy_view.gd (a tela de Sinergias inteira); shots/04b_si…` |
| médio | medio | Os quatro primeiros dos nove nós carregam 0,8% das mortes — a metade da run que todo jogador vê toda vez não tem aposta nenhuma. | `medido em tools/autoplay.tscn --runs=1000; causas em src/run/node_gen.gd:156-158 (enemy_count_for) e data/tuning.json:169-188 (danger_max/min_by_node)` |
| baixo | pequeno | A frase que justifica a arquitetura headless descreve um lote que não pode ter existido. | `README.md:175 e README.md:188` |
| baixo | pequeno | F11 e a opção 'Tela cheia' saem de sincronia, e a tela de Configurações passa a mentir sobre o próprio estado. | `src/ui/main.gd:341-346 (F11) contra src/ui/screen_options.gd:54-56 (_aplicar_janela) e :112-118 (o botão)` |

---

## Apêndice B — o que está bom e não deve ser mexido

Cada frente foi obrigada a listar forças com o mesmo rigor dos defeitos.


**Simulação e mecânicas**

- A separação do §22.3 é real, não declarada: `grep -n "Node\|scene\|get_node" src/sim/*.gd` não encontra nada em 1969 linhas de simulação. Isso não é cosmético — é o que me permitiu rodar 200 runs completas (1539 combates) em 51 s e o que torna cada número deste relatório verificável em vez de opinável.
- O determinismo é levado a sério até o detalhe irritante. Todos os desempates são por id ou species_id (combat_sim.gd:539, :549, :556, :235), o embaralhamento de `enemy_random_distinct` usa o RNG semeado do sim (ability_runner.gd:254-260), `_separate` desempata dois corpos no mesmo pixel por id sem sorteio (combat_sim.gd:1146), e `_layout` reordena `units` uma vez para dar ordem estável ao resto do combate. A seção [determinismo] do smoke_test passa.
- `max_reaction_chain` fecha a recursão Eletrocussão -> chain -> strike -> Eletrocussão POR CONSTRUÇÃO, e o comentário em combat_sim.gd:63-69 explica que antes ela terminava por acidente (as auras acabavam) até as arenas encharcarem o campo inteiro. O teste [cadeia de reacoes termina] fecha o laço com evidência: 2,9 s, 19 reações, `_react_depth` de volta a zero.
- A regra de imunidade a Controle dentro do resolvedor (reaction_resolver.gd:93-97) é o tipo de achado que quase ninguém encontra: sem ela, Congelar queimava 2 UA por golpe durante os 5 s de imunidade — um imposto invisível em toda build de Gelo. Está implementada com `continue` (a próxima aura ainda pode reagir), não com `return`, que é a forma certa.
- O par `separation_settle` + `_leash_to_target` resolve um problema real com números medidos nos dois sentidos da troca (tuning.json `_separation_settle_doc`: 1.0 -> 83% de remexida e 4,6% de pares encavalados; 0.5 -> 52% e 7,5%; 0.0 -> 33% e 12,7%). Rodei o movimento_probe agora e ele reproduz: 51,9% e 6,5%. Escolher 0.5 com a tabela na mão é engenharia de jogo, não chute.
- A fadiga de cura (combat_sim.gd:845-860) mata a forma dominante de impasse sem precisar mexer em dano, e o `_heal_falloff_doc` registra o compromisso explicitamente (aos 18 s/0.045 a vitória cai para 33%; aos 30 s/0.025 fica em 36% e os impasses caem ~20%). No autoplay de agora, `Arcano/Curandeiro x Curandeiro` aparece 10 vezes em 93 impasses — deixou de ser a forma única.
- O vocabulário de ops do AbilityRunner com `push_warning` em vez de crash para op desconhecida (ability_runner.gd:164-165) é o que permite o dado andar à frente do código. A matriz de reações em Db com lookup O(1) e `reactions_between()` alimentando a tela de Sinergias (shots/04b_sinergias.png) faz o sistema inteiro ficar legível ao jogador numa tela só — as 8 reações, o `kind`, o multiplicador e o custo em UA, tudo vindo do mesmo JSON que o simulador executa.
- A instrumentação do autoplay é melhor do que a da maioria dos protótipos: vitória por dupla inicial, onde as runs morrem por nó, composição dos impasses com os Papéis nomeados, alcance de cada momento por passo. Foi ela que me deu os dois números mais úteis do relatório (dupla inicial de 55% a 5%; 51% das runs chegam ao passo 8) sem eu escrever uma linha de código.

**Run, economia e decisões**

- A ferramenta `--momentos=` do autoplay (tools/autoplay.gd:44-52) é a melhor coisa deste projeto. É um instrumento construído para responder exatamente a pergunta 'onde ponho a loja' sem editar dados a cada tentativa, e o comentário ao lado ('escolher onde a loja entra e uma decisao de alcance, e alcance se mede') é a frase que separa este projeto de um protótipo que chuta. Usei essa ferramenta para medir 6 arranjos de momentos nesta revisão — não precisei escrever nada.
- A métrica de ALCANCE POR PASSO (autoplay.gd:384-393) é uma invenção genuína e rara. 'Loja 38%' não diz se o problema é a loja ou o passo 8, e o autor percebeu isso e instrumentou a diferença. O resultado medido hoje (passo 1: 100%, passo 4: 96%, passo 6: 77%, passo 8: 50%) é o dado que deveria guiar toda decisão de conteúdo do jogo, e ele já existe.
- A disciplina de `_doc` nos JSON. `_loja_duas_vezes` (tuning.json:209) tem a aritmética, o número medido por arranjo e a razão de a Troca ter saído. `_hp_scale_doc`, `_heal_falloff_doc`, `_separation_settle_doc`, `_boss_power_doc` — cada constante controversa tem o experimento que a produziu escrito ao lado, com os dois valores testados. Isso é raro em projeto de uma pessoa só e é o que me permitiu discordar de coisas específicas em vez de palpitar em geral.
- O momento de Poder é o único que é uma decisão limpa, e é limpo por construção: 6 Ativos em data/actives.json, teto de 3 (max_actives), a run começa com um só, e há exatamente 2 momentos de Poder. O jogador termina TODA run sem metade da Mão do Domador, e a escolha é entre 3 cartas por vez. O comentário em tuning.json:114 explica por quê a run deixou de começar com os três — 'a unica agencia do jogador dentro do combate ja vinha pronta e nunca crescia'. É o desenho certo, e é o modelo para consertar a Loja e a Cozinha.
- O mecanismo `pendente` em EventGen.resolve_chance (event_gen.gd:251-263): o modelo não abre tela, devolve o que ficou por escolher e a tela resolve com os mesmos painéis da Feira. É a solução correta para 'o evento concede mas não decide', e o comentário registra o bug que ela mata (o evento sorteava o item E quem recebia, e podia reescrever a Afinidade de um Prismon qualquer sem avisar). É uma pena que esteja num sistema inalcançável.
- O `_blocker` da loja (screen_shop.gd:81-91) diz o motivo na cara — 'você não tem esse Prismon', 'nenhum Prismon com espaço de item' — em vez de apagar o botão. E o cancelamento do PickerOverlay devolve o Éter (screen_shop.gd:122-126), com o comentário certo: 'cancelar não pode custar nada, senão o painel vira uma armadilha e o jogador para de abrir'. Isso é atenção a uma classe de erro que a maioria dos protótipos só descobre em playtest.
- O determinismo por semente atravessa a camada de run inteira sem exceção: NodeGen.generate_pair (seed*7919 + index*104729), EventGen._rng (seed*4243 + index*7877 + salt), com sal distinto por tipo de momento e por `roll`. Reabrir uma tela não re-sorteia, e renovar muda de propósito. Isso é o que torna qualquer medição que eu fiz reproduzível — e é o que torna o bug do CSV o único furo real na cadeia de medição.
- O `passive_cap` em EnemyGen.compose (enemy_gen.gd:26-42): teto de unidades sem dano no bando inimigo, com a razão medida escrita ao lado ('tanque nao mata tanque em 45 s, e curandeiro alonga qualquer impasse'). O diagnóstico de impasses do autoplay confirma que o modo de falha é real (168 impasses em 400 runs, o mais comum sendo Arcano/Curandeiro x Curandeiro, 23 casos). O gerador foi corrigido pelo dado, não pela intuição.
- CombatBuilder como ponte única entre run e sim, com writeback explícito (combat_builder.gd:132-143) e sem piso de HP ('quem voltou nocauteado entra com 1 de HP mesmo. O piso antigo curava de graça quem tinha caído'). A separação do §22.3 está respeitada de verdade — foi por isso que consegui rodar 400 runs completas e uma sonda de economia sem tocar em uma única cena.

**Balanceamento medido**

- A separacao sim/cena do 22.3 nao e retorica: copiei APENAS data/, src/, tools/, scenes/ e theme/ para um projeto novo no scratchpad, removi o autoload do plugin de editor, e o autoplay reproduziu o original ate o ultimo digito (37% / 12.4 s / 5.5% / 2.18 / 35.6 / 89%, 3071 combates). Nao ha um unico numero de balanceamento preso a um Node. Isso e o que permitiu fazer 25 medicoes independentes neste review.
- O determinismo por semente e real e barato: 400 runs / 3071 combates em 59 a 109 s (148 a 271 ms por run). Rodadas repetidas com as mesmas sementes dao exatamente os mesmos numeros, inclusive entre o projeto original e a copia. Isso vale mais que qualquer alvo verde - e a base sem a qual nenhum dos achados acima seria verificavel.
- Os instrumentos que o autoplay JA tem sao melhores que os da maioria dos prototipos: o histograma de 'onde as runs morrem' e o 'alcance por passo' (passo 4 = 96% das runs, passo 8 = 50%) sao exatamente o par de numeros que a maioria dos roguelites nunca mede. Foi deles que saiu, sem nenhuma instrumentacao minha, a primeira versao da curva de vitoria por no.
- A experiencia registrada em _loja_duas_vezes (tuning.json:207-212) e ciencia de verdade: tres arranjos medidos com 240 runs cada, com os tres resultados escritos (loja no passo 4 = 38%, no passo 5 = 36%, no passo 3 = 31%) e a justificativa aritmetica de por que a Troca saiu. Meus numeros confirmam o alcance previsto: 96% das runs chegam ao passo 4 e 50% ao passo 8.
- A reparticao do multiplicador do chefe (ATK inteiro, HP pela raiz, DEF intocada, src/run/enemy_gen.gd:128-135) esta com a forma certa e mede bem: boss_power leva a vitoria da run de 48% para 20% entre 2.0 e 6.5 SEM mover um decimo da mediana de combate normal (12.5 s em todos os pontos). E um botao isolado, que e exatamente o que um botao de dificuldade deve ser.
- combat.pe_soft_cap e um botao vivo e bem comportado: 120 -> 9999 moveu a vitoria de 36% para 32%, os ativos de 2.21 para 2.59 e as reacoes de 36.1 para 42.2. Esta fazendo trabalho de verdade, ao contrario de um quarto do arquivo.
- O teto de unidades sem dano em times inimigos (enemy_gen.gd:29-35) resolveu o que NOTAS 1.3 dizia que resolveria: a forma dominante de impasse hoje e Arcano/Curandeiro x Curandeiro (23 de 168 impasses), nao mais times de 3-4 Guardioes. O achado antigo foi corrigido e ficou corrigido.
- Quatro dos seis alvos passam honestamente mesmo quando se tira o chefe da conta, que era a maneira facil de inflar: reacoes 29.8 nas lutas normais (faixa de build de reacao 25-45), cozinha 89% (>70%), relogio 4.6% nas lutas normais (<6%), vitoria 37% (35-45%). A cozinha em particular subiu de 77% para 89% desde o README - um alvo que estava travado ha semanas e destravou e ninguem atualizou o placar.
- A cultura de _doc: fui cacar numeros mortos e encontrei justificativa escrita para quase todos os numeros vivos. Foi por causa disso que este review pode discordar de coisas especificas (o _hp_scale_doc, o _boss_duration_doc, o _heal_falloff_doc) em vez de so listar suspeitas - da para saber o que era intencao e o que era deriva.

**Comportamento da interface**

- A Cozinha e o PickerOverlay escrevem o MOTIVO em vez de apagar o botão. screen_kitchen.gd:80-85 devolve "nenhum Prismon com espaço no Estômago" / "Éter insuficiente", e picker_overlay.gd:84-85 imprime na própria linha de cada criatura o resultado do callback `_why` — "estômago cheio (3/3)", "sem espaço de item (2/2)", e nos Núcleos a troca literal "Gelo → Fogo" (screen_shop.gd:139-147). É a resposta certa para "estado que falta" e ela já existe; o que falta é a Feira copiá-la.
- Cancelar nunca cobra. screen_shop.gd:122-126 devolve o Éter quando o jogador abre o painel de "quem leva o item" e desiste, com o motivo escrito no comentário ("senão o painel vira uma armadilha e o jogador para de abrir"). E screen_chance.gd:124-127 trata recusar um achado como legítimo, anotando "ninguém quis X" em vez de forçar a entrega.
- Onde há mais de um destino possível, o jogo pergunta. screen_shop.gd:107-127 e screen_kitchen.gd:100-117 abrem o PickerOverlay quando mais de uma criatura pode receber o item ou o prato, e screen_kitchen.gd:128-140 acrescenta o ElementPicker para o Guisado Cromático — o comentário nas linhas 123-127 conta que sem ele o prato cobrava Éter e não fazia nada. Automatismo invisível virou decisão visível.
- `ScreenCombat.aim_at` (screen_combat.gd:302-321) é o ÚNICO ponto que decide o que um clique no campo faz, e o teste automatizado usa o mesmo caminho do jogador. Junto com `_arm` (linhas 271-290), que decide pela FORMA do modo (`begins_with("all_")`, `ends_with("_area")`, `ends_with("_pick_element")`) em vez de por uma lista de nomes — um modo de mira novo passa a funcionar sem tocar no arquivo.
- As três armadilhas de tooltip já resolvidas em tooltip_layer.gd são corretas e não-óbvias: `is_instance_valid` para o alvo liberado que compara igual a null (linhas 78-79), esconder SEMPRE que o alvo muda e não só ao sair para o vazio (linhas 79-90), e a conferência por quadro de que o cursor cai de fato dentro do retângulo, para o caso em que a tela se reconstrói sob um mouse parado (linhas 130-131). Foi por isso que o quarto defeito que achei é de TEMPO (um tween não morto) e não de lógica — a lógica está fechada.
- A tabela do log soma os Prismons de mesmo nome com "×2" (screen_result.gd:121-144) e esconde a coluna inteiramente zerada (linha 161). São dois problemas reais de leitura — duas Coallas viravam duas linhas sem explicação, e uma briga sem curandeiro gastava 84 px numa pilha de zeros — resolvidos com regra, não com ajuste.

**Composição do combate**

- O `to_screen`/`to_field` como funil único de projeção (field_view.gd:170-175). Tudo que é desenhado no campo — piso, sombras, marcas, projéteis, mira, faixas — passa por essas duas funções. É por isso que a proposta de câmera que segue o centróide cabe em cinco linhas em vez de trinta arquivos. Não mexa nisso.
- A regra de nome que ESMAECE em vez de empurrar (field_view.gd:91-109, 531-553). É a decisão certa e está bem argumentada: um nome ausente por 0,17 s confunde menos que um nome apontando para o vazio. O desempate por chave estável (lado, depois id) é o detalhe que impede a piscada mútua, e ele está lá.
- O filtro de 3% do HP máximo para dano, cura e escudo (field_view.gd:255-268, 290-300). Com hp_scale 3.7 essa é a diferença entre uma tela de números e uma tela de combate. O comentário registra o raciocínio e o número.
- As arenas como .tscn com um Sprite2D por adereço (field_view.gd:29-48, assets/arenas/*.tscn). O ajuste fino acontece olhando o jogo, e o shader cenario_fade resolve a curvatura e o desbote lendo a posição de mundo em vez de assar máscara na textura — é a solução correta para peças arrastáveis, e o comentário explica por que o CanvasGroup falhou.
- A lição escrita em arena_chao.gd:38-41 — “no chão da arena, marca sorteada vira ruído; se for para voltar com poça, que venha desenhada e posicionada”. É a melhor frase de direção de arte do projeto inteiro, e o ladrilho em grade da Câmara e as lajes irmãs da Assombrada a cumprem.
- O CombatPanel responde “o que esta criatura está fazendo AGORA” em texto (combat_panel.gd:151-165). “armando o golpe”, “indo até Hipocampo”, “⚡ ultimate pronta” — é a única camada da tela em que a intenção de uma unidade é legível, e ela existe justamente porque a barrinha de 5 px não respondia. A geometria das duas linhas (nome+número / estado+auras) está resolvida e alinhada.
- A zona morta de separação no clinch (combat_sim.gd:1128-1160), com a troca medida e registrada: 1.0 → 83% de remexida e 4,6% de encavalamento; 0.5 → 52% e 7,5%; 0.0 → 33% e 12,7%. Escolher 0.5 com esses três pontos na mão é o padrão que o resto das decisões visuais deveria seguir.
- A tabela SNAP de tamanhos de fonte (ui.gd:45-68) e a descoberta de que 1.5× é o pior caso de rasterização de pixel art. É conhecimento real, custou um probe, e está documentado onde quem for mexer vai ler.

**Composição dos menus**

- A família PickPanel é o melhor trabalho de composição do projeto. Medi o bounding box de 07b_loja.png e 07d_cozinha.png: (323,148)-(1276,751) nos DOIS, idêntico ao pixel; 07f e 07g batem na largura e variam só o suficiente no conteúdo. Quatro momentos diferentes da run — comprar, cozinhar, aprender, trocar — com uma geometria só. O jogador aprende a ler uma vez, como diz o comentário de pick_panel.gd:15-17, e isso é verdade na imagem, não só na intenção.
- A conta de altura da lista em pick_panel.gd:47-64. `ROW_H = 90`, `LINHAS_VISIVEIS = 4`, `altura_da_lista() = 4*(90+6)-6 = 378`: a caixa recebe um número INTEIRO de linhas e nunca mostra uma quarta linha cortada ao meio. É raro alguém derivar a altura do contêiner a partir da linha em vez de chutar um número redondo, e o comentário que explica por que 322 px dava 3,45 linhas é exatamente o tipo de registro que impede a regressão.
- 13_run_evento.png é uma prova de que o cartão de comparação SABE alinhar: nome 462-489, elemento 511-530, ultimate 541-567, desbloqueia 599-614, reações 638-654 — cinco linhas batendo ao pixel nos dois cartões. Quando o conteúdo é simétrico, a tela é impecável. O problema é só a condicional que quebra a simetria, não o desenho.
- A tira de nove cores no alto de 01_titulo.png, com as quatro fora do slice escurecidas em 62% (screen_title.gd:33-42). Em 14 px de altura e sem uma palavra, ela diz "este jogo tem nove elementos e cinco estão vivos". É exatamente o tipo de informação que normalmente vira um parágrafo de changelog.
- A escala tipográfica de ui.gd:40-80 e a descoberta de que 1.5x é o pior caso possível numa fonte de pixel de em=18 — 27 px alterna a fileira dobrada de dois em dois e o olho lê como fonte quebrada, 26 px espalha o erro e o traço fica limpo. Isso foi MEDIDO em tools/fit_probe, não deduzido, e está escrito onde quem for mexer vai ler. Toda a nitidez do texto nos prints vem daí.
- 04c_sinergias_pobre.png resolve um problema que quase todo jogo de sinergia erra: as reações bloqueadas não somem nem ficam só cinzas, elas dizem o que FALTA — "Derretimento · falta ❄", "Geada Mortal · falta ❄ 🌿". O estado apagado vira instrução. E a lista mantém a ordem e a posição da versão rica, então a mesma reação fica no mesmo lugar nas duas equipes.
- O medalhão de lado fixo (monster_portrait.gd:43-63) e a decisão, registrada em roster_rail.gd:73-75 e picker_overlay.gd:72-73, de fazer a maior dimensão do sprite ocupar 86% do diâmetro em vez de aplicar 62% seco. É por isso que Pinto-Raio (47x46) e Coalla (26x34) preenchem o aro com o mesmo peso aparente, e por isso as colunas de nome não ficam serrilhadas. Dez dos doze pontos de retrato do projeto já usam essa peça.
- O tooltip do trilho (roster_rail.gd:103-120) carrega HP, ATK, DEF, VEL, PE, Vontade, a ultimate com texto, cada item, cada prato e o estômago — e a ficha visível ficou com duas coisas só, nome e vida. A decisão registrada em roster_rail.gd:84-87 de cortar seis números por Cara e mandá-los para onde se compara com calma está certa, e é a razão de o trilho não parecer uma planilha. (O nome está quebrado hoje, mas isso é o bug do achado 1, não um erro de desenho.)
- docs/pecas/*.png existir. Uma folha de peças gerada do próprio código, com os seis estados do botão nomeados em português e os ícones com o tamanho escrito no cabeçalho, é infraestrutura de direção de arte que a maioria dos protótipos não tem. Metade dos meus achados de consistência só é demonstrável porque essa folha existe para contradizer o código.

**Partículas, efeitos e shaders**

- cenario_fade.gdshader é a melhor ideia visual do projeto. Tirar a curvatura da PRÓPRIA elipse do piso — `arco = 1 - sqrt(1 - dx²)`, `VERTEX.y += arco * curvatura` — em vez de um mapa de deslocamento pintado, e ainda deixá-la 45% mais rasa que a borda para a folga CRESCER nas pontas, é uma solução que funciona e se justifica sozinha. Em shots/11b_run_combate.png as montanhas abraçam a arena e não tocam o piso em ponto algum da largura. E o fato de o fade ler a posição ANTES do deslocamento (linhas 63-69) é o detalhe que separa quem testou de quem adivinhou.
- O diagnóstico do CanvasGroup está registrado no lugar certo e pela razão certa (cenario_fade.gdshader:36-40): o buffer não chegava ao shader nem por COLOR nem por texture(TEXTURE, UV), e o cenário saía branco. A conclusão — material em cada sprite, e o corte lendo posição de MUNDO para a lápide não levar o próprio desbotado junto — é a saída certa para um cenário feito de nós arrastáveis.
- A constante SQUASH = 0.34 compartilhada por sombra, anel de aura, mira, onda de reação e marca de chão (field_view.gd:139) é a razão pela qual a arena lê como um plano e não como adesivos colados na tela. É uma decisão de uma linha que resolve cinco lugares, e o comentário que a acompanha nomeia exatamente o sintoma que ela cura.
- As três regras das partículas — relógio da TELA (4× não vira tempestade), atrás das criaturas, e envolvendo o campo inteiro e não só a elipse (arena_particulas.gd:12-19) — estão certas as três. A do relógio em especial: é ela que impede que a decoração conte uma mentira sobre o ritmo da briga. O nascimento já espalhado (`_nascer(true)` no `trocar`) é o detalhe que evita a chuva "ligando" um segundo depois do começo.
- A limpeza de 11/09 no ArenaChao — jogar fora as manchas e riscos sorteados e ficar só com o que tem ESTRUTURA — foi acertada e é comprovável no print: em shots/05_combate.png, y=522, os três anéis do Campo Magnético aparecem como degraus de +20 em RGB exatamente em x=511, 649, 786, 1145 e 1421, que são os raios 0.34/0.60/0.86 × 530 espelhados no centro. Isso lê como piso construído. Poça sorteada teria lido como sujeira na tela, como o comentário registra.
- O anel de aura com espessura = UA e raio limitado a `separation_radius/2 - 8` (field_view.gd:822-831) é a peça que faz a leitura elemental existir sem entulhar o campo: os anéis de duas criaturas coladas não se cruzam mais. Mantenha essa trava intacta — várias das minhas propostas acendem coisas em volta do corpo e nenhuma delas deve crescer para além desse limite.
- A agregação dos floaters (somar no número que já está no ar em vez de empilhar, e crescer a fonte a cada soma, com teto) e as pistas dos pops resolvem o problema real: em shots/05_combate.png lê-se "Arco Voltaico ×2" e "Detonação ×7" em vez de nove rótulos no mesmo pixel. A escolha de dar ao rótulo de nome um FADE em vez de empurrá-lo de pista (field_view.gd:100-107) é a mesma qualidade de raciocínio — um nome ausente por 0,17 s confunde menos que um nome no lugar errado.
- pixelize.gdshader ancora o shimmer na GRADE e não na UV (linha 119), então o brilho anda de bloco em bloco em vez de deslizar por dentro deles. Esse é o erro que 90% das implementações desse efeito comete. E o guarda de `Juice.enabled` em logo_view.gd:54-61, com o `set_process(false)` explícito, mostra que a interação entre animação e ferramenta de print já foi pensada — vale repetir esse guarda em qualquer efeito novo que anime na entrada.
- screen_flash e hitstop já são dados por reação em data/reactions.json (0.55/0.06 no Derretimento, 0.30/0.03 na Eletrocussão), e o hitstop é consumido de verdade em screen_combat.gd:221-224 parando o passo da simulação sem parar a tela. A tabela está pronta para ser usada com mais força — é o multiplicador 0.13 em .gd que está segurando o efeito, não o dado.

**Identidade visual**

- As sete arenas são a identidade visual real do projeto e são genuinamente boas. assets/arenas/ tem 7 arenas × 8 camadas de parallax, remapeadas por luminância para uma rampa própria (tools/retonar_arenas.py) e com adereços colocados à mão em .aseprite. Medido nos prints: Campo Magnético dá céu (48,39,28) H=0.09 S=0.40 e piso (56,49,43) S=0.23; Chuva Constante dá céu (34,42,60) H=0.62 S=0.43 e piso (39,43,56) S=0.29. São mundos de verdade, quentes e frios, e o piso acompanha o clima em vez de ficar cinza. Não mexer nisso — o problema é que ele está trancado em 1 das 11 telas.
- O trabalho tipográfico está medido, não chutado, e está certo. src/ui/ui.gd:60-80 documenta que a m6x11plus tem upem 1152 com 64 unidades por pixel, logo o em vale 18px, e que 1.5× (27px) é o PIOR caso possível porque a fileira dobrada alterna de dois em dois e o olho lê como fonte quebrada — enquanto 26px (1.444×) espalha o erro de forma irregular e sai limpo no mesmo tamanho aparente. shots/15_corpo.png é a prova visual disso lado a lado. A escada 18/26/36/54 e a tabela SNAP devem ser preservadas inteiras em qualquer direção de arte nova.
- A arena elíptica com anel de piso e as marcas de chão. NOTAS.md §5.12 explica por que o retângulo saiu (quatro cantos que ninguém usava e que o desenho tinha de fingir que existiam) e src/ui/arena_chao.gd:28-42 registra a lição certa — "marca sorteada vira ruído": as manchas e riscos aleatórios saíram e ficou só o que tem ESTRUTURA, a grade de ladrilho da Câmara e os anéis concêntricos do Campo Magnético. É exatamente o raciocínio que falta no resto da interface, e aqui ele já foi feito.
- A disciplina de 9-patch é séria e está documentada com as armadilhas resolvidas. assets/CREDITOS.md registra os três erros que custaram tempo: AXIS_STRETCH_MODE_TILE em vez de STRETCH para bordas com grão; a faixa que não estica na vertical porque as pontas de 64px destruiriam a silhueta do laço; e o ProgressBar do Godot que desenha o preenchimento a partir de (0,0) sobre toda a moldura. As margens de corte foram MEDIDAS pelo script (CELL_MARGIN em ui.gd:189) e existe uma ferramenta (tools/ui_probe.tscn) que desenha cada peça em quatro tamanhos antes de ir para a tela. A infraestrutura para trocar de direção de arte está pronta.
- O centro da faixa de título foi acertado por medição no PNG, não por olho: ui.gd registra que a tinta opaca vai da linha 6 à 57 de uma peça de 64, centro visual em 31.5, e que 8/16 de margem punha o texto 4px acima — encostando o acento de ESTÁ na borda. Margens iguais de 8/8 põem o centro em 32. Esse nível de rigor é o que torna a direção nova executável.
- O Juice está no lugar certo do ponto de vista arquitetural: `Juice.make_reactive(b, b)` mora DENTRO de `UI.button()` (ui.gd:310), então todo botão do jogo responde ao toque por construção. Uma linha e a interface inteira ganhou comportamento. A sombra dura e a lajota que afunda ao apertar entram exatamente no mesmo ponto, sem tocar em nenhuma tela.
- A decisão da barra de rolagem, com a razão escrita: prisma_theme.gd:155-162 conta que a anterior era um trilho preto a 35% com grabber cinza-escuro de 2px de raio, invisível sobre painel escuro, e que quem não soubesse que havia mais conteúdo nunca ia descobrir. Agora tem borda própria e grabber claro de 14px. E o achado técnico junto: ScrollBar no Godot 4 não tem "scroll_width" — quem define a espessura é o content_margin do StyleBox do trilho.
- O pipeline forma-vem-da-espécie / cor-vem-da-afinidade está implementado com rig MEDIDO, não estimado (tools/build_monster_rig.py gera data/monster_rig.json com meia-largura na altura da cabeça, ombro e quadril, e âncora de cada membro). É o que faz um Núcleo Ígneo mudar a criatura na tela na hora, e é a leitura que o pilar "elemento é estado, não tipo" precisa. Essa é a única parte do jogo onde a cor JÁ é atmosfera e não código.

**Consenso do crítico**

- A separação §22.3 (src/sim/ não conhece nenhum Node) é o ativo real do projeto, e o consenso é tácito e total: NENHUMA das 8 frentes atacou essa fronteira, e as 8 dependeram dela. A frente `numeros` só pôde falar em taxa de vitória, a frente `run` só pôde falar em alcance de momento e eu só pude derrubar o achado do apollo porque `autoplay` roda 7.628 combates sem abrir janela. Quase todos os achados do mapa são reparos DENTRO de uma arquitetura que ninguém propôs mudar — isso é o sinal mais forte que um vertical slice pode dar.
- O hábito de escrever a medição ao lado do número, nos `_doc` do tuning.json e no NOTAS.md. Não é documentação decorativa: `_heal_falloff_doc` registra o compromisso testado ('aos 18 s e 0.045/s a forma dominante do impasse cai pela metade, mas a vitoria desce a 33%'), `_boss_duration_doc` explica por que 90 s e não 45, `_energia` registra a subida de 2.0 para 2.6 com a mediana antes e depois. Várias frentes tiveram que dizer 'discordo da justificativa' em vez de 'isto é um defeito' — que é exatamente o que uma justificativa escrita existe para provocar. Sem isso, as 8 revisões teriam produzido cinco vezes mais ruído.
- O bloco [arena e modificadores] do tools/smoke_test.gd (:717-824) prova efeito com SIMULAÇÃO REAL, não com leitura de dado: 'a mare molha o SEU lado (2.0 UA)', 'o estimulo aumenta o ATK (24 -> 32)', 'e para no teto de 3', 'quem cai na Assombrada vira fantasma / NAO conta como vivo / NAO causa dano / mas AINDA aplica aura', 'Ferozes deixa o inimigo mais forte (66 -> 73)'. Rodei a suíte inteira: === TUDO OK ===. A única crítica que o mapa fez a esse bloco foi que ele não faz o MESMO com item, relíquia e ressonância — ou seja, o pedido é mais do que já funciona. É o melhor padrão de teste do repositório e é o molde certo para a asserção de cobertura.
- A tela de log pós-combate (src/ui/screen_result.gd:147-201). Coluna zerada não aparece (:161), cópias da mesma espécie somam com '×2' em vez de virarem duas linhas confusas (:121-144), e cada célula tem barra de fundo proporcional ao melhor da coluna (:222-224), então a comparação entre criaturas se lê sem ler os dígitos. Visível funcionando em shots/06_log_de_combate.png e shots/12_run_log.png. As duas críticas do mapa a essa tela são 'falta o lado do inimigo' e 'ela é estreita demais para a área' — pedidos de mais, sobre uma peça que já resolve o problema difícil.
- A tela de Configurações cumpre a regra que ela mesma escreveu ('Só entra aqui o que MUDA alguma coisa'). Verifiquei as quatro uma a uma: tremor chega a field_view.gd:274, números a field_view.gd:343, velocidade a screen_combat.gd:42, tela cheia a screen_options.gd:54-56 — e as quatro persistem em user://config.cfg entre sessões. Num projeto onde acabei de contar ~35 chaves de dado que ninguém lê, uma tela com 100% de opções vivas merece ser citada. (O único furo é a dessincronia com F11, que reportei.)
- O determinismo por semente atravessa run e combate e é o que tornou esta revisão possível de cruzar. NodeGen (:17), EventGen (:26) e CombatSim (:79-81) derivam tudo de `Run.seed_value`, e o resultado é que oito revisores independentes viram o MESMO primeiro combate e os mesmos pares — inclusive o smoke_test conferindo 48 pares em 6 sementes com 0 falhas ('em 48 pares, a da direita nunca e mais facil'). Isso é infraestrutura, não sorte.
- A escrita das 8 reações, na tela de Sinergias. É prosa de jogador, não de planilha: 'O golpe inteiro dobra de força. A aura é consumida por completo — é a reação mais cara e a que mais dói.' / 'Não consome a aura. É a única que encadeia.' / 'Arranca 4% do HP MÁXIMO do alvo, além do dano. Quanto mais gordo o inimigo, mais dói.' Visível em shots/04b_sinergias.png. Duas frentes reclamaram do ARRANJO dessa tela (a barra de rolagem roxa, o texto da Vaporizar) e nenhuma reclamou do texto — porque é a melhor redação do projeto jogável.
