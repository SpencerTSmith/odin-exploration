#version 450 core

in VS_OUT {
  vec2 uv;
  vec3 normal;
  vec3 world_position;
  vec4 sun_space_position;
} fs_in;

layout(location=0) out vec4 frag_color;

#include "include.glsl"

layout(binding = 0) uniform sampler2D mat_diffuse;
layout(binding = 1) uniform sampler2D mat_specular;
layout(binding = 2) uniform sampler2D mat_emissive;
layout(binding = 3) uniform sampler2D mat_normal;
uniform float mat_shininess;

layout(binding = 4) uniform samplerCube skybox;

layout(binding = 5) uniform sampler2D sun_shadow_map;

layout(binding = 6) uniform samplerCubeArray point_light_shadows;

uniform vec4 mul_color;

// Must sample the texture first and pass in that color... keeps this nice and generic
vec3 phong_diffuse(vec3 normal, vec3 light_direction, vec3 diffuse_color) {
	float diffuse_intensity = max(dot(normal, light_direction), 0.0);
	vec3 diffuse = diffuse_intensity * diffuse_color;

  return diffuse;
}

// Must sample the texture first and pass in that color... keeps this nice and generic
vec3 phong_specular(vec3 normal, vec3 light_direction, vec3 view_direction, vec3 specular_color, float shininess) {
	vec3 reflect_direction = reflect(-light_direction, normal);
  vec3 halfway_direction = normalize(light_direction + view_direction);

	float specular_intensity = pow(max(dot(normal, halfway_direction), 0.0), shininess);
	vec3 specular = specular_intensity * specular_color;

  return specular;
}

// Only a function since it is used multiple times
vec3 phong_ambient(float ambient_intensity, vec3 color) {
	vec3 ambient = ambient_intensity * color;

  return ambient;
}

vec3 phong_skybox_mix(vec3 normal, vec3 view_direction, vec3 color, samplerCube skybox, float intensity) {
  vec3 skybox_reflection = texture(skybox, reflect(-view_direction, normal)).rgb;
  vec3 result = mix(color, skybox_reflection, intensity * length(color));

  return result;
}

float attenuation(vec3 light_pos, float light_radius, vec3 frag_pos) {
  float distance = length(light_pos - frag_pos);

  if (distance >= light_radius) return 0.0;

  float ratio = distance / light_radius;
  float falloff = 1.0 - ratio * ratio;

  return smoothstep(0.0, 1.0, falloff);
}

vec3 spot_phong(Spot_Light light, vec3 diffuse_sample, vec3 specular_sample, float shininess,
                     vec3 normal, vec3 view_direction, vec3 frag_position) {

	vec3 light_direction = normalize(light.position.xyz - frag_position);

	vec3 diffuse = phong_diffuse(normal, light_direction, diffuse_sample);

	vec3 specular = phong_specular(normal, light_direction, view_direction, specular_sample, shininess);

  diffuse  = phong_skybox_mix(normal, view_direction, diffuse,  skybox, 0.1);
  specular = phong_skybox_mix(normal, view_direction, specular, skybox, 0.5);

	// ATTENUATION
	float attenuation = attenuation(light.position.xyz, light.radius, frag_position);

	// SPOT EDGES - Cosines of angle
	float theta = dot(light_direction, normalize(-light.direction.xyz));
	float epsilon = light.inner_cutoff - light.outer_cutoff; // Angle cosine between inner cone and outer
	float spot_intensity = clamp((theta - light.outer_cutoff) / epsilon, 0.0, 1.0);

	vec3 phong = attenuation * light.intensity * light.color.rgb * (spot_intensity * (diffuse + specular));

	// FIXME: just to make sure not getting negative
	return clamp(phong, 0.0, 1.0);
}

vec3 direction_phong(Direction_Light light, vec3 diffuse_sample, vec3 specular_sample, float shininess,
                          vec3 normal, vec3 view_direction) {

	vec3 light_direction = normalize(-light.direction.xyz);

	vec3 diffuse = phong_diffuse(normal, light_direction, diffuse_sample);

	vec3 specular = phong_specular(normal, light_direction, view_direction, specular_sample, shininess);

  diffuse  = phong_skybox_mix(normal, view_direction, diffuse,  skybox, 0.1);
  specular = phong_skybox_mix(normal, view_direction, specular, skybox, 0.5);

	vec3 phong = light.intensity * light.color.rgb * (diffuse + specular);

	return clamp(phong, 0.0, 1.0);
}

vec3 point_phong(Point_Light light, vec3 diffuse_sample, vec3 specular_sample, float shininess,
                      vec3 normal, vec3 view_direction, vec3 frag_position) {
	vec3 light_direction = normalize(light.position.xyz - frag_position);

	vec3 diffuse = phong_diffuse(normal, light_direction, diffuse_sample);

	vec3 specular = phong_specular(normal, light_direction, view_direction, specular_sample, shininess);

  diffuse  = phong_skybox_mix(normal, view_direction, diffuse,  skybox, 0.1);
  specular = phong_skybox_mix(normal, view_direction, specular, skybox, 0.5);

	// ATTENUATION
	float attenuation = attenuation(light.position.xyz, light.radius, frag_position);

	vec3 phong = attenuation * light.intensity * light.color.rgb * (diffuse + specular);

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

// Fix shadow acne, surfaces facing away get large bias, surfaces facing toward get less
float shadow_bias(vec3 normal, vec3 to_light_dir) {
  float facing_dot  = max(dot(normal, to_light_dir), 0.0);
  float slope_scale = 0.005;
  float min_bias    = 0.0005;
  float bias        = min_bias + slope_scale * (1.0 - facing_dot);

  return bias;
}

float sun_shadow(sampler2D shadow_map, vec4 light_space_position, vec3 to_light_dir, vec3 normal) {

  // Perspective divide
  vec3 projected = light_space_position.xyz / light_space_position.w;
  // From NDC to [0, 1]
  projected = projected * 0.5 + 0.5;
  if (projected.z > 1.0)
    return 0.0;

  float mapped_depth = texture(shadow_map, projected.xy).r;
  float actual_depth = projected.z;

  int sample_count = 16;
  vec2 sample_offsets[16] = vec2[] (
    vec2(-1.5, -1.5), vec2(-0.5, -1.5), vec2( 0.5, -1.5), vec2( 1.5, -1.5),
    vec2(-1.5, -0.5), vec2(-0.5, -0.5), vec2( 0.5, -0.5), vec2( 1.5, -0.5),
    vec2(-1.5,  0.5), vec2(-0.5,  0.5), vec2( 0.5,  0.5), vec2( 1.5,  0.5),
    vec2(-1.5,  1.5), vec2(-0.5,  1.5), vec2( 0.5,  1.5), vec2( 1.5,  1.5)
  );


  // Fix shadow acne, surfaces facing away get large bias, surfaces facing toward get less
  float bias = shadow_bias(normal, normalize(to_light_dir));

  float shadow = 0.0;
  float view_distance = length(frame.camera_position.xyz - fs_in.world_position);

  float disk_radius = 1.0 + (view_distance / 10.0);
  disk_radius       = clamp(disk_radius, 1.0, 4.0);

  vec2 texel_size = 1.0 / textureSize(shadow_map, 0);

  for (int i = 0; i < sample_count; ++i) {
    vec2 sample_uv = projected.xy + sample_offsets[i] * disk_radius * texel_size;

    // Sample uvs depth
    float map_depth = texture(shadow_map, sample_uv).r;

    float visibility = (actual_depth - bias) > map_depth ? 1.0 : 0.0;

    shadow += visibility * 1.0;
  }

  shadow /= float(sample_count);

  // float shadow = 0.0;
  // vec2 texel_size = 1.0 / textureSize(shadow_map, 0);
  // for (int x = -3; x <= 3; ++x) {
  //   for (int y = -3; y <= 3; ++y) {
  //     float pcf_depth = texture(shadow_map, projected.xy + vec2(x, y) * texel_size).r;
  //     shadow += actual_depth - bias > pcf_depth ? 1.0 : 0.0;
  //   }
  // }
  // shadow /= 49.0;
  //
  return shadow;
}

// NOTE: Light z far for now just means the lights radius
float point_shadow(samplerCubeArray map, int light_index, vec3 frag_pos, vec3 frag_normal, vec3 light_pos, float light_z_far, vec3 view_pos) {
  vec3 light_to_frag = frag_pos - light_pos;

  // Actual depth of the frag pos to the light
  float actual_depth = length(light_to_frag);

  // PCF
  int sample_count = 20;
  vec3 sample_offsets[20] = vec3[] (
    vec3( 1,  1,  1), vec3( 1, -1,  1), vec3(-1, -1,  1), vec3(-1,  1,  1),
    vec3( 1,  1, -1), vec3( 1, -1, -1), vec3(-1, -1, -1), vec3(-1,  1, -1),
    vec3( 1,  1,  0), vec3( 1, -1,  0), vec3(-1, -1,  0), vec3(-1,  1,  0),
    vec3( 1,  0,  1), vec3(-1,  0,  1), vec3( 1,  0, -1), vec3(-1,  0, -1),
    vec3( 0,  1,  1), vec3( 0, -1,  1), vec3( 0, -1, -1), vec3( 0,  1, -1)
  );

  float shadow = 0.0;

  // Fix shadow acne, surfaces facing away get large bias, surfaces facing toward get less
  vec3 to_light_dir = normalize(-light_to_frag);
  float bias        = shadow_bias(frag_normal, to_light_dir);

  float view_dist   = length(view_pos - frag_pos);
  float disk_radius = (1.0 + (view_dist / light_z_far)) / 30.0;

  for (int i = 0; i < sample_count; ++i) {
    vec3 sample_location = light_to_frag + sample_offsets[i] * disk_radius;

    // Sample locations depth
    float map_depth = texture(map, vec4(sample_location, float(light_index))).r * light_z_far;

    float visibility = (actual_depth - bias) > map_depth ? 1.0 : 0.0;

    shadow += visibility * 1.0;
  }

  shadow /= float(sample_count);

  return shadow;
}

void main() {
  vec3 result = vec3(0.0);
  float alpha = texture(mat_diffuse, fs_in.uv).a;

  switch (frame.debug_mode)
  {
  case DEBUG_MODE_NONE:
    vec3 diffuse_sample  = vec3(texture(mat_diffuse, fs_in.uv));
    vec3 specular_sample = vec3(texture(mat_specular, fs_in.uv));
    vec3 emissive        = vec3(texture(mat_emissive, fs_in.uv));

    // // Textures are in range 0 -> 1
    // vec3 normal = texture(mat_normal, fs_in.uv).rgb;
    // // To [-1, 1]
    // normal = normalize(normal * 2.0 - 1.0);


    vec3 normal = normalize(fs_in.normal);

	  vec3 view_direction = normalize(frame.camera_position.xyz - fs_in.world_position);

    vec3 ambient = vec3(0.02); // Little bit of global ambient

	  vec3 all_point_phong = vec3(0.0);
	  for (int i = 0; i < frame.lights.points_count; i++)
    {
      Point_Light light = frame.lights.points[i];
      float distance    = length(light.position.xyz - fs_in.world_position);

      if (distance < light.radius)
      {
        float point_shadow = 1.0 - point_shadow(point_light_shadows, i, fs_in.world_position, normal,
                                                light.position.xyz, light.radius, frame.camera_position.xyz);

        vec3 point_phong  = point_phong(light, diffuse_sample, specular_sample, mat_shininess,
                                        normal, view_direction, fs_in.world_position);
        point_phong *= point_shadow;

        all_point_phong += point_phong;

        ambient += phong_ambient(light.ambient, light.color.xyz);
      }
	  }

	  vec3 direction_phong = direction_phong(frame.lights.direction, diffuse_sample, specular_sample, mat_shininess,
                                           normal, view_direction);

    float shadow = 1.0 - sun_shadow(sun_shadow_map, fs_in.sun_space_position, -frame.lights.direction.direction.xyz, normal);

    direction_phong *= shadow;

    ambient += phong_ambient(frame.lights.direction.ambient, frame.lights.direction.color.xyz);

	  vec3 spot_phong = spot_phong(frame.lights.spot, diffuse_sample, specular_sample, mat_shininess,
                                      normal, view_direction, fs_in.world_position);

    ambient += phong_ambient(frame.lights.spot.ambient, frame.lights.spot.color.xyz);

    ambient *= diffuse_sample;

	  result = all_point_phong + direction_phong + spot_phong + emissive + ambient;
    break;
  case DEBUG_MODE_DEPTH:
    float depth = gl_FragCoord.z;
    float linear_depth = linearize_depth(depth, frame.z_near, frame.z_far);
    result = depth_to_color(linear_depth, frame.z_far);
    break;
  }

  frag_color = vec4(result, alpha) * mul_color;

  // float brightness = dot(frag_color.rgb, vec3(0.2126, 0.7152, 0.0722));
  //
  // if (brightness > 1.0) {
  //   bright_color = vec4(frag_color.rgb, 1.0);
  // } else {
  //   bright_color = vec4(0.0, 0.0, 0.0, 1.0);
  // }
}
