const std = @import("std");
const zinit = @import("zinit");
const menu = @import("menu");

const EventLoop = zinit.event.EventLoop;
const WindowEvent = zinit.event.WindowEvent;
const Window = zinit.window.Window;

const App = struct {
    paths: *const Paths,
    taskbar: *menu.Taskbar = undefined,

    playing: std.atomic.Value(bool),

    pub fn onWindow(self: *@This(), el: *EventLoop, win: *Window, event: WindowEvent) !void {
        switch (event) {
            .close => el.closeWindow(win.id()),
            .menu => |me| switch (me.kind) {
                .taskbar => switch (me.target) {
                    0 => {
                        std.debug.print("Previous\n", .{});
                    },
                    1 => {
                        std.debug.print("Play/Pause\n", .{});
                        const playing = !self.playing.load(.seq_cst);
                        self.playing.store(playing, .seq_cst);
                        if (playing) {
                            std.debug.print("Set Icon To Pause\n", .{});
                            try self.taskbar.setIcon(1, .custom(self.paths.pause) );
                            try self.taskbar.setTooltip(1, "Pause");
                            try self.taskbar.setJumpList(.{
                                .tasks = &.{
                                    .{ .label = "Previous", .args = "--prev", .icon = self.paths.prev },
                                    .{ .label = "Pause", .args = "--pause", .icon = self.paths.pause },
                                    .{ .label = "Next", .args = "--next", .icon = self.paths.next },
                                },
                            });
                        } else {
                            std.debug.print("Set Icon To Play\n", .{});
                            try self.taskbar.setIcon(1, .custom(self.paths.play) );
                            try self.taskbar.setTooltip(1, "Play");
                            try self.taskbar.setProgress(.paused, 1, 0);
                            try self.taskbar.setJumpList(.{
                                .tasks = &.{
                                    .{ .label = "Previous", .args = "--prev", .icon = self.paths.prev },
                                    .{ .label = "Play", .args = "--play", .icon = self.paths.play },
                                    .{ .label = "Next", .args = "--next", .icon = self.paths.next },
                                },
                            });
                        }
                    },
                    2 => {
                        std.debug.print("Next\n", .{});
                    },
                    else => {}
                },
                else => {}
            },
            else => {},
        }
    }
};

pub const Paths = struct {
    arena: std.heap.ArenaAllocator,

    app: []const u8 = "",

    play: []const u8 = "",
    pause: []const u8 = "",
    prev: []const u8 = "",
    next: []const u8 = "",

    pub fn init(allocator: std.mem.Allocator) !@This() {
        var instance = @This() {
            .arena = std.heap.ArenaAllocator.init(allocator),
        };
        errdefer instance.deinit();
        const allo = instance.arena.allocator();

        instance.app = try std.fs.cwd().realpathAlloc(allo, "examples/assets/images/icon.ico");

        instance.play = try std.fs.cwd().realpathAlloc(allo, "examples/assets/play.ico");
        instance.pause = try std.fs.cwd().realpathAlloc(allo, "examples/assets/pause.ico");
        instance.next = try std.fs.cwd().realpathAlloc(allo, "examples/assets/skip-next.ico");
        instance.prev = try std.fs.cwd().realpathAlloc(allo, "examples/assets/skip-previous.ico");

        return instance;
    }

    pub fn deinit(self: *const @This()) void {
        self.arena.deinit();
    }
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}).init;
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len > 1) {
        var client = std.http.Client{ .allocator = allocator };
        defer client.deinit();

        for (args[1..args.len]) |arg| {
            var uri: []const u8 = "";
            if (match("--play", arg)) {
                uri = "http://127.0.0.1:34617/play";
            } else if (match("--pause", arg)) {
                uri = "http://127.0.0.1:34617/pause";
            } else if (match("--next", arg)) {
                uri = "http://127.0.0.1:34617/next";
            } else if (match("--prev", arg)) {
                uri = "http://127.0.0.1:34617/prev";
            } else {
                std.debug.print("Invalid argument: {s}\n", .{ arg });
                return;
            }

            var response_body = std.io.Writer.Allocating.init(allocator);
            defer response_body.deinit();

            _ = try client.fetch(.{
                .method = .POST,
                .location = .{ .url = uri },
                .payload = "",
                .response_writer = &response_body.writer,
                .headers = .{
                    .content_type = .{ .override = "text/plain" },
                }
            });
        }
        return;
    }

    const paths = try Paths.init(allocator);
    defer paths.deinit();

    var event_loop = try EventLoop.init(allocator);
    defer event_loop.deinit();

    const window = try event_loop.createWindow(.{
        .icon = .custom(paths.app),
    });

    var app = App {
        .paths = &paths,
        .playing = .init(false),
    };

    var taskbar = try menu.Taskbar.attach(allocator, window.id(), .{
        .state = @ptrCast(&app),
        .buttons = &.{
            menu.Taskbar.Button {
                .icon = .custom(paths.prev),
                .tooltip = "Prev"
            },
            menu.Taskbar.Button {
                .icon = .custom(paths.play),
                .tooltip = "Play",
            },
            menu.Taskbar.Button {
                .icon = .custom(paths.next),
                .tooltip = "Next",
            }
        }
    });
    defer taskbar.detach();

    app.taskbar = taskbar;

    try taskbar.markFullscreen(true);
    try taskbar.setJumpList(.{
        .tasks = &.{
            .{ .label = "Previous", .args = "--prev", .icon = paths.prev },
            .{ .label = "Play", .args = "--play", .icon = paths.play },
            .{ .label = "Next", .args = "--next", .icon = paths.next },
        },
    });

    _ = try std.Thread.spawn(.{}, progressWorker, .{ &app });
    _ = try std.Thread.spawn(.{}, serverWorker, .{ allocator, &app });

    while (event_loop.isActive()) {
        try event_loop.wait();
        while (event_loop.pop()) |e| {
            switch (e) {
                .window => |w| {
                    try app.onWindow(event_loop, w.target, w.event);
                },
                else => {}
            }
        }
    }
}

fn progressWorker(app: *App) void {
    const total_seconds = ((60 * 2) + 38);

    var current: u64 = 0;

    while (true) {
        if (app.playing.load(.seq_cst)) {
            if (current >= total_seconds) current = 0;
            app.taskbar.setProgress(.normal, current, total_seconds) catch {};
            current += 1;
        }

        std.Thread.sleep(std.time.ns_per_s);
    }
}

fn serverWorker(allocator: std.mem.Allocator, app: *App) void {
    const address = std.net.Address.parseIp4("127.0.0.1", 34617) catch return;
    var server = address.listen(.{}) catch return;

    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    _ = arena.allocator();

    while (true) {
        const conn = server.accept() catch return;
        defer conn.stream.close();

        var in: [8192]u8 = undefined;
        var out: [8192]u8 = undefined;

        var conn_reader = conn.stream.reader(&in);
        var conn_writer = conn.stream.writer(&out);

        var http_server = std.http.Server.init(&conn_reader.interface_state, &conn_writer.interface);

        var request = http_server.receiveHead() catch return;

        switch (request.head.method) {
            .POST => {
                if (match("/play", request.head.target)) {
                    app.playing.store(true, .seq_cst);
                    app.taskbar.setIcon(1, .custom(app.paths.pause) ) catch {};
                    app.taskbar.setTooltip(1, "Pause") catch {};
                    app.taskbar.setJumpList(.{
                        .tasks = &.{
                            .{ .label = "Previous", .args = "--prev", .icon = app.paths.prev },
                            .{ .label = "Pause", .args = "--pause", .icon = app.paths.pause },
                            .{ .label = "Next", .args = "--next", .icon = app.paths.next },
                        },
                    }) catch {};
                    request.respond("ok", .{ .status = .ok }) catch return;
                } else if (match("/pause", request.head.target)) {
                    app.playing.store(false, .seq_cst);
                    app.taskbar.setIcon(1, .custom(app.paths.play) ) catch {};
                    app.taskbar.setTooltip(1, "Play") catch {};
                    app.taskbar.setProgress(.paused, 1, 1) catch {};
                    app.taskbar.setJumpList(.{
                        .tasks = &.{
                            .{ .label = "Previous", .args = "--prev", .icon = app.paths.prev },
                            .{ .label = "Play", .args = "--play", .icon = app.paths.play },
                            .{ .label = "Next", .args = "--next", .icon = app.paths.next },
                        },
                    }) catch {};
                    request.respond("ok", .{ .status = .ok }) catch return;
                } else if (match("/next", request.head.target)) {
                    std.debug.print("Next\n", .{});
                    request.respond("ok", .{ .status = .ok }) catch return;
                } else if (match("/prev", request.head.target)) {
                    std.debug.print("Previous\n", .{});
                    request.respond("ok", .{ .status = .ok }) catch return;
                } else {
                    std.debug.print("POST[404] Path Not Found: {s}\n", .{request.head.target});
                    request.respond("", .{ .status = .not_found }) catch return;
                }
            },
            else => {
                std.debug.print("{t}[405] Method Not ALlowed: {s}\n", .{request.head.method, request.head.target});
                request.respond("Method Not Allowed", .{ .status = .method_not_allowed }) catch return;
            }
        }
    }
}

/// Match the string to a pattern
fn match(pattern: []const u8, url: []const u8) bool {
    return std.mem.eql(u8, url, pattern);
}
