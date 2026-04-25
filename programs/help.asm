[BITS 16]
[ORG 0x0000]

start:
	mov si, help
	mov bx, 0x0F
	int 0x21
	retf

help db "                                    SectorOS", 10, 13
     db "                                 Made by Desvor", 10, 13
     db "help - show this menu", 10, 13
     db "hello - gets hello from SectorOS", 10, 13
     db "dir - show files at current directory", 10, 13
     db 0