[BITS 16]
[ORG 0x0000]

start:
	mov si, msg
	mov bx, 0x0F
	call print
	retf

msg db "Hello world, from program", 10, 13, 0


%include "./programs/inc/sstd.inc"
USE_PRINT
