#ifndef SAHEL1_H
#define SAHEL1_H

#include <stdint.h>

#define REG32(addr) (*(volatile uint32_t *)(addr))

/* Memory map ------------------------------------------------------------ */
#define UART0_BASE  0x30000000u
#define UART1_BASE  0x30001000u
#define I2C0_BASE   0x30002000u
#define I2C1_BASE   0x30003000u
#define SPI0_BASE   0x30004000u   /* LoRa */
#define SPI1_BASE   0x30005000u   /* Caméra */
#define PWM_BASE    0x30006000u
#define GPIO_BASE   0x30007000u
#define TIMER_BASE  0x30008000u
#define AES_BASE    0x30009000u
#define NDVI_BASE   0x3000A000u

/* UART regs */
#define UART_DATA(B)    REG32((B) + 0x00)
#define UART_STAT(B)    REG32((B) + 0x04)
#define UART_DIV(B)     REG32((B) + 0x08)

/* SPI regs */
#define SPI_DATA(B)     REG32((B) + 0x00)
#define SPI_CTRL(B)     REG32((B) + 0x04)
#define SPI_STAT(B)     REG32((B) + 0x08)
#define SPI_DIV(B)      REG32((B) + 0x0C)

/* I2C regs */
#define I2C_DATA(B)     REG32((B) + 0x00)
#define I2C_CMD(B)      REG32((B) + 0x04)
#define I2C_STAT(B)     REG32((B) + 0x08)
#define I2C_DIV(B)      REG32((B) + 0x0C)

/* PWM (par canal i, espacé 0x10) */
#define PWM_PERIOD(i)   REG32(PWM_BASE + (i)*0x10 + 0x00)
#define PWM_DUTY(i)     REG32(PWM_BASE + (i)*0x10 + 0x04)
#define PWM_CFG(i)      REG32(PWM_BASE + (i)*0x10 + 0x08)

/* GPIO */
#define GPIO_DIR        REG32(GPIO_BASE + 0x00)
#define GPIO_OUT        REG32(GPIO_BASE + 0x04)
#define GPIO_IN         REG32(GPIO_BASE + 0x08)

/* Timer */
#define TIMER_COUNT     REG32(TIMER_BASE + 0x00)
#define TIMER_COMPARE   REG32(TIMER_BASE + 0x04)
#define TIMER_CTRL      REG32(TIMER_BASE + 0x08)
#define TIMER_WDT       REG32(TIMER_BASE + 0x0C)

/* AES */
#define AES_CTRL        REG32(AES_BASE + 0x00)
#define AES_STAT        REG32(AES_BASE + 0x04)
#define AES_KEY(i)      REG32(AES_BASE + 0x10 + (i)*4)
#define AES_DIN(i)      REG32(AES_BASE + 0x20 + (i)*4)
#define AES_DOUT(i)     REG32(AES_BASE + 0x30 + (i)*4)

/* NDVI */
#define NDVI_CTRL       REG32(NDVI_BASE + 0x00)
#define NDVI_STAT       REG32(NDVI_BASE + 0x04)
#define NDVI_RED        REG32(NDVI_BASE + 0x08)
#define NDVI_NIR        REG32(NDVI_BASE + 0x0C)
#define NDVI_OUT        REG32(NDVI_BASE + 0x10)
#define NDVI_NPIX       REG32(NDVI_BASE + 0x14)
#define NDVI_THRESH     REG32(NDVI_BASE + 0x18)
#define NDVI_HEALTHY    REG32(NDVI_BASE + 0x1C)

/* PicoRV32 cycle counter */
static inline uint32_t rdcycle(void) {
    uint32_t c; __asm__ volatile ("rdcycle %0" : "=r"(c)); return c;
}
static inline void delay_cycles(uint32_t n) {
    uint32_t s = rdcycle();
    while ((rdcycle() - s) < n) { }
}

#endif
