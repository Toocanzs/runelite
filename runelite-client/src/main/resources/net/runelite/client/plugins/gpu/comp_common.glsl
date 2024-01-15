/*
 * Copyright (c) 2018, Adam <Adam@sigterm.info>
 * Copyright (c) 2024, Toocanzs <https://github.com/toocanzs>
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

#define PI 3.1415926535897932384626433832795f
#define UNIT PI / 1024.0f

layout(std140) uniform uniforms {
  float cameraYaw;
  float cameraPitch;
  int centerX;
  int centerY;
  int zoom;
  float cameraX;
  float cameraY;
  float cameraZ;
  ivec2 sinCosTable[2048];
};

struct modelinfo {
  int offset;              // offset into vertex buffer
  int toffset;             // offset into texture buffer
  int size;                // length in faces
  int idx;                 // write idx in target buffer
  int flags;               // buffer, hillskew, plane, orientation
  int modelSizePrefixSum;  // exclusive prefix sum of model triangle counts for finding model associated with a particular triangle quickly
  int x;                   // scene position x
  int y;                   // scene position y
  int z;                   // scene position z
};

struct modelprioritydata {
  int totalNum[12];        // number of faces with a given priority
  int totalDistance[12];   // sum of distances to faces of a given priority
  int totalMappedNum[18];  // number of faces with a given adjusted priority
  int min10;               // minimum distance to a face of priority 10
  int _pad;
};

struct renderpriority {
  int distanceBasedRenderPriority;
  int priorityIndex;
};

layout(std430, binding = 0) readonly buffer modelbuffer_in {
  modelinfo modelInfos[];
};

layout(std430, binding = 1) readonly buffer vertexbuffer_in {
  ivec4 vertexBuffer[];
};

layout(std430, binding = 2) readonly buffer tempvertexbuffer_in {
  ivec4 tempVertexBuffer[];
};

layout(std430, binding = 3) writeonly buffer vertex_out {
  ivec4 vertexOutBuffer[];
};

layout(std430, binding = 4) writeonly buffer uv_out {
  vec4 uvOutBuffer[];
};

layout(std430, binding = 5) readonly buffer texturebuffer_in {
  vec4 textureBuffer[];
};

layout(std430, binding = 6) readonly buffer temptexturebuffer_in {
  vec4 tempTextureBuffer[];
};

layout(std430, binding = 7) buffer priority_data_inout {
  modelprioritydata modelPriorityData[];
};

layout(std430, binding = 8) buffer render_priorities_inout {
  renderpriority renderPriorities[];
};

int binary_search_for_model_index(int modelCount, int triangleIndex) {
  int low = 0;
  int high = modelCount - 1;
  while (low <= high) {
    int mid = low + (high - low) / 2;

    modelinfo info = modelInfos[mid];
    int triangleStartIndex = info.modelSizePrefixSum;
    int triangleEndIndex = info.modelSizePrefixSum + info.size;

    if (triangleIndex >= triangleStartIndex && triangleIndex < triangleEndIndex) {
      return mid;
    }
    else if (triangleIndex >= triangleEndIndex) {
      low = mid + 1;
    }
    else {
      high = mid - 1;
    }
  }
  return -1;
}