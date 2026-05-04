# SAHEL-1 — SoC ASIC pour Drone Agricole

> Puce open-source destinée aux drones agricoles à bas coût pour l'Afrique,
> soumissionnable sur **eFabless / ChipFoundry** (shuttle SKY130, flow OpenLane,
> harnais Caravel).

[![License: Apache 2.0](https://img.shields.io/badge/license-Apache--2.0-blue.svg)](LICENSE)
[![PDK](https://img.shields.io/badge/PDK-SkyWater%20SKY130-green.svg)](https://github.com/google/skywater-pdk)
[![Flow](https://img.shields.io/badge/flow-OpenLane-orange.svg)](https://github.com/The-OpenROAD-Project/OpenLane)

---

## 1. Mission

Concevoir une puce **dédiée à l'agriculture de précision** dans le contexte
sahélien et ouest-africain :

- **Cartographie NDVI temps-réel** (santé des cultures) via accélérateur HW.
- **Pulvérisation ciblée** (économie d'intrants : eau, pesticides, engrais).
- **Liaison radio longue portée LoRa** (zones rurales sans 4G).
- **Télémétrie chiffrée AES-128** (contre détournement / vol de drone).
- **Faible consommation** (vols longs sous chaleur ≥ 40 °C).
- **Bas coût** : un seul ASIC remplace MCU + FPGA + crypto-chip.

## 2. Cible silicium

| Paramètre              | Valeur                                  |
|------------------------|-----------------------------------------|
| Foundry                | SkyWater 130 nm (open shuttle)          |
| Programme              | eFabless **ChipIgnite** / ChipFoundry   |
| Harnais                | **Caravel** (user_project_wrapper)      |
| Surface utilisateur    | 2.92 mm × 3.52 mm (~10.3 mm²)           |
| Fréquence cible        | 50 MHz (cœur), 25 MHz (périphériques)   |
| Tension                | 1.8 V cœur / 3.3 V I/O                  |
| Boîtier                | QFN-48 ou WLCSP                         |
| Toolchain              | OpenLane + Yosys + OpenROAD + Magic     |

## 3. Architecture

```
                    ┌──────────────────── SAHEL-1 SoC ────────────────────┐
                    │                                                      │
   GPS UART ───────►│  UART0  ┐                                            │
   Debug UART ◄────►│  UART1  │                                            │
                    │         │                                            │
   IMU/Baro I²C ◄──►│  I2C0   ├───┐                                        │
   Sol I²C     ◄──►│  I2C1   │   │                                        │
                    │         │   │                                        │
   LoRa SX1276 ◄──►│  SPI0   ├───┤                                        │
   Caméra MS   ◄──►│  SPI1   │   │      ┌───────────────┐                  │
                    │         │   ├─WB──►│   PicoRV32    │                  │
   4× ESC moteurs ◄│  PWM0-3 │   │      │  (RV32IMC)    │                  │
   2× Pompes      ◄│  PWM4-5 │   │      │   50 MHz      │                  │
                    │         │   │      └───────────────┘                  │
   16× GPIO    ◄──►│  GPIO   ├───┤                                        │
                    │         │   │      ┌───────────────┐                  │
                    │  TIMER  ├───┤      │ NDVI ACCEL    │  ◄── caméra MS  │
                    │         │   ├─────►│  R+NIR → idx  │                  │
                    │  AES128 ├───┤      └───────────────┘                  │
                    │         │   │                                        │
                    │  SRAM   ├───┘                                        │
                    │  32 KB  │                                            │
                    └─────────┴────────────────────────────────────────────┘
```

Voir `docs/architecture.md` pour les détails (mapping mémoire, IRQ, etc.).

## 4. Arborescence

```
drone-asic/
├── README.md                  ← ce fichier
├── LICENSE                    ← Apache-2.0
├── info.yaml                  ← métadonnées Caravel/eFabless
├── Makefile                   ← raccourcis build/sim/harden
├── docs/
│   ├── architecture.md
│   ├── memory_map.md
│   └── pinout.md
├── rtl/
│   ├── agri_drone_soc.v       ← top SoC
│   ├── wb_intercon.v          ← interconnect Wishbone
│   ├── ndvi_accel.v           ← accélérateur NDVI
│   ├── aes128.v               ← chiffrement télémétrie
│   ├── pwm.v                  ← contrôleur PWM (ESC + pompes)
│   ├── spi_master.v           ← SPI (LoRa, caméra)
│   ├── i2c_master.v           ← I²C (capteurs)
│   ├── uart.v                 ← UART (GPS, debug)
│   ├── gpio.v                 ← GPIO
│   ├── timer.v                ← timer/watchdog
│   ├── sram_wrap.v            ← wrapper SRAM SKY130
│   └── user_project_wrapper.v ← intégration Caravel
├── tb/
│   ├── tb_soc.v               ← TB top
│   ├── tb_ndvi.v
│   ├── tb_pwm.v
│   └── ...
├── openlane/
│   └── agri_drone_soc/
│       ├── config.json        ← config OpenLane
│       └── pin_order.cfg
├── firmware/
│   ├── Makefile
│   ├── linker.ld
│   ├── start.S
│   ├── main.c                 ← démo NDVI + LoRa
│   └── drivers/
└── scripts/
    ├── run_sim.sh
    └── run_openlane.sh
```

## 5. Démarrage rapide

### Pré-requis
```bash
# Outils open-source
sudo apt install iverilog gtkwave verilator yosys
# OpenLane (via Docker)
docker pull efabless/openlane:latest
# RISC-V toolchain pour le firmware
sudo apt install gcc-riscv64-unknown-elf
```

### Cloner
```bash
git clone https://github.com/tandia00/drone-asic.git
cd drone-asic
git submodule update --init --recursive   # picorv32, caravel, sky130
```

### Simulation RTL
```bash
make sim          # tous les TB Icarus
make sim-soc      # TB du SoC top
make wave         # ouvre GTKWave
```

### Synthèse + Place&Route (GDSII)
```bash
make harden       # invoque OpenLane/Docker → gds/agri_drone_soc.gds
```

### Firmware
```bash
make -C firmware  # produit firmware/build/firmware.hex
```

## 6. Soumission à la fonderie

1. **Vérifier** : `make lint && make sim && make harden` doivent passer.
2. **DRC/LVS** : automatiques dans OpenLane (Magic + Netgen).
3. **Antenna / STA** : rapport dans `runs/.../reports/`.
4. **Empaqueter** :
   ```bash
   make tarball   # crée submission/sahel1-<date>.tar.gz
   ```
5. **Soumettre** via le portail [efabless.com/projects](https://platform.efabless.com)
   en attachant `info.yaml` + GDS final + rapports.

Coût indicatif **ChipIgnite** (2025) : ≈ 9 750 USD pour 100 puces packagées.

## 7. Roadmap

- [x] v0.1 — RTL fonctionnel + simulation
- [ ] v0.2 — Place&Route propre, fermeture timing 50 MHz
- [ ] v0.3 — Tape-out shuttle MPW
- [ ] v1.0 — Carte d'évaluation drone (PCB autopilote)

## 8. Crédits & Licence

Conçu pour les jeunes ingénieurs et makers africains (Yam Pukri, BambaraTech,
ESMT, 2iE, ENSP, etc.). Basé sur PicoRV32 (Claire Wolf, ISC), Caravel (eFabless,
Apache-2.0), SKY130 PDK (Google/SkyWater, Apache-2.0).

Code original sous **Apache-2.0** — voir `LICENSE`.
