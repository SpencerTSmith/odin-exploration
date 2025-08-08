#version 450 core
// layout(location = 0) in vec2 vert_position;
// layout(location = 1) in vec2 vert_uv;

out VS_OUT {
  vec2 uv;
} vs_out;

void main() {
  // Hardcoded vertex positions for a full-screen quad
  vec2 vert_positions[6] = vec2[](
    vec2(-1.0, -1.0), // Bottom-left
    vec2( 1.0, -1.0), // Bottom-right
    vec2(-1.0,  1.0), // Top-left
    vec2( 1.0, -1.0), // Bottom-right
    vec2( 1.0,  1.0), // Top-right
    vec2(-1.0,  1.0)  // Top-left
  );

  // Corresponding texture coordinates
  vec2 vert_uvs[6] = vec2[](
    vec2(0.0, 0.0), // Bottom-left
    vec2(1.0, 0.0), // Bottom-right
    vec2(0.0, 1.0), // Top-left
    vec2(1.0, 0.0), // Bottom-right
    vec2(1.0, 1.0), // Top-right
    vec2(0.0, 1.0)  // Top-left
  );

  vs_out.uv   = vert_uvs[gl_VertexID];
  gl_Position = vec4(vert_positions[gl_VertexID], 0.0, 1.0);
}
