#include "../sahel1.h"

void uart_init(uint32_t base, uint32_t div) { UART_DIV(base) = div; }

static int uart_tx_busy(uint32_t base) { return UART_STAT(base) & 0x1; }

void uart_putc(uint32_t base, char c)
{
    while (uart_tx_busy(base)) ;
    UART_DATA(base) = (uint32_t)(uint8_t)c;
}

void uart_puts(uint32_t base, const char *s)
{
    while (*s) {
        if (*s == '\n') uart_putc(base, '\r');
        uart_putc(base, *s++);
    }
}
