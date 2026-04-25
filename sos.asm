[BITS 16]
[ORG 0x7C00]

start:
	cli
		xor ax, ax
		mov ds, ax
		mov es, ax
		mov ax, 0x2000
		mov ss, ax
		mov sp, 0xFFFE

		mov word [0x20 * 4], int_clear
		mov word [0x20 * 4 + 2], cs
		mov word [0x21 * 4], int_print
		mov word [0x21 * 4 + 2], cs
		mov word [0x22 * 4], int_read
		mov word [0x22 * 4 + 2], cs
	sti

	int 0x20

	mov si, hello
	mov bx, 0x0F
	int 0x21

	mov ah, 0x42
	mov dl, 0x80
	mov si, DAP_struct
	int 0x13
	jc err_de

shell_loop:
	; clear the cmd
	mov di, cmd
    mov cx, 32
    xor al, al
    rep stosb

    ; read to cmd
	mov di, cmd
	mov dl , 0x0D
	int 0x22
	call printNL

	mov ax, 0x07C0
	mov es, ax
	mov si, 0x200
	mov bx, 11

.search_loop:
	cmp byte [es:si], 0
	jz err_fnf

	mov di, cmd
	push si
	call strcmp
	pop si
	jnc .program_find

	add si, 0x10
	jmp .search_loop

.program_find:
	mov ax, [es:si + 12]
	mov [DAP_struct.sec_ptr], ax
	mov word [DAP_struct.sec_ptr + 2], 0
	mov word [DAP_struct.sec_ptr + 4], 0
	mov word [DAP_struct.sec_ptr + 6], 0
	mov ax, [es:si + 14]
	add ax, 511
	shr ax, 9
	
	xor bx, bx
	mov es, bx
	
	mov [DAP_struct.sec_num], ax
	mov word [DAP_struct.buf_ptr], 0
	mov word [DAP_struct.buf_ptr + 2], 0x1000

	mov ah, 0x42
	mov dl, 0x80
	mov si, DAP_struct
	int 0x13
	jc err_de

	mov ax, 0x1000
	mov ds, ax
	mov es, ax
	call 0x1000:0x0000
	xor ax, ax
	mov ds, ax
	mov es, ax

	jmp shell_loop

err_fnf:
	mov si, err_fnf_text
	mov bx, 0x0F
	int 0x21
    jmp shell_loop

err_de:
    mov si, err_de_text
    mov bx, 0x0F
    int 0x21
    mov al, ah
    mov ah, 0x0E
   	int 0x10
	jmp shell_loop


;0x20
int_clear:
	mov ax, 0x0600
	mov bh, 0x0F
	xor cx, cx
	mov dx, 0x184F
	int 0x10
	mov ah, 0x02
	xor bh, bh
	xor dx, dx
	int 0x10
	iret

; 0x21
int_print:
	mov ah, 0x0E
.put:
	lodsb
	test al, al
	jz .done
	int 0x10
	jmp .put
.done:
	iret

; 0x22
int_read:
	xor cx, cx

.read:
	xor ah, ah
	int 0x16
	cmp al, dl
	jz .done
	cmp al, 0x08
	jz .backspace
	stosb
	mov ah, 0x0E
	int 0x10
	inc cx
	jmp .read

.done:
	mov word [es:di], 0
	iret

.backspace:
	test cx, cx
	jz .read
	mov ah, 0x0E
	int 0x10
	mov al, ' '
	int 0x10
	mov al, 0x08
	int 0x10
	dec di
	dec cx
	jmp .read

printNL:
	mov ah, 0x0E
	mov al, 0x0A
	int 0x10
	mov al, 0x0D
	int 0x10
	ret

; es:si    - 1 str
; ds:di    - 2 str
; bx       - max size
; ret      - set cf if err
; destruct - cx, di, si, al
strcmp:
	xor cx, cx
.ccmp:
	cmp cx, bx
	jz .neq
	
	mov al, [es:si]
	
	cmp al, [di]
	jnz .neq
	
	test al, al
	jz .eq
	
	inc si
	inc di
	inc cx
	jmp .ccmp
	
.neq:
	stc
	ret
	
.eq:
	clc
	ret

hello          db "All good",  10, 13, 0
err_fnf_text   db "ERR: File not found", 10, 13, 0
err_de_text    db "ERR: Disk error", 10, 13, 0
cmd   times 32 db 0

align 4
DAP_struct:
	.DAP_size db 0x10
	.res      db 0x00
	.sec_num  dw 1
	.buf_ptr  dw 0x0200
			  dw 0x07C0
	.sec_ptr  dq 1

times 510 - ($ - $$) db 0
dw 0xAA55
