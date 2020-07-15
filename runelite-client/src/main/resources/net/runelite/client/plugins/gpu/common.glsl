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

#include to_screen.glsl

/*
 * Rotate a vertex by a given orientation in JAU
 */
ivec4 rotate(ivec4 vertex, int orientation) {
  ivec2 sinCos = sinCosTable[orientation];
  int s = sinCos.x;
  int c = sinCos.y;
  int x = vertex.z * s + vertex.x * c >> 16;
  int z = vertex.z * c - vertex.x * s >> 16;
  return ivec4(x, vertex.y, z, vertex.w);
}

/*
 * Calculate the distance to a vertex given the camera angle
 */
int distance(ivec4 vertex, int cameraYaw, int cameraPitch) {
  int yawSin = int(65536.0f * sin(cameraYaw * UNIT));
  int yawCos = int(65536.0f * cos(cameraYaw * UNIT));

  int pitchSin = int(65536.0f * sin(cameraPitch * UNIT));
  int pitchCos = int(65536.0f * cos(cameraPitch * UNIT));

  int j = vertex.z * yawCos - vertex.x * yawSin >> 16;
  int l = vertex.y * pitchSin + j * pitchCos >> 16;

  return l;
}

/*
 * Calculate the distance to a face
 */
int face_distance(ivec4 vA, ivec4 vB, ivec4 vC, int cameraYaw, int cameraPitch) {
  int dvA = distance(vA, cameraYaw, cameraPitch);
  int dvB = distance(vB, cameraYaw, cameraPitch);
  int dvC = distance(vC, cameraYaw, cameraPitch);
  int faceDistance = (dvA + dvB + dvC) / 3;
  return faceDistance;
}

void face_to_screen(ivec4 vA, ivec4 vB, ivec4 vC, out vec3 sA, out vec3 sB, out vec3 sC) {
  ivec3 cameraPos = ivec3(cameraX, cameraY, cameraZ);
  sA = toScreen(vA.xyz - cameraPos, cameraYaw, cameraPitch, centerX, centerY, zoom);
  sB = toScreen(vB.xyz - cameraPos, cameraYaw, cameraPitch, centerX, centerY, zoom);
  sC = toScreen(vC.xyz - cameraPos, cameraYaw, cameraPitch, centerX, centerY, zoom);
}

/*
 * Test if a face is visible (not backward facing)
 */
bool face_visible(ivec4 vA, ivec4 vB, ivec4 vC, ivec4 position) {
  vec3 sA, sB, sC;
  face_to_screen(vA + position, vB + position, vC + position, sA, sB, sC);
  return (sA.x - sB.x) * (sC.y - sB.y) - (sC.x - sB.x) * (sA.y - sB.y) > 0;
}

void keep_culled_verts_together(inout ivec4 A, inout ivec4 B, inout ivec4 C) {
  vec3 sA, sB, sC;
  face_to_screen(A, B, C, sA, sB, sC);
  if (-sA.z < 50 || -sB.z < 50 || -sC.z < 50) {
    //Make sure all the vertices share the same position so these vertices can be culled later in the in the vertex shader
    A = B = C = ivec4(0,0,0,0);
  }
}