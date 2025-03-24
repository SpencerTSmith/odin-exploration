#version 450 core

in VS_OUT {
  vec3 uvw;
} fs_in;

uniform samplerCube skybox;

out vec4 frag_color;

void main() {
  frag_color = texture(skybox, fs_in.uvw);
}
