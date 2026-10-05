shader_type canvas_item;
render_mode blend_mix;
// O PISO COMO SUPERFICIE, e nao como contorno.
//
// ANTES ERAM DOIS DISCOS EMPILHADOS. O de dentro tinha 72% do raio e a soma
// dos dois alfas produzia um DEGRAU MEDIVEL: em shots/11b_run_combate.png, na
// linha y=522, a cor saltava de (36,38,50) para (43,47,61) em x=588 e voltava
// em x=1350 — exatamente 0,72 x 530 do centro. O olho le esse degrau como o
// anel de um alvo de dardos, nao como chao.
//
// Aqui a queda e CONTINUA do centro para a borda. Uma queda continua sozinha
// nao resolve nada: com o alfa caindo de 0,26 a 0,09 ao longo de ~380 px, a
// cor composta anda ~15 degraus de 8 bits, e 380/15 da FAIXAS de ~25 px —
// troca-se um degrau de 700 px por quinze de 25.
//
// Por isso o DITHER ORDENADO 4x4 de Bayer e obrigatorio, nao enfeite: ele
// espalha o erro de quantizacao numa trama fixa de 4x4 pixels de TELA. Como o
// jogo roda 1:1 sem escala, essa trama tem exatamente o tamanho do pixel do
// jogo — e a mesma gramatica do resto da arte, e nao um ruido de outro jogo.
//
// A trama e ancorada em FRAGCOORD (pixel de tela) e nao na UV: ancorada na UV
// ela nadaria junto com a camera quando o campo se desloca.

uniform vec2 tamanho = vec2(1134.0, 700.0);  // o retangulo do FieldView, em px
uniform vec2 centro = vec2(567.0, 418.0);    // centro da elipse, local ao Control
uniform vec2 raio = vec2(530.0, 235.0);      // meia-largura e meia-altura

uniform vec4 cor : source_color = vec4(0.4, 0.4, 0.46, 1.0);
uniform float alfa_centro = 0.26;
uniform float alfa_borda = 0.09;
// a mare/estimulo da arena acende o piso inteiro por ~0,7 s
uniform float pulso = 0.0;
// EXPOENTE DA QUEDA. 1.0 e uma rampa reta e le como cone; acima de 1 o miolo
// fica chapado por mais tempo e a queda se concentra na borda, que e como uma
// superficie iluminada de cima se comporta.
uniform float curva = 1.6;
// AMPLITUDE DO DITHER, em alfa. Tem de valer UM degrau de 8 bits na cor
// COMPOSTA: passo = 1 / (255 * contraste), e o contraste e a diferenca entre a
// cor do piso e o fundo da tela. Quem mede isso e o ArenaPiso, que conhece as
// duas cores; aqui so chega o numero.
uniform float passo = 0.008;
// DESBOTE NA BORDA DO PROPRIO RETANGULO, em px.
//
// A elipse do chao tem 1060 px de largura e o campo tem 872: horizontalmente o
// QUAD acaba antes da elipse, em t = 0,82, onde o alfa ainda vale 0,136. O
// recorte do FieldView (clip_contents, 16/09) corta exatamente ali — e um
// corte a 0,136 de alfa e uma linha reta de 15 de luma subindo a tela inteira,
// medida em z_combate_cheio.png. Lida como a moldura de uma caixa, que e o
// oposto de "superficie".
//
// Com o desbote, o chao chega transparente na tesoura: quem termina o desenho
// e a tinta, nao o recorte. Quando a camera esta no fim do curso a borda REAL
// da elipse cai junto com a do quad, e os dois desbotes se somam no mesmo
// lugar em vez de brigar.
uniform float margem = 0.0;

// A matriz classica de Bayer 4x4, em ordem de varredura.
const float BAYER[16] = float[16](
	 0.0,  8.0,  2.0, 10.0,
	12.0,  4.0, 14.0,  6.0,
	 3.0, 11.0,  1.0,  9.0,
	15.0,  7.0, 13.0,  5.0
);

void fragment() {
	// A GEOMETRIA SAI DA UV, nao de FRAGCOORD: assim o piso e o mesmo esteja o
	// Control onde estiver na tela (o combate ja desloca o campo na horizontal).
	vec2 px = UV * tamanho;
	vec2 d = (px - centro) / max(raio, vec2(1.0, 1.0));
	float t = clamp(length(d), 0.0, 1.4);

	float a = mix(alfa_centro, alfa_borda, pow(min(t, 1.0), curva)) + pulso;

	ivec2 celula = ivec2(mod(FRAGCOORD.xy, 4.0));
	float limiar = (BAYER[celula.y * 4 + celula.x] + 0.5) / 16.0 - 0.5;
	a += limiar * passo;

	// A BORDA E CURTA de proposito: ~5 px na horizontal. Uma borda longa
	// devolveria o problema — o piso voltaria a ser um halo sem contorno, que
	// e o oposto do que se quer. O dither entra ANTES do recorte para nao
	// vazar uma trama fraca para fora da elipse.
	a *= smoothstep(1.0, 0.99, t);

	// o desbote do retangulo entra DEPOIS do recorte da elipse: ele nao muda a
	// forma do chao, so garante que nenhuma borda do quad apareca como linha
	if (margem > 0.5) {
		vec2 dist = min(px, tamanho - px);
		a *= clamp(min(dist.x, dist.y) / margem, 0.0, 1.0);
	}

	COLOR = vec4(cor.rgb, clamp(a, 0.0, 1.0));
}
