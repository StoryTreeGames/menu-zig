const std = @import("std");

const menu = @import("menu_zig");

const zinit = @import("zinit");

const Window = zinit.window.Window;
const event = zinit.event;
const EventLoop = event.EventLoop;
const UserEvent = event.UserEvent;
const WindowEvent = event.WindowEvent;

const App = struct {
    context_menu: *menu.Menu,
    window_menu: *menu.Menu,

    systray: *menu.SystemTray,

    fn handle_menu(el: *EventLoop, w: *Window, selected: MenuEvent) void {
        switch (selected) {
            .quit => el.closeWindow(w.id()),
            .toggle_visible => switch(w.visibility()) {
                .hidden => w.show(),
                else => w.hide(),
            },
            else => {}
        }
    }

    pub fn handleEvent(self: *const @This(), event_loop: *EventLoop, window: *Window, evt: WindowEvent) !void {
        switch (evt) {
            .close => {
                event_loop.closeWindow(window.id());
            },
            .mouse => |mi| {
                if (mi.button == .right) {
                    if (self.context_menu.popupAtCursor(window.id())) |e| {
                        e.select();
                        const selected: MenuEvent = @enumFromInt(e.info.id);
                        std.debug.print("{t}\n", .{ selected });
                        @This().handle_menu(event_loop, window, selected);
                    }
                }
            },
            .menu => |me| switch (me.kind) {
                .window => if (self.window_menu.transform(me.target)) |e| {
                    e.select();
                    @This().handle_menu(event_loop, window, e.into(MenuEvent));
                },
                else => {}
            },
            else => {},
        }
    }

    pub fn handleUserEvent(event_loop: *EventLoop, evt: UserEvent) void {
        switch (evt.id) {
            SystrayUserEvent.ID => switch (evt.into(SystrayUserEvent)) {
                .quit => event_loop.closeAll(),
                .click => std.debug.print("Systray Clicked\n", .{}),
            },
            else => {}
        }
    }
};

const SystemTrayHandler = struct  {
    event_loop: *EventLoop,
    pub fn handler(self: *@This(), evt: menu.SystemTrayEvent) void {
        switch (evt) {
            .click => self.event_loop.push(SystrayUserEvent.ID, SystrayUserEvent.click) catch {},
            .select => |me| {
                me.select();

                const selected: SystrayEvent = @enumFromInt(me.info.id);
                switch (selected) {
                    .quit => self.event_loop.push(SystrayUserEvent.ID, SystrayUserEvent.quit) catch {},
                }
            }
        }
    }
};

const MenuEvent = enum(u32) {
    toggle_visible,
    watch,
    quit,

    color_green,
    color_red,
    color_blue,
    color_black,
};

const SystrayEvent = enum(u32) {
    quit
};

const SystrayUserEvent = enum(u32) {
    pub const ID = 1;

    click,
    quit,
};

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
        .icon = .custom(path),
        // System tray requires a window. However we can hide it so that only the
        // system tray icon is visible.
        .show = .restore,
    });

    const window2 = try event_loop.createWindow(.{
        .title = "Window 2",
        .icon = .custom(path),
        // System tray requires a window. However we can hide it so that only the
        // system tray icon is visible.
        .show = .restore,
    });

    const shared_window_menu = try menu.Menu.init(allocator, .{
        .items = &.{
            .submenu("Window", &.{
                .action(MenuEvent.toggle_visible, "&Toggle Visible"),
                .toggle(MenuEvent.watch, "&Copy\tCtrl+C", false),
                .separator,
                .action(MenuEvent.quit, "&Quit\tAlt+F4"),
            }),
            .submenu("Color", &.{
                .group(&.{
                    .radio(MenuEvent.color_green, "Green", false),
                    .radio(MenuEvent.color_red, "Red", true),
                    .radio(MenuEvent.color_blue, "Blue", false),
                    .radio(MenuEvent.color_black, "Black", false),
                }),
            })
        }
    });
    defer shared_window_menu.deinit();

    try shared_window_menu.attach(window1.id());
    defer shared_window_menu.detach(window1.id());

    try shared_window_menu.attach(window2.id());
    defer shared_window_menu.detach(window2.id());

    const context_menu = try menu.Menu.init(allocator, .{
        .items = &.{
            .action(MenuEvent.toggle_visible, "Toggle Visible"),
            .toggle(MenuEvent.watch, "Watch\tCtrl+W", false),
            .separator,
            .submenu("Color", &.{
                .group(&.{
                    .radio(MenuEvent.color_green, "Green", false),
                    .radio(MenuEvent.color_red, "Red", true),
                    .radio(MenuEvent.color_blue, "Blue", false),
                    .radio(MenuEvent.color_black, "Black", false),
                })
            }),
            .separator,
            .action(MenuEvent.quit, "Quit"),
        },
    });
    defer context_menu.deinit();

    const systray_menu = try menu.Menu.init(allocator, .{
        .items = &.{
            .action(SystrayEvent.quit, "Quit"),
        },
    });
    defer systray_menu.deinit();
    const systray = try menu.SystemTray.initWithHandler(
        allocator,
        .{
            .tip = "Zig System Tray",
            .menu = systray_menu,
            .icon = .custom(path),
        },
        SystemTrayHandler { .event_loop = event_loop },
    );
    defer systray.deinit();

    const app = App {
        .context_menu = context_menu,
        .window_menu = shared_window_menu,
        .systray = systray,
    };

    while (event_loop.isActive()) {
        try event_loop.wait();
        while (event_loop.pop()) |e| {
            switch (e) {
                .window => |w| {
                    try app.handleEvent(event_loop, e.window.target, w.event);
                },
                .user => |u| {
                    App.handleUserEvent(event_loop, u);
                },
                else => {}
            }
        }
    }
}
