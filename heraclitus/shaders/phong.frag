#version 450 core

in VS_OUT {
  vec2 uv;
  vec3 normal;
  vec3 world_position;
  vec4 light_space_position;
} fs_in;

out vec4 frag_color;

#include "include.glsl"

uniform Material material;

uniform samplerCube skybox;
uniform sampler2D   light_depth;

uniform vec4 mul_color;

// All functions expect already normalized vectors
vec3 calc_point_phong(Point_Light light, Material material, vec3 normal, vec3 view_direction, vec3 frag_position, vec2 frag_uv);
vec3 calc_direction_phong(Direction_Light light, Material material, vec3 normal, vec3 view_direction, vec2 frag_uv);
vec3 calc_spot_phong(Spot_Light light, Material material, vec3 normal, vec3 view_direction, vec3 frag_position, vec2 frag_uv);

float calc_shadow(sampler2D shadow_map, vec4 light_space_position, vec3 light_direction, vec3 normal);

float linearize_depth(float depth, float near, float far);
vec3 depth_to_color(float linear_depth, float far);

void main() {
  vec3 result = vec3(0.0);
  vec4 texture_color = texture(material.diffuse, fs_in.uv);

  switch (frame.debug_mode) {
  case DEBUG_MODE_NONE:
	  vec3 normal = normalize(fs_in.normal);
	  vec3 view_direction = normalize(vec3(frame.camera_position) - fs_in.world_position);

	  vec3 point_phong = vec3(0.0);
	  for (int i = 0; i < frame.lights.points_count; i++) {
	  	point_phong += calc_point_phong(frame.lights.points[i], material, normal, view_direction, fs_in.world_position, fs_in.uv);
	  }

	  vec3 direction_phong = calc_direction_phong(frame.lights.direction, material, normal, view_direction, fs_in.uv);

	  vec3 spot_phong = calc_spot_phong(frame.lights.spot, material, normal, view_direction, fs_in.world_position, fs_in.uv);

	  vec3 emission = vec3(texture(material.emission, fs_in.uv));

    float shadow = 1.0 - calc_shadow(light_depth, fs_in.light_space_position, vec3(0.0, 0.0, 0.0), normal);

	  result = shadow * (point_phong + direction_phong + spot_phong) + emission;
    break;
  case DEBUG_MODE_DEPTH:
    float depth = gl_FragCoord.z;
    float linear_depth = linearize_depth(depth, frame.z_near, frame.z_far);
    result = depth_to_color(linear_depth, frame.z_far);
    break;
  }

  frag_color = vec4(result, texture_color.w) * mul_color;
}

// Must sample the texture first and pass in that color... keeps this nice and generic
vec3 calc_phong_diffuse(vec3 normal, vec3 light_direction, vec3 diffuse_color) {
	float diffuse_intensity = max(dot(normal, light_direction), 0.0);
	vec3 diffuse = diffuse_intensity * diffuse_color;

  return diffuse;
}

// Must sample the texture first and pass in that color... keeps this nice and generic
vec3 calc_phong_specular(vec3 normal, vec3 light_direction, vec3 view_direction, vec3 specular_color, float shininess) {
	vec3 reflect_direction = reflect(-light_direction, normal);
  vec3 halfway_direction = normalize(light_direction + view_direction);

	float specular_intensity = pow(max(dot(normal, halfway_direction), 0.0), shininess);
	vec3 specular = specular_intensity * specular_color;

  return specular;
}

// Only a function since it is used multiple times
vec3 calc_phong_ambient(float ambient_intensity, vec3 color) {
	vec3 ambient = ambient_intensity * color;

  return ambient;
}

vec3 calc_phong_skybox_mix(vec3 normal, vec3 view_direction, vec3 color, samplerCube skybox, float intensity) {
  vec3 skybox_reflection = texture(skybox, reflect(-view_direction, normal)).rgb;
  vec3 result = mix(color, skybox_reflection, intensity * length(color));

  return result;
}

vec3 calc_spot_phong(Spot_Light light, Material material, vec3 normal, vec3 view_direction, vec3 frag_position, vec2 frag_uv) {
	vec3 ambient = calc_phong_ambient(light.ambient, vec3(texture(material.diffuse, frag_uv)));

	vec3 light_direction = normalize(light.position.xyz - frag_position);

	vec3 diffuse = calc_phong_diffuse(normal, light_direction, vec3(texture(material.diffuse, frag_uv)));

	vec3 specular = calc_phong_specular(normal, light_direction, view_direction, vec3(texture(material.specular, frag_uv)), material.shininess);

  diffuse  = calc_phong_skybox_mix(normal, view_direction, diffuse,  skybox, 0.1);
  specular = calc_phong_skybox_mix(normal, view_direction, specular, skybox, 0.5);

	// ATTENUATION
	float distance = length(light.position.xyz - frag_position);
	float attenuation = 1.0 / (light.attenuation.x + light.attenuation.y * distance + light.attenuation.z * (distance * distance));

	// SPOT EDGES - Cosines of angle
	float theta = dot(light_direction, normalize(-light.direction.xyz));
	float epsilon = light.inner_cutoff - light.outer_cutoff; // Angle cosine between inner cone and outer
	float spot_intensity = clamp((theta - light.outer_cutoff) / epsilon, 0.0, 1.0);

	vec3 phong = attenuation * light.intensity * light.color.rgb * (spot_intensity * (diffuse + specular) + ambient);

	// FIXME: just to make sure not getting negative
	return clamp(phong, 0.0, 1.0);
}

vec3 calc_direction_phong(Direction_Light light, Material material, vec3 normal, vec3 view_direction, vec2 frag_uv) {
	vec3 ambient = calc_phong_ambient(light.ambient, vec3(texture(material.diffuse, frag_uv)));

	vec3 light_direction = normalize(-light.direction.xyz);

	vec3 diffuse = calc_phong_diffuse(normal, light_direction, vec3(texture(material.diffuse, frag_uv)));

	vec3 specular = calc_phong_specular(normal, light_direction, view_direction, vec3(texture(material.specular, frag_uv)), material.shininess);

  diffuse  = calc_phong_skybox_mix(normal, view_direction, diffuse,  skybox, 0.1);
  specular = calc_phong_skybox_mix(normal, view_direction, specular, skybox, 0.5);

	vec3 phong = light.intensity * light.color.rgb * (ambient + diffuse + specular);

	return clamp(phong, 0.0, 1.0);
}

vec3 calc_point_phong(Point_Light light, Material material, vec3 normal, vec3 view_direction, vec3 frag_position, vec2 frag_uv) {
	vec3 ambient = calc_phong_ambient(light.ambient, vec3(texture(material.diffuse, frag_uv)));

	vec3 light_direction = normalize(light.position.xyz - frag_position);

	vec3 diffuse = calc_phong_diffuse(normal, light_direction, vec3(texture(material.diffuse, frag_uv)));

	vec3 specular = calc_phong_specular(normal, light_direction, view_direction, vec3(texture(material.specular, frag_uv)), material.shininess);

  diffuse  = calc_phong_skybox_mix(normal, view_direction, diffuse,  skybox, 0.1);
  specular = calc_phong_skybox_mix(normal, view_direction, specular, skybox, 0.5);

	// ATTENUATION
	float distance = length(light.position.xyz - frag_position);
	float attenuation = 1.0 / (light.attenuation.x + light.attenuation.y * distance + light.attenuation.z * (distance * distance));

	vec3 phong = attenuation * light.intensity * light.color.rgb * (ambient + diffuse + specular);

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

float calc_shadow(sampler2D shadow_map, vec4 light_space_position, vec3 light_direction, vec3 normal) {
  // Fix shadow acne, surfaces facing away get large bias, surfaces facing toward get less
  float bias = max(0.05 * (1.0 - dot(normal, light_direction)), 0.005);

  // Perspective divide
  vec3 projected = light_space_position.xyz / light_space_position.w;
  // From NDC to [0, 1]
  projected = projected * 0.5 + 0.5;

  float mapped_depth = texture(shadow_map, projected.xy).r;
  float actual_depth = projected.z;

  // float shadow = actual_depth - bias > mapped_depth && projected.z <= 1.0 ? 1.0 : 0.0;
  float shadow = 0.0;
  vec2 texel_size = 1.0 / textureSize(shadow_map, 0);
  for (int x = -3; x <= 3; ++x) {
    for (int y = -3; y <= 3; ++y) {
      float pcf_depth = texture(shadow_map, projected.xy + vec2(x, y) * texel_size).r;
      shadow += actual_depth - bias > pcf_depth ? 1.0 : 0.0;
    }
  }
  shadow /= 49.0;

  if (projected.z > 1.0)
    shadow = 0.0;

  return shadow;
}
