const std = @import("std");

const menu = @import("menu_zig");

const zinit = @import("zinit");
const event = zinit.event;
const input = zinit.input;

const Window = zinit.window.Window;
const EventLoop = event.EventLoop;
const WindowEvent = event.WindowEvent;

pub fn handleEvent(m: *menu.Menu, event_loop: *EventLoop, window: *Window, evt: WindowEvent) !void {
    switch (evt) {
        .close => event_loop.closeWindow(window.id()),
        .mouse_input => |mi| {
            if (mi.button == .right) {
                if (m.popupAtCursor(window)) |e| {
                    e.select();
                    const select: MyMenu = @enumFromInt(e.info.id);
                    switch (select) {
                        .quit => event_loop.closeWindow(window.id()),
                        .toggle_visible => switch(window.visibility()) {
                            .hidden => window.show(),
                            else => window.hide(),
                        },
                        else => {}
                    }
                }
            }
        },
        else => {},
    }
}

fn menuEvent(ev: *EventLoop, win: *Window, evt: menu.MenuEvent) void {
    evt.select();

    const selected: MyMenu = @enumFromInt(evt.info.id);
    switch (selected) {
        .toggle_visible => switch(win.visibility()) {
            .hidden => win.show(),
            else => win.hide(),
        },
        .quit => ev.closeWindow(win.id()),
        else => {}
    }
}

const MyMenu = enum(u32) {
    toggle_visible,
    watch,
    quit,

    color_green,
    color_red,
    color_blue,
    color_black,
};

fn systemTrayEvent(ev: *EventLoop, win: *Window, payload: menu.SystemTrayEvent) void {
    switch (payload) {
        .click => std.debug.print("Systray clicked", .{}),
        .select => |me| {
            me.select();

            const selected: MyMenu = @enumFromInt(me.info.id);
            switch (selected) {
                .toggle_visible => switch(win.visibility()) {
                    .hidden => win.show(),
                    else => win.hide(),
                },
                .quit => ev.closeWindow(win.id()),
                else => {}
            }
        }
    }
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}).init;
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var event_loop = try EventLoop.init(allocator);
    defer event_loop.deinit();

    const path = try std.fs.cwd().realpathAlloc(allocator, "examples/assets/images/icon.ico");
    defer allocator.free(path);

    const window1 = try event_loop.createWindow(.{
        .title = "Window 1",
        .icon = .{ .custom = path },
        // System tray requires a window. However we can hide it so that only the
        // system tray icon is visible.
        .show = .restore,
    });

    const window2 = try event_loop.createWindow(.{
        .title = "Window 2",
        .icon = .{ .custom = path },
        // System tray requires a window. However we can hide it so that only the
        // system tray icon is visible.
        .show = .restore,
    });

    const shared_window_menu = try menu.Menu.init(allocator, .{
        .onevent = &menuEvent,
        .items = &.{
            .submenu("Window", &.{
                .action(MyMenu.toggle_visible, "&Toggle Visible"),
                .toggle(MyMenu.watch, "&Copy\tCtrl+C", false),
                .separator,
                .action(MyMenu.quit, "&Quit\tAlt+F4"),
            }),
            .submenu("Color", &.{
                .group(&.{
                    .radio(MyMenu.color_green, "Green", false),
                    .radio(MyMenu.color_red, "Red", true),
                    .radio(MyMenu.color_blue, "Blue", false),
                    .radio(MyMenu.color_black, "Black", false),
                }),
            })
        }
    });
    defer shared_window_menu.deinit();

    try shared_window_menu.attach(event_loop, window1);
    defer shared_window_menu.detach(event_loop, window1);

    try shared_window_menu.attach(event_loop, window2);
    defer shared_window_menu.detach(event_loop, window2);

    const context_menu = try menu.Menu.init(allocator, .{
        .items = &.{
            .action(MyMenu.toggle_visible, "Toggle Visible"),
            .toggle(MyMenu.watch, "&Watch\tCtrl+W", false),
            .separator,
            .submenu("Color", &.{
                .group(&.{
                    .radio(MyMenu.color_green, "Green", false),
                    .radio(MyMenu.color_red, "Red", true),
                    .radio(MyMenu.color_blue, "Blue", false),
                    .radio(MyMenu.color_black, "Black", false),
                })
            }),
            .separator,
            .action(MyMenu.quit, "Quit"),
        },
    });
    defer context_menu.deinit();

    const systray = try menu.SystemTray.init(allocator, .{
        .id = 1,
        .tip = "Some Tip",
        .onevent = &systemTrayEvent,
        .menu = context_menu,
    });
    defer systray.deinit();

    try systray.attach(event_loop, window1);
    defer systray.detach(event_loop, window1);

    while (event_loop.isActive()) {
        try event_loop.wait();
        while (event_loop.pop()) |e| {
            switch (e) {
                .window => |w| {
                    try handleEvent(context_menu, event_loop, e.window.target, w.event);
                },
                else => {}
            }
        }
    }
}
