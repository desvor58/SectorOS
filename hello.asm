[BITS 16]
[ORG 0x0000]

start:
	mov si, msg
	mov bx, 0x0F
	int 0x21
	retf

msg db "Hello, world, from program", 10, 13, 0
