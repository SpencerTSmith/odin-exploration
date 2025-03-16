#version 450 core
layout(location = 0) in vec3 vert_position;
layout(location = 1) in vec2 vert_uv;
layout(location = 2) in vec3 vert_normal;
layout(location = 3) in vec3 vert_color;

layout(location = 0) out vec3 frag_color;
layout(location = 1) out vec2 frag_uv;
layout(location = 2) out vec3 frag_normal;
layout(location = 3) out vec3 frag_world_position;

layout(std140, binding = 0) uniform Frame_UBO {
	mat4 projection;
	mat4 view;
	vec3 camera_position;
} frame;

uniform mat4 model;

void main() {
    gl_Position = frame.projection * frame.view * model * vec4(vert_position, 1.0);
    frag_color = vert_color;
		// FIXME: do this in image loading, not here, probably
    frag_uv = vec2(vert_uv.x, 1.0 - vert_uv.y);

		// FIXME: slow, probably
		frag_normal = mat3(transpose(inverse(model))) * vert_normal;

		frag_world_position = vec3(model * vec4(vert_position, 1.0));
}
