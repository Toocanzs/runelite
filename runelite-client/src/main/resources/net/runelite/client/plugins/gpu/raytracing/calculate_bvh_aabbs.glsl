#include version_header
#include thread_config


// The explaination of how this works can be found here
// https://developer.nvidia.com/blog/thinking-parallel-part-iii-tree-construction-gpu/
// and also a more formal explaination is in the paper here
// https://developer.nvidia.com/blog/parallelforall/wp-content/uploads/2012/11/karras2012hpg_paper.pdf
// Also the following DirectX-Graphics-Samples project was referenced heavily in writing this code (licence included at the bottom of this file)
// https://github.com/microsoft/DirectX-Graphics-Samples/blob/master/Libraries/D3D12RaytracingFallback/src/BuildBVHSplits.hlsli

uniform uint leaf_node_count;
uniform uint leaf_node_offset;

#include "raytracing/bvh_node.glsl"

layout(std430, binding = 0) buffer _nodes {
    BVHNode nodes[];
};

layout(local_size_x = THREAD_COUNT) in;
void main() {
    if (gl_GlobalInvocationID.x < leaf_node_count) {
        uint leaf_index = gl_GlobalInvocationID.x + leaf_node_offset;
        
        // Note that leaf nodes already have calculated their AABB min/max, so we go up to the parent node immediately
        uint current_node_index = leaf_index;
        while (true) {
            current_node_index = nodes[current_node_index].parent_index;
            uint number_of_threads_before_this = atomicAdd(nodes[current_node_index].thread_counter, 1);
            if (number_of_threads_before_this != 0) break; // Only one thread calculates the AABB for this node, and the other one will be kicked out

            uint left_child_index = nodes[current_node_index].left_child_index;
            uint right_child_index = nodes[current_node_index].right_child_index;
            nodes[current_node_index].aabb_min = min(nodes[left_child_index].aabb_min, nodes[right_child_index].aabb_min);
            nodes[current_node_index].aabb_max = max(nodes[left_child_index].aabb_max, nodes[right_child_index].aabb_max);
        }
    }
}