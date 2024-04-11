const std = @import("std");

const Board = "pico_w";

// RP2040 -- This includes a specific header file.
const IsRP2040 = true;

// Choose whether Stdio goes to USB or UART
const StdioUsb = true;
const PicoStdlibDefine = if (StdioUsb) "LIB_PICO_STDIO_USB" else "LIB_PICO_STDIO_UART"; 

// Pico SDK path can be specified here for your convenience
const PicoSDKPath: ?[]const u8 = null;

// arm-none-eabi toolchain path may be specified here as well
const ARMNoneEabiPath: ?[] const u8 = null;


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
    
    // get and perform basic verification on the pico sdk path
    // if the sdk path contains the pico_sdk_init.cmake file then we know its correct
    const pico_sdk_path = 
        if(PicoSDKPath) |sdk_path| sdk_path
        else std.process.getEnvVarOwned(b.allocator, "PICO_SDK_PATH") catch null
            orelse {
                std.log.err("The Pico SDK path must be set either through the PICO_SDK_PATH environment variable or at the top of build.zig.", .{});
                return; 
            };    
    
    const pico_init_cmake_path = b.pathJoin(&.{pico_sdk_path, "pico_sdk_init.cmake"});
    std.fs.cwd().access(pico_init_cmake_path, .{}) catch {
        std.log.err(
            \\Provided Pico SDK path does not contain the file pico_sdk_init.cmake
            \\Tried: {s}
            \\Are you sure you entered the path correctly?"
            , .{pico_init_cmake_path});
        return;
    };

    // default arm-none-eabi includes
    lib.linkLibC();

    // Standard libary headers may be in different locations on different platforms
    const arm_header_location = blk: {
        if (ARMNoneEabiPath) |path| {
            break :blk path;
        }

        if (std.process.getEnvVarOwned(b.allocator, "ARM_NONE_EABI_PATH") catch null) |path| {
            break :blk path;
        }
        
        const unix_path = "/usr/arm-none-eabi/include";
        if(std.fs.accessAbsolute(unix_path, .{})) |_| {
            break :blk unix_path;
        } else |err| err catch {};

        break :blk error.StandardHeaderLocationNotSpecified;
    } catch |err| {
        err catch {};
        std.log.err(
            \\Could not determine ARM Toolchain include directory.
            \\Please set the ARM_NONE_EABI_PATH environment variable with the correct path
            \\or set the ARMNoneEabiPath variable at the top of build.zig 
            , .{});
        return;
    };
    lib.addSystemIncludePath(.{.path = arm_header_location});

    // find the board header
    const board_header = blk: {
        const boards_directory_path = b.pathJoin(&.{pico_sdk_path, "src/boards/include/boards/"});
        var boards_dir = try std.fs.cwd().openIterableDir(boards_directory_path, .{});
        defer boards_dir.close();
        
        var it = boards_dir.iterate();
        while (try it.next()) |file| {
            if (std.mem.containsAtLeast(u8, file.name, 1, Board)) {
                // found the board header
                break :blk file.name;
            }    
        }
        std.log.err("Could not find the header file for board '{s}'\n", .{Board});
        return;
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
    // Find all folders called include in the Pico SDK
    {
        const pico_sdk_src = try std.fmt.allocPrint(b.allocator, "{s}/src", .{pico_sdk_path});
        var dir = try std.fs.cwd().openIterableDir(pico_sdk_src, .{
            .no_follow = true, 
        });
        var walker = try dir.walk(b.allocator);
        defer walker.deinit();
        while (try walker.next()) |entry| {
            if (std.mem.eql(u8,entry.basename,"include")) {
                if (! std.mem.containsAtLeast(u8, entry.path, 1, "host")) {
                    const pico_sdk_include = try std.fmt.allocPrint(b.allocator, "{s}\\src\\{s}", .{pico_sdk_path,entry.path});
                    lib.addIncludePath(std.build.LazyPath{.path = pico_sdk_include});
                }
            }
        }
    }


    // Define UART or USB constant for headers
    lib.defineCMacroRaw(PicoStdlibDefine);

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
    const cmake_pico_sdk_path = b.fmt("-DPICO_SDK_PATH={s}", .{pico_sdk_path});
    const cmake_argv = [_][]const u8{"cmake",  "-B", "./build", "-S .", "-DPICO_BOARD=" ++ Board,cmake_pico_sdk_path ,uart_or_usb};
    const cmake_step = b.addSystemCommand(&cmake_argv);
    cmake_step.step.dependOn(&install_step.step);

    const make_argv = [_][]const u8{"cmake",  "--build", "./build", "--parallel"};
    const make_step = b.addSystemCommand(&make_argv);
    make_step.step.dependOn(&cmake_step.step);

    const uf2_create_step = b.addInstallFile(.{.path = "build/mlem.uf2"}, "firmware.uf2");
    uf2_create_step.step.dependOn(&make_step.step);

    const uf2_step = b.step("uf2", "Create firmware.uf2");
    uf2_step.dependOn(&uf2_create_step.step);
    b.default_step = uf2_step;
}
