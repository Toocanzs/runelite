/*
 * Copyright (c) 2018, Adam <Adam@sigterm.info>
 * All rights reserved.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions are met:
 *
 * 1. Redistributions of source code must retain the above copyright notice, this
 *    list of conditions and the following disclaimer.
 * 2. Redistributions in binary form must reproduce the above copyright notice,
 *    this list of conditions and the following disclaimer in the documentation
 *    and/or other materials provided with the distribution.
 *
 * THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
 * ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
 * WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
 * DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE LIABLE FOR
 * ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
 * (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
 * LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
 * ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
 * (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
 * SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 */
#version 430

#define SAMPLING_MITCHELL 1
#define SAMPLING_CATROM 2
#define SAMPLING_XBR 3

uniform sampler2D tex;

uniform int samplingMode;
uniform ivec2 sourceDimensions;
uniform ivec2 targetDimensions;
uniform int colorBlindMode;
uniform vec4 alphaOverlay;
uniform int vertexCount;
uniform vec3 cameraPosition;
uniform float brightness;
uniform vec2 aspectScaling;

uniform mat4 viewMatrix;
//uniform mat4 projection;

layout(std430, binding = 0) readonly buffer _Vertexbuffer {
    ivec4 vb[];
} Vertexbuffer;

#include "raytracing/bvh_node.glsl"

layout(std430, binding = 1) readonly buffer _nodes {
    BVHNode bvh_nodes[];
};

#include "scale/bicubic.glsl"
#include "scale/xbr_lv2_frag.glsl"
#include "colorblind.glsl"
#include "hsl_to_rgb.glsl"

in vec2 TexCoord;
in XBRTable xbrTable;

out vec4 FragColor;

vec4 alphaBlend(vec4 src, vec4 dst) {
  return vec4(src.rgb + dst.rgb * (1.0f - src.a), src.a + dst.a * (1.0f - src.a));
}

vec3 triIntersect( in vec3 ro, in vec3 rd, in vec3 v0, in vec3 v1, in vec3 v2 )
{
    // https://iquilezles.org/articles/intersectors/
    vec3 v1v0 = v1 - v0;
    vec3 v2v0 = v2 - v0;
    vec3 rov0 = ro - v0;
    vec3  n = cross( v1v0, v2v0 );
    vec3  q = cross( rov0, rd );
    float d = 1.0/dot( rd, n );
    float u = d*dot( -q, v2v0 );
    float v = d*dot(  q, v1v0 );
    float t = d*dot( -n, rov0 );
    if( u<0.0 || v<0.0 || (u+v)>1.0 ) t = -1.0;
    return vec3( t, u, v );
}

uint signBit(float f) {
  uint negZero = 0x80000000;
  uint signBit = negZero &  floatBitsToUint(f);
  return signBit;
}

#define INFINITY uintBitsToFloat(0x7F800000)

float intersect(vec3 rayOrigin, vec3 invRayDir, BVHNode node) {
  // https://tavianator.com/2022/ray_box_boundary.html
  float tmin = 0;
  float tmax = uintBitsToFloat(0x7F800000); // positive infinity as uint float bytes
  for (int d = 0; d < 3; d++) {
    bool sign = bool(signBit(invRayDir[d]));
    ivec3 bminCorner = sign ? node.aabb_max : node.aabb_min;
    ivec3 bmaxCorner = (!sign) ? node.aabb_max : node.aabb_min;
    float bmin = bminCorner[d];
    float bmax = bmaxCorner[d];

    float dmin = (bmin - rayOrigin[d]) * invRayDir[d];
    float dmax = (bmax - rayOrigin[d]) * invRayDir[d];

    tmin = max(dmin, tmin);
    tmax = min(dmax, tmax);
  }
  return tmin < tmax ? tmin : INFINITY;
}

bool intersect(vec3 rayOrigin, vec3 invRayDir, BVHNode node) {
  float dont_care;
  return intersect(rayOrigin, invRayDir, node, dont_care);
}


void main() {
  vec4 c;

  if (samplingMode == SAMPLING_CATROM || samplingMode == SAMPLING_MITCHELL) {
    c = textureCubic(tex, TexCoord, samplingMode);
  } else if (samplingMode == SAMPLING_XBR) {
    c = textureXBR(tex, TexCoord, xbrTable, ceil(1.0 * targetDimensions.x / sourceDimensions.x));
  } else {  // NEAREST or LINEAR, which uses GL_TEXTURE_MIN_FILTER/GL_TEXTURE_MAG_FILTER to affect sampling
    c = texture(tex, TexCoord);
  }

  vec3 rayDir = normalize(vec3((-1. + 2. * TexCoord), 2));
  rayDir.xy *= aspectScaling;
  rayDir = (inverse(viewMatrix) * vec4(rayDir * vec3(1,-1,-1), 0)).xyz;
  vec3 invRayDir = 1.0 / rayDir; // NOTE: The following code relies on divide by zero returning an infinity of the same sign as defined by IEEE 754
  vec3 rayOrigin = cameraPosition;

  float lowestDepth = uintBitsToFloat(0x7F800000); // positive infinity as uint float bytes
  BVHNode root = bvh_nodes[0];

  /*while (root.leaf_object_id_plus_one == 0) {
    root = bvh_nodes[root.left_child_index];
  }*/

  bool intersected_root = intersect(rayOrigin, invRayDir, root) != INFINITY;

  /*BVHNode current_node = root;
  #define STACK_SIZE 64
  int stack[STACK_SIZE];
  uint stack_pointer = 0;
  while (intersected_root && stack_pointer < STACK_SIZE) {
    // Stack based traversal from https://jacco.ompf2.com/2022/04/18/how-to-build-a-bvh-part-2-faster-rays/
    if (nodes[current_node].leaf_object_id_plus_one == 0) {// leaf
      uint triangle_index = nodes[current_node].leaf_object_id_plus_one - 1;
      ivec4 vA = Vertexbuffer.vb[triangle_index + 0];
      ivec4 vB = Vertexbuffer.vb[triangle_index + 1];
      ivec4 vC = Vertexbuffer.vb[triangle_index + 2];

      vec3 tuv = triIntersect(rayOrigin, rayDir, vec3(vA.x, vA.y, vA.z), vec3(vB.x, vB.y, vB.z), vec3(vC.x, vC.y, vC.z));
      // hit = tuv.x >= 0;
      // TODO: Store this triangle index as the closest along with the depth, only sample at the end
      if (stack_pointer == 0) {
        break;
      } else {
        current_node = stack[--stack_pointer];
      }
      continue;
    }
    uint left_child_index = nodes[current_node].left_child_index;
    uint right_child_index = nodes[current_node].left_child_index;

    float distance1 = intersect(rayOrigin, invRayDir, nodes[left_child_index], distance_left);
    float distance2 = intersect(rayOrigin, invRayDir, nodes[right_child_index], distance_right);

    if (distance1 > distance2) {

    }
  }*/
  
  int hits = 0;
  int count = 0;
  if (intersected_root) {
    c.rgb = vec3(1,0,1);
  }
  /*for (int i = 0; i < vertexCount; i+=3) {
    ivec4 vA = Vertexbuffer.vb[i + 0];
    ivec4 vB = Vertexbuffer.vb[i + 1];
    ivec4 vC = Vertexbuffer.vb[i + 2];

    vec3 tuv = triIntersect(rayOrigin, rayDir, vec3(vA.x, vA.y, vA.z), vec3(vB.x, vB.y, vB.z), vec3(vC.x, vC.y, vC.z));

    if (tuv.x >= 0 && tuv.x < lowestDepth) {
        vec3 colorA = hslToRgb(vA.w & 0xffff);
        vec3 colorB = hslToRgb(vB.w & 0xffff);
        vec3 colorC = hslToRgb(vC.w & 0xffff);

        vec3 barry = vec3(1.0 - tuv.y - tuv.z, tuv.y, tuv.z);
        c.rgb = barry.x * colorA + barry.y * colorB + barry.z * colorC;
        lowestDepth = tuv.x;
    }
  }*/

  c = alphaBlend(c, alphaOverlay);
  c.rgb = colorblind(colorBlindMode, c.rgb);

  FragColor = c;
}
