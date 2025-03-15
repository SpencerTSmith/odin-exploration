package main

import "core:fmt"

Material :: struct {
	diffuse:   Texture,
	specular:  Texture,
	emission:  Texture,
	shininess: f32,
}

make_material :: proc {
	make_material_default,
	make_material_from_files,
}

make_material_default :: proc() -> (material: Material) {
	material.diffuse = make_texture()
	material.specular = make_texture()
	material.emission = make_texture()
	material.shininess = 0.0

	return
}

make_material_from_files :: proc(diffuse, specular, emission: string,
																 shininess: f32) -> (material: Material, ok: bool) {
	material.diffuse, ok  = make_texture(diffuse)
	if !ok {
		material.diffuse = make_texture()
		fmt.printf("Unable to create diffuse texture for material, using default")
	}

	material.specular, ok  = make_texture(specular)
	if !ok {
		material.specular = make_texture()
		fmt.printf("Unable to create specular texture for material, using default")
	}

	material.emission, ok = make_texture(emission)
	if !ok {
		material.emission = make_texture()
		fmt.printf("Unable to create emission texture for material, using default")
	}

	material.shininess = shininess
	return
}

free_material :: proc(material: ^Material) {
	free_texture(&material.diffuse)
	free_texture(&material.specular)
	free_texture(&material.emission)
}

bind_material :: proc(material: Material, program: Shader_Program) {
	if state.current_material != material {
		bind_texture(material.diffuse, .BIND_0);
		bind_texture(material.specular, .BIND_1);
		bind_texture(material.emission, .BIND_2);
		set_shader_uniform(program, "material.diffuse", 0)
		set_shader_uniform(program, "material.specular", 1)
		set_shader_uniform(program, "material.emission", 2)
		set_shader_uniform(program, "material.shininess", material.shininess)

		state.current_material = material
	}
}
