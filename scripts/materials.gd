extends RefCounted
## All materials are procedural (noise textures + shaders) so the APK needs no image assets.

static func noise_tex(seed: int, freq: float, octaves: int, size: int, normal: bool = false, bump: float = 6.0, ramp: Gradient = null, cellular: bool = false) -> NoiseTexture2D:
	var n := FastNoiseLite.new()
	n.seed = seed
	n.frequency = freq
	n.fractal_octaves = octaves
	n.fractal_type = FastNoiseLite.FRACTAL_FBM
	if cellular:
		n.noise_type = FastNoiseLite.TYPE_CELLULAR
		n.cellular_return_type = FastNoiseLite.RETURN_DISTANCE2_DIV
	else:
		n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	var t := NoiseTexture2D.new()
	t.width = size
	t.height = size
	t.seamless = true
	t.noise = n
	t.generate_mipmaps = true
	if normal:
		t.as_normal_map = true
		t.bump_strength = bump
	if ramp:
		t.color_ramp = ramp
	return t


static func grad(cols: Array, offs: Array) -> Gradient:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array(offs)
	g.colors = PackedColorArray(cols)
	return g


const ROAD_SHADER := """
shader_type spatial;
render_mode cull_disabled;
uniform sampler2D grain : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D grain_n : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D macro : filter_linear_mipmap, repeat_enable;
uniform float road_half = 7.0;
uniform float track_len = 3000.0;
uniform vec3 tint : source_color = vec3(1.0);
uniform float highway = 0.0;
uniform float two_way = 1.0;
uniform float wet = 0.0;
void fragment() {
	vec2 m = UV; // x = lateral metres (-half..half), y = arc metres
	float g = texture(grain, m * 0.35).r;
	float g2 = texture(grain, m * 0.09 + 0.37).r;
	float mac = texture(macro, m * 0.012).r;
	float tone = 0.115 + 0.07 * (g - 0.5) + 0.05 * (g2 - 0.5) + 0.05 * (mac - 0.5);
	float ax = abs(m.x);
	// rubbered-in racing line: darker, smoother band that wanders across the road
	float line_pos = sin(m.y * 0.004) * 3.2;
	float rubber = exp(-pow((m.x - line_pos) / 1.6, 2.0)) * (0.6 + 0.4 * mac);
	tone *= 1.0 - 0.28 * rubber;
	vec3 col = vec3(tone) * tint;
	float rough = 0.86 - 0.1 * g - 0.12 * rubber;
	float aa = max(fwidth(m.x), 0.002) * 1.2;
	float edge = smoothstep(road_half - 0.6 - aa, road_half - 0.6 + aa, ax) * (1.0 - smoothstep(road_half - 0.28 - aa, road_half - 0.28 + aa, ax));
	float dash = step(fract(m.y / 14.0), 0.42);
	float centre = (1.0 - smoothstep(0.08 - aa, 0.08 + aa, ax)) * dash;
	if (highway > 0.5) {
		// 4 lanes: dashed lane lines at +-3.5 m; centre = double yellow (two-way) or dashed white (one-way)
		float lane_d = step(fract(m.y / 12.0), 0.3);
		float lanes = (1.0 - smoothstep(0.07 - aa, 0.07 + aa, abs(ax - 3.5))) * lane_d;
		if (two_way > 0.5) {
			float dy = 1.0 - smoothstep(0.06 - aa, 0.06 + aa, abs(ax - 0.17));
			col = mix(col, vec3(0.88, 0.66, 0.1), dy * (0.82 + 0.18 * g));
			rough = mix(rough, 0.55, dy);
			centre = lanes;
		} else {
			centre = max((1.0 - smoothstep(0.07 - aa, 0.07 + aa, ax)) * lane_d, lanes);
		}
	}
	float sy = mod(m.y, track_len);
	float chk = 0.0;
	if (highway < 0.5 && (sy < 2.4 || sy > track_len - 0.01)) {
		chk = mod(floor((m.x + 20.0) / 0.6) + floor(sy / 0.6), 2.0);
		col = mix(col, vec3(0.86), chk);
	}
	// grid boxes behind the start line
	float back = track_len - sy;
	if (highway < 0.5 && back > 4.0 && back < 64.0) {
		float row = mod(back - 4.0, 10.0);
		float slot = step(row, 0.18) * step(abs(abs(m.x) - 3.4), 1.6);
		col = mix(col, vec3(0.82), slot * 0.9);
	}
	float paint = max(edge, centre) * (0.82 + 0.18 * g);
	col = mix(col, vec3(0.86), paint);
	rough = mix(rough, 0.55, paint);
	// damp / slushy road: darker, glossier
	col *= 1.0 - 0.35 * wet;
	rough = mix(rough, 0.25, wet * (0.6 + 0.4 * mac));
	ALBEDO = col;
	ROUGHNESS = rough;
	SPECULAR = 0.45;
	NORMAL_MAP = texture(grain_n, m * 0.35).rgb;
	NORMAL_MAP_DEPTH = 0.7 * (1.0 - 0.6 * paint);
}
"""

const CURB_SHADER := """
shader_type spatial;
render_mode cull_disabled;
uniform sampler2D grain : filter_linear_mipmap, repeat_enable;
void fragment() {
	float stripe = step(0.5, fract(UV.y / 2.4));
	vec3 red = vec3(0.62, 0.05, 0.04);
	vec3 white = vec3(0.86);
	float g = texture(grain, UV * vec2(0.5, 0.3)).r;
	vec3 col = mix(red, white, stripe) * (0.88 + 0.2 * g);
	// dirty, worn edge
	col *= 1.0 - 0.25 * smoothstep(0.75, 1.0, UV.x);
	ALBEDO = col;
	ROUGHNESS = 0.55 + 0.2 * g;
	SPECULAR = 0.5;
	// raised ridges across the curb
	float r = sin(UV.y * 6.2831 / 0.6);
	NORMAL_MAP = normalize(vec3(0.5, 0.5 + r * 0.12, 1.0));
}
"""

const TERRAIN_SHADER := """
shader_type spatial;
uniform sampler2D detail : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D detail_n : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D macro : filter_linear_mipmap, repeat_enable;
uniform vec3 col_a : source_color;
uniform vec3 col_b : source_color;
uniform vec3 col_dirt : source_color;
uniform vec3 col_rock : source_color;
uniform vec3 col_sand : source_color;
uniform float water_level = -1000.0;
uniform float rock_slope = 0.82;
varying vec3 wpos;
varying vec3 wnorm;
void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnorm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}
void fragment() {
	vec2 p = wpos.xz;
	float d1 = texture(detail, p * 0.21).r;
	float d2 = texture(detail, p * 0.047 + 0.31).r;
	float mac = texture(macro, p * 0.0021).r;
	float mac2 = texture(macro, p * 0.0093 + 0.5).r;
	vec3 base = mix(col_a, col_b, smoothstep(0.3, 0.7, mac));
	base *= 0.82 + 0.3 * d1 + 0.18 * (d2 - 0.5);
	float dirt = smoothstep(0.62, 0.78, mac2 + 0.15 * (d2 - 0.5));
	base = mix(base, col_dirt * (0.85 + 0.3 * d1), dirt);
	float slope = 1.0 - wnorm.y;
	float rock = smoothstep(1.0 - rock_slope - 0.06, 1.0 - rock_slope + 0.06, slope + 0.05 * (d2 - 0.5));
	base = mix(base, col_rock * (0.75 + 0.4 * d2), rock);
	float sand = 1.0 - smoothstep(water_level + 1.0, water_level + 7.0, wpos.y + 2.0 * (d2 - 0.5));
	base = mix(base, col_sand * (0.9 + 0.2 * d1), sand);
	ALBEDO = base;
	ROUGHNESS = mix(0.95, 0.75, rock);
	SPECULAR = 0.3;
	NORMAL_MAP = texture(detail_n, p * 0.21).rgb;
	NORMAL_MAP_DEPTH = 0.8 + rock;
}
"""

const SKY_SHADER := """
shader_type sky;
uniform vec3 zenith : source_color;
uniform vec3 horizon : source_color;
uniform vec3 ground_col : source_color;
uniform vec3 sun_tint : source_color = vec3(1.0, 0.95, 0.85);
uniform float sun_size = 0.012;
uniform float cloud_cover = 0.52;
uniform float cloud_bright = 1.0;
uniform sampler2D cloud_noise : filter_linear_mipmap, repeat_enable;
void sky() {
	vec3 d = EYEDIR;
	float h = d.y;
	vec3 col = mix(horizon, zenith, pow(clamp(h, 0.0, 1.0), 0.55));
	col = mix(col, ground_col, smoothstep(0.0, -0.1, h));
	float sd = max(dot(d, LIGHT0_DIRECTION), 0.0);
	vec3 sunc = sun_tint;
	col += sunc * (pow(sd, 6.0) * 0.18 + pow(sd, 48.0) * 0.45);
	if (h > 0.0) {
		vec2 uv = d.xz / (h + 0.1) * 0.06;
		float n = texture(cloud_noise, uv).r;
		float n2 = texture(cloud_noise, uv * 3.1 + vec2(0.37, 0.11)).r;
		float dens = n * 0.72 + n2 * 0.28;
		float c = smoothstep(cloud_cover, cloud_cover + 0.22, dens);
		c *= smoothstep(0.0, 0.18, h);
		float shade = 0.72 + 0.35 * smoothstep(cloud_cover, cloud_cover + 0.4, n2);
		vec3 cc = mix(horizon, vec3(1.0), 0.65) * shade * cloud_bright + sunc * pow(sd, 4.0) * 0.5;
		col = mix(col, cc, c * 0.9);
	}
	float disk = smoothstep(cos(sun_size), cos(sun_size * 0.7), dot(d, LIGHT0_DIRECTION));
	col += sunc * disk * 12.0;
	COLOR = col;
}
"""

const WATER_SHADER := """
shader_type spatial;
render_mode cull_back;
uniform sampler2D wave_n : hint_normal, filter_linear_mipmap, repeat_enable;
uniform vec3 deep : source_color = vec3(0.02, 0.12, 0.2);
void fragment() {
	vec3 wp = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec2 p = wp.xz;
	vec3 n1 = texture(wave_n, p * 0.02 + vec2(TIME * 0.006, TIME * 0.004)).rgb;
	vec3 n2 = texture(wave_n, p * 0.051 - vec2(TIME * 0.009, -TIME * 0.005)).rgb;
	NORMAL_MAP = normalize(n1 + n2 - 1.0) * 0.5 + 0.5;
	NORMAL_MAP_DEPTH = 0.6;
	ALBEDO = deep;
	ROUGHNESS = 0.06;
	SPECULAR = 0.6;
	METALLIC = 0.0;
}
"""

const FOLIAGE_SHADER := """
shader_type spatial;
render_mode cull_disabled, depth_draw_opaque;
uniform sampler2D leaf_mask : filter_linear_mipmap, repeat_enable;
uniform vec3 leaf_col : source_color = vec3(0.2, 0.35, 0.12);
uniform float mask_scale = 1.0;
uniform float cutoff = 0.5;
uniform float wind = 1.0;
varying float vvar;
void vertex() {
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float sway = sin(TIME * 1.7 + wp.x * 0.13 + wp.z * 0.11) * 0.06 + sin(TIME * 3.9 + wp.x * 0.7) * 0.02;
	VERTEX.x += sway * wind * max(VERTEX.y - 1.0, 0.0) * 0.12;
	VERTEX.z += sway * wind * max(VERTEX.y - 1.0, 0.0) * 0.08;
	vvar = fract(sin(dot(MODEL_MATRIX[3].xz, vec2(12.9898, 78.233))) * 43758.5453);
}
void fragment() {
	float m = texture(leaf_mask, UV * mask_scale).r;
	vec2 c = UV * 2.0 - 1.0;
	float fall = 1.0 - smoothstep(0.55, 1.0, length(c));
	float a = m * 0.75 + fall * 0.55 - 0.18;
	if (a < cutoff) { discard; }
	vec3 col = leaf_col * (0.75 + 0.5 * m) * (0.85 + 0.3 * vvar);
	ALBEDO = col;
	ROUGHNESS = 0.8;
	SPECULAR = 0.25;
	BACKLIGHT = col * 0.6;
}
"""

const GRASS_SHADER := """
shader_type spatial;
render_mode cull_disabled;
uniform vec3 root_col : source_color = vec3(0.12, 0.2, 0.06);
uniform vec3 tip_col : source_color = vec3(0.45, 0.6, 0.22);
varying float vh;
varying float vvar;
void vertex() {
	vh = UV.y;
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vvar = fract(sin(dot(wp.xz, vec2(12.9898, 78.233))) * 43758.5453);
	float w = sin(TIME * 2.3 + wp.x * 0.35 + wp.z * 0.3) * 0.12 + sin(TIME * 5.1 + wp.z) * 0.03;
	VERTEX.x += w * UV.y * UV.y;
	VERTEX.z += w * 0.6 * UV.y * UV.y;
	NORMAL = vec3(0.0, 1.0, 0.0);
}
void fragment() {
	vec3 col = mix(root_col, tip_col * (0.8 + 0.4 * vvar), vh);
	ALBEDO = col;
	ROUGHNESS = 0.85;
	SPECULAR = 0.2;
	BACKLIGHT = col * 0.5;
}
"""

const MOUNTAIN_SHADER := """
shader_type spatial;
uniform vec3 rock : source_color;
uniform vec3 snow : source_color = vec3(0.92, 0.94, 0.98);
uniform float snow_line = 220.0;
uniform sampler2D detail : filter_linear_mipmap, repeat_enable;
varying vec3 wpos;
varying vec3 wn;
void vertex() { wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; wn = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz); }
void fragment() {
	float d = texture(detail, wpos.xz * 0.004 + wpos.y * 0.002).r;
	vec3 c = rock * (0.75 + 0.5 * d);
	float s = smoothstep(snow_line - 30.0, snow_line + 30.0, wpos.y + 60.0 * (d - 0.5)) * smoothstep(0.35, 0.7, wn.y);
	ALBEDO = mix(c, snow, s);
	ROUGHNESS = 0.9;
}
"""


static func shader_mat(code: String) -> ShaderMaterial:
	var sh := Shader.new()
	sh.code = code
	var m := ShaderMaterial.new()
	m.shader = sh
	return m


static func std(col: Color, rough: float, metal: float = 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.roughness = rough
	m.metallic = metal
	return m
