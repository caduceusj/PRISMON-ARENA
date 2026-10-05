class_name TooltipLayer
extends Control
## A dica que aparece sob o cursor (pedido do autor, 04/09).
##
## O tooltip da engine é um popup que ela cria e destrói sozinha — não dá para
## animar, nem posicionar, nem estilizar além do tema. Por isso a engine é
## desligada (`gui/timers/tooltip_delay_sec` alto no project.godot) e a dica
## passa a ser desenhada aqui.
##
## COR NO LUGAR DE LINHA EM BRANCO (04/09, autor: "tá enorme, coisa que podia
## ser menor tirando essas quebras de linha e talvez adicionando fontes de
## cores diferentes ou em negrito"). As dicas separavam campos com `\n\n`, e
## três campos viravam cinco linhas de painel. Agora o texto vira BBCode: o
## nome sai em dourado, os rótulos em cinza, e os campos cabem na mesma linha
## separados por `·`. A dica encolheu para um terço sem perder nada.
##
## O TAMANHO É RESOLVIDO NO QUADRO SEGUINTE. Medir no mesmo quadro em que o
## texto muda devolve lixo — a altura de um texto que quebra linha depende da
## largura, e a largura só existe depois do layout. Era isso que produzia um
## painel de tela inteira com o texto no rodapé.

const ATRASO := 0.25          # espera antes de aparecer, para não piscar ao passar
const SURGE := 0.10           # duração da entrada
const ESCALA_INICIAL := 0.86  # de onde ela cresce
const MARGEM := Vector2(16, 20)
const LARGURA_MAX := 340.0    # onde o texto quebra

## Lado da imagem que substitui um glifo. 16 e nao 22 (o corpo do texto menos
## folga): os icones sao 32x32 nativos e as escalas limpas de 32 sao 16, 32 e
## 48 — qualquer valor no meio reamostra pixel art em fracao quebrada, que e a
## mesma regra de UI.icon_px.
const ICONE_DICA := 16.0

## Trocar de alvo com uma dica JÁ ABERTA não paga a espera de novo. Sem isto,
## percorrer uma fileira de etiquetas dá um pisca-pisca de meio segundo entre
## cada uma; com isto, a dica simplesmente troca de texto.
const REENGATE := 0.45

var _painel: PanelContainer
var _rt: RichTextLabel
var _alvo: Control = null
var _espera := 0.0
var _medir := 0               # quadros restantes até o tamanho estar pronto
var _relogio := 0.0           # tempo desta camada, para a janela de reengate
var _fechou_em := -99.0       # quando a última dica saiu de cena

## O TWEEN DE ENTRADA, GUARDADO — este é o quarto tooltip grudado (revisão
## 15/09). Ver `_matar_entrada()`, logo abaixo de `_assentar`.
var _entrada: Tween = null


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_index = 4096

	_painel = PanelContainer.new()
	_painel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_painel.add_theme_stylebox_override("panel",
		UI.frame(UI.C_PANEL_HI, UI.ACCENT, 14, 9))
	_painel.visible = false
	add_child(_painel)

	_rt = UI.rich("", UI.F_SMALL)
	_rt.custom_minimum_size = Vector2(LARGURA_MAX, 0)
	_rt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_painel.add_child(_rt)
	set_process(true)


func _process(delta: float) -> void:
	_relogio += delta
	if _medir > 0:
		_medir -= 1
		if _medir == 0:
			_assentar()
		return
	var sob := _hovered_com_dica()
	# O ALVO MORREU JUNTO COM A TELA (autor, 04/09: "cliquei e continua
	# aparecendo mesmo depois de selecionar a arena").
	#
	# Trocar de tela libera o controle que estava sob o cursor. E aqui mora uma
	# armadilha do GDScript: uma referência LIBERADA compara IGUAL a `null`.
	# Então `sob != _alvo` dava FALSO (null contra liberado), a linha seguinte
	# via `_alvo == null` como VERDADEIRO e voltava — e o painel nunca era
	# escondido. A dica da tela anterior ficava por cima da tela nova, para
	# sempre. Nenhuma das duas comparações revela isso; só `is_instance_valid`.
	var morreu: bool = _painel.visible and not is_instance_valid(_alvo)
	if sob != _alvo or morreu:
		# ESCONDE SEMPRE, e não só ao sair para o vazio (defeito relatado pelo
		# autor, 04/09: "passo o hover e ativa o do quadrado do encounter em
		# vez do menor"). As etiquetas de arena vivem DENTRO do cartão do
		# encontro, então ir de um para o outro nunca passa pelo vazio: o alvo
		# trocava, mas o painel continuava visível e, por já estar visível, o
		# `_process` só o reposicionava — a dica do cartão seguia o cursor
		# sobre a etiqueta, para sempre.
		_alvo = sob
		_espera = 0.0
		_esconder()
		return
	if _alvo == null:
		return
	if _painel.visible:
		_posicionar()
		return
	_espera += delta
	if _espera >= _atraso():
		_mostrar(String(_alvo.tooltip_text))


## Quanto esperar antes de abrir. Zero quando a animação está desligada (as
## ferramentas precisam do estado final) e zero logo depois de outra dica ter
## fechado — ver REENGATE.
func _atraso() -> float:
	if not Juice.enabled:
		return 0.0
	if _relogio - _fechou_em < REENGATE:
		return 0.0
	return ATRASO


## O Control sob o cursor que tem dica. Sobe pela árvore: a dica costuma estar
## no cartão, e quem recebe o mouse é um filho dele (o botão invisível, um
## ícone). Sem subir, quase nenhuma dica apareceria.
func _hovered_com_dica() -> Control:
	var c: Control = get_viewport().gui_get_hovered_control()
	# CONFERE QUE ELE AINDA ESTÁ ALI (autor, 04/09: "os tooltips às vezes não
	# somem depois de eu clicar").
	#
	# O motor só recalcula quem está sob o cursor quando o mouse SE MOVE ou
	# quando um nó entra/sai da árvore. Clicar num prato refaz o painel: o que
	# estava sob o cursor muda de lugar, o mouse continua parado, e o motor
	# segue apontando para o controle antigo. A dica ficava pendurada na tela
	# até o jogador mexer o mouse — e é a dica ERRADA, de um pedaço da tela que
	# já saiu dali.
	#
	# Não dá para consertar isso reagindo ao clique: entre o clique e a
	# reconstrução ainda é tudo válido. O que resolve é perguntar, a cada
	# quadro, se o cursor de fato cai dentro do controle.
	if c != null and not c.get_global_rect().has_point(c.get_global_mouse_position()):
		return null
	while c != null:
		if String(c.tooltip_text).strip_edges() != "":
			return c
		c = c.get_parent_control()
	return null


func _mostrar(txt: String) -> void:
	if txt.strip_edges() == "":
		return
	_matar_entrada()
	_rt.text = formatar(txt)
	# LARGURA SOB MEDIDA: o mínimo fixo fazia "Curto" ocupar os mesmos 340 px
	# de uma dica de cinco campos. Aqui a caixa é a da linha mais comprida, e
	# só quebra quando passa do teto.
	_rt.custom_minimum_size = Vector2(_largura_para(txt), 0)
	_painel.visible = true
	_painel.modulate.a = 0.0
	# o tamanho real só existe depois de o layout rodar; até lá o painel fica
	# invisível de fato (alfa 0), e não num tamanho errado piscando na tela
	_medir = 2


func _assentar() -> void:
	_matar_entrada()
	_painel.reset_size()
	_posicionar()
	if not Juice.enabled:
		_painel.scale = Vector2.ONE
		_painel.modulate.a = 1.0
		return
	# SURGE AMPLIADO E RÁPIDO. O painel é filho direto desta camada, fora de
	# qualquer container, então escalar aqui não transborda nada — que é
	# justamente o que impede a escala nos cartões (ver Juice).
	_painel.pivot_offset = Vector2.ZERO
	_painel.scale = Vector2.ONE * ESCALA_INICIAL
	_entrada = create_tween()
	_entrada.set_parallel(true)
	_entrada.tween_property(_painel, "scale", Vector2.ONE, SURGE) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_entrada.tween_property(_painel, "modulate:a", 1.0, SURGE)


## O QUARTO TOOLTIP GRUDADO (revisão 15/09, achado médio · confirmado).
##
## Os três anteriores estão documentados em `_process` e em `_hovered_com_dica`.
## Este é do mesmo feitio — um estado que sobrevive à troca de alvo — só que o
## estado não é uma referência, é uma ANIMAÇÃO.
##
## O tween de `_assentar` dura SURGE = 0,10 s e escreve `modulate:a` e `scale`
## do painel a cada quadro. Esconder a dica nunca o matava: `_esconder` só
## apaga `visible`, e um tween não olha para `visible`. Sozinho isso seria
## inofensivo — o painel já saiu de cena. O que fecha a armadilha é o REENGATE:
## dentro de 0,45 s da dica anterior o atraso é ZERO, então a dica seguinte
## abre no mesmo quadro em que o cursor troca de alvo, e cai DENTRO dos 0,10 s
## do tween que ficou para trás.
##
## O estrago é exatamente o que os dois quadros de `_medir` existem para
## impedir. `_mostrar` põe `modulate.a = 0` e espera o layout para só então
## medir e posicionar; o tween velho reescreve esse alfa no quadro seguinte e o
## painel aparece com o TEXTO NOVO na CAIXA E NA POSIÇÃO DA DICA ANTERIOR, por
## dois quadros. Numa fileira de etiquetas — que é onde o reengate vive — isso
## acontece a cada etiqueta.
##
## A INVARIANTE que passou a valer: ENQUANTO `_medir > 0`, o painel está a alfa
## ZERO. Nada além deste tween conseguia quebrá-la, e ela foi verificada com o
## bug reintroduzido de propósito: com ele, `modulate.a` mede 0,038–0,055 nos
## quadros de medição (headless, onde o quadro é curtíssimo); sem ele mede
## 0,000. A 60 fps os dois quadros de `_medir` pegam 33 ms dos 100 ms do SURGE,
## então o que se vê na tela é bem mais que 0,05 — o que a sonda cobra, e o que
## basta cobrar, é que seja exatamente zero.
func _matar_entrada() -> void:
	if _entrada != null and _entrada.is_valid():
		_entrada.kill()
	_entrada = null


func _esconder() -> void:
	# só conta como "fechou" o que chegou a aparecer: esconder um painel que
	# nunca abriu não pode liberar o reengate
	if _painel.visible:
		_fechou_em = _relogio
	_matar_entrada()
	_painel.visible = false
	_painel.modulate.a = 0.0
	_medir = 0


## Folga entre a dica e o controle que a originou, quando ela precisa sair de
## cima dele. Seis px é a sombra dura do kit mais um pixel: a dica encosta na
## linha sem tocá-la, e continua lendo como uma coisa que saiu dali.
const FOLGA_DO_ALVO := 6.0


## Junto ao cursor, e sempre DENTRO da tela: perto da borda direita ou de
## baixo a dica vira para o outro lado em vez de sair do ecrã.
##
## E NUNCA POR CIMA DA LINHA QUE A ORIGINOU — ver `_fora_do_alvo`.
func _posicionar() -> void:
	var m := get_local_mouse_position()
	var p := m + MARGEM
	var tam := _painel.size
	if p.x + tam.x > size.x:
		p.x = m.x - tam.x - MARGEM.x
	if p.y + tam.y > size.y:
		p.y = m.y - tam.y - 6.0
	_painel.position = _fora_do_alvo(_na_tela(p, tam), tam)


func _na_tela(p: Vector2, tam: Vector2) -> Vector2:
	return p.clamp(Vector2.ZERO, (size - tam).max(Vector2.ZERO))


## A DICA NUNCA COBRE O QUE A ORIGINOU (autor, 16/09: *"alguns vários problemas
## de sobreposição"*).
##
## O cursor pousa no meio de uma linha de 480 px; a dica abre 16 px à direita e
## 20 px abaixo dele — ou seja, DENTRO da linha. O que o jogador vê é uma caixa
## escura em cima justamente do texto que ele estava tentando ler, e encavalada
## na borda do painel da lista. Pior: o gesto que pede a explicação é o mesmo
## que apaga a coisa explicada.
##
## O conserto não mexe no caso comum. Se a posição junto ao cursor já não toca
## o alvo, ela fica como está — é o que acontece com ícone, medalhão e etiqueta,
## que são menores que a margem. Só quando há sobreposição a dica procura saída,
## nesta ordem: descer, subir, ir para a direita, ir para a esquerda. Descer
## primeiro porque a peça que mais dispara isto é a LINHA DE LISTA — larga e
## baixa —, e para ela descer é o menor deslocamento possível.
##
## Se nenhuma das quatro couber (um alvo maior que a folga que sobra na tela),
## fica onde estava: cobrir é ruim, sair do ecrã é pior.
func _fora_do_alvo(p: Vector2, tam: Vector2) -> Vector2:
	if not is_instance_valid(_alvo):
		return p
	var r: Rect2 = _alvo.get_global_rect()
	r.position -= global_position
	if not Rect2(p, tam).intersects(r):
		return p
	var saidas: Array[Vector2] = [
		Vector2(p.x, r.end.y + FOLGA_DO_ALVO),
		Vector2(p.x, r.position.y - tam.y - FOLGA_DO_ALVO),
		Vector2(r.end.x + FOLGA_DO_ALVO, p.y),
		Vector2(r.position.x - tam.x - FOLGA_DO_ALVO, p.y),
	]
	for cand in saidas:
		var q := _na_tela(cand, tam)
		if not Rect2(q, tam).intersects(r):
			return q
	return p


## A largura que o texto PEDE, até o teto. Mede o texto cru (sem marcação):
## a marcação não muda os glifos desenhados, só a cor deles, então medir o
## texto simples dá o mesmo resultado e é muito mais barato.
##
## As linhas 2 em diante viram UMA linha separada por `·`, então a conta soma
## o comprimento delas em vez de pegar a maior.
func _largura_para(txt: String) -> float:
	var f: Font = PrismaTheme.body_font if PrismaTheme.body_font != null \
		else ThemeDB.fallback_font
	var sz := UI.fs(UI.F_SMALL)
	var linhas: Array = []
	for l in txt.split("\n"):
		var s := String(l).strip_edges()
		if s != "":
			linhas.append(s)
	if linhas.is_empty():
		return 80.0
	var maior: float = f.get_string_size(String(linhas[0]),
		HORIZONTAL_ALIGNMENT_LEFT, -1, sz).x
	var juntas := ""
	for i in range(1, linhas.size()):
		juntas += ("     " if juntas != "" else "") + String(linhas[i])
	if juntas != "":
		maior = maxf(maior, f.get_string_size(juntas,
			HORIZONTAL_ALIGNMENT_LEFT, -1, sz).x)
	return clampf(maior + 4.0 + _folga_dos_glifos(txt, f, sz), 80.0, LARGURA_MAX)


## O que a imagem ocupa a mais do que o glifo que ela substituiu.
##
## A medida acima e feita no texto CRU, e desde que `formatar` troca os glifos
## por `[img]` o desenho tem um lado de 16 px onde a conta viu um caractere.
## Sem esta folga, uma dica de uma linha com dois itens passa a quebrar em
## duas — o defeito que a largura sob medida existia para evitar.
static func _folga_dos_glifos(txt: String, f: Font, sz: int) -> float:
	var extra := 0.0
	for ch in Icons.GLIFOS:
		var g := String(ch)
		if not txt.contains(g) or Icons.glifo_icone(g) == "":
			continue
		var largura: float = f.get_string_size(g, HORIZONTAL_ALIGNMENT_LEFT, -1, sz).x
		extra += float(txt.count(g)) * maxf(ICONE_DICA - largura, 0.0)
	return extra


## Texto simples vira BBCode, por convenção — nenhuma tela precisa escrever
## marcação, e as dicas que já existem melhoram sozinhas.
##
##   1ª linha           → nome, em dourado e negrito
##   linhas em branco   → somem (eram elas que inchavam o painel)
##   demais linhas      → juntam-se numa só, separadas por `·`
##   "Rótulo: valor"    → o rótulo fica cinza, o valor claro
##   "⚡ Nome — texto"   → o nome do golpe fica na cor de destaque
##   ⚡ ◆ ◇ → ▲ ❄       → viram IMAGEM do atlas (ver `Icons.marcar`)
##
## OS GLIFOS SAEM DA FONTE DO SISTEMA (revisão 15/09). Nenhuma fonte do projeto
## contém ★ ⚡ ❄ ◆ ◇ → — assets/CREDITOS.md já registrava o risco: eles vêm de
## um fallback do sistema operacional e mudam de forma entre máquinas. A troca
## acontece AQUI, e não nas vinte telas que escrevem as dicas, porque este é o
## funil único por onde todo texto de dica passa. Uma linha, e a interface
## inteira para de depender de uma fonte que não é nossa.
static func formatar(txt: String) -> String:
	var linhas: Array = []
	for l in txt.split("\n"):
		var s := String(l).strip_edges()
		if s != "":
			linhas.append(s)
	if linhas.is_empty():
		return ""

	var out := "[b][color=#f0d98a]%s[/color][/b]" % _escapar(String(linhas[0]))
	var resto: Array = []
	for i in range(1, linhas.size()):
		resto.append(_realce(String(linhas[i])))
	if not resto.is_empty():
		out += "\n" + "  [color=#5b566e]·[/color]  ".join(resto)
	# DEPOIS do escape: `_escapar` troca "[" por "[lb]" para que um texto vindo
	# dos dados não abra marcação, e as tags de imagem não podem passar por lá.
	return Icons.marcar(out, int(ICONE_DICA))


static func _realce(linha: String) -> String:
	# "Arena: Chuva Constante" — o rótulo é estrutura, não conteúdo
	var i := linha.find(":")
	if i > 0 and i < 18:
		return "[color=#8f88a8]%s[/color] %s" % [
			_escapar(linha.substr(0, i)), _escapar(linha.substr(i + 1).strip_edges())]
	# "⚡ Arco Voltaico — Encadeia entre 3 inimigos"
	#
	# DIVIDE, não conta índice: a versão anterior fazia `substr(j + 3)` supondo
	# que o travessão mais o espaço ocupavam três posições, e comia a primeira
	# letra do texto — "Encadeia" virava "rcadeia". Dividir não tem essa
	# aritmética para errar.
	var partes := linha.split("—", true, 1)
	if partes.size() == 2:
		return "[color=#9f8cff]%s[/color] [color=#5b566e]—[/color] %s" % [
			_escapar(String(partes[0]).strip_edges()),
			_escapar(String(partes[1]).strip_edges())]
	return _escapar(linha)


## O texto vem dos dados e pode conter colchetes; sem escapar, um "[" viraria
## abertura de marcação e comeria o resto da dica.
static func _escapar(s: String) -> String:
	return s.replace("[", "[lb]")
