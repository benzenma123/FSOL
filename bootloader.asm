; Felix OS Bootloader
[BITS 16]
[ORG 0x7C00]

    cli
    xor ax, ax
    mov ds, ax
    mov es, ax
    mov ss, ax
    mov sp, 0x7C00
    sti

    mov si, msg
    call print16

    ; load kernel to 0x10000
    mov ax, 0x1000
    mov es, ax
    xor bx, bx
    mov ah, 0x02
    mov al, 17
    mov ch, 0
    mov cl, 2
    mov dh, 0
    mov dl, 0x00
    int 0x13
    jc  hang

    mov si, msgok
    call print16

    ; enable A20
    in  al, 0x92
    or  al, 2
    out 0x92, al

    cli
    lgdt [gdt_desc]

    mov eax, cr0
    or  al, 1
    mov cr0, eax
    jmp dword 0x08:pm_entry

print16:
    lodsb
    test al, al
    jz .r
    mov ah, 0x0E
    xor bh, bh
    int 0x10
    jmp print16
.r: ret

hang:
    cli
    hlt

msg:    db 'Felix OS', 13, 10, 0
msgok:  db 'OK', 13, 10, 0

align 4
gdt_start:
    dq 0
    dq 0x00CF9A000000FFFF   ; 0x08 code32
    dq 0x00CF92000000FFFF   ; 0x10 data32
    dq 0x00AF9A000000FFFF   ; 0x18 code64
    dq 0x00AF92000000FFFF   ; 0x20 data64
gdt_end:
gdt_desc:
    dw gdt_end - gdt_start - 1
    dd gdt_start

[BITS 32]
pm_entry:
    mov ax, 0x10
    mov ds, ax
    mov ss, ax
    mov es, ax
    mov esp, 0x9F000

    ; mark PM reached
    mov byte [0xB8000], 'P'
    mov byte [0xB8001], 0x0F

    ; copy kernel 0x10000 -> 0x100000
    mov esi, 0x10000
    mov edi, 0x100000
    mov ecx, (17*512)/4
    rep movsd

    ; mark copy done
    mov byte [0xB8002], 'C'
    mov byte [0xB8003], 0x0F

    ; page tables at 0x70000 (well above bootloader/kernel load area)
    ; zero 3 pages
    mov edi, 0x70000
    xor eax, eax
    mov ecx, 0x3000/4
    rep stosd

    ; PML4[0] -> PDP at 0x71000
    mov dword [0x70000], 0x71003
    mov dword [0x70004], 0

    ; PDP[0] -> PD at 0x72000
    mov dword [0x71000], 0x72003
    mov dword [0x71004], 0

    ; PD: 512 x 2MB identity map
    mov edi, 0x72000
    mov eax, 0x00000083
    mov ecx, 0
.map:
    mov [edi], eax
    mov dword [edi+4], 0
    add eax, 0x200000
    add edi, 8
    inc ecx
    cmp ecx, 512
    jl  .map

    ; mark page tables done
    mov byte [0xB8004], 'G'
    mov byte [0xB8005], 0x0F

    ; load CR3
    mov eax, 0x70000
    mov cr3, eax

    ; enable PAE
    mov eax, cr4
    or  eax, 0x20
    mov cr4, eax

    ; enable long mode via EFER
    mov ecx, 0xC0000080
    rdmsr
    or  eax, 0x100
    wrmsr

    ; enable paging
    mov eax, cr0
    or  eax, 0x80000000
    mov cr0, eax

    ; mark long mode enabled
    mov byte [0xB8006], 'L'
    mov byte [0xB8007], 0x0F

    jmp 0x18:lm_entry

[BITS 64]
lm_entry:
    mov ax, 0x20
    mov ds, ax
    mov es, ax
    mov ss, ax
    mov rsp, 0x200000

    mov byte [0xB8008], '6'
    mov byte [0xB8009], 0x0F
    mov byte [0xB800A], '4'
    mov byte [0xB800B], 0x0F

    jmp 0x100000

lm_halt:
    cli
    hlt
    jmp lm_halt

times 510-($-$$) db 0
dw 0xAA55
