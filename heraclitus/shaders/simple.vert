#version 450 core

layout(location = 0) in vec3 in_position;
layout(location = 1) in vec3 in_color;
layout(location = 2) in vec2 in_uv;
layout(location = 3) in vec3 in_normal;

layout(location = 0) out vec3 out_color;
layout(location = 1) out vec2 out_uv;
layout(location = 2) out vec3 out_normal;
layout(location = 3) out vec3 frag_world_position;

uniform mat4 model;
uniform mat4 view;
uniform mat4 projection;

void main() {
    gl_Position = projection * view * model * vec4(in_position, 1.0);
    out_color = in_color;
    out_uv = in_uv;
		out_normal = mat3(transpose(inverse(model))) * in_normal;
		frag_world_position = vec3(model * vec4(in_position, 1.0));
}
