#version 450 core

layout(location = 0) in vec3 in_color;
layout(location = 1) in vec2 in_uv;
layout(location = 2) in vec3 in_normal;
layout(location = 3) in vec3 frag_position;

layout(location = 0) out vec4 frag_color;

uniform vec3 object_color;

uniform vec3 light_color;
uniform vec3 light_position;

const float AMBIENT_STRENGTH = 0.2;

void main() {
	vec3 norm = normalize(in_normal);
	vec3 light_direction = normalize(light_position - frag_position);
	float light_intensity = max(dot(norm, light_direction), 0.0) + AMBIENT_STRENGTH;

  frag_color = vec4(light_color * light_intensity * object_color, 1.0);
}
