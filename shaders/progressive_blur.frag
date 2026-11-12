// Variable ("progressive") blur for a screen edge: the blur radius is
// largest at the edge (top or bottom) and eases smoothly to zero uHeight
// away from it, so there is no seam. Used as a BackdropFilter through
// ImageFilter.shader, behind the status bar and the tab bar.
#version 460 core
#include <flutter/runtime_effect.glsl>

// Set by the engine: the size of the input texture.
uniform vec2 uSize;
// Where the blur reaches zero, in physical pixels from the edge.
uniform float uHeight;
// Blur radius at the edge, in physical pixels.
uniform float uMaxRadius;
// 0: the edge is the top; 1: the edge is the bottom.
uniform float uFromBottom;
// Set by the engine: what is behind the status bar.
uniform sampler2D uTexture;

out vec4 fragColor;

const int TAPS = 32;
const float GOLDEN_ANGLE = 2.39996323;

void main() {
  vec2 p = FlutterFragCoord().xy;
#ifdef IMPELLER_TARGET_OPENGLES
  p.y = uSize.y - p.y;
#endif
  // Distance from the edge; 1 at the edge, 0 at uHeight, with a smooth ease
  // so the end has no visible line.
  float fromEdge = mix(p.y, uSize.y - p.y, uFromBottom);
  float t = clamp(1.0 - fromEdge / uHeight, 0.0, 1.0);
  float radius = uMaxRadius * t * t * (3.0 - 2.0 * t);

  vec2 uv = p / uSize;
#ifdef IMPELLER_TARGET_OPENGLES
  uv.y = 1.0 - uv.y;
#endif
  if (radius < 0.5) {
    fragColor = texture(uTexture, uv);
    return;
  }

  // Gaussian-weighted samples on a golden-angle spiral (an even disc).
  vec4 sum = vec4(0.0);
  float weight = 0.0;
  float sigma = radius * 0.5;
  for (int i = 0; i < TAPS; i++) {
    float fi = float(i);
    float d = sqrt((fi + 0.5) / float(TAPS)) * radius;
    float a = fi * GOLDEN_ANGLE;
    vec2 offset = vec2(cos(a), sin(a)) * d;
#ifdef IMPELLER_TARGET_OPENGLES
    offset.y = -offset.y;
#endif
    float k = exp(-(d * d) / (2.0 * sigma * sigma));
    sum += texture(uTexture, uv + offset / uSize) * k;
    weight += k;
  }
  fragColor = sum / weight;
}
