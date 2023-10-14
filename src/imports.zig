pub const p = @cImport({
    @cDefine("PICO_CYW43_ARCH_THREADSAFE_BACKGROUND", "1");
    @cInclude("pico/stdlib.h");
    @cInclude("pico/cyw43_arch.h");
    @cInclude("hardware/gpio.h");
    @cInclude("pico/binary_info.h");
});