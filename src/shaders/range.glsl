@header const z = @import("zalgebra")
@ctype mat4 z.Mat4

@vs vs
layout(binding = 0) uniform vs_params {
    mat4 mvp;
};

in vec2 pos;
in vec2 offset;
in vec2 scale;

void main() {
    vec2 world_pos = pos * scale + offset;
    gl_Position = mvp * vec4(world_pos, 0.0, 1.0);
}
@end

@fs fs
out vec4 frag_color;
void main() {
    frag_color = vec4(0.56, 0.69, 0.88, 1.0);
}
@end

@program range vs fs
