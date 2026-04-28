[BITS 16]
[ORG 0x0000]

start:
    xor ax, ax
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
    
; ax - num
print_ax_hex:
    push bp
    mov bp, sp
    pusha              ; Сохраняем все регистры

    sub sp, 6          ; Выделяем место под строку (4 знака + \0 + выравнивание)
    mov di, sp         ; DI указывает на начало временного буфера

    mov cx, 4          ; 4 цифры
    mov bx, ax         ; Копируем число в BX, чтобы работать с ним
.loop:
    rol bx, 4          ; Берем старшую тетраду
    mov al, bl
    and al, 0Fh
    add al, '0'
    cmp al, '9'
    jbe .store
    add al, 7
.store:
    mov [di], al       ; Кладем символ в буфер
    inc di
    loop .loop

    mov byte [di], 0   ; Добавляем нуль-терминатор (\0) для INT 0x21

    ; Подготовка к вызову INT 0x21
    mov si, sp         ; DS:SI — указатель на нашу строку в стеке
    mov bx, 0x0F         ; BX - цвет и страница (по умолчанию 0)
    int 0x21           ; Вывод строки

    add sp, 6          ; Очищаем буфер в стеке
    popa
    pop bp
    ret