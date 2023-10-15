pub const p = @cImport({
    @cInclude("stdio.h");
    @cInclude("pico/stdlib.h");
    // PICO W specific header
    @cInclude("pico/cyw43_arch.h"); 
    @cInclude("hardware/gpio.h");
    @cInclude("pico/binary_info.h");
});
const std = @import("std");

// Basically the pico_w blink sample
export fn main() c_int {
    _ = p.stdio_init_all();
     if (p.cyw43_arch_init() != 0) {
        return -1;
    }   
    while (true) {
        p.cyw43_arch_gpio_put(p.CYW43_WL_GPIO_LED_PIN, true);
        p.sleep_ms(100);
        p.cyw43_arch_gpio_put(p.CYW43_WL_GPIO_LED_PIN, false);
        p.sleep_ms(50);
        _ = p.printf("Hello world\n");   
    }
}
