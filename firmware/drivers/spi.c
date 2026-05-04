#include "../sahel1.h"

void spi_init(uint32_t base, uint32_t div, int mode)
{
    SPI_DIV(base)  = div;
    SPI_CTRL(base) = (mode & 3) << 2; /* CS off */
}

uint8_t spi_xfer(uint32_t base, uint8_t b)
{
    SPI_DATA(base) = b;
    SPI_CTRL(base) = (SPI_CTRL(base) & ~1u) | 0x3; /* start + cs on */
    while (!(SPI_STAT(base) & 0x2)) ;
    SPI_CTRL(base) &= ~0x2; /* cs off */
    return (uint8_t)SPI_DATA(base);
}
