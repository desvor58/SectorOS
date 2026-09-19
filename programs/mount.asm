[BITS 16]
[ORG 0x0000]

start:
    xor ax, ax
    mov es, ax
    mov si, 0x500

    call skip_prog_name
    jc list_mode

    mov di, dir_buf
    call read_arg
    jc list_mode

    mov di, idx_buf
    call read_arg
    jc usage

do_mount:
    mov si, idx_buf
    call parse_hex
    mov [disk_idx], al

    mov dl, [disk_idx]
    call disk_present
    jc err_nodisk

    call resolve_current
    jc err_de

    mov si, dir_buf
.nav_loop:
    mov di, namebuf
    call copy_comp
    jc .last

    call find_entry
    jc err_pnf
    call nav_into
    jc err_de
    jmp .nav_loop

.last:
    cmp byte [namebuf], 0
    jz usage

    call find_entry
    jc .create

    mov al, [es:si+11]
    cmp al, 'M'
    jz .write_mnt
    cmp al, 'D'
    jz .write_mnt
    jmp err_notdir

.create:
    call find_free
    jc err_full

    push si
    mov cx, 11
    xor bx, bx
.cp_name:
    mov al, [namebuf+bx]
    mov [es:si+bx], al
    inc bx
    loop .cp_name
    pop si

.write_mnt:
    mov al, [disk_idx]
    mov byte [es:si+11], 'M'
    xor ah, ah
    mov word [es:si+12], ax
    mov word [es:si+14], 0

    mov ax, [fht_sec]
    mov dl, [cur_disk]
    call write_sec
    jc err_de

    mov bx, 0x0F
    mov si, msg_ok_mnt
    call print
    mov si, dir_buf
    call print
    mov si, msg_ok_to
    call print
    mov al, [disk_idx]
    call print_disk_idx
    mov si, newline
    call print
    retf


list_mode:
    mov bx, 0x0F
    mov si, msg_header
    call print

    call walk_mounted

    mov byte [dl_cur], 0
.disk_loop:
    mov dl, [dl_cur]
    call disk_present
    jc .disk_next

    mov bx, 0x0F
    mov si, msg_disk_item
    call print
    mov al, [dl_cur]
    call print_disk_idx

    cmp byte [es:0x6FD], al
    jnz .not_boot
    mov si, msg_boot
    call print
.not_boot:

    mov dl, [dl_cur]
    call is_mounted
    test al, al
    jz .not_mounted
    mov si, msg_stat_mnt
    call print
    jmp .disk_next
.not_mounted:
    mov si, msg_stat_not
    call print
.disk_next:
    inc byte [dl_cur]
    jnz .disk_loop
    retf


usage:
    mov bx, 0x04
    mov si, msg_usage
    call print
    retf

err_nodisk:
    mov bx, 0x04
    mov si, msg_nodisk
    call print
    retf

err_pnf:
    mov bx, 0x04
    mov si, msg_pnf
    call print
    retf

err_notdir:
    mov bx, 0x04
    mov si, msg_notdir
    call print
    retf

err_full:
    mov bx, 0x04
    mov si, msg_full
    call print
    retf

err_de:
    mov bx, 0x04
    mov si, msg_de
    call print
    retf


; es:si = cmdline; out: si = start of first arg; CF=1 if no args
skip_prog_name:
.lp:
    mov al, [es:si]
    test al, al
    jz .none
    cmp al, ' '
    jz .skip
    inc si
    jmp .lp
.skip:
    inc si
.lp2:
    mov al, [es:si]
    cmp al, ' '
    jnz .ok
    inc si
    jmp .lp2
.ok:
    clc
    ret
.none:
    stc
    ret


; es:si = input; ds:di = buf; out: si past arg; CF=1 if no token, buf null-terminated
read_arg:
    mov bx, di
.skip:
    mov al, [es:si]
    test al, al
    jz .none
    cmp al, ' '
    jnz .got
    inc si
    jmp .skip
.got:
.copy:
    mov al, [es:si]
    test al, al
    jz .done
    cmp al, ' '
    jz .space
    mov [di], al
    inc di
    inc si
    jmp .copy
.space:
    inc si
.done:
    xor al, al
    mov [di], al
    mov di, bx
    clc
    ret
.none:
    mov di, bx
    stc
    ret


; es:si = path; ds:di = 11-byte zero-padded namebuf; out: si past comp+sep
; CF=1 if ended at null, CF=0 if ended at '/'
copy_comp_es:
    push ax
    push cx
    push bx
    mov bp, di
    mov cx, 11
    xor al, al
.zfill:
    mov [di], al
    inc di
    loop .zfill
    mov di, bp
    xor bx, bx
.copy:
    mov al, [es:si]
    test al, al
    jz .null
    cmp al, '/'
    jz .sep
    cmp bl, 11
    jae .skip
    mov [di], al
    inc di
    inc bl
.skip:
    inc si
    jmp .copy
.sep:
    inc si
    clc
    jmp .done
.null:
    stc
.done:
    mov di, bp
    pop bx
    pop cx
    pop ax
    ret


; ds:si = path; ds:di = 11-byte zero-padded namebuf; out: si past comp+sep
; CF=1 if ended at null, CF=0 if ended at '/'
copy_comp:
    push ax
    push cx
    push bx
    mov bp, di
    mov cx, 11
    xor al, al
.zfill:
    mov [di], al
    inc di
    loop .zfill
    mov di, bp
    xor bx, bx
.copy:
    mov al, [si]
    test al, al
    jz .null
    cmp al, '/'
    jz .sep
    cmp bl, 11
    jae .skip
    mov [di], al
    inc di
    inc bl
.skip:
    inc si
    jmp .copy
.sep:
    inc si
    clc
    jmp .done
.null:
    stc
.done:
    mov di, bp
    pop bx
    pop cx
    pop ax
    ret


; es=0; FHT at 0x800; ds:di = 11-byte name; out: CF=0, es:si = entry
find_entry:
    mov si, 0x800
.lp:
    cmp byte [es:si], 0
    jz .nf
    push si
    push di
    mov cx, 11
.cmp:
    mov al, [di]
    cmp al, [es:si]
    jnz .next
    inc di
    inc si
    loop .cmp
    pop di
    pop si
    clc
    ret
.next:
    pop di
    pop si
    add si, 0x10
    jmp .lp
.nf:
    stc
    ret


; es=0; out: CF=0, es:si = free slot; CF=1 table full
find_free:
    mov si, 0x800
    mov cx, 32
.lp:
    cmp byte [es:si], 0
    jz .free
    add si, 0x10
    loop .lp
    stc
    ret
.free:
    clc
    ret


; es:si = entry (type D or M); updates cur_disk/fht_sec, loads FHT at 0x800
nav_into:
    mov al, [es:si+11]
    cmp al, 'D'
    jz .dir
    cmp al, 'M'
    jz .mount
    stc
    ret
.dir:
    mov ax, [es:si+12]
    mov [fht_sec], ax
    mov dl, [cur_disk]
    call load_sec
    ret
.mount:
    mov al, [es:si+12]
    mov [cur_disk], al
    mov word [fht_sec], 2
    mov dl, [cur_disk]
    mov ax, 2
    call load_sec
    ret


; loads current dir (0x60D path) FHT at 0x800; sets cur_disk/fht_sec; CF=1 err
resolve_current:
    mov al, [es:0x6FE]
    mov [cur_disk], al
    cmp byte [es:0x60D], 0
    jz .root
    mov si, 0x60D
.rep:
    mov di, namebuf
    call copy_comp_es
    call find_entry
    jc .err
    call nav_into
    jc .err
    cmp byte [es:si], 0
    jz .ok
    jmp .rep
.root:
    mov word [fht_sec], 2
    mov dl, [cur_disk]
    mov ax, 2
    call load_sec
    jc .err
.ok:
    clc
    ret
.err:
    stc
    ret


; ds:si = hex str ("0xNN" or plain); out: al
parse_hex:
    push dx
    xor al, al
    cmp byte [si], '0'
    jne .pfx_done
    mov dl, [si+1]
    cmp dl, 'x'
    jz .pfx_skip
    cmp dl, 'X'
    jnz .pfx_done
.pfx_skip:
    add si, 2
.pfx_done:
    xor dx, dx
.loop:
    mov dl, [si]
    test dl, dl
    jz .done
    cmp dl, ' '
    jz .done
    cmp dl, '9'
    jbe .dec
    and dl, 0xDF
    sub dl, 'A' - 10
    jmp .have
.dec:
    sub dl, '0'
.have:
    shl al, 4
    or al, dl
    inc si
    jmp .loop
.done:
    pop dx
    ret


; dl = disk; out: CF=1 if absent
disk_present:
    mov ah, 0x41
    mov bx, 0x55AA
    int 0x13
    jc .no
    cmp bx, 0xAA55
    jne .no
    clc
    ret
.no:
    stc
    ret


; dl = disk; al = 1 if mounted else 0
is_mounted:
    push bx
    push cx
    push di
    mov cl, [mnt_cnt]
    test cl, cl
    jz .no
    mov di, mnt_buf
.cmp:
    cmp dl, [di]
    jz .yes
    inc di
    dec cl
    jnz .cmp
.no:
    xor al, al
    jmp .done
.yes:
    mov al, 1
.done:
    pop di
    pop cx
    pop bx
    ret


; al = disk; add to mnt_buf if not present
add_mounted:
    push ax
    push bx
    push cx
    push di
    mov cl, [mnt_cnt]
    mov di, mnt_buf
    test cl, cl
    jz .add
.cmp:
    cmp al, [di]
    jz .done
    inc di
    dec cl
    jnz .cmp
.add:
    cmp byte [mnt_cnt], 32
    jae .done
    mov [di], al
    inc byte [mnt_cnt]
.done:
    pop di
    pop cx
    pop bx
    pop ax
    ret


; walk current FS tree, collect mounted disk numbers into mnt_buf
walk_mounted:
    push ax
    push bx
    push cx
    push dx
    push si
    push di
    push bp
    xor ax, ax
    mov es, ax
    mov byte [mnt_cnt], 0
    mov al, [es:0x6FE]
    mov [cur_disk], al
    mov word [fht_sec], 2
    mov word [entry_off], 0x0800
    mov word [stk_ptr], wstk
    mov dl, [cur_disk]
    mov ax, 2
    call load_sec
    jc .err
.scan:
    mov si, [entry_off]
    cmp si, 0x0800 + 512
    jae .retrace
    cmp byte [es:si], 0
    jz .retrace
    mov al, [es:si+11]
    cmp al, 'M'
    jz .mount
    cmp al, 'D'
    jz .dir
    jmp .next
.mount:
    mov al, [es:si+12]
    call add_mounted
    jmp .next
.dir:
    mov bx, [stk_ptr]
    cmp bx, wstk_end
    jae .next
    mov al, [cur_disk]
    mov [bx], al
    mov ax, [fht_sec]
    mov [bx+2], ax
    mov ax, [entry_off]
    add ax, 16
    mov [bx+4], ax
    add word [stk_ptr], 6
    mov ax, [es:si+12]
    mov [fht_sec], ax
    mov word [entry_off], 0x0800
    mov dl, [cur_disk]
    call load_sec
    jc .retrace
    jmp .scan
.next:
    add word [entry_off], 16
    jmp .scan
.retrace:
    mov bx, [stk_ptr]
    cmp bx, wstk
    jbe .ok
    sub word [stk_ptr], 6
    mov bx, [stk_ptr]
    mov al, [bx]
    mov [cur_disk], al
    mov ax, [bx+2]
    mov [fht_sec], ax
    mov ax, [bx+4]
    mov [entry_off], ax
    mov dl, [cur_disk]
    mov ax, [fht_sec]
    call load_sec
    jc .err
    jmp .scan
.ok:
    clc
.jret:
    pop bp
    pop di
    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    ret
.err:
    stc
    jmp .jret


; ax = lba, dl = disk; read 1 sector to 0x0800
load_sec:
    pusha
    mov si, DAP
    mov [si+8], ax
    mov word [si+2], 1
    mov word [si+4], 0x0800
    mov word [si+6], 0
    mov ah, 0x42
    int 0x13
    popa
    ret


; ax = lba, dl = disk; write 1 sector from 0x0800
write_sec:
    pusha
    mov si, DAP
    mov [si+8], ax
    mov word [si+2], 1
    mov word [si+4], 0x0800
    mov word [si+6], 0
    mov ah, 0x43
    mov al, 0
    int 0x13
    popa
    ret


; al = byte; print as 2 hex digits after "0x"
print_disk_idx:
    push ax
    push si
    mov bx, 0x0F
    mov si, msg_prefix
    call print
    pop si
    pop ax
    jmp print_hex_byte


print_hex_byte:
    push ax
    shr al, 4
    call .nib
    pop ax
    and al, 0x0F
.nib:
    add al, '0'
    cmp al, '9'
    jbe .put
    add al, 7
.put:
    mov ah, 0x0E
    mov bx, 0x0F
    int 0x10
    ret


msg_header db "Present disks:", 10, 13, 0
msg_disk_item db "  Disk ", 0
msg_boot db " (boot)", 0
msg_stat_mnt db " mounted", 10, 13, 0
msg_stat_not db " not mounted", 10, 13, 0

msg_ok_mnt db "Mounted ", 0
msg_ok_to db " -> disk ", 0
msg_prefix db "0x", 0

msg_usage db "Usage: mount <dir_name> <disk_index>   |   mount - list disks", 10, 13, 0
msg_nodisk db "Disk not present", 10, 13, 0
msg_pnf db "File not found", 10, 13, 0
msg_notdir db "Its not a directory", 10, 13, 0
msg_full db "Directory is full", 10, 13, 0
msg_de db "Disk error", 10, 13, 0
newline db 10, 13, 0

dir_buf resb 64
idx_buf resb 16
namebuf resb 16
disk_idx resb 1
dl_cur resb 1
cur_disk resb 1
mnt_cnt resb 1
fht_sec resw 1
entry_off resw 1
stk_ptr resw 1
mnt_buf resb 32

align 4
wstk resb 192
wstk_end equ wstk + 192

align 4
DAP:
    db 0x10
    db 0
    dw 1
    dw 0x0800
    dw 0
    dq 2

%include "./programs/inc/sstd.inc"
USE_PRINT