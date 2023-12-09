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

layout(std430, binding = 0) buffer _Vertexbuffer {
    ivec4 vb[];
} Vertexbuffer;

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

void main() {
  vec4 c;

  if (samplingMode == SAMPLING_CATROM || samplingMode == SAMPLING_MITCHELL) {
    c = textureCubic(tex, TexCoord, samplingMode);
  } else if (samplingMode == SAMPLING_XBR) {
    c = textureXBR(tex, TexCoord, xbrTable, ceil(1.0 * targetDimensions.x / sourceDimensions.x));
  } else {  // NEAREST or LINEAR, which uses GL_TEXTURE_MIN_FILTER/GL_TEXTURE_MAG_FILTER to affect sampling
    c = texture(tex, TexCoord);
  }

  c = alphaBlend(c, alphaOverlay);
  c.rgb = colorblind(colorBlindMode, c.rgb);

  vec3 rayDir = normalize(vec3((-1. + 2. * TexCoord), 2));
  rayDir.xy *= aspectScaling;
  rayDir = (inverse(viewMatrix) * vec4(rayDir * vec3(1,-1,-1), 0)).xyz;

  vec3 rayOrigin = cameraPosition;

  c = vec4(0,0,0,1);

  float lowestDepth = uintBitsToFloat(0x7F800000); // positive infinity as uint float bytes
  for (int i = 0; i < vertexCount; i+=3) {
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
  }
  FragColor = c;
}
