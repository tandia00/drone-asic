#include "../sahel1.h"

void i2c_init(uint32_t base, uint32_t div)
{
    I2C_DIV(base) = div;
}

static void i2c_wait(uint32_t base) { while (I2C_STAT(base) & 0x1) ; }

int i2c_write_reg(uint32_t base, uint8_t addr, uint8_t reg, uint8_t val)
{
    /* Start + write addr */
    I2C_DATA(base) = (addr << 1);
    I2C_CMD(base)  = 0x9;     /* start | write */
    i2c_wait(base);
    if (!(I2C_STAT(base) & 0x2)) return -1;

    I2C_DATA(base) = reg;
    I2C_CMD(base)  = 0x8;
    i2c_wait(base);

    I2C_DATA(base) = val;
    I2C_CMD(base)  = 0xA;     /* write | stop */
    i2c_wait(base);
    return 0;
}

int i2c_read_reg(uint32_t base, uint8_t addr, uint8_t reg, uint8_t *val)
{
    I2C_DATA(base) = (addr << 1);
    I2C_CMD(base)  = 0x9; i2c_wait(base);
    I2C_DATA(base) = reg;
    I2C_CMD(base)  = 0x8; i2c_wait(base);
    /* repeated start + read */
    I2C_DATA(base) = (addr << 1) | 1;
    I2C_CMD(base)  = 0x9; i2c_wait(base);
    I2C_CMD(base)  = 0x16;    /* read | stop | nack */
    i2c_wait(base);
    *val = (uint8_t)I2C_DATA(base);
    return 0;
}
