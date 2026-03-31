const std = @import("std");
const zinit = @import("zinit");
const menu = @import("menu_zig");

const EventLoop = zinit.event.EventLoop;
const WindowEvent = zinit.event.WindowEvent;
const Window = zinit.window.Window;

const App = struct {
    taskbar: *menu.Taskbar = undefined,

    loading: bool = true,

    pub fn onWindow(el: *EventLoop, win: *Window, event: WindowEvent) !void {
        switch (event) {
            .close => el.closeWindow(win.id()),
            else => {},
        }
    }

    pub fn onTaskbar(el: *EventLoop, win: *Window, state: ?*anyopaque, id: u32) void {
        const this: *@This() = @ptrCast(@alignCast(state.?));
        std.debug.print("TASKBAR @ {d}\n", .{ id });

        switch (id) {
            0 => {
                this.loading = !this.loading;
                if (this.loading) {
                    this.taskbar.setProgress(.indeterminate, 0, 100) catch {};
                } else {
                    this.taskbar.setProgress(.@"error", 100, 100) catch {};
                }
            },
            2 => el.closeWindow(win.id()),
            else => {}
        }
    }
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}).init;
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var event_loop = try EventLoop.init(allocator);
    defer event_loop.deinit();

    const path = try std.fs.cwd().realpathAlloc(allocator, "examples/assets/images/icon.ico");
    defer allocator.free(path);

    const window = try event_loop.createWindow(.{
        .icon = .{ .custom = path },
    });

    var app = App {};

    var taskbar = try menu.Taskbar.attach(allocator, event_loop, window, .{
        .onevent = &App.onTaskbar,
        .state = @ptrCast(&app),
        .buttons = &.{
            menu.Taskbar.Button {
                .icon = .{
                    .symbol = .information,
                },
                .tooltip = "Toggle Progress"
            },
            menu.Taskbar.Button {
                .icon = .{
                    .custom = path,
                },
                .background = false,
            },
            menu.Taskbar.Button {
                .icon = .{
                    .symbol = .@"error",
                },
                .tooltip = "Close",
            }
        }
    });
    defer taskbar.detach(event_loop);

    app.taskbar = taskbar;

    try taskbar.markFullscreen(true);

    try taskbar.setProgress(.indeterminate, 0, 100);

    while (event_loop.isActive()) {
        try event_loop.wait();
        while (event_loop.pop()) |e| {
            switch (e) {
                .window => |w| {
                    try App.onWindow(event_loop, w.target, w.event);
                },
                else => {}
            }
        }
    }
}
