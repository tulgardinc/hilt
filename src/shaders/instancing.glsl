@header const z = @import("zalgebra")
@ctype mat4 z.Mat4
@ctype vec3 z.Vec3

@vs vs
layout(binding = 0) uniform vs_params {
    mat4 mvp;
};

in vec3 pos;
in vec4 color0;
in vec3 inst_pos;

out vec4 color;

void main() {
    vec4 pos = vec4(pos + inst_pos, 1.0);
    gl_Position = mvp * pos;
    color = color0;
}
@end

@fs fs
in vec4 color;
out vec4 frag_color;
void main() {
    frag_color = color;
}
@end

@program instancing vs fs
