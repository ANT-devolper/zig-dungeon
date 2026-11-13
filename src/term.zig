//! Terminal input mode. While the game runs, stdin is switched to "raw"
//! mode: every key press is read at once, without Enter and without echo.
//! When stdin is not a console (a redirected file), nothing changes.

const std = @import("std");
const builtin = @import("builtin");

const is_windows = builtin.os.tag == .windows;

const STD_INPUT_HANDLE: u32 = @bitCast(@as(i32, -10));
const ENABLE_LINE_INPUT: u32 = 0x0002;
const ENABLE_ECHO_INPUT: u32 = 0x0004;

extern "kernel32" fn GetStdHandle(n: u32) callconv(.winapi) ?*anyopaque;
extern "kernel32" fn GetConsoleMode(h: *anyopaque, mode: *u32) callconv(.winapi) c_int;
extern "kernel32" fn SetConsoleMode(h: *anyopaque, mode: u32) callconv(.winapi) c_int;

const Saved = if (is_windows)
    struct { handle: *anyopaque, mode: u32 }
else
    std.posix.termios;

/// The original stdin mode, restored by `restore`. Null when stdin is not a
/// console or the mode could not be changed.
pub const RawMode = struct {
    saved: ?Saved = null,

    /// Turns off line buffering and echo on stdin, if it is a console.
    pub fn enable() RawMode {
        if (is_windows) {
            const h = GetStdHandle(STD_INPUT_HANDLE) orelse return .{};
            var mode: u32 = 0;
            if (GetConsoleMode(h, &mode) == 0) return .{};
            // Keep ENABLE_PROCESSED_INPUT, so Ctrl+C still quits.
            if (SetConsoleMode(h, mode & ~(ENABLE_LINE_INPUT | ENABLE_ECHO_INPUT)) == 0) return .{};
            return .{ .saved = .{ .handle = h, .mode = mode } };
        } else {
            const fd = std.posix.STDIN_FILENO;
            const old = std.posix.tcgetattr(fd) catch return .{};
            var raw = old;
            raw.lflag.ICANON = false;
            raw.lflag.ECHO = false;
            // Enter sends '\r', like the Windows console.
            raw.iflag.ICRNL = false;
            raw.cc[@backingInt(std.posix.V.MIN)] = 1;
            raw.cc[@backingInt(std.posix.V.TIME)] = 0;
            std.posix.tcsetattr(fd, .NOW, raw) catch return .{};
            return .{ .saved = old };
        }
    }

    /// Puts stdin back the way it was before `enable`.
    pub fn restore(self: RawMode) void {
        const saved = self.saved orelse return;
        if (is_windows) {
            _ = SetConsoleMode(saved.handle, saved.mode);
        } else {
            std.posix.tcsetattr(std.posix.STDIN_FILENO, .NOW, saved) catch {};
        }
    }
};
