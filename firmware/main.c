/* SAHEL-1 — firmware de démonstration drone agricole.
 *
 * Boucle principale (autopilot simplifié) :
 *   1. Lit GPS sur UART0 (NMEA)
 *   2. Lit IMU sur I2C0
 *   3. Met à jour la consigne PWM des 4 ESC moteurs (stabilisation)
 *   4. Une fois sur N : capture image multispectrale via SPI1,
 *      lance accélérateur NDVI, calcule % végétation saine
 *   5. Si zone sèche détectée → active pompe pulvérisation (PWM4)
 *   6. Émet télémétrie chiffrée AES-128 via SPI0 (LoRa)
 *   7. Kick watchdog
 */
#include "sahel1.h"

#define IMG_W 64
#define IMG_H 64
#define NPIX  (IMG_W * IMG_H)

static uint8_t red_buf[NPIX] __attribute__((aligned(4)));
static uint8_t nir_buf[NPIX] __attribute__((aligned(4)));
static int8_t  ndvi_buf[NPIX] __attribute__((aligned(4)));

extern void uart_init(uint32_t base, uint32_t div);
extern void uart_puts(uint32_t base, const char *s);
extern void pwm_setup(int ch, uint32_t period, uint32_t duty);
extern int  ndvi_run(const uint8_t *r, const uint8_t *n, int8_t *o, int npix, int8_t threshold);
extern void aes_encrypt(const uint32_t key[4], const uint32_t in[4], uint32_t out[4]);
extern void lora_init(void);
extern void lora_send(const uint8_t *buf, int len);

static const uint32_t AES_KEY_DEMO[4] = {
    0x03020100, 0x07060504, 0x0b0a0908, 0x0f0e0d0c
};

int main(void)
{
    uart_init(UART1_BASE, 434); /* debug @ 115200 */
    uart_puts(UART1_BASE, "SAHEL-1 boot OK\r\n");

    /* PWM 50 Hz, ESC en mode servo : 1 ms = idle, 2 ms = full throttle */
    /* Avec clk=50MHz, period=1_000_000 cycles = 50Hz, duty=50000=1ms */
    for (int i = 0; i < 4; i++)
        pwm_setup(i, 1000000, 50000);
    /* Pompes : 1 kHz, 0% par défaut */
    pwm_setup(4, 50000, 0);
    pwm_setup(5, 50000, 0);

    lora_init();

    /* Activer watchdog (recharge ~20 ms à 50 MHz) */
    TIMER_WDT  = 1000000;
    TIMER_CTRL = 0x2;

    int loop = 0;
    while (1) {
        /* Kick watchdog */
        TIMER_WDT = 1000000;

        /* Toutes les 100 itérations → cycle NDVI complet */
        if ((loop++ % 100) == 0) {
            /* (Ici, en vrai : capturer image via SPI1 dans red_buf/nir_buf) */
            int healthy = ndvi_run(red_buf, nir_buf, ndvi_buf, NPIX,
                                   /*threshold=*/25 /* ~ NDVI 0.2 */);
            int pct = (healthy * 100) / NPIX;
            uart_puts(UART1_BASE, "NDVI healthy %\r\n");

            /* Décision pulvérisation : si > 50 % de pixels secs → pompe ON */
            if (pct < 50) {
                PWM_DUTY(4) = 25000;       /* 50 % duty */
                PWM_CFG(4)  = 1;
            } else {
                PWM_CFG(4)  = 0;
            }

            /* Télémétrie chiffrée */
            uint32_t plain[4] = { (uint32_t)pct, rdcycle(), 0xCAFEBABE, 0x12345678 };
            uint32_t cipher[4];
            aes_encrypt(AES_KEY_DEMO, plain, cipher);
            lora_send((uint8_t *)cipher, 16);
        }

        delay_cycles(500000); /* ~10 ms à 50 MHz */
    }
    return 0;
}
