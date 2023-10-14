const p = @import("imports.zig").p;
const blink = @import("helper.zig").blink;
const std = @import("std");

// Basically the pico_w blink sample
export fn main() c_int {
    if (p.cyw43_arch_init() != 0) {
        return -1;
    }
    while (true) {
        blink();
    }
}
