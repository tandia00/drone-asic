/* Pilote minimaliste Semtech SX1276 sur SPI0 — uniquement init + send.
 * Adapté à un drone : 868 MHz, SF7, BW 125 kHz, +14 dBm.
 */
#include "../sahel1.h"

extern void    spi_init(uint32_t base, uint32_t div, int mode);
extern uint8_t spi_xfer(uint32_t base, uint8_t b);

#define REG_OPMODE          0x01
#define REG_FRF_MSB         0x06
#define REG_PA_CONFIG       0x09
#define REG_FIFO            0x00
#define REG_FIFO_ADDR_PTR   0x0D
#define REG_FIFO_TX_BASE    0x0E
#define REG_PAYLOAD_LEN     0x22
#define REG_DIO_MAPPING1    0x40

static void wr(uint8_t reg, uint8_t val) {
    spi_xfer(SPI0_BASE, reg | 0x80);
    spi_xfer(SPI0_BASE, val);
}
static uint8_t rd(uint8_t reg) {
    spi_xfer(SPI0_BASE, reg & 0x7F);
    return spi_xfer(SPI0_BASE, 0);
}

void lora_init(void)
{
    spi_init(SPI0_BASE, /*div=*/25, /*mode=*/0); /* 50MHz/25 = 2 MHz */
    wr(REG_OPMODE, 0x80); /* sleep + LoRa mode */
    /* FRF pour 868 MHz : 868e6 / 61.035 ≈ 0xD90000 */
    wr(REG_FRF_MSB,     0xD9);
    wr(REG_FRF_MSB + 1, 0x00);
    wr(REG_FRF_MSB + 2, 0x00);
    wr(REG_PA_CONFIG, 0x8F);  /* PA_BOOST, +14 dBm */
    wr(REG_OPMODE, 0x81);     /* standby */
}

void lora_send(const uint8_t *buf, int len)
{
    wr(REG_OPMODE, 0x81);
    wr(REG_FIFO_TX_BASE, 0x00);
    wr(REG_FIFO_ADDR_PTR, 0x00);
    for (int i = 0; i < len; i++) wr(REG_FIFO, buf[i]);
    wr(REG_PAYLOAD_LEN, (uint8_t)len);
    wr(REG_OPMODE, 0x83);     /* TX */
    /* attendre fin TX (DIO0=TxDone). Polling minimaliste : */
    while ((rd(0x12) & 0x08) == 0) ; /* IRQ flags : TxDone */
    wr(0x12, 0xFF);
}
