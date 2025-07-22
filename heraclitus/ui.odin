package main

MAX_IMMEDIATE_VERTICES :: 100

Immediate_State :: struct {
  vertex_buffer: Vertex_Buffer,
  vertex_count:  i32,
}

Immediate_Vertex :: struct {
  position: vec3,
  color:    vec3,
}

immediate_init :: proc() {
}

immediate_vertex :: proc (x, y, z: f32) {

}

immediate_quad :: proc() {

}

immediate_flush :: proc() {

}
