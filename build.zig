const std = @import("std");
const Tag = std.Target.Os.Tag;
const builtin = @import("builtin");

const NAME = "menu_zig";
const EXAMPLES = "examples";

const examples = [_]Example{
    .{ .name = "menu", .path = EXAMPLES ++ "/menu.zig" },
    .{ .name = "taskbar", .path = EXAMPLES ++ "/taskbar.zig" },
};

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    var deps: std.ArrayList(std.Build.Module.Import) = .empty;
    defer deps.deinit(b.allocator);

    const mod = b.addModule("menu_zig", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    switch (builtin.target.os.tag) {
        .windows => {
            const windows_zig = b.dependency("windows", .{});

            // Note: To build exe so a console window doesn't appear
            // Add this to any exe build: `exe.subsystem = .Windows;`
            mod.addImport("windows", windows_zig.module("windows"));
            try deps.append(b.allocator, .{ .name = "windows", .module = windows_zig.module("windows") });
        },
        else => {}
    }

    try deps.append(b.allocator, .{ .name = NAME, .module = mod });

    inline for (examples) |example| {
        addExample(
            b,
            target,
            optimize,
            example,
            deps.items,
            builtin.target.os.tag == .linux,
            &.{
                .{ "wayland-client", .linux },
            },
            null,
        );
    }
}

const Example = struct {
    name: []const u8,
    path: []const u8,
};

pub fn addExample(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    comptime example: Example,
    imports: []const std.Build.Module.Import,
    link_lib_c: bool,
    system_libraries: []const std.meta.Tuple(&.{ []const u8, Tag }),
    assets_dir: ?*std.Build.Step,
) void {
    const estep = b.step("example-" ++ example.name, "Run example-" ++ example.name);

    const exe = b.addExecutable(.{ .name = example.name, .root_module = b.createModule(.{
        .root_source_file = b.path(example.path),
        .target = target,
        .optimize = optimize,
        .imports = imports,
    }) });

    if (b.lazyDependency("zinit", .{
        .target = target,
        .optimize = optimize,
    })) |zinit_dep| {
        exe.root_module.addImport("zinit", zinit_dep.module("zinit"));
    }

    // exe.addWin32ResourceFile(.{ .file = b.path("app.rc") });

    if (assets_dir) |ad| {
        exe.step.dependOn(ad);
    }

    b.installArtifact(exe);

    if (link_lib_c) exe.linkLibC();
    for (system_libraries) |library| {
        if (library[1] == builtin.target.os.tag) {
            exe.linkSystemLibrary(library[0]);
        }
    }

    const ecmd = b.addRunArtifact(exe);
    ecmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        ecmd.addArgs(args);
    }

    estep.dependOn(&ecmd.step);
}
