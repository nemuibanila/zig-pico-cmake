const p = @import("imports.zig").p;


// Even though it gets compiled to a single object file, you are not limited to a single source file.
pub fn blink() void {
    p.cyw43_arch_gpio_put(p.CYW43_WL_GPIO_LED_PIN, true);
    p.sleep_ms(100);
    p.cyw43_arch_gpio_put(p.CYW43_WL_GPIO_LED_PIN, false);
    p.sleep_ms(50);
}