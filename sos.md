# SectorOperationSystem
SOS - its an experimental OS, writen at nasm.
SOS works **full at boot sector**

# Interupts
## 0x20 CLEAR
> clearing display
> **destruct** - ax, bx, cx, dx

## 0x21 PRINT
> print string from ds:si to \0.
> **ds** - segment of string.
> **si** - pointer to string.
> **bx** - color and page.
> **destruct** - ax, si

## 0x22 READ
> read string from user to *end char* and write to buffer with \0 to the end.
> **es** - segment of buffer.
> **di** - pointer to buffer.
> **dl** - end char.
> **destruct** - ax, cx, di

# File system
```
1 sector - SectorOS

struct {
	char     file_name[11];	   // null-terminater name
	uint8_t  file_type;        // E - executble, F - text file, D - directory
	uint16_t data_start_sec;   // number of file sector
	uint16_t data_size; 	   // size of text
} tbl[];

files data...
```

