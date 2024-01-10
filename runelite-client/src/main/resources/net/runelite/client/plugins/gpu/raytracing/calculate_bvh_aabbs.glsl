#include version_header
#include thread_config

// Build AABBs by going up from the leaf nodes and calculating the combined AABB of children as we go up 
// As described in the paper https://developer.nvidia.com/blog/parallelforall/wp-content/uploads/2012/11/karras2012hpg_paper.pdf

uniform uint leaf_node_count;
uniform uint leaf_node_offset;

#include "raytracing/bvh_node.glsl"

layout(std430, binding = 0) coherent buffer _nodes {
    volatile BVHNode nodes[];
};

layout(local_size_x = THREAD_COUNT) in;
void main() {
    if (gl_GlobalInvocationID.x < leaf_node_count) {
        uint leaf_index = gl_GlobalInvocationID.x + leaf_node_offset;
        
        uint current_node_index = leaf_index;
        
        while (true) {
            bool is_internal_node = current_node_index < leaf_node_offset;
            if (is_internal_node) {
                uint left_child_index = nodes[current_node_index].left_child_index;
                uint right_child_index = nodes[current_node_index].right_child_index;

                // TODO: get rid of coherent and atomic exchange this part?
                nodes[current_node_index].aabb_max = max(nodes[left_child_index].aabb_max, nodes[right_child_index].aabb_max);
                nodes[current_node_index].aabb_min = min(nodes[left_child_index].aabb_min, nodes[right_child_index].aabb_min);
            }

            if (current_node_index == 0) break; // Root

            uint parent_index = nodes[current_node_index].parent_index;
            uint position = atomicAdd(nodes[parent_index].thread_counter, 1);
            if (position != 0) {
                current_node_index = parent_index;
            } else {
                break;
            }
        }
    }
}