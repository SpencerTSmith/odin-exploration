#version 450 core

layout(location = 0) in vec3 in_color;
layout(location = 1) in vec2 in_uv;

layout(location = 0) out vec4 out_color;

uniform sampler2D tex0;
uniform sampler2D tex1;

void main() {
    out_color = mix(texture(tex0, in_uv), texture(tex1, in_uv), .2);
}
