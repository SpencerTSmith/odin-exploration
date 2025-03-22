#version 450 core

in VS_OUT {
  vec2 uv;
  vec3 normal;
  vec3 world_position;
} fs_in;

out vec4 out_color;

struct Point_Light {
	vec3  position;

	vec3	color;
	vec3  attenuation;

	float intensity;
	float ambient;
};

struct Direction_Light {
	vec3  direction;

	vec3  color;

	float intensity;
	float ambient;
};

struct Spot_Light {
	vec3  position;
	vec3  direction;

	vec3  color;
	vec3  attenuation;

	float intensity;
	float ambient;

	// Cosine
	float inner_cutoff;
	float outer_cutoff;
};

struct Material {
	sampler2D diffuse;
	sampler2D	specular;
	sampler2D emission;
	float			shininess;
};

#define FRAME_UBO_BINDING 0
layout(std140, binding = FRAME_UBO_BINDING) uniform Frame_UBO {
	mat4  projection;
	mat4  view;
	vec4  camera_position;
  float z_near;
  float z_far;
  int   debug_mode;
} frame;
#define DEBUG_MODE_NONE  0
#define DEBUG_MODE_DEPTH 1

#define LIGHT_UBO_BINDING 1
#define MAX_POINT_LIGHTS 16
layout(std140, binding = LIGHT_UBO_BINDING) uniform Light_UBO {
	Direction_Light direction;
	Point_Light     points[MAX_POINT_LIGHTS];
	int							points_count;
  Spot_Light			spot;
} lights;

uniform Material material;

vec3 calc_point_phong(Point_Light light, Material material, vec3 normal, vec3 view_direction, vec3 frag_position, vec2 frag_uv) {
	// AMBIENT
	vec3 ambient = light.ambient * vec3(texture(material.diffuse, frag_uv));

	// DIFFUSE
	vec3 light_direction = normalize(light.position - frag_position);
	// Is the pixel facing the light, it reflects more
	float diffuse_intensity = max(dot(normal, light_direction), 0.0);
	vec3 diffuse = diffuse_intensity * vec3(texture(material.diffuse, frag_uv));

	// SPECULAR
	// what direction, from the light to the normal of the fragment is the reflection
	vec3 reflect_direction = reflect(-light_direction, normal);
	// Is the reflection pointing towards the camera, and how shiny is the material?
	float specular_intensity = pow(max(dot(view_direction, reflect_direction), 0.0), material.shininess);
	vec3 specular = specular_intensity * vec3(texture(material.specular, frag_uv));

	// ATTENUATION
	float distance = length(light.position - frag_position);
	float attenuation = 1.0 / (light.attenuation.x + light.attenuation.y * distance + light.attenuation.z * (distance * distance));

	vec3 phong = attenuation * light.intensity * light.color * (ambient + diffuse + specular);

	return clamp(phong, 0.0, 1.0);
}

vec3 calc_direction_phong(Direction_Light light, Material material, vec3 normal, vec3 view_direction, vec2 frag_uv) {
	// AMBIENT
	vec3 ambient = light.ambient * vec3(texture(material.diffuse, frag_uv));

	// DIFFUSE
	vec3 light_direction = normalize(-light.direction);
	// Is the pixel facing the light, it reflects more
	float diffuse_intensity = max(dot(normal, light_direction), 0.0);
	vec3 diffuse = diffuse_intensity * vec3(texture(material.diffuse, frag_uv));

	// SPECULAR
	// what direction, from the light to the normal of the fragment is the reflection
	vec3 reflect_direction = reflect(-light_direction, normal);
	// Is the reflection directioning towards the camera, and how shiny is the material?
	float specular_intensity = pow(max(dot(view_direction, reflect_direction), 0.0), material.shininess);
	vec3 specular = specular_intensity * vec3(texture(material.specular, frag_uv));

	vec3 phong = light.intensity * light.color * (ambient + diffuse + specular);

	return clamp(phong, 0.0, 1.0);
}

vec3 calc_spot_phong(Spot_Light light, Material material, vec3 normal, vec3 view_direction, vec3 frag_position, vec2 frag_uv) {
	// AMBIENT
	vec3 ambient = light.ambient * vec3(texture(material.diffuse, frag_uv));

	vec3 light_direction = normalize(light.position - frag_position);

	// DIFFUSE
	float diffuse_intensity = max(dot(normal, light_direction), 0.0);
	vec3 diffuse = diffuse_intensity * vec3(texture(material.diffuse, frag_uv));

	// SPECULAR
	vec3 reflect_direction = reflect(-light_direction, normal);
	float specular_intensity = pow(max(dot(view_direction, reflect_direction), 0.0), material.shininess);
	vec3 specular = specular_intensity * vec3(texture(material.specular, frag_uv));

	// ATTENUATION
	float distance = length(light.position - frag_position);
	float attenuation = 1.0 / (light.attenuation.x + light.attenuation.y * distance + light.attenuation.z * (distance * distance));

	// SPOT EDGES - Cosines of angle
	float theta = dot(light_direction, normalize(-light.direction));
	float epsilon = light.inner_cutoff - light.outer_cutoff; // Angle cosine between inner cone and outer
	float spot_intensity = clamp((theta - light.outer_cutoff) / epsilon, 0.0, 1.0);

	vec3 phong = attenuation * light.intensity * light.color * (spot_intensity * (diffuse + specular) + ambient);

	// FIXME: just to make sure not getting negative
	return clamp(phong, 0.0, 1.0);
}

float linearize_depth(float depth, float near, float far) {
  float ndc = (depth * 2.0) - 1.0;
  // Unproject basically
  float linear_depth = (2.0 * near * far) / (far + near - ndc * (far - near));

  return linear_depth;
}

vec3 depth_to_color(float linear_depth, float far) {
  float normalized_depth = clamp((linear_depth / far), 0.0, 1.0);

  float brightness = normalized_depth;

  return brightness * vec3(1.0, 0.0, 0.0);
}

void main() {
  vec3 result = vec3(0.0);
  vec4 texture_color = texture(material.diffuse, fs_in.uv);

  switch (frame.debug_mode) {
  case DEBUG_MODE_NONE:

	  vec3 normal = normalize(fs_in.normal);
	  vec3 view_direction = normalize(vec3(frame.camera_position) - fs_in.world_position);

	  vec3 point_phong = vec3(0.0);
	  for (int i = 0; i < lights.points_count; i++) {
	  	point_phong += calc_point_phong(lights.points[i], material, normal, view_direction, fs_in.world_position, fs_in.uv);
	  }

	  vec3 direction_phong = calc_direction_phong(lights.direction, material, normal, view_direction, fs_in.uv);

	  vec3 spot_phong = calc_spot_phong(lights.spot, material, normal, view_direction, fs_in.world_position, fs_in.uv);

	  // EMISSION
	  vec3 emission = vec3(texture(material.emission, fs_in.uv));

	  result = point_phong + direction_phong + spot_phong + emission;
    break;

  case DEBUG_MODE_DEPTH:
    float depth = gl_FragCoord.z;
    float linear_depth = linearize_depth(depth, frame.z_near, frame.z_far);
    result = depth_to_color(linear_depth, frame.z_far);
    break;

  }

  out_color = vec4(result, texture_color.w);
}
