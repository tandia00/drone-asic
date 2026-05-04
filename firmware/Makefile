# Firmware SAHEL-1 — RV32IMC sur PicoRV32
CROSS  := riscv64-unknown-elf-
CC     := $(CROSS)gcc
OBJCOPY:= $(CROSS)objcopy
OBJDUMP:= $(CROSS)objdump

CFLAGS := -march=rv32imc -mabi=ilp32 -Os -Wall -Wextra -ffreestanding \
          -nostdlib -fno-builtin -ffunction-sections -fdata-sections
LDFLAGS:= -T linker.ld -nostdlib -Wl,--gc-sections

BUILD := build
SRC   := start.S main.c drivers/uart.c drivers/spi.c drivers/i2c.c \
         drivers/pwm.c drivers/lora.c drivers/ndvi.c drivers/aes.c
OBJ   := $(addprefix $(BUILD)/, $(SRC:.c=.o))
OBJ   := $(OBJ:.S=.o)

all: $(BUILD)/firmware.hex

$(BUILD)/%.o: %.c | $(BUILD)
	@mkdir -p $(dir $@)
	$(CC) $(CFLAGS) -c $< -o $@

$(BUILD)/%.o: %.S | $(BUILD)
	@mkdir -p $(dir $@)
	$(CC) $(CFLAGS) -c $< -o $@

$(BUILD)/firmware.elf: $(OBJ)
	$(CC) $(CFLAGS) $(LDFLAGS) -o $@ $^

$(BUILD)/firmware.bin: $(BUILD)/firmware.elf
	$(OBJCOPY) -O binary $< $@

$(BUILD)/firmware.hex: $(BUILD)/firmware.bin
	hexdump -v -e '1/4 "%08x\n"' $< > $@

$(BUILD):
	mkdir -p $@

clean:
	rm -rf $(BUILD)

.PHONY: all clean
