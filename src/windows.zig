const std = @import("std");

const zinit = @import("zinit");
const EventLoop = zinit.event.EventLoop;
const QueuedEvent = zinit.event.QueuedEvent;
const Window = zinit.window.Window;

const root = @import("./root.zig");
const Info = root.Info;
const Action = root.Action;
const Checkable = root.Checkable;
const Item = root.Item;

const windows = @import("windows");
const windows_and_messaging = windows.win32.ui.windows_and_messaging;
const shell = windows.win32.ui.shell;

const HWND = windows.win32.foundation.HWND;
const WM_USER = windows_and_messaging.WM_USER;
const NOTIFYICONDATAW = shell.NOTIFYICONDATAW;

const Shell_NotifyIconW = shell.Shell_NotifyIconW;
const NIM_ADD = shell.NIM_ADD;
const NIM_MODIFY = shell.NIM_MODIFY;
const NIM_DELETE = shell.NIM_DELETE;
const NIM_SETVERSION = shell.NIM_SETVERSION;
const NOTIFYICON_VERSION_4 = shell.NOTIFYICON_VERSION_4;

const CheckMenuItem = windows_and_messaging.CheckMenuItem;
const CheckMenuRadioItem = windows_and_messaging.CheckMenuRadioItem;

const HMENU = windows_and_messaging.HMENU;

pub const Builder = struct {
    allocator: std.mem.Allocator,
    count: *usize,

    context: ?HMENU = null,
    current: HMENU,

    menus: *std.ArrayListUnmanaged(HMENU),
    itemToMenu: *std.AutoArrayHashMapUnmanaged(usize, Info),

    pub fn sub(self: *@This(), inner: HMENU) @This() {
        return .{
            .allocator = self.allocator,
            .count = self.count,
            .menus = self.menus,
            .itemToMenu = self.itemToMenu,
            .current = inner,
        };
    }

    pub fn appendSeparator(self: *@This()) !void {
        if (windows_and_messaging.AppendMenuA(self.current, windows_and_messaging.MF_SEPARATOR, 0, null) == 0) {
            return error.AppendMenuSeparator;
        }

        if (self.context) |context| {
            if (windows_and_messaging.AppendMenuA(context, windows_and_messaging.MF_SEPARATOR, 0, null) == 0) {
                return error.AppendMenuSeparator;
            }
        }
    }

    pub fn appendAction(self: *@This(), action: Action) !void {
        self.count.* += 1;
        const label = try self.allocator.allocSentinel(u8, action.label.len, 0);
        @memcpy(label, action.label);
        try self.itemToMenu.put(self.allocator, self.count.*, .{
            .id = action.id,
            .menu = @ptrCast(self.current),
            .payload = .{ .action = .{ .label = label } },
        });

        if (windows_and_messaging.AppendMenuA(self.current, windows_and_messaging.MF_STRING, self.count.*, label.ptr) == 0) {
            return error.AppendMenuAction;
        }

        if (self.context) |context| {
            if (windows_and_messaging.AppendMenuA(context, windows_and_messaging.MF_STRING, self.count.*, label.ptr) == 0) {
                return error.AppendMenuAction;
            }
        }
    }

    pub fn appendToggle(self: *@This(), checkable: Checkable) !void {
        self.count.* += 1;
        const label = try self.allocator.allocSentinel(u8, checkable.label.len, 0);
        @memcpy(label, checkable.label);
        try self.itemToMenu.put(self.allocator, self.count.*, .{
            .id = checkable.id,
            .menu = @ptrCast(self.current),
            .payload = .{
                .toggle = .{ .label = label, .state = checkable.default },
            },
        });

        if (windows_and_messaging.AppendMenuA(
            self.current,
            if (checkable.default) windows_and_messaging.MF_CHECKED else windows_and_messaging.MF_UNCHECKED,
            self.count.*,
            label.ptr,
        ) == 0) {
            return error.AppendMenuToggle;
        }

        if (self.context) |context| {
            if (windows_and_messaging.AppendMenuA(
                context,
                if (checkable.default) windows_and_messaging.MF_CHECKED else windows_and_messaging.MF_UNCHECKED,
                self.count.*,
                label.ptr,
            ) == 0) {
                return error.AppendMenuToggle;
            }
        }
    }

    pub fn appendRadioGroup(self: *@This(), items: []const Checkable) !void {
        const start = self.count.* + 1;
        const end = start + items.len;

        var checked: ?usize = null;
        for (items, start..) |item, i| {
            try self.appendRadioItem(item, start, end);
            if (item.default) checked = i;
        }

        if (checked) |idx| {
            std.debug.print("Selected: {d}\n", .{ idx });
            _ = CheckMenuRadioItem(self.current, @intCast(start), @intCast(end), @intCast(idx), 0x0);
        }
    }

    pub fn appendRadioItem(self: *@This(), checkable: Checkable, start: usize, end: usize) !void {
        self.count.* += 1;
        const label = try self.allocator.allocSentinel(u8, checkable.label.len, 0);
        @memcpy(label, checkable.label);
        try self.itemToMenu.put(self.allocator, self.count.*, .{
            .id = checkable.id,
            .menu = @ptrCast(self.current),
            .payload = .{
                .radio = .{
                    .group = .{ start, end },
                    .label = label,
                },
            },
        });

        if (windows_and_messaging.AppendMenuA(
            self.current,
            windows_and_messaging.MF_BYCOMMAND,
            self.count.*,
            label.ptr,
        ) == 0) {
            return error.AppendMenuRadioItem;
        }

        if (self.context) |context| {
            if (windows_and_messaging.AppendMenuA(
                context,
                windows_and_messaging.MF_BYCOMMAND,
                self.count.*,
                label.ptr,
            ) == 0) {
                return error.AppendMenuRadioItem;
            }
        }
    }

    pub fn appendMenu(self: *@This(), items: []const Item) !void {
        for (items) |item| {
            switch (item) {
                .separator => try self.appendSeparator(),
                .action_item => |action| try self.appendAction(action),
                .toggle_item => |toggle| try self.appendToggle(toggle),
                .radio_group_item => |group| try self.appendRadioGroup(group),
                .menu_item => |subMenu| {
                    const innerMenu = windows_and_messaging.CreatePopupMenu().?;
                    try self.menus.append(self.allocator, innerMenu);

                    if (windows_and_messaging.AppendMenuA(
                        self.current,
                        windows_and_messaging.MF_POPUP,
                        @intFromPtr(innerMenu),
                        subMenu.label.ptr,
                    ) == 0) {
                        return error.AppendMenuSubmenu;
                    }

                    if (self.context) |context| {
                        if (windows_and_messaging.AppendMenuA(
                            context,
                            windows_and_messaging.MF_POPUP,
                            @intFromPtr(innerMenu),
                            subMenu.label.ptr,
                        ) == 0) {
                            return error.AppendMenuSubmenu;
                        }
                    }

                    var inner = self.sub(innerMenu);
                    try inner.appendMenu(subMenu.items);
                },
            }
        }
    }
};

pub const MenuEvent = struct {
    id: u32,
    info: *Info,

    /// Select an item. This applies to radio and toggle items
    ///
    /// - `radio`: Will select the current item out of the list making it the currently selected option
    /// - `toggle`: Will toggle the current item inverting it's state. True is now false, and false is now true.
    pub fn select(self: *const @This()) void {
        switch (self.info.payload) {
            .toggle => |*ti| {
                ti.state = !ti.state;
                _ = CheckMenuItem(@ptrCast(@alignCast(self.info.menu)), self.id, if (ti.state) 0x8 else 0x0);
            },
            .radio => |r| {
                _ = CheckMenuRadioItem(@ptrCast(@alignCast(self.info.menu)), @intCast(r.group[0]), @intCast(r.group[1]), self.id, 0x0);
            },
            else => {},
        }
    }
};

pub const Menu = struct {
    arena: std.heap.ArenaAllocator,

    onevent: ?root.OnMenuEvent = null,

    main: HMENU = undefined,
    context: HMENU = undefined,
    menus: std.ArrayListUnmanaged(HMENU) = .empty,
    item_to_info: std.AutoArrayHashMapUnmanaged(usize, Info) = .empty,

    pub fn init(allocator: std.mem.Allocator, menu: root.MenuOptions) !*@This() {
        var instance = try allocator.create(Menu);
        instance.* = .{
            .arena = std.heap.ArenaAllocator.init(allocator),
            .onevent = menu.onevent,
        };
        errdefer instance.deinit();

        const a = instance.arena.allocator();

        instance.main = windows_and_messaging.CreateMenu().?;
        instance.context = windows_and_messaging.CreatePopupMenu().?;

        var count: usize = 0;
        var builder = Builder{
            .allocator = a,
            .context = instance.context,
            .current = instance.main,
            .menus = &instance.menus,
            .itemToMenu = &instance.item_to_info,
            .count = &count,
        };

        try builder.appendMenu(menu.items);

        return instance;
    }

    pub fn deinit(self: *@This()) void {
        defer self.arena.child_allocator.destroy(self);
        defer self.arena.deinit();

        for (self.menus.items) |m| _ = windows_and_messaging.DestroyMenu(m);

        _ = windows_and_messaging.DestroyMenu(self.main);
        _ = windows_and_messaging.DestroyMenu(self.context);
    }

    /// Attaches the menu to the specified window and calls platform specific APIs
    /// to render the menu.
    ///
    /// *IMPORTANT:* `detachWindow` must be called during cleanup to remove hooks
    /// into the event loop
    pub fn attach(self: *const @This(), event_loop: *EventLoop, window: *Window) !void {
        _ = windows_and_messaging.SetMenu(window.handle, self.main);
        _ = windows_and_messaging.DrawMenuBar(window.handle);
        try event_loop.addCommand(0, window.id(), &handle_user_event, @ptrCast(@constCast(self)));
    }

    /// Removes the menu from the specified window if it is attached and calls platform
    /// specific APIs to remove the menu from the render.
    pub fn detach(_: *const @This(), event_loop: *EventLoop, window: *Window) void {
        if (event_loop.removeCommand(0, window.id())) {
            _ = windows_and_messaging.SetMenu(window.handle, null);
            _ = windows_and_messaging.DrawMenuBar(window.handle);
        }
    }

    pub fn popup(self: *const @This(), window: *const Window, x: i32, y: i32) ?MenuEvent {
        // _ = windows_and_messaging.SetForegroundWindow(self.handle);
        const selected = windows_and_messaging.TrackPopupMenu(
            self.context,
            .{ .RIGHTBUTTON = 1, .RETURNCMD = 1 },
            x,
            y,
            0,
            window.handle,
            null,
        );
        _ = windows_and_messaging.PostMessageW(window.handle, windows_and_messaging.WM_NULL, 0, 0);

        const id: u32 = @bitCast(selected);
        if (self.item_to_info.getPtr(id)) |info| {
            return .{ .id = id, .info = info };
        }
        return null;
    }

    pub fn popupAtCursor(self: *const @This(), window: *const Window) ?MenuEvent {
        var pt: windows.win32.foundation.POINT = undefined;
        _ = windows_and_messaging.GetCursorPos(&pt);
        return self.popup(window, pt.x, pt.y);
    }

    fn handle_user_event(event_loop: *EventLoop, window: *Window, state: ?*anyopaque, payload: u32) ?QueuedEvent {
        const this: *const @This() = @ptrCast(@alignCast(state.?));
        if (this.item_to_info.getPtr(@intCast(payload))) |info| {
            if (this.onevent) |onevent| {
                onevent(event_loop, window, .{ .id = payload, .info = info });
            }
        }
        return null;
    }
};

pub const SystemTray = struct {
    arena: std.heap.ArenaAllocator,

    id: u32,
    onevent: ?root.OnSystemTrayEvent,

    menu: *Menu = undefined,
    tip_wide: ?[:0]const u16 = null,

    pub fn init(allocator: std.mem.Allocator, tray: root.SystemTrayOptions) !*@This() {
        var instance = try allocator.create(SystemTray);
        instance.* = .{
            .arena = std.heap.ArenaAllocator.init(allocator),
            .id = tray.id,
            .onevent = tray.onevent,
            .menu = tray.menu,
        };
        errdefer instance.deinit();

        if (tray.tip) |tip| {
            instance.tip_wide = try std.unicode.utf8ToUtf16LeAllocZ(instance.arena.allocator(), tip);
        }

        return instance;
    }

    pub fn attach(self: *const @This(), event_loop: *EventLoop, window: *Window) !void {
        var nid = std.mem.zeroes(NOTIFYICONDATAW);
        nid.cbSize = @sizeOf(NOTIFYICONDATAW);
        nid.hWnd = window.handle;
        nid.uID = WM_USER + self.id;
        nid.uCallbackMessage = WM_USER + self.id;
        nid.uFlags = .{ .MESSAGE = 1, .ICON = 1 };
        nid.hIcon = Window.getHIcon(window.icon);

        if (self.tip_wide) |tip| {
            nid.uFlags.TIP = 1;
            nid.uFlags.SHOWTIP = 1;

            const tip_len = @min(tip.len, nid.szTip.len);
            @memcpy(nid.szTip[0..tip_len], tip[0..tip_len]);
            nid.szTip[tip_len] = 0;
        }

        _ = Shell_NotifyIconW(NIM_ADD, &nid);
        nid.Anonymous.uVersion = NOTIFYICON_VERSION_4;
        _ = Shell_NotifyIconW(NIM_SETVERSION, &nid);

        try event_loop.addUserCommand(self.id, window.id(), &handle_user_event, @ptrCast(@constCast(self)));
    }

    pub fn detach(self: *const @This(), event_loop: *EventLoop, window: *Window) void {
        _ = event_loop.removeUserCommand(self.id, window.id());

        var nid = std.mem.zeroes(NOTIFYICONDATAW);
        nid.cbSize = @sizeOf(NOTIFYICONDATAW);
        nid.hWnd = window.handle;
        nid.uID = WM_USER + self.id;
        _ = Shell_NotifyIconW(NIM_DELETE, &nid);
    }

    pub fn updateIcon(self: *@This(), window: *const Window) void {
        var nid = std.mem.zeroes(NOTIFYICONDATAW);
        nid.cbSize = @sizeOf(NOTIFYICONDATAW);
        nid.hWnd = window.handle;
        nid.uID = WM_USER + self.id;
        nid.uFlags = .{ .MESSAGE = 1, .ICON = 1 };
        nid.hIcon = Window.getHIcon(window.icon);

        if (self.tip_wide) |tip| {
            nid.uFlags.TIP = 1;
            nid.uFlags.SHOWTIP = 1;

            const tip_len = @min(tip.len, nid.szTip.len);
            @memcpy(nid.szTip[0..tip_len], tip[0..tip_len]);
            nid.szTip[tip_len] = 0;
        }

        _ = Shell_NotifyIconW(NIM_MODIFY, &nid);
    }

    pub fn deinit(self: *@This()) void {
        defer self.arena.child_allocator.destroy(self);
        defer self.arena.deinit();
    }

    fn handle_user_event(event_loop: *EventLoop, window: *Window, state: ?*anyopaque, payload: u32) ?QueuedEvent {
        const this: *const @This() = @ptrCast(@alignCast(state.?));
        if (payload == windows_and_messaging.WM_CONTEXTMENU or payload == windows_and_messaging.WM_RBUTTONUP) {
            if (this.menu.popupAtCursor(window)) |evt| {
                if (this.onevent) |onevent| {
                    onevent(event_loop, window, .{ .select = evt });
                }
            }
        } else if (payload == windows_and_messaging.WM_LBUTTONUP) {
            if (this.onevent) |onevent| {
                onevent(event_loop, window, .{ .click = {} });
            }
        }
        return null;
    }
};
