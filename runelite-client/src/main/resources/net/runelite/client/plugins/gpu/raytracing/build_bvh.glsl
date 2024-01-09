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

ivec2 determine_range(int index) {
    int d = get_longest_common_prefix(index, index + 1) - get_longest_common_prefix(index, index - 1);
    d = clamp(d, -1, 1); // TODO: replace with sign() like the paper does?
    int min_prefix = get_longest_common_prefix(index, index - d);

    int max_length = 2;
    while (get_longest_common_prefix(index, index + max_length * d) > min_prefix) {
        max_length *= 4; // TODO: Use 2 instead of 4 like the paper does?
    }

    int len = 0;
    for (int t = max_length / 2; t > 0; t /= 2) {
        if (get_longest_common_prefix(index, index + (len + t) * d) > min_prefix)
        {
            len = len + t;
        }
    }

    int j = index + len * d;
    return ivec2(min(index, j), max(index, j));
}

int find_split(int first, int last) {
    uint first_code = sorted_key_values[first].value;
    uint last_code = sorted_key_values[last].value;

    if (first_code == last_code)
        return (first + last) >> 1;
    
    int common_prefix = get_longest_common_prefix(first, last);
    int split = first;
    int step = last - first;
    do
    {
        step = (step + 1) >> 1;
        int new_split = split + step;

        if (new_split < last)
        {
            uint split_code = sorted_key_values[new_split].value;
            int split_prefix = get_longest_common_prefix(first, new_split);
            if (split_prefix > common_prefix)
                split = new_split;
        }
    }
    while (step > 1);

    return split;
}

layout(local_size_x = THREAD_COUNT) in;
void main() {
    if (gl_GlobalInvocationID.x < num_bvh_nodes) {
        uint node_index = gl_GlobalInvocationID.x;

        nodes[node_index].thread_counter = 0;

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

            ivec2 range = determine_range(int(node_index));
            int first = range.x;
            int last = range.y;

            if (first == 0 && last == (morton_key_value_count - 1)) {
                // This is the root node.
                // We set it's parent to itself so that when we go up the tree later to build AABBs, it will
                // enter the root node a second time, and we exit on the second entry to any node (using thread_counter to keep track of how many other threads have touched the node)
                // Basically this lets us terminate the AABB building easily at the root node
                nodes[node_index].parent_index = node_index;
            }

            int split = find_split(first, last);

            // If the split is at the start or the end of the range we grab a leaf node as the child instead of an internal one
            uint left_child_index;
            if (split == first) {
                left_child_index = split + leaf_node_offset;
            } else {
                left_child_index = split + internal_node_offset;
            }

            uint right_child_index;
            if (split + 1 == last) {
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