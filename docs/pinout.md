# SAHEL-1 — Pinout (Caravel `io[37:0]`)

Caravel offre 38 broches utilisateur. Affectation proposée :

| io[]   | Direction | Fonction              | Notes                  |
|--------|-----------|-----------------------|------------------------|
| 0      | in        | XTAL_IN (50 MHz)      | déjà géré par Caravel  |
| 1      | in        | RESET_N               |                        |
| 2-3    | i/o       | UART0 RX/TX (GPS)     | NMEA 9600 b            |
| 4-5    | i/o       | UART1 RX/TX (debug)   | 115200 b               |
| 6-7    | i/o       | I2C0 SCL/SDA          | IMU + baro             |
| 8-9    | i/o       | I2C1 SCL/SDA          | sondes sol             |
| 10-13  | out/in    | SPI0 (LoRa) CS,CLK,MOSI,MISO |                |
| 14     | in        | LoRa DIO0 (IRQ)       |                        |
| 15-18  | out/in    | SPI1 (caméra) CS,CLK,MOSI,MISO |               |
| 19     | in        | Caméra VSYNC          |                        |
| 20-23  | out       | PWM0..3 (ESC moteurs) |                        |
| 24-25  | out       | PWM4..5 (pompes)      |                        |
| 26-37  | i/o       | GPIO0..11             | LEDs, switches, relais |
