# SAHEL-1 — Architecture détaillée

## 1. Vue d'ensemble

SAHEL-1 est un **System-on-Chip RISC-V** mono-cœur, optimisé pour les
contrôleurs de vol de drones agricoles. Il intègre tout ce qu'il faut pour
remplacer un ensemble *MCU + FPGA + crypto-chip + sensor-hub* dans un seul
silicium SKY130.

## 2. Cœur

- **PicoRV32** (Claire Wolf, ISC) — RV32IMC, 50 MHz cible.
- 32 KB SRAM on-chip (pile + données + buffers image).
- ROM bootloader 4 KB (charge le firmware depuis flash externe SPI).

## 3. Bus

- **Wishbone B4 classic**, 32 bits, single-master (cœur), multi-slave.
- Décodage par tranches de 4 KB sur les bits `addr[15:12]`.
- Latence 1 cycle pour les périphériques rapides, 2-3 cycles pour AES/NDVI.

## 4. Mapping mémoire

Voir `memory_map.md`.

## 5. Périphériques

### 5.1 PWM (motor + spray)
- 6 canaux indépendants, 16 bits.
- Mode standard 50 Hz (servo/ESC PPM 1 ms – 2 ms).
- Mode rapide OneShot125 / DShot300 pour ESC numériques.
- Canaux 4-5 dédiés pompes/électrovannes pulvérisation (PWM 1 kHz).

### 5.2 SPI maître
- 2 instances. SPI0 : module radio LoRa SX1276/SX1262 (jusqu'à 10 km LoS).
- SPI1 : caméra multispectrale (capteurs RED + NIR à 800 nm).
- Mode 0/1/2/3, jusqu'à 12.5 MHz.

### 5.3 I²C maître
- 2 instances, 100/400 kHz.
- I2C0 : IMU MPU-9250, baromètre BMP280.
- I2C1 : sondes humidité/température sol (capteurs locaux bon marché).

### 5.4 UART
- 2 instances. UART0 : GPS NMEA u-blox NEO-6M (9600 bauds).
- UART1 : debug/console (115200 bauds).

### 5.5 GPIO
- 16 broches programmables (LED status, switches, relais).

### 5.6 Timer / Watchdog
- Timer 32 bits + watchdog matériel (sécurité vol).

### 5.7 Accélérateur NDVI
- Calcule `NDVI = (NIR - RED) / (NIR + RED)` en pipeline.
- Entrée : 2 buffers DMA (canal R + canal NIR), 8 bits/pixel.
- Sortie : NDVI signé 8 bits par pixel (-128..127).
- Débit : 1 pixel/cycle → 50 Mpix/s à 50 MHz (largement suffisant pour caméra
  drone 640×480 @ 30 fps).
- Implémentation : division par approximation de Newton-Raphson 8 itérations
  (économise ≈ 70 % de surface vs. divider IEEE).

### 5.8 AES-128
- Mode ECB, 11 rounds, S-box ROM.
- Latence 12 cycles/bloc → ≈ 4 MB/s à 50 MHz.
- Utilisé pour chiffrer le flux LoRa de télémétrie (anti-piratage).

## 6. Horloges & reset

- Entrée : oscillateur externe 50 MHz (XTAL).
- PLL interne en option (non implémenté en v0.1, slot prévu).
- Reset : actif bas, synchronisé sur clock domain principal.

## 7. Consommation estimée

| Mode                 | Conso typique |
|----------------------|---------------|
| Run plein (50 MHz)   | ≈ 35 mW       |
| NDVI actif           | ≈ 50 mW       |
| Idle (gated clock)   | ≈ 5 mW        |
| Deep-sleep           | ≈ 50 µW       |

→ Avec une LiPo 3S 5000 mAh, marge de plusieurs heures de vol.

## 8. Robustesse climat

- Pads SKY130 spécifiés -40 °C à +125 °C → adaptés Sahel.
- Watchdog matériel (reset auto en cas de freeze logiciel).
- ECC parity sur SRAM (option v0.2).
