#include version_header

struct MinMax {
    int minX;
    int minY;
    int minZ;

    int maxX;
    int maxY;
    int maxZ;
};

layout(std430, binding = 0) buffer _min_max {
    MinMax global_min_max;
};

// Call with glDispatchCompute(1,1,1)
layout(local_size_x = 1) in;
void main() {
    // Setup the min/max to int32 max/min so we can do atomic min/max later and get the actual min/max
    global_min_max.minX = 2147483647;
    global_min_max.minX = 2147483647;
    global_min_max.minX = 2147483647;

    global_min_max.maxX = -2147483648;
    global_min_max.maxY = -2147483648;
    global_min_max.maxZ = -2147483648;
}