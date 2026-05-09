/* linker.ld - Felix OS Kernel */
/* _start MUST be at 0x100000 - that's where bootloader jumps */

ENTRY(_start)

SECTIONS
{
    . = 0x100000;

    .text ALIGN(4096) :
    {
        /* force _start to be very first thing */
        KEEP(*(.text._start))
        *(.text)
    }

    .rodata ALIGN(4096) :
    {
        *(.rodata)
    }

    .data ALIGN(4096) :
    {
        *(.data)
    }

    .bss ALIGN(4096) :
    {
        *(COMMON)
        *(.bss)
    }

    /DISCARD/ :
    {
        *(.comment)
        *(.note*)
    }
}
