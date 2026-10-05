shader_type canvas_item;
render_mode blend_mix;
// A MORTE. O evento `death` e emitido em combat_sim.gd:828 com pos e nome
// desde sempre, e nenhuma camada da tela o consumia: o momento mais importante
// da briga era um corte seco de cor, o corpo trocava de tinta e pronto.
//
// DESMANCHE EM BLOCO. Nada de textura de ruido: o limiar sai de um hash da
// coordenada de TELA quantizada, entao o grao tem o tamanho do pixel do jogo e
// nao borra em 1600x900 sem escala. Com `bloco = 2` o grao e de 2x2 px, que e
// o tamanho do detalhe dos sprites das criaturas.
uniform float bloco : hint_range(1.0, 8.0) = 2.0;
uniform vec4 cor_saida : source_color = vec4(1.0);

float hash21(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123);
}

void fragment() {
	vec4 t = texture(TEXTURE, UV);
	// com NEAREST o alfa da arte e 0 ou 1, entao COLOR.a DENTRO da silhueta e
	// exatamente o alfa do modulate — e por ele que o progresso viaja, um valor
	// por comando de desenho, sem precisar de um uniform por criatura
	float prog = COLOR.a;
	float h = hash21(floor(FRAGCOORD.xy / max(bloco, 1.0)));
	COLOR = vec4(mix(t.rgb, cor_saida.rgb, prog * 0.85), t.a * step(prog, h));
}
