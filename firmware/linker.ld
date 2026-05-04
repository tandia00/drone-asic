OUTPUT_ARCH(riscv)
ENTRY(_start)

MEMORY {
    ROM (rx)  : ORIGIN = 0x00000000, LENGTH = 4K
    RAM (rwx) : ORIGIN = 0x10000000, LENGTH = 32K
}

SECTIONS {
    .text : { *(.text.init) *(.text*) } > ROM
    .rodata : { *(.rodata*) } > ROM
    .data : { *(.data*) } > RAM AT > ROM
    .bss  : { *(.bss*) *(COMMON) } > RAM
    _stack_top = ORIGIN(RAM) + LENGTH(RAM);
}
