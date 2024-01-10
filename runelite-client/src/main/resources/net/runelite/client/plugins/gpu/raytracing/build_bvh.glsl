#include version_header
#include thread_config


// The explaination of how this works can be found here
// https://developer.nvidia.com/blog/thinking-parallel-part-iii-tree-construction-gpu/
// and also a more formal explaination is in the paper here
// https://developer.nvidia.com/blog/parallelforall/wp-content/uploads/2012/11/karras2012hpg_paper.pdf
// Also the following DirectX-Graphics-Samples project was referenced heavily in writing this code (licence included at the bottom of this file)
// https://github.com/microsoft/DirectX-Graphics-Samples/blob/master/Libraries/D3D12RaytracingFallback/src/BuildBVHSplits.hlsli

uniform uint num_bvh_nodes;
uniform uint morton_key_value_count;
uniform uint leaf_node_offset;
#define internal_node_offset 0

struct KeyValue {
    uint key;
    uint value;
};

#include "raytracing/bvh_node.glsl"

layout(std430, binding = 0) writeonly buffer _nodes {
    BVHNode nodes[];
};

layout(std430, binding = 1) readonly buffer _sorted_key_values {
    KeyValue sorted_key_values[];
};

layout(std430, binding = 2) readonly buffer _vertex_buffer {
    ivec4 vertex_buffer[];
};

int count_leading_zeros(uint num) {
    return 31 - findMSB(num);
}

int get_longest_common_prefix(int indexA, int indexB) {
    if (indexA < 0 || indexB < 0 || indexA >= morton_key_value_count || indexB >= morton_key_value_count) return -1;

    uint mortonA = sorted_key_values[indexA].value;
    uint mortonB = sorted_key_values[indexB].value;
    if (mortonA != mortonB) {
        return count_leading_zeros(mortonA ^ mortonB);
    }
    return count_leading_zeros(uint(indexA) ^ uint(indexB)) + 31; // TODO: Paper seems to only use count_leading_zeros(indexA ^ indexB) without the + 31 that the DirectX example does
}

layout(local_size_x = THREAD_COUNT) in;
void main() {
    if (gl_GlobalInvocationID.x < num_bvh_nodes) {
        uint node_index = gl_GlobalInvocationID.x;

        
        nodes[node_index].left_child_index = 0xFFFFFFFF;
        nodes[node_index].right_child_index = 0xFFFFFFFF;
        nodes[node_index].thread_counter = 0;
        barrier();

        if (node_index >= leaf_node_offset) {
            // Leaf node
            uint triangle_index = node_index - leaf_node_offset;

            uint base_vertex_index = triangle_index * 3;
            ivec3 vA = vertex_buffer[base_vertex_index + 0].xyz;
            ivec3 vB = vertex_buffer[base_vertex_index + 1].xyz;
            ivec3 vC = vertex_buffer[base_vertex_index + 2].xyz;

            ivec3 aabb_min = min(vA, min(vB, vC));
            ivec3 aabb_max = max(vA, max(vB, vC));

            nodes[node_index].leaf_object_id_plus_one = sorted_key_values[triangle_index].key + 1;
            nodes[node_index].aabb_min = aabb_min;
            nodes[node_index].aabb_max = aabb_max;
        } else {
            // Internal node
            nodes[node_index].leaf_object_id_plus_one = 0; // Internal nodes have no object ID
            if (node_index == 0) { // Root node
                nodes[node_index].parent_index = 0xFFFFFFFF;
            }

            // Determine direction of the range
            int i = int(node_index);
            int d = sign(get_longest_common_prefix(i, i + 1) - get_longest_common_prefix(i, i - 1));
            // Compute upper bound for the length of the range
            int delta_min = get_longest_common_prefix(i, i - d);
            int l_max = 2;
            while (get_longest_common_prefix(i, i + l_max * d) > delta_min) {
                l_max = l_max * 2;
            }
            
            // Find the other end using binary search
            int l = 0;
            for (int t = l_max; t >= 1; t /= 2) {
                if (get_longest_common_prefix(i, i + (l + t) * d) > delta_min) {
                    l = l + t;
                }
            }
            int j = i + l * d;
            // Find the split position using binary search
            int delta_node = get_longest_common_prefix(i, j);
            int s = 0;
            int divisor = 2;
            while (true) {
                // For loop version was annoying to do with the ceiling function so we're doing a while loop I guess
                int t = int(ceil(float(l)/divisor)); // TODO: DivideAndRoundUp{ return (dividend - 1) / divisor + 1; }
                if (get_longest_common_prefix(i, i + (s + t) * d) > delta_node) {
                    s = s + t;
                }
                if (t <= 1) break;
                divisor *= 2;
            }
            
            int split = i + s * d + min(d, 0);

            uint left_child_index;
            if (min(i, j) == split) {
                left_child_index = split + leaf_node_offset;
            } else {
                left_child_index = split + internal_node_offset;
            }

            uint right_child_index;
            if (max(i, j) == (split + 1)) {
                right_child_index = split + leaf_node_offset + 1;
            } else {
                right_child_index = split + internal_node_offset + 1;
            }

            // Write children
            nodes[node_index].left_child_index = left_child_index;
            nodes[node_index].right_child_index = right_child_index;
            // Write children's parent
            nodes[left_child_index].parent_index = node_index;
            nodes[right_child_index].parent_index = node_index;
        }
    }
}

// A few functions were translated from the following project 
// https://github.com/microsoft/DirectX-Graphics-Samples/blob/master/Libraries/D3D12RaytracingFallback/src/BuildBVHSplits.hlsli
// License of that project is included below.

/*
The MIT License (MIT)

Copyright (c) 2015 Microsoft

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.

*/