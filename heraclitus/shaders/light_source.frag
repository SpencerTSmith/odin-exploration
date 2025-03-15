#version 450 core

layout(location = 0) in vec3 in_color;
layout(location = 1) in vec2 in_uv;
layout(location = 2) in vec3 in_normal;
layout(location = 3) in vec3 world_position;

layout(location = 0) out vec4 out_color;

uniform vec3 light_color;

void main() {
    out_color = vec4(light_color, 1.0);
}
