struct Point_Light {
  mat4  proj_views[6];
	vec4  position;

	vec4	color;

  float radius;
	float intensity;
	float ambient;
};

struct Direction_Light {
  mat4  proj_view;
	vec4  direction;

	vec4  color;

	float intensity;
	float ambient;
};

struct Spot_Light {
	vec4  position;
	vec4  direction;

	vec4  color;

  float radius;
	float intensity;
	float ambient;

	// Cosine
	float inner_cutoff;
	float outer_cutoff;
};

#define MAX_POINT_LIGHTS 128

#define FRAME_UBO_BINDING 0
layout(std140, binding = FRAME_UBO_BINDING) uniform Frame_UBO {
  mat4  projection;
  mat4  orthographic;
  mat4  view;
  mat4  proj_view;
  vec4  camera_position;
  float z_near;
  float z_far;
  int   debug_mode;
  vec4  scene_extents;
  struct {
  	Direction_Light direction;
  	Point_Light     points[MAX_POINT_LIGHTS];
  	int							points_count;
    Spot_Light			spot;
  } lights;
} frame;
#define DEBUG_MODE_NONE  0
#define DEBUG_MODE_DEPTH 1
