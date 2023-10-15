pub const p = @cImport({
    @cInclude("stdio.h");
    @cInclude("pico/stdlib.h");
    @cInclude("pico/cyw43_arch.h");
    @cInclude("hardware/gpio.h");
    @cInclude("pico/binary_info.h");
});