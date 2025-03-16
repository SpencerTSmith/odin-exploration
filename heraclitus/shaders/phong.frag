#version 450 core

layout(location = 0) in vec3 in_color;
layout(location = 1) in vec2 frag_uv;
layout(location = 2) in vec3 frag_normal;
layout(location = 3) in vec3 frag_world_position;

layout(location = 0) out vec4 frag_color;

struct Point_Light {
	vec3 position;

	vec3 color;
	vec3 ambient;
	vec3 diffuse;
	vec3 specular;

	vec3 attenuation;
};

struct Direction_Light {
	vec3 direction;

	vec3 color;
	vec3 ambient;
	vec3 diffuse;
	vec3 specular;
};

struct Spot_Light {
	// Angle's Cosine
	float inner_cutoff;
	float outer_cutoff;

	vec3 position;
	vec3 direction;

	vec3 color;
	vec3 ambient;
	vec3 diffuse;
	vec3 specular;

	vec3 attenuation;
};

struct Material {
	sampler2D diffuse;
	sampler2D	specular;
	sampler2D emission;
	float			shininess;
};

const vec3 AMBIENT_LIGHT = vec3(0.01, 0.01, 0.01);

layout(std140, binding = 0) uniform Frame_UBO {
	mat4 projection;
	mat4 view;
	vec3 camera_position;
} frame;

#define MAX_POINT_LIGHTS 16
layout(std140, binding = 1) uniform Light_UBO {
	Direction_Light direction_light;
	Point_Light     point_lights[MAX_POINT_LIGHTS];
	int							point_lights_count;
  Spot_Light			spot_light;
};

uniform Material material;

vec3 calc_point_phong(Point_Light light, Material material, vec3 normal, vec3 view_direction, vec3 frag_position) {
	// AMBIENT
	vec3 ambient = light.ambient * vec3(texture(material.diffuse, frag_uv));

	// DIFFUSE
	vec3 light_direction = normalize(light.position - frag_position);
	// Is the pixel facing the light, it reflects more
	float diffuse_intensity = max(dot(normal, light_direction), 0.0);
	vec3 diffuse = light.diffuse * diffuse_intensity * vec3(texture(material.diffuse, frag_uv));

	// SPECULAR
	// what direction, from the light to the normal of the fragment is the reflection
	vec3 reflect_direction = reflect(-light_direction, normal);
	// Is the reflection pointing towards the camera, and how shiny is the material?
	float specular_intensity = pow(max(dot(view_direction, reflect_direction), 0.0), material.shininess);
	vec3 specular = light.specular * (specular_intensity * vec3(texture(material.specular, frag_uv)));

	// ATTENUATION
	float distance = length(light.position - frag_position);
	float attenuation = 1.0 / (light.attenuation.x + light.attenuation.y * distance + light.attenuation.z * (distance * distance));

	vec3 phong = attenuation * light.color * (ambient + diffuse + specular);

	// FIXME: just to make sure not getting negative
	return max(phong, vec3(0.0, 0.0, 0.0));
}

vec3 calc_direction_phong(Direction_Light light, Material material, vec3 normal, vec3 view_direction) {
	// AMBIENT
	vec3 ambient = light.ambient * vec3(texture(material.diffuse, frag_uv));

	// DIFFUSE
	vec3 light_direction = normalize(-light.direction);
	// Is the pixel facing the light, it reflects more
	float diffuse_intensity = max(dot(normal, light_direction), 0.0);
	vec3 diffuse = light.diffuse * diffuse_intensity * vec3(texture(material.diffuse, frag_uv));

	// SPECULAR
	// what direction, from the light to the normal of the fragment is the reflection
	vec3 reflect_direction = reflect(-light_direction, normal);
	// Is the reflection directioning towards the camera, and how shiny is the material?
	float specular_intensity = pow(max(dot(view_direction, reflect_direction), 0.0), material.shininess);
	vec3 specular = light.specular * (specular_intensity * vec3(texture(material.specular, frag_uv)));

	vec3 phong = light.color * (ambient + diffuse + specular);

	// FIXME: just to make sure not getting negative
	return max(phong, vec3(0.0, 0.0, 0.0));
}

vec3 calc_spot_phong(Spot_Light light, Material material, vec3 normal, vec3 view_direction, vec3 frag_position) {
	// AMBIENT
	vec3 ambient = light.ambient * vec3(texture(material.diffuse, frag_uv));

	vec3 light_direction = normalize(light.position - frag_position);

	// DIFFUSE
	float diffuse_intensity = max(dot(normal, light_direction), 0.0);
	vec3 diffuse = light.diffuse * diffuse_intensity * vec3(texture(material.diffuse, frag_uv));

	// SPECULAR
	vec3 reflect_direction = reflect(-light_direction, normal);
	float specular_intensity = pow(max(dot(view_direction, reflect_direction), 0.0), material.shininess);
	vec3 specular = light.specular * (specular_intensity * vec3(texture(material.specular, frag_uv)));

	// ATTENUATION
	float distance = length(light.position - frag_position);
	float attenuation = 1.0 / (light.attenuation.x + light.attenuation.y * distance + light.attenuation.z * (distance * distance));

	// SPOT EDGES - Cosines of angle
	float theta = dot(light_direction, normalize(-light.direction));
	float epsilon = light.inner_cutoff - light.outer_cutoff; // Angle cosine between inner cone and outer
	float spot_intensity = clamp((theta - light.outer_cutoff) / epsilon, 0.0, 1.0);

	vec3 phong = attenuation * light.color * (spot_intensity * (diffuse + specular) + ambient);

	// FIXME: just to make sure not getting negative
	return max(phong, vec3(0.0, 0.0, 0.0));
}

void main() {
	vec3 normal = normalize(frag_normal);
	vec3 view_direction = normalize(frame.camera_position - frag_world_position);

	vec3 point_phong = vec3(0.0);
	for (int i = 0; i < point_lights_count; i++) {
		point_phong += calc_point_phong(point_lights[i], material, normal, view_direction, frag_world_position);
	}

	vec3 direction_phong = calc_direction_phong(direction_light, material, normal, view_direction);

	vec3 spot_phong = calc_spot_phong(spot_light, material, normal, view_direction, frag_world_position);

	// EMISSION
	vec3 emission = vec3(texture(material.emission, frag_uv));

	vec3 result = point_phong + direction_phong + spot_phong + emission + AMBIENT_LIGHT;

  frag_color = vec4(result, 1.0);
}
