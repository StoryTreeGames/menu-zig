const std = @import("std");
const zinit = @import("zinit");

const builtin = @import("builtin");

const EventLoop = zinit.event.EventLoop;
const Window = zinit.window.Window;

pub const Taskbar = @import("./taskbar.zig");

pub const SystemTray = switch (builtin.target.os.tag) {
    .windows => @import("./windows.zig").SystemTray,
    else => @compileError("unsupported platform"),
};

pub const Menu = switch (builtin.target.os.tag) {
    .windows => @import("./windows.zig").Menu,
    else => @compileError("unsupported platform"),
};

pub const MenuEvent = switch(builtin.target.os.tag) {
    .windows => @import("./windows.zig").MenuEvent,
    else => @compileError("unsupported platform"),
};

pub const OnMenuEvent = *const fn (event_loop: *EventLoop, window: *Window, info: MenuEvent) void;
pub const MenuOptions = struct {
    items: []const Item,
    onevent: ?OnMenuEvent = null,
};

pub const SystemTrayEvent = union(enum) {
    click: void,
    select: MenuEvent,
};

pub const OnSystemTrayEvent = *const fn (event_loop: *EventLoop, window: *Window, event: SystemTrayEvent) void;
pub const SystemTrayOptions = struct {
    id: u32,
    menu: *Menu,

    tip: ?[]const u8 = null,
    onevent: ?OnSystemTrayEvent = null,
};

pub const Checkable = struct {
    id: u32,
    label: []const u8,
    default: bool = false,

    pub fn radio(comptime id: anytype, label: []const u8, default: bool) @This() {
        return .{
            .id = Id.of(id),
            .label = label,
            .default = default,
        };
    }
};

pub const SubMenu = struct {
    label: [:0]const u8,
    items: []const Item,
};

pub const Action = struct {
    id: u32,
    label: []const u8,
};

pub const Item = union(enum) {
    separator: void,
    action_item: Action,
    toggle_item: Checkable,
    menu_item: SubMenu,
    radio_group_item: []const Checkable,

    pub fn action(comptime id: anytype, label: []const u8) @This() {
        return .{
            .action_item = .{
                .id = Id.of(id),
                .label = label,
            },
        };
    }

    pub fn toggle(comptime id: anytype, label: []const u8, default: bool) @This() {
        return .{
            .toggle_item = .{
                .id = Id.of(id),
                .label = label,
                .default = default,
            },
        };
    }

    pub fn submenu(label: [:0]const u8, items: []const Item) @This() {
        return .{
            .menu_item = .{
                .label = label,
                .items = items,
            },
        };
    }

    pub fn group(radio_group: []const Checkable) @This() {
        return .{ .radio_group_item = radio_group };
    }
};

pub const Id = struct {
    pub fn of(comptime kind: anytype) u32 {
        const info = @typeInfo(@TypeOf(kind));

        return switch (info) {
            .@"enum" => @intFromEnum(kind),
            .comptime_int => kind,
            .int => |inner| switch(inner.signedness) {
                .signed => @bitCast(@as(i32, @intCast(kind))),
                .unsigned => @intCast(kind),
            },
            // .@"" => @intFromEnum(kind),
            else => @panic("invalid menu item identifier type"),
        };
    }
};

pub const Info = struct {
    id: u32,
    menu: *anyopaque,
    payload: Payload,

    pub fn isAction(self: *const @This()) bool {
        return self.payload == .action;
    }

    pub fn isToggle(self: *const @This()) bool {
        return self.payload == .toggle;
    }

    pub fn isRadio(self: *const @This()) bool {
        return self.payload == .radio;
    }

    pub fn label(self: *const @This()) [:0]const u8 {
        return switch (self) {
            .action => |a| a.label,
            .toggle => |a| a.label,
            .radio => |a| a.label,
        };
    }

    pub const Payload = union(enum) {
        action: struct { label: [:0]const u8 },
        toggle: struct {
            label: [:0]const u8,
            state: bool,
        },
        radio: struct {
            group: std.meta.Tuple(&.{ usize, usize }),
            label: [:0]const u8,
        },
    };
};
