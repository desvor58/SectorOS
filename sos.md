# SectorOperationSystem
SOS - its an experimental OS, writen at nasm.
SOS works **full at boot sector**

# Interupts
## 0x20 CLEAR
> clearing display  \
> **destruct** - ax, bx, cx, dx

## 0x21 PRINT
> print string from ds:si to \0. \
> **ds** - segment of string.  \
> **si** - pointer to string.  \
> **bx** - color and page.  \
> **destruct** - ax, si

## 0x22 READ
> read string from user to *end char* and write to buffer with \0 to the end.  \
> **es** - segment of buffer.  \
> **di** - pointer to buffer.  \
> **destruct** - ax, cx, di

# File system
```
1 sector - SectorOS

struct {
	char     file_name[11];	   // null-terminated name
	uint8_t  file_type;        // E - executable, F - text file, D - directory
	uint16_t data_start_sec;   // number of file sector
	uint16_t data_size; 	   // size of text
} tbl[];

files data...
```

# Memory map
```
0x0000:0x0000
     ???
0x0000:0x7C00
   SectorOS
0x1000:0x0000
     PLS      (executable programs loads hear)
0x2000:0x0000
	  ^
	  | SectorOS/PLS stack
0x2000:0xFFFE
```

