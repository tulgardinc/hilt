const std = @import("std");
const zalg = @import("zalgebra");
const State = @import("main.zig").State;

pub const Viewport = struct {
    width: f32,
    height: f32,
    position: zalg.Vec2,
    target_position: zalg.Vec2,
    vel: zalg.Vec2,
    accel: zalg.Vec2,
    damping: f32,
    stiffness: f32,

    const Self = @This();

    pub fn init() Self {
        return Self{
            .height = 0,
            .width = 0,
            .position = zalg.Vec2.zero(),
            .vel = zalg.Vec2.zero(),
            .accel = zalg.Vec2.zero(),
            .target_position = zalg.Vec2.zero(),
            .stiffness = 300.0,
            .damping = 2.0 * @sqrt(300.0),
        };
    }

    pub fn update(self: *Self) void {
        self.accel = self.vel.mul(zalg.Vec2.set(-self.damping)).sub(self.position.sub(self.target_position).mul(zalg.Vec2.set(self.stiffness)));
        self.vel = self.vel.add(self.accel.mul(zalg.Vec2.set(State.delta_time)));
        self.position = self.position.add(self.vel.mul(zalg.Vec2.set(State.delta_time)));
    }

    pub fn setPosition(self: *Self, new_position: zalg.Vec2) void {
        self.target_position = new_position;
    }

    pub fn getDesiredPosition(self: *const Self) zalg.Vec2 {
        return self.target_position;
    }
};

pub const CubicEaseOut = struct {
    start: f32,
    target: f32,
    time: f32,
    duration: f32,
    value: f32,

    const Self = @This();

    pub fn init(start: f32, target: f32, duration: f32) CubicEaseOut {
        std.debug.assert(duration > 0);
        return .{ .start = start, .target = target, .time = 0, .duration = duration, .value = 0 };
    }

    pub fn update(self: *Self, delta_time: f32) void {
        self.time += delta_time;
        const t = self.time / self.duration;
        const mult = 1 - std.math.pow(f32, 1 - t, 3);
        self.value = self.start + (self.target - self.start) * mult;
    }

    pub fn done(self: *const Self) bool {
        return self.time / self.duration >= 1.0;
    }
};
