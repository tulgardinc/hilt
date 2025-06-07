@header const z = @import("zalgebra")
@ctype mat4 z.Mat4

@vs vs
layout(binding = 0) uniform vs_params {
    mat4 mvp;
};

in vec2 pos;

void main() {
    gl_Position = mvp * vec4(pos, 0.0, 1.0);
}
@end

@fs fs

out vec4 frag_color;
void main() {
    frag_color = vec4(0.255, 0.055, 0.549, 1.0);
}
@end

@program cursor vs fs
