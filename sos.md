# SectorOperationSystem
SOS - its an experimental OS, writen at nasm.
SOS works **full at boot sector**

# Interupts
## 0x20 CLEAR
> clearing display  \
> **destruct** - ax, bx, cx, dx

## 0x21 PRINT
> print string from ds:si to \0  \
> **ds:si** - far pointer to string  \
> **bx** - color and page  \
> **destruct** - ax, si

## 0x22 READ
> read string from user to *end char* and write to buffer with \0 to the end  \
> **es:di** - far pointer to buffer  \
> **destruct** - ax, cx, di

## 0x23 GET FILE TEXT
> write file text to segment \
> si - name of file
> es - segment to writing  \
> ret - ah - err code(0 - ok, 1 - fnf, 2 - de), al - file type  \
> **destruct** - ds, ax, bx, si, di

# File system
```
1 sector - SectorOS

struct FileHeader {
	char     file_name[11];	   // null-terminated name
	uint8_t  file_type;        // E - executable, F - text file, D - directory
	uint16_t data_start_sec;   // number of file sector
	uint16_t data_size; 	   // size of text
};

files data...
```

# Memory map
```
    0x00000
      IVT
    0x00400
   BIOS data
    0x00500
 SectorOS data
    0x00600
      FHT         File Headers Table
    0x07C00
	SectorOS
    0x10000
	  ^
	  | SectorOS/PLS stack
    0x20000
      PLS         executable programs loads hear
    0x30000
```
