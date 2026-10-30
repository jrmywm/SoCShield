ENTRY(_start)
MEMORY { RAM (rwx) : ORIGIN = 0, LENGTH = 64K }
SECTIONS {
 .text : { KEEP(*(.text.start)) *(.text*) } > RAM
 .rodata : { *(.rodata*) } > RAM
 .data : { *(.data*) *(.sdata*) } > RAM
 . = ALIGN(4);
 .bss (NOLOAD) : { _bss_start = .; *(.bss*) *(.sbss*) *(COMMON) . = ALIGN(4); _bss_end = .; } > RAM
 _stack_top = ORIGIN(RAM) + LENGTH(RAM);
 ASSERT(_bss_end < _stack_top - 4096, "firmware leaves less than 4 KiB stack")
}
