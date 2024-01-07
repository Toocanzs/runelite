#include version_header
#include thread_config

uniform uint num_bvh_nodes;
uniform uint num_elements;
uniform uint leaf_node_offset;
#define internal_node_offset 0

struct KeyValue {
    uint key;
    uint value;
};

struct BVHNode {
    // NOTE: The placement of the vec3 components is important here.
    // We want no padding to reduce the total size of this struct, and since it would pad up to vec4 size, we put a uint after the vec3 in place of the would-be padding
    vec3 aabb_min;
    uint parent_index;

    vec3 aabb_max;
    uint left_child_index;

    uint right_child_index;
    uint leaf_object_id_plus_one; // if this node is a leaf this will be != 0
    uint thread_counter;
    uint _unused; // To pad up to 12*4 bytes (may not be needed?)
};

layout(std430, binding = 0) writeonly buffer _nodes {
    BVHNode nodes[];
};

layout(std430, binding = 1) readonly buffer _sorted_key_values {
    KeyValue sorted_key_values[];
};

int count_leading_zeros(uint num) {
    return 31 - findMSB(num);
}

int get_longest_common_prefix(int indexA, int indexB) {
    if (indexA < 0 || indexB < 0 || indexA >= num_elements || indexB >= num_elements) return -1;

    uint mortonA = sorted_key_values[indexA].value;
    uint mortonB = sorted_key_values[indexB].value;
    if (mortonA != mortonB) {
        return count_leading_zeros(mortonA ^ mortonB);
    }
    return count_leading_zeros(uint(indexA) ^ uint(indexB)) + 31;
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
            nodes[node_index].leaf_object_id_plus_one = sorted_key_values[node_index - leaf_node_offset].key + 1;
        } else {
            nodes[node_index].leaf_object_id_plus_one = 0;

            ivec2 range = determine_range(int(node_index));
            int first = range.x;
            int last = range.y;

            int split = find_split(first, last);

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

// A few functions werre translated from the following project https://github.com/microsoft/DirectX-Graphics-Samples/blob/master/Libraries/D3D12RaytracingFallback/src/BuildBVHSplits.hlsli
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