const std = @import("std");
const zalg = @import("zalgebra");
const State = @import("main.zig").State;

position: zalg.Vec2,
target_position: zalg.Vec2,
vel: zalg.Vec2,
accel: zalg.Vec2,
damping: f32,
stiffness: f32,

const Self = @This();

pub fn init() Self {
    return Self{
        .position = zalg.Vec2.zero(),
        .vel = zalg.Vec2.zero(),
        .accel = zalg.Vec2.zero(),
        .target_position = zalg.Vec2.zero(),
        .stiffness = 1200.0,
        .damping = 2.0 * @sqrt(1200.0),
    };
}

pub fn update(self: *Self) void {
    self.accel = self.vel.mul(zalg.Vec2.set(-self.damping)).sub(self.position.sub(self.target_position).mul(zalg.Vec2.set(self.stiffness)));
    self.vel = self.vel.add(self.accel.mul(zalg.Vec2.set(State.delta_time)));
    self.position = self.position.add(self.vel.mul(zalg.Vec2.set(State.delta_time)));
}
