shader_type canvas_item;
// O CENARIO CURVA ACOMPANHANDO A ARENA, e desbota nas bordas.
//
// Duas coisas num shader so, porque as duas dependem de onde o pixel esta no
// mundo — e nao de onde ele esta na textura.
//
// -------------------------------------------------------------------------
// 1. A CURVA (autor, 11/09: "as arenas estao se misturando com as montanhas de
//    um jeito muito estranho... o que voce podia fazer e aplicar um shader
//    similar ao de FNAF pra criar profundidade das montanhas fazendo elas
//    circularem a arena").
//
// A ideia vem do shader de deslocamento falso do FNAF: empurrar o pixel na
// vertical por uma quantidade que varia ao longo da imagem, e deixar o olho
// completar a profundidade. Aqui a quantidade nao vem de um mapa de textura —
// vem da PROPRIA ELIPSE do piso.
//
// O topo da elipse, visto de cima, esta em `centro.y - hh*sqrt(1 - dx^2)`. Se o
// cenario desce `hh * (1 - sqrt(1 - dx^2))` conforme se afasta do centro, o
// horizonte dele fica PARALELO a borda de tras da arena, a uma folga constante.
// Com `curvatura = hh` a conta fecha exatamente; valores menores achatam o arco.
//
// O efeito e a paisagem abracando a arena em vez de cruzar por cima dela numa
// reta — que era o "se misturando de um jeito estranho" do print.
//
// -------------------------------------------------------------------------
// 2. O DESBOTE das bordas.
//
// O corte precisa ser do CENARIO, nao da peca: cada elemento e um no proprio,
// arrastavel no editor, e uma mascara assada na textura andaria JUNTO com a
// peca — a lapide levaria o proprio desbotado para onde fosse.
//
// Por isso o fade tambem le a posicao no mundo, ja deslocada pela curva: o
// recorte acompanha o arco em vez de cortar numa reta enquanto a arte curva.
//
// NAO E UM CanvasGroup. A primeira tentativa achatava os filhos num CanvasGroup
// e cortava o resultado — mas o buffer dele nao chegava ao shader: nem o COLOR
// de entrada nem texture(TEXTURE, UV) traziam o desenho, e o cenario saia como
// um borrao BRANCO. Com o material em cada sprite, COLOR e o que sempre foi
// (textura x modulate) e o alfa se mexe sem surpresa.

// --- a curva -------------------------------------------------------------
uniform vec2 arena_centro = vec2(0.0);   // centro da elipse do piso, no canvas
uniform float arena_raio = 530.0;        // meia-largura da elipse
uniform float curvatura = 235.0;         // quanto a borda desce; = meia-altura

// --- o desbote -----------------------------------------------------------
uniform vec2 origem = vec2(0.0);         // canto superior esquerdo, no canvas
uniform vec2 tamanho = vec2(1280.0, 260.0);
uniform float topo_fim = 0.37;           // onde o ceu termina de aparecer (0..1)
uniform float horizonte = 0.65;          // ate aqui a imagem aparece inteira
uniform float rodape_fim = 0.91;         // daqui para baixo nao aparece nada
uniform float lateral = 0.16;            // fracao da largura que some em cada lado

// --- o ar quente ---------------------------------------------------------
// SO O SOLO VULCANICO (autor: "os efeitos que faltam"). Quem liga e o
// FieldView, que ja escreve uniforms todo quadro: `calor = 1` no Solo
// Vulcanico e `calor = 0` nas outras seis — o valor padrao. Para as outras
// arenas o shader e literalmente o mesmo de antes: o `if` nem entra.
//
// DISTORCE A UV DA PECA, NAO A TELA. Distorcer a tela exigiria
// BackBufferCopy + hint_screen_texture, um buffer inteiro por quadro. Aqui o
// deslocamento e em TEXELS INTEIROS da propria peca: com o filtro NEAREST o
// tremor anda de pixel em pixel, como o resto do jogo, em vez de borrar.
//
// A MASCARA VEM DA ALTURA NO DESENHO, nao de uma lista de pecas: cada sprite
// e um no proprio e todos dividem este material, entao nao ha como ligar o
// calor peca a peca sem editar a cena. Mas ar quente sobe DO CHAO — abaixo do
// horizonte (uv.y > 0.60) estao justamente os veios e as bocas de lava, e o
// ceu e as montanhas ficam parados, que e o que a fisica pede de graca.
uniform float calor = 0.0;
uniform float calor_amplitude = 1.6;     // teto do deslocamento, em texels

varying vec2 mundo;

void vertex() {
	vec2 w = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
	float dx = clamp((w.x - arena_centro.x) / max(arena_raio, 1.0), -1.0, 1.0);
	float arco = 1.0 - sqrt(max(0.0, 1.0 - dx * dx));
	float desce = arco * curvatura;
	VERTEX.y += desce;
	// O FADE LE A POSICAO SEM O DESLOCAMENTO, de proposito. O desbote e uma
	// propriedade da LINHA DA IMAGEM — "a 170 da textura fica o horizonte" —
	// e nao do lugar da tela onde ela foi parar. Lendo a posicao ja deslocada,
	// a montanha que desce nas bordas saia do intervalo e era apagada: na
	// primeira tentativa o cenario inteiro sumiu e sobraram so uns riscos de
	// lava. Assim o recorte viaja JUNTO com a curva.
	mundo = w;
}

void fragment() {
	vec2 uv = (mundo - origem) / max(tamanho, vec2(1.0, 1.0));
	float y = uv.y;

	if (calor > 0.001) {
		float quente = smoothstep(0.60, 0.88, y) * calor;
		// duas ondas de periodos primos entre si: uma so periodica denuncia o
		// seno, e o olho pega a repeticao em menos de dois segundos
		float onda = sin(mundo.y * 0.21 + TIME * 3.1)
			+ 0.5 * sin(mundo.y * 0.09 - TIME * 2.2 + mundo.x * 0.013);
		float texels = floor(onda * quente * calor_amplitude + 0.5);
		vec2 passo_uv = vec2(1.0) / max(vec2(textureSize(TEXTURE, 0)), vec2(1.0));
		// AS PECAS DESTA ARENA NAO TEM MODULATE (todas brancas, ver o .tscn),
		// entao COLOR de entrada E a textura e reamostrar nao perde tinta.
		COLOR = texture(TEXTURE, UV + vec2(texels * passo_uv.x, 0.0));
	}
	float fy;
	if (y <= topo_fim) {
		fy = pow(clamp(y, 0.0, 1.0) / max(topo_fim, 0.001), 1.3);
	} else if (y <= horizonte) {
		fy = 1.0;
	} else if (y >= rodape_fim) {
		fy = 0.0;
	} else {
		fy = 1.0 - (y - horizonte) / max(rodape_fim - horizonte, 0.001);
	}
	float fx = clamp(min(uv.x, 1.0 - uv.x) / max(lateral, 0.001), 0.0, 1.0);
	COLOR.a *= pow(clamp(fx * fy, 0.0, 1.0), 1.2);
}
