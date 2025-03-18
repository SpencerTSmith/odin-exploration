#version 450 core
layout(location = 0) in vec3 vert_position;
layout(location = 1) in vec2 vert_uv;
layout(location = 2) in vec3 vert_normal;

out vec2 frag_uv;
out vec3 frag_normal;
out vec3 frag_world_position;

#define FRAME_UBO_BINDING 0
layout(std140, binding = FRAME_UBO_BINDING) uniform Frame_UBO {
	mat4 projection;
	mat4 view;
	vec3 camera_position;
} frame;

uniform mat4 model;

void main() {
    gl_Position = frame.projection * frame.view * model * vec4(vert_position, 1.0);

		// FIXME: do this in image loading, not here, probably
    frag_uv = vec2(vert_uv.x, vert_uv.y);

		// FIXME: slow, probably
		frag_normal = mat3(transpose(inverse(model))) * vert_normal;

		frag_world_position = vec3(model * vec4(vert_position, 1.0));
}
