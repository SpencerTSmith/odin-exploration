#version 450 core

in VS_OUT {
  vec2 uv;
  vec3 normal;
  vec3 world_position;
  vec4 light_space_position;
} fs_in;

out vec4 frag_color;

#include "include.glsl"

layout(binding = 0) uniform sampler2D mat_diffuse;
layout(binding = 1) uniform sampler2D mat_specular;
layout(binding = 2) uniform sampler2D mat_emissive;
uniform float mat_shininess;

layout(binding = 3) uniform samplerCube skybox;

layout(binding = 4) uniform sampler2D   light_depth;

layout(binding = 5) uniform samplerCube light_cube;
uniform float light_z_far;
uniform float light_position;

uniform vec4 mul_color;

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

vec3 calc_spot_phong(Spot_Light light, vec3 diffuse_sample, vec3 specular_sample, float shininess,
                     vec3 normal, vec3 view_direction, vec3 frag_position) {
	vec3 ambient = calc_phong_ambient(light.ambient, diffuse_sample);

	vec3 light_direction = normalize(light.position.xyz - frag_position);

	vec3 diffuse = calc_phong_diffuse(normal, light_direction, diffuse_sample);

	vec3 specular = calc_phong_specular(normal, light_direction, view_direction, specular_sample, shininess);

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

vec3 calc_direction_phong(Direction_Light light, vec3 diffuse_sample, vec3 specular_sample, float shininess,
                          vec3 normal, vec3 view_direction) {
	vec3 ambient = calc_phong_ambient(light.ambient, diffuse_sample);

	vec3 light_direction = normalize(-light.direction.xyz);

	vec3 diffuse = calc_phong_diffuse(normal, light_direction, diffuse_sample);

	vec3 specular = calc_phong_specular(normal, light_direction, view_direction, specular_sample, shininess);

  diffuse  = calc_phong_skybox_mix(normal, view_direction, diffuse,  skybox, 0.1);
  specular = calc_phong_skybox_mix(normal, view_direction, specular, skybox, 0.5);

	vec3 phong = light.intensity * light.color.rgb * (ambient + diffuse + specular);

	return clamp(phong, 0.0, 1.0);
}

vec3 calc_point_phong(Point_Light light, vec3 diffuse_sample, vec3 specular_sample, float shininess,
                      vec3 normal, vec3 view_direction, vec3 frag_position) {
	vec3 ambient = calc_phong_ambient(light.ambient, diffuse_sample);

	vec3 light_direction = normalize(light.position.xyz - frag_position);

	vec3 diffuse = calc_phong_diffuse(normal, light_direction, diffuse_sample);

	vec3 specular = calc_phong_specular(normal, light_direction, view_direction, specular_sample, shininess);

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

float calc_sun_shadow(sampler2D shadow_map, vec4 light_space_position, vec3 light_direction, vec3 normal) {
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

float calc_shadow(samplerCube map, vec3 frag_pos, vec3 light_pos, float light_z_far) {
  vec3 frag_to_light = frag_pos - light_pos;

  float closest_depth = texture(map, frag_to_light).r;
  closest_depth *= light_z_far;

  float current_depth = length(frag_to_light);

  float bias   = 0.05;
  float shadow = current_depth - bias > closest_depth ? 1.0 : 0.0;

  return shadow;
}

void main() {
  vec3 result = vec3(0.0);
  float alpha = texture(mat_diffuse, fs_in.uv).a;

  vec3 diffuse_sample  = vec3(texture(mat_diffuse, fs_in.uv));
  vec3 specular_sample = vec3(texture(mat_specular, fs_in.uv));
	vec3 emissive        = vec3(texture(mat_emissive, fs_in.uv));

  switch (frame.debug_mode) {
  case DEBUG_MODE_NONE:
	  vec3 normal = normalize(fs_in.normal);
	  vec3 view_direction = normalize(vec3(frame.camera_position) - fs_in.world_position);

	  vec3 point_phong = vec3(0.0);
	  for (int i = 0; i < frame.lights.points_count; i++) {
	  	point_phong += calc_point_phong(frame.lights.points[i], diffuse_sample, specular_sample, mat_shininess,
                                      normal, view_direction, fs_in.world_position);
	  }

	  vec3 direction_phong = calc_direction_phong(frame.lights.direction, diffuse_sample, specular_sample, mat_shininess,
                                                normal, view_direction);

	  vec3 spot_phong = calc_spot_phong(frame.lights.spot, diffuse_sample, specular_sample, mat_shininess,
                                      normal, view_direction, fs_in.world_position);

    float shadow = 1.0 - calc_sun_shadow(light_depth, fs_in.light_space_position, vec3(0.0, 0.0, 0.0), normal);

    float point_shadow = 1.0 - calc_shadow(light_cube, fs_in.world_position, frame.lights.points[0].position.xyz, light_z_far);

	  result = (point_phong * point_shadow) + (direction_phong * shadow) + spot_phong + emissive;
    break;
  case DEBUG_MODE_DEPTH:
    float depth = gl_FragCoord.z;
    float linear_depth = linearize_depth(depth, frame.z_near, frame.z_far);
    result = depth_to_color(linear_depth, frame.z_far);
    break;
  }

  frag_color = vec4(result, alpha) * mul_color;
}
