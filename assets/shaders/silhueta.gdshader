shader_type canvas_item;
render_mode blend_mix;
// HIT-FLASH: a criatura que acabou de apanhar pisca BRANCA por 3 quadros.
//
// POR QUE PRECISA DE SHADER. `draw_texture_rect_region` so aceita modulate
// MULTIPLICATIVO, e branco x cor = cor: nao existe tinta branca por modulate.
// E no Godot 4 o material pertence ao CanvasItem, nao ao comando de desenho —
// entao nao da para trocar o material no meio do `_draw` do FieldView.
//
// A saida e esta CAMADA: um Control filho do FieldView, com material proprio,
// que redesenha por cima so quem apanhou agora.
//
// COMO A MASCARA CHEGA AQUI. COLOR entra como textura x modulate DO COMANDO.
// Passando Color(1, 1, 1, forca) no modulate, COLOR.a ja e
// alfa_da_textura * forca — a mascara exata da silhueta, de graca. O rgb da
// textura e descartado e a cor vem do uniform.
uniform vec4 cor : source_color = vec4(1.0);

void fragment() {
	COLOR = vec4(cor.rgb, COLOR.a);
}
