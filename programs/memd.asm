[BITS 16]
[ORG 0x0000]

start:
    mov ax, 0x0000
    mov es, ax

    mov si, 0x600
    mov cx, 0x100

.lp:
    mov ax, [es:si]
    mov bl, ah
    mov ah, al
    mov al, bl
    call print_ax_hex
    add si, 2
    loop .lp

	retf


%include "./programs/inc/sstd.inc"
USE_PRINT
USE_PRINT_AX_HEX
