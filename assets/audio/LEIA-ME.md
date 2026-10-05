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

- `golpe.wav` — 0.08 s
- `critico.wav` — 0.20 s
- `reacao.wav` — 0.23 s
- `morte.wav` — 0.42 s
- `ativo.wav` — 0.30 s
- `cura.wav` — 0.34 s
- `escudo.wav` — 0.26 s
- `controle.wav` — 0.26 s
- `clique.wav` — 0.04 s
- `hover.wav` — 0.03 s
- `moeda.wav` — 0.20 s
- `vitoria.wav` — 0.82 s
- `derrota.wav` — 0.90 s
- `recruta.wav` — 0.44 s

## Ambientes de arena (`ambiente/`)

Um por arena, pelo `id` de `data/enemies.json`. Laço de 3.2 s.

- `solo_vulcanico.wav`
- `chuva_constante.wav`
- `nevasca.wav`
- `campo_magnetico.wav`
- `bosque_vivo.wav`
- `arena_assombrada.wav`
- `camara_de_estimulos.wav`
