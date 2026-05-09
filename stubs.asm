; stubs.asm - Felix OS Module Stubs + Shell
[BITS 64]
[DEFAULT REL]

extern fsol_signal_main
extern fsol_signal_os
extern fsol_signal_os1
extern fsol_signal_tty

section .text

global fsol_vga
global fsol_ui
global fsol_i915
global fsol_tty
global fsol_list
global fsol_keyboard
global fsol_cmd_dispatch
global fsol_disk
global fsol_checkcurdir
global fsol_changedir
global fsol_insp_load
global fsol_insp_pci
global fsol_insp_disk
global fsol_run
global fsol_os_register
global fsol_wm

; ---- VGA constants ----
VGA         equ 0xB8000
COLS        equ 80
ROWS        equ 25

; ---- stubs ----
fsol_i915:
fsol_vga:
fsol_ui:
fsol_os_register:
    ret

; ================================================================
; TTY entry point
; ================================================================
fsol_tty:
    ; clear screen first
    mov rdi, VGA
    mov rcx, COLS * ROWS
    mov ax, 0x0700
.cl:
    mov [rdi], ax
    add rdi, 2
    loop .cl

    ; init and draw WM frame
    mov byte [wm_win_count], 1
    mov byte [wm_focus], 0
    mov byte [wm_workspace], 1
    mov byte [wm_shift], 0
    call wm_draw_frame

    ; prompt starts inside win1 border: row 2, col 1
    mov qword [cur_row], 2
    mov qword [cur_col], 1

    ; print first prompt
    call new_prompt

    ; enter keyboard loop
    call fsol_keyboard
    ret

; ================================================================
; new_prompt: print "User > " on current row, update cur_col
; ================================================================
new_prompt:
    push rbx
    ; compute VGA address for cur_row
    mov rax, [cur_row]
    mov rcx, COLS * 2
    mul rcx
    add rax, VGA
    mov rbx, rax

    lea rsi, [prompt]
    mov ah, 0x07
.lp: mov al, [rsi]
    test al, al
    jz .done
    mov [rbx], ax
    add rbx, 2
    inc rsi
    jmp .lp
.done:
    ; cur_col = 1 (border) + 7 (prompt length) = 8
    mov qword [cur_col], 8
    ; update hardware cursor
    call update_cursor
    pop rbx
    ret

; ================================================================
; update_cursor: move VGA hardware cursor to cur_row, cur_col
; ================================================================
update_cursor:
    push rax
    push rcx
    push rdx
    ; pos = row*80 + col
    mov eax, dword [cur_row]
    mov ecx, COLS
    imul eax, ecx
    add eax, dword [cur_col]
    ; high byte
    mov rdx, 0x3D4
    mov al, 0x0E
    out dx, al
    inc rdx
    mov eax, dword [cur_row]
    mov ecx, COLS
    imul eax, ecx
    add eax, dword [cur_col]
    shr eax, 8
    out dx, al
    ; low byte
    dec rdx
    mov al, 0x0F
    out dx, al
    inc rdx
    mov eax, dword [cur_row]
    mov ecx, COLS
    imul eax, ecx
    add eax, dword [cur_col]
    and eax, 0xFF
    out dx, al
    pop rdx
    pop rcx
    pop rax
    ret

; ================================================================
; scroll_up: scroll all rows up by 1, clear last row
; ================================================================
scroll_up:
    push rax
    push rcx
    push rsi
    push rdi
    ; copy rows 1..ROWS-1 to rows 0..ROWS-2
    mov rsi, VGA + COLS*2   ; source row 1
    mov rdi, VGA            ; dest   row 0
    mov rcx, (ROWS-1)*COLS
.sc: mov ax, [rsi]
    mov [rdi], ax
    add rsi, 2
    add rdi, 2
    loop .sc
    ; clear last row
    mov rcx, COLS
    mov ax, 0x0700
.cl: mov [rdi], ax
    add rdi, 2
    loop .cl
    pop rdi
    pop rsi
    pop rcx
    pop rax
    ret

; ================================================================
; print_line: print rdi string on cur_row in color ah, then
;             advance cur_row (scroll if needed)
; ================================================================
print_line:
    push rbx
    push rsi
    mov rsi, rdi
    ; compute row address
    mov rax, [cur_row]
    mov rcx, COLS * 2
    mul rcx
    add rax, VGA
    mov rbx, rax
.lp: mov al, [rsi]
    test al, al
    jz .done
    mov [rbx], ax
    add rbx, 2
    inc rsi
    jmp .lp
.done:
    ; advance row
    inc qword [cur_row]
    cmp qword [cur_row], ROWS - 1
    jl .no_scroll
    ; scroll and stay on last usable row
    call scroll_up
    dec qword [cur_row]
.no_scroll:
    pop rsi
    pop rbx
    ret

; ================================================================
; keyboard loop
; ================================================================
fsol_keyboard:
    push rbx
    push r12
    push r13
    push r14

    lea r13, [input_buf]    ; current write pos in buffer
    lea r14, [input_buf]    ; buffer base

.loop:
    ; wait for PS/2 data
    in  al, 0x64
    test al, 1
    jz  .loop

    in  al, 0x60

    ; ignore key release (bit 7)
    test al, 0x80
    jnz .loop

    ; save scancode
    mov bl, al

    ; flush any remaining bytes in PS/2 buffer
.flush:
    in  al, 0x64
    test al, 1
    jz  .flushed
    in  al, 0x60
    jmp .flush
.flushed:
    mov al, bl              ; restore our scancode

    ; check for extended key prefix (E0 = Super, arrows etc)
    cmp al, 0xE0
    je  .extended_key

    ; check for extended key prefix (E0 = Super, arrows etc)
    cmp al, 0xE0
    je  .extended_key

    ; also check left shift (0x2A) for Super+Shift combos
    cmp al, 0x2A
    je  .shift_pressed

.normal_key:
    ; convert scancode to ASCII
    movzx rbx, al
    lea rcx, [scanmap]
    mov al, [rcx + rbx]
    test al, al
    jz  .loop

    cmp al, 0x0D            ; Enter
    je  .enter

    cmp al, 0x08            ; Backspace
    je  .backspace

    ; printable — don't overflow buffer
    mov rcx, r13
    sub rcx, r14
    cmp rcx, 77
    jge .loop

    ; store in buffer
    mov [r13], al
    inc r13

    ; save char on stack before mul destroys rax
    movzx rax, al
    push rax                ; save ASCII char

    ; compute VGA address
    mov rax, [cur_row]
    imul rax, COLS * 2
    add rax, VGA
    mov rbx, rax
    mov rax, [cur_col]
    imul rax, 2
    add rbx, rax

    pop rax                 ; restore ASCII char into al
    mov ah, 0x07
    mov [rbx], ax
    inc qword [cur_col]
    call update_cursor
    jmp .loop

.backspace:
    ; can't go before prompt col 8
    cmp qword [cur_col], 8
    jle .loop
    dec qword [cur_col]
    dec r13
    ; erase on screen
    mov rax, [cur_row]
    mov rcx, COLS * 2
    mul rcx
    add rax, VGA
    mov rbx, rax
    mov rcx, [cur_col]
    lea rbx, [rbx + rcx*2]
    mov word [rbx], 0x0720
    call update_cursor
    jmp .loop

.enter:
    ; null terminate
    mov byte [r13], 0

    ; echo the command on its own line then advance
    ; (already visible, just move to next row)
    inc qword [cur_row]
    cmp qword [cur_row], ROWS - 1
    jl .no_scroll_enter
    call scroll_up
    dec qword [cur_row]
.no_scroll_enter:

    ; dispatch command
    lea rdi, [input_buf]
    call fsol_cmd_dispatch

    ; reset buffer
    lea r13, [input_buf]

    ; print new prompt
    call new_prompt
    jmp .loop

; ---- WM: extended key (E0 prefix = Super/arrows) ----
.extended_key:
.ext_wait:
    in  al, 0x64
    test al, 1
    jz  .ext_wait
    in  al, 0x60
    test al, 0x80
    jnz .loop
    cmp al, 0x5B        ; left Super
    jne .loop
    cmp byte [wm_shift], 1
    je  .super_shift
    ; Super alone = cycle focus
    movzx rax, byte [wm_focus]
    inc al
    movzx rcx, byte [wm_win_count]
    cmp al, cl
    jl  .sf
    xor al, al
.sf:mov [wm_focus], al
    call wm_draw_frame
    jmp .loop
.super_shift:
.ss_wait:
    in  al, 0x64
    test al, 1
    jz  .ss_wait
    in  al, 0x60
    test al, 0x80
    jnz .loop
    cmp al, 0x03
    je  .ws2
    cmp al, 0x04
    je  .ws3
    jmp .loop
.ws2:
    mov byte [wm_workspace], 2
    mov byte [wm_shift], 0
    call wm_clear_all
    call wm_draw_frame
    call new_prompt
    jmp .loop
.ws3:
    mov byte [wm_workspace], 3
    mov byte [wm_shift], 0
    call wm_clear_all
    call wm_draw_frame
    call new_prompt
    jmp .loop
.shift_pressed:
    mov byte [wm_shift], 1
    jmp .loop

    jmp .loop

    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; ================================================================
; command dispatcher
; ================================================================
fsol_cmd_dispatch:
    push r15
    mov r15, rdi

    lea rsi, [cmd_ls]
    mov rdi, r15
    call strcmp64
    jz .ls

    lea rsi, [cmd_lsblk]
    mov rdi, r15
    call strcmp64
    jz .lsblk

    lea rsi, [cmd_pwd]
    mov rdi, r15
    call strcmp64
    jz .pwd

    lea rsi, [cmd_cd]
    mov rdi, r15
    call strcmp64
    jz .cd

    ; unknown
    lea rdi, [msg_unknown]
    mov ah, 0x0C            ; red
    call print_line
    jmp .done

.ls:
    lea rdi, [msg_ls]
    mov ah, 0x0A
    call print_line
    jmp .done

.lsblk:
    lea rdi, [msg_lsblk]
    mov ah, 0x0A
    call print_line
    jmp .done

.pwd:
    lea rdi, [msg_pwd]
    mov ah, 0x0A
    call print_line
    jmp .done

.cd:
    lea rdi, [msg_cd]
    mov ah, 0x0E
    call print_line

.done:
    pop r15
    ret

; ================================================================
; strcmp: rdi=s1 rsi=s2, ZF=1 if equal
; ================================================================
strcmp64:
    push rbx
.lp:
    mov al, [rdi]
    mov bl, [rsi]
    cmp al, bl
    jne .ne
    test al, al
    jz  .eq
    inc rdi
    inc rsi
    jmp .lp
.eq: xor al, al
    pop rbx
    ret
.ne: or al, 1
    pop rbx
    ret

; ================================================================
; stubs
; ================================================================
fsol_list:
fsol_disk:
fsol_checkcurdir:
fsol_changedir:
fsol_run:
    ret

fsol_insp_load:
fsol_insp_pci:
fsol_insp_disk:
    xor al, al
    ret

; ================================================================
; WM - Felix OS Window Manager
; Implements wm.fsol:
;   - tiling layout (1/2/3/4 windows)
;   - Super key focus switching
;   - Workspace switching (Super+Shift+2/3)
;   - PS/2 cursor (.)
; ================================================================

; WM constants
WM_ATTR_FOCUS   equ 0x0B    ; cyan - focused window title
WM_ATTR_UNFOCUS equ 0x07    ; grey - unfocused window
WM_ATTR_TOPBAR  equ 0x70    ; black on grey - top bar
WM_ATTR_BORDER  equ 0x08    ; dark grey border

; box drawing chars (CP437)
CHAR_TL  equ 0xC9           ; ╔
CHAR_TR  equ 0xBB           ; ╗
CHAR_BL  equ 0xC8           ; ╚
CHAR_BR  equ 0xBC           ; ╝
CHAR_H   equ 0xCD           ; ═
CHAR_V   equ 0xBA           ; ║
CHAR_ML  equ 0xCC           ; ╠
CHAR_MR  equ 0xB9           ; ╣
CHAR_MT  equ 0xCB           ; ╦
CHAR_MB  equ 0xCA           ; ╩
CHAR_MM  equ 0xCE           ; ╬

fsol_wm:
    ; init WM state
    mov byte [wm_win_count], 1
    mov byte [wm_focus], 0
    mov byte [wm_workspace], 1
    mov byte [wm_shift], 0
    ; draw frame then return - keyboard loop handles WM input
    call wm_draw_frame
    ret

; ----------------------------------------------------------------
; wm_clear_all: clear entire screen
; ----------------------------------------------------------------
wm_clear_all:
    mov rdi, VGA
    mov rcx, COLS * ROWS
    mov ax, 0x0720
.cl:
    mov [rdi], ax
    add rdi, 2
    loop .cl
    ret

; ----------------------------------------------------------------
; wm_draw_char: draw char al with attr ah at row rcx, col rdx
; ----------------------------------------------------------------
wm_draw_char:
    push rax
    push rbx
    push rcx
    push rdx
    mov rbx, rcx
    imul rbx, COLS * 2
    add rbx, VGA
    imul rdx, 2
    add rbx, rdx
    mov [rbx], ax
    pop rdx
    pop rcx
    pop rbx
    pop rax
    ret

; ----------------------------------------------------------------
; wm_draw_hline: draw horizontal line
;   al=char, ah=attr, rcx=row, rdx=start col, r8=length
; ----------------------------------------------------------------
wm_draw_hline:
    push rbx
    push rcx
    push rdx
    push r8
    mov rbx, rcx
    imul rbx, COLS * 2
    add rbx, VGA
    imul rdx, 2
    add rbx, rdx
.hl:
    mov [rbx], ax
    add rbx, 2
    dec r8
    jnz .hl
    pop r8
    pop rdx
    pop rcx
    pop rbx
    ret

; ----------------------------------------------------------------
; wm_draw_vline: draw vertical line
;   al=char, ah=attr, rcx=start row, rdx=col, r8=height
; ----------------------------------------------------------------
wm_draw_vline:
    push rbx
    push rcx
    push r8
    mov rbx, rcx
    imul rbx, COLS * 2
    add rbx, VGA
    push rdx
    imul rdx, 2
    add rbx, rdx
    pop rdx
.vl:
    mov [rbx], ax
    add rbx, COLS * 2
    dec r8
    jnz .vl
    pop r8
    pop rcx
    pop rbx
    ret

; ----------------------------------------------------------------
; wm_draw_topbar: draw top status bar
; ----------------------------------------------------------------
wm_draw_topbar:
    push rbx
    push rcx
    ; clear top bar
    mov rdi, VGA
    mov rcx, COLS
    mov ax, WM_ATTR_TOPBAR << 8 | ' '
.cl:
    mov [rdi], ax
    add rdi, 2
    loop .cl
    ; print "Felix OS WM" on top bar
    mov rbx, VGA
    lea rsi, [wm_title]
    mov ah, WM_ATTR_TOPBAR
.lp:
    mov al, [rsi]
    test al, al
    jz .done
    mov [rbx], ax
    add rbx, 2
    inc rsi
    jmp .lp
.done:
    ; print workspace number top right
    mov rbx, VGA + (COLS - 14) * 2
    lea rsi, [wm_ws_label]
    mov ah, WM_ATTR_TOPBAR
.ws:
    mov al, [rsi]
    test al, al
    jz .wsdone
    mov [rbx], ax
    add rbx, 2
    inc rsi
    jmp .ws
.wsdone:
    ; print workspace number
    mov rbx, VGA + (COLS - 2) * 2
    movzx rax, byte [wm_workspace]
    add al, '0'
    mov ah, WM_ATTR_TOPBAR
    mov [rbx], ax
    pop rcx
    pop rbx
    ret

; ----------------------------------------------------------------
; wm_draw_window: draw a single window border
;   r12=row, r13=col, r14=width, r15=height, bl=focused
;   rsi=title string
; ----------------------------------------------------------------
wm_draw_window:
    push rax
    push rbx
    push rcx
    push rdx
    push r8

    ; choose attribute
    test bl, bl
    mov ah, WM_ATTR_UNFOCUS
    jz .attr_set
    mov ah, WM_ATTR_FOCUS
.attr_set:
    ; top-left corner
    mov al, CHAR_TL
    mov rcx, r12
    mov rdx, r13
    call wm_draw_char

    ; top-right corner
    mov al, CHAR_TR
    mov rcx, r12
    mov rdx, r13
    add rdx, r14
    dec rdx
    call wm_draw_char

    ; bottom-left corner
    mov al, CHAR_BL
    mov rcx, r12
    add rcx, r15
    dec rcx
    mov rdx, r13
    call wm_draw_char

    ; bottom-right corner
    mov al, CHAR_BR
    mov rcx, r12
    add rcx, r15
    dec rcx
    mov rdx, r13
    add rdx, r14
    dec rdx
    call wm_draw_char

    ; top horizontal line
    mov al, CHAR_H
    mov rcx, r12
    mov rdx, r13
    inc rdx
    mov r8, r14
    sub r8, 2
    call wm_draw_hline

    ; bottom horizontal line
    mov al, CHAR_H
    mov rcx, r12
    add rcx, r15
    dec rcx
    mov rdx, r13
    inc rdx
    mov r8, r14
    sub r8, 2
    call wm_draw_hline

    ; left vertical line
    mov al, CHAR_V
    mov rcx, r12
    inc rcx
    mov rdx, r13
    mov r8, r15
    sub r8, 2
    call wm_draw_vline

    ; right vertical line
    mov al, CHAR_V
    mov rcx, r12
    inc rcx
    mov rdx, r13
    add rdx, r14
    dec rdx
    mov r8, r15
    sub r8, 2
    call wm_draw_vline

    ; print title on top border
    mov rbx, r12
    imul rbx, COLS * 2
    add rbx, VGA
    mov rcx, r13
    inc rcx
    imul rcx, 2
    add rbx, rcx
    test bl, bl
    mov ah, WM_ATTR_FOCUS
    jnz .title_lp
    mov ah, WM_ATTR_UNFOCUS
.title_lp:
    mov al, [rsi]
    test al, al
    jz .title_done
    mov [rbx], ax
    add rbx, 2
    inc rsi
    jmp .title_lp
.title_done:

    pop r8
    pop rdx
    pop rcx
    pop rbx
    pop rax
    ret

; ----------------------------------------------------------------
; wm_draw_frame: draw all windows based on wm_win_count
; ----------------------------------------------------------------
wm_draw_frame:
    push rbx
    push r12
    push r13
    push r14
    push r15

    call wm_draw_topbar

    movzx rax, byte [wm_win_count]
    cmp al, 1
    je  .one_win
    cmp al, 2
    je  .two_win
    cmp al, 3
    je  .three_win
    jmp .four_win

.one_win:
    ; win1: full screen minus top bar
    ; row=1, col=0, w=80, h=24
    mov r12, 1
    mov r13, 0
    mov r14, 80
    mov r15, 24
    movzx rbx, byte [wm_focus]
    mov bl, 1              ; always focused
    lea rsi, [win1_title]
    call wm_draw_window
    jmp .done

.two_win:
    ; win1: left half row=1 col=0 w=40 h=24
    mov r12, 1
    mov r13, 0
    mov r14, 40
    mov r15, 24
    movzx rbx, byte [wm_focus]
    cmp bl, 0
    sete bl
    lea rsi, [win1_title]
    call wm_draw_window

    ; win2: right half row=1 col=40 w=40 h=24
    mov r12, 1
    mov r13, 40
    mov r14, 40
    mov r15, 24
    movzx rbx, byte [wm_focus]
    cmp bl, 1
    sete bl
    lea rsi, [win2_title]
    call wm_draw_window
    jmp .done

.three_win:
    ; win1: top left row=1 col=0 w=26 h=13
    mov r12, 1
    mov r13, 0
    mov r14, 26
    mov r15, 13
    movzx rbx, byte [wm_focus]
    cmp bl, 0
    sete bl
    lea rsi, [win1_title]
    call wm_draw_window

    ; win2: bottom left row=13 col=0 w=26 h=12
    mov r12, 13
    mov r13, 0
    mov r14, 26
    mov r15, 12
    movzx rbx, byte [wm_focus]
    cmp bl, 1
    sete bl
    lea rsi, [win2_title]
    call wm_draw_window

    ; win3: right row=1 col=26 w=54 h=24
    mov r12, 1
    mov r13, 26
    mov r14, 54
    mov r15, 24
    movzx rbx, byte [wm_focus]
    cmp bl, 2
    sete bl
    lea rsi, [win3_title]
    call wm_draw_window
    jmp .done

.four_win:
    ; win1: top left row=1 col=0 w=40 h=13
    mov r12, 1
    mov r13, 0
    mov r14, 40
    mov r15, 13
    movzx rbx, byte [wm_focus]
    cmp bl, 0
    sete bl
    lea rsi, [win1_title]
    call wm_draw_window

    ; win2: bottom left row=13 col=0 w=40 h=12
    mov r12, 13
    mov r13, 0
    mov r14, 40
    mov r15, 12
    movzx rbx, byte [wm_focus]
    cmp bl, 1
    sete bl
    lea rsi, [win2_title]
    call wm_draw_window

    ; win3: top right row=1 col=40 w=40 h=13
    mov r12, 1
    mov r13, 40
    mov r14, 40
    mov r15, 13
    movzx rbx, byte [wm_focus]
    cmp bl, 2
    sete bl
    lea rsi, [win3_title]
    call wm_draw_window

    ; win4: bottom right row=13 col=40 w=40 h=12
    mov r12, 13
    mov r13, 40
    mov r14, 40
    mov r15, 12
    movzx rbx, byte [wm_focus]
    cmp bl, 3
    sete bl
    lea rsi, [win4_title]
    call wm_draw_window

.done:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; ================================================================
section .data

banner:  db 'Felix OS v0.1 - Felix OS Language (FSOL)', 0
prompt:  db 'User > ', 0

cmd_ls:    db 'ls', 0
cmd_lsblk: db 'lsblk', 0
cmd_pwd:   db 'pwd', 0
cmd_cd:    db 'cd', 0

msg_ls:     db 'file1.fsol  file2.fsol  mainOS.fsol', 0
msg_lsblk:  db 'sda    8G   disk', 0
msg_pwd:    db '/root', 0
msg_cd:     db 'cd: not yet implemented', 0
msg_unknown:db '?: unknown command', 0

; WM strings
wm_title:    db 'Felix OS WM', 0
wm_ws_label: db 'Workspace ', 0
win1_title:  db ' Shell ', 0
win2_title:  db ' Win 2 ', 0
win3_title:  db ' Win 3 ', 0
win4_title:  db ' Win 4 ', 0

; PS/2 scancode set 1 → ASCII
; scancode: 00   01    02  03  04  05  06  07  08  09  0A  0B  0C  0D  0E    0F
scanmap:   db 0, 0,   '1','2','3','4','5','6','7','8','9','0','-','=',0x08, 0x09
;          10   11   12   13   14   15   16   17   18   19   1A   1B   1C    1D
           db 'q','w','e','r','t','y','u','i','o','p','[',']', 0x0D, 0
;          1E   1F   20   21   22   23   24   25   26   27    28    29
           db 'a','s','d','f','g','h','j','k','l',';', 0x27, '`',  0
;          2B    2C   2D   2E   2F   30   31   32   33   34   35   36
           db 0x5C,'z','x','c','v','b','n','m',',','.','/',  0
;          37  38  39    3A  3B  3C  3D  3E  3F  40  41  42  43  44  45  46
           db 0,  0,  ' ', 0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0
           times 128 db 0

; ================================================================
section .bss

cur_row:      resq 1
cur_col:      resq 1
input_buf:    resb 80
wm_win_count: resb 1
wm_focus:     resb 1
wm_workspace: resb 1
wm_shift:     resb 1
