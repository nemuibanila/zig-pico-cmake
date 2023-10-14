const std = @import("std");

const PicoBoard = "-DPICO_BOARD=pico_w";
// Although this function looks imperative, note that its job is to
// declaratively construct a build graph that will be executed by an external
// runner.
pub fn build(b: *std.Build) anyerror!void {
    // Standard target options allows the person running `zig build` to choose
    // what target to build for. Here we do not override the defaults, which
    // means any target is allowed, and the default is native. Other options
    // for restricting supported target set are available.
    const target = std.zig.CrossTarget{
        .abi = .eabi,
        .cpu_arch = .thumb,
        .cpu_model = .{.explicit = &std.Target.arm.cpu.cortex_m0plus},
        .os_tag = .freestanding,
    };

    // Standard optimization options allow the person running `zig build` to select
    // between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall. Here we do not
    // set a preferred release mode, allowing the user to decide how to optimize.
    const optimize = b.standardOptimizeOption(.{});


    const lib = b.addObject(.{
        .name = "zig-pico",
        // In this case the main source file is merely a path, however, in more
        // complicated build scripts, this could be a generated file.
        .root_source_file = .{ .path = "src/main.zig" },
        .target = target,
        .optimize = optimize,
    });

    const pico_sdk_path = std.os.getenv("PICO_SDK_PATH") orelse return error.PicoSDKEnvNotSet;
    std.debug.print("{s}\n", .{pico_sdk_path});

    // default arm-none-eabi includes
    lib.linkLibC();
    lib.addSystemIncludePath(.{.path = "/usr/arm-none-eabi/include"});

    // requires running cmake at least once
    lib.addSystemIncludePath(.{.path = "build/generated/pico_base"});

    // PICO SDK includes    
    const pico_sdk_src = try std.fmt.allocPrint(b.allocator, "{s}/src", .{pico_sdk_path});
    //  -type d -name include"
    // find all folders called include in the Pico SDK
    const find_argv = [_][]const u8{"find", pico_sdk_src, "-type", "d", "-name", "include"};
    const directories = b.exec(&find_argv);
    var splits = std.mem.splitSequence(u8, directories, "\n");
    while (splits.next()) |include_dir| {
        lib.addIncludePath(std.build.LazyPath{.path = include_dir});
    }

    // required for pico_w wifi
    const cyw43_include = try std.fmt.allocPrint(b.allocator, "{s}/lib/cyw43-driver/src", .{pico_sdk_path});
    lib.addIncludePath(.{ .path = cyw43_include});
    
    // required by cyw43
    const lwip_include = try std.fmt.allocPrint(b.allocator, "{s}/lib/lwip/src/include", .{pico_sdk_path});
    lib.addIncludePath(.{ .path = lwip_include});

    // options headers
    lib.addIncludePath(.{ .path = "config/"});

    // This declares intent for the library to be installed into the standard
    // location when the user invokes the "install" step (the default step when
    // running `zig build`).
    // b.installArtifact(lib);
    const compiled = lib.getEmittedBin();
    const install_step = b.addInstallFile(compiled, "mlem.o");
    install_step.step.dependOn(&lib.step);
    
    // create build directory
    if (std.fs.cwd().makeDir("build")) |_| {} else |err| {
        if (err != error.PathAlreadyExists) return err;
    }

    const cmake_argv = [_][]const u8{"cmake", "-B", "./build", "-S .", PicoBoard};
    const cmake_step = b.addSystemCommand(&cmake_argv);
    cmake_step.step.dependOn(&install_step.step);

    const make_argv = [_][]const u8{"make", "-C", "./build"};
    const make_step = b.addSystemCommand(&make_argv);
    make_step.step.dependOn(&cmake_step.step);

    const uf2_step = b.addInstallFile(.{.path = "build/mlem.uf2"}, "firmware.uf2");
    uf2_step.step.dependOn(&make_step.step);

    b.default_step.dependOn(&uf2_step.step);

}
