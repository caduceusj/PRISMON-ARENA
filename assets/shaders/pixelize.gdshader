shader_type canvas_item;
// PIXELIZAÇÃO do logotipo (pedido do autor, 04/09).
//
// O logo é arte vetorial de traço limpo e o resto do jogo é pixel art de 18 px
// por em. Sem tratamento os dois não pertencem à mesma tela: o logo fica liso
// demais ao lado de uma interface que assume o pixel como unidade.
//
// O shader amostra a textura numa grade grossa, então o logo passa a ser feito
// de blocos — a mesma gramática do resto. `pixel_size` é animado na entrada:
// começa grosso e afina até o valor de repouso, e o logotipo "se resolve" na
// tela em vez de simplesmente aparecer.

// lado do bloco, em pixels da TEXTURA (não da tela)
uniform float pixel_size : hint_range(1.0, 64.0) = 5.0;

// leve balanço de matiz: o logo original é holográfico, e o passo de quantização
// mata o degradê. Isto devolve um pouco do brilho sem repintar a arte.
uniform float shimmer : hint_range(0.0, 1.0) = 0.25;
uniform float speed : hint_range(0.0, 4.0) = 0.6;

void fragment() {
	vec2 tex_size = vec2(textureSize(TEXTURE, 0));
	vec2 grid = max(vec2(pixel_size), vec2(1.0)) / tex_size;

	// centro do bloco: amostrar no canto faria a grade "andar" meio pixel
	vec2 uv = floor(UV / grid) * grid + grid * 0.5;
	vec4 c = texture(TEXTURE, uv);

	if (shimmer > 0.0 && c.a > 0.0) {
		// onda diagonal lenta, ancorada na GRADE e não em UV — assim o brilho
		// anda de bloco em bloco em vez de deslizar por dentro deles
		float w = sin((uv.x + uv.y) * 6.0 + TIME * speed) * 0.5 + 0.5;
		vec3 tint = vec3(1.0 - shimmer * 0.20 * w,
			1.0 - shimmer * 0.06 * (1.0 - w),
			1.0 + shimmer * 0.18 * w);
		c.rgb *= tint;
	}
	COLOR = c;
}
