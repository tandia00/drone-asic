# SAHEL-1 — Memory map

| Base addr   | Taille | Périphérique     | Notes                          |
|-------------|--------|------------------|--------------------------------|
| 0x0000_0000 |  4 KB  | Boot ROM         | Bootloader, vecteurs reset/IRQ |
| 0x1000_0000 | 32 KB  | SRAM             | Code + données                 |
| 0x3000_0000 |  4 KB  | UART0 (GPS)      |                                |
| 0x3000_1000 |  4 KB  | UART1 (debug)    |                                |
| 0x3000_2000 |  4 KB  | I2C0             |                                |
| 0x3000_3000 |  4 KB  | I2C1             |                                |
| 0x3000_4000 |  4 KB  | SPI0 (LoRa)      |                                |
| 0x3000_5000 |  4 KB  | SPI1 (caméra)    |                                |
| 0x3000_6000 |  4 KB  | PWM (6 canaux)   |                                |
| 0x3000_7000 |  4 KB  | GPIO             |                                |
| 0x3000_8000 |  4 KB  | TIMER + WDT      |                                |
| 0x3000_9000 |  4 KB  | AES-128          |                                |
| 0x3000_A000 |  4 KB  | NDVI accelerator | slave idx 12 (DMA actif sur bus) |

## Registres NDVI (offset depuis base)

| Offset | Nom        | Description                              |
|--------|------------|------------------------------------------|
| 0x00   | CTRL       | bit0 = start, bit1 = irq_en              |
| 0x04   | STATUS     | bit0 = busy, bit1 = done                 |
| 0x08   | RED_ADDR   | Adresse buffer canal Rouge               |
| 0x0C   | NIR_ADDR   | Adresse buffer canal NIR                 |
| 0x10   | OUT_ADDR   | Adresse buffer NDVI sortie               |
| 0x14   | NPIX       | Nombre de pixels (entier)                |
| 0x18   | THRESHOLD  | Seuil végétation saine (signé 8b)        |
| 0x1C   | HEALTHY_CT | Compteur de pixels > THRESHOLD (RO)      |

## Registres AES (offset)

| Offset | Nom        | Description                              |
|--------|------------|------------------------------------------|
| 0x00   | CTRL       | bit0 = start, bit1 = enc/dec, bit2 = irq |
| 0x04   | STATUS     | bit0 = busy, bit1 = done                 |
| 0x10   | KEY[0..3]  | Clé 128 bits (4 mots)                    |
| 0x20   | DIN[0..3]  | Bloc d'entrée                            |
| 0x30   | DOUT[0..3] | Bloc de sortie (RO)                      |

## Registres PWM (offset, ×6 canaux espacés de 0x10)

| Offset | Nom    | Description                  |
|--------|--------|------------------------------|
| 0x00   | PERIOD | Période (cycles)             |
| 0x04   | DUTY   | Rapport cyclique             |
| 0x08   | CFG    | bit0 = enable, bit1 = invert |
