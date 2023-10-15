const std = @import("std");

const Board = "pico_w";

// RP2040 -- This includes a specific header file.
const IsRP2040 = true;

// Choose whether Stdio goes to USB or UART
const StdioUsb = true;
const PicoStdlibDefine = if (StdioUsb) "LIB_PICO_STDIO_USB" else "LIB_PICO_STDIO_UART"; 

pub fn build(b: *std.Build) anyerror!void {
    
    // ------------------
    const target = std.zig.CrossTarget{
        .abi = .eabi,
        .cpu_arch = .thumb,
        .cpu_model = .{.explicit = &std.Target.arm.cpu.cortex_m0plus},
        .os_tag = .freestanding,
    };

    const optimize = b.standardOptimizeOption(.{});


    const lib = b.addObject(.{
        .name = "zig-pico",
        .root_source_file = .{ .path = "src/main.zig" },
        .target = target,
        .optimize = optimize,
    });

    const pico_sdk_path = std.os.getenv("PICO_SDK_PATH") orelse return error.PicoSDKEnvNotSet;
    std.debug.print("{s}\n", .{pico_sdk_path});

    // default arm-none-eabi includes
    lib.linkLibC();
    lib.addSystemIncludePath(.{.path = "/usr/arm-none-eabi/include"});

    // find the board header
    const board_header = try blk: {
        const boards_directory_path = try std.fmt.allocPrint(b.allocator, "{s}/src/boards/include/boards/", .{pico_sdk_path});
        var boards_dir = try std.fs.cwd().openIterableDir(boards_directory_path, .{});
        defer boards_dir.close();
        
        var it = boards_dir.iterate();
        while (try it.next()) |file| {
            if (std.mem.containsAtLeast(u8, file.name, 1, Board)) {
                // found the board header
                break :blk file.name;
            }    
        }
        break :blk error.BoardHeaderNotFound;
    };

    // Autogenerate the header file like the pico sdk would
    const cmsys_exception_prefix = if (IsRP2040) "" else "//";
    const header_str = try std.fmt.allocPrint(b.allocator, 
    \\#include "{s}/src/boards/include/boards/{s}"
    \\{s}#include "{s}/src/rp2_common/cmsis/include/cmsis/rename_exceptions.h"
    ,.{pico_sdk_path, board_header, cmsys_exception_prefix, pico_sdk_path});
    
    // Write and include the generated header
    const config_autogen_step = b.addWriteFile("pico/config_autogen.h", header_str);
    lib.step.dependOn(&config_autogen_step.step);
    lib.addIncludePath(config_autogen_step.getDirectory());

    // requires running cmake at least once
    lib.addSystemIncludePath(.{.path = "build/generated/pico_base"});

    // PICO SDK includes    
    const pico_sdk_src = try std.fmt.allocPrint(b.allocator, "{s}/src", .{pico_sdk_path});
    //  -type d -name include"
    // find all folders called include in the Pico SDK
    const find_argv = [_][]const u8{"find", pico_sdk_src, "-type", "d", "-name", "include"};
    const directories = b.exec(&find_argv);
    var splits = std.mem.splitSequence(u8, directories, "\n");

    // Define UART or USB constant for headers
    lib.defineCMacroRaw(PicoStdlibDefine);

    while (splits.next()) |include_dir| {
        // filter host headers
        if (std.mem.containsAtLeast(u8, include_dir, 1, "src/host")) {
            continue;
        }

        lib.addIncludePath(std.build.LazyPath{.path = include_dir});
    }

    // required for pico_w wifi
    lib.defineCMacroRaw("PICO_CYW43_ARCH_THREADSAFE_BACKGROUND");
    const cyw43_include = try std.fmt.allocPrint(b.allocator, "{s}/lib/cyw43-driver/src", .{pico_sdk_path});
    lib.addIncludePath(.{ .path = cyw43_include});
    
    // required by cyw43
    const lwip_include = try std.fmt.allocPrint(b.allocator, "{s}/lib/lwip/src/include", .{pico_sdk_path});
    lib.addIncludePath(.{ .path = lwip_include});

    // options headers
    lib.addIncludePath(.{ .path = "config/"});

    const compiled = lib.getEmittedBin();
    const install_step = b.addInstallFile(compiled, "mlem.o");
    install_step.step.dependOn(&lib.step);
    
    // create build directory
    if (std.fs.cwd().makeDir("build")) |_| {} else |err| {
        if (err != error.PathAlreadyExists) return err;
    }

    const uart_or_usb = if (StdioUsb) "-DSTDIO_USB=1" else "-DSTDIO_UART=1";
    const cmake_argv = [_][]const u8{"cmake", "-B", "./build", "-S .", "-DPICO_BOARD=" ++ Board, uart_or_usb};
    const cmake_step = b.addSystemCommand(&cmake_argv);
    cmake_step.step.dependOn(&install_step.step);

    const make_argv = [_][]const u8{"make", "-C", "./build"};
    const make_step = b.addSystemCommand(&make_argv);
    make_step.step.dependOn(&cmake_step.step);

    const uf2_step = b.addInstallFile(.{.path = "build/mlem.uf2"}, "firmware.uf2");
    uf2_step.step.dependOn(&make_step.step);

    b.default_step.dependOn(&uf2_step.step);

}
