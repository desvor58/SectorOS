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
```
in:       es:si - name of file
          dx - segment to writing
out:      ah - err code
               0 - ok
       	       1 - fnf
       	       2 - de
          al - file type
destruct: ds=0, bx, si, di
```

## 0x24 SET FILE TEXT
> write text to file \
> **ds:si** - name of file
> **es** - segment to writing  \
> ret - ah - err code(0 - ok, 1 - fnf, 2 - de), al - file type  \
> **destruct** - ds, ax, bx, si, di

## 0x25 GET FILE HEADER
```
int 0x25
in:       es:si - name of file
out:      ah - err code
               0 - ok
               1 - fnf
          0x0000:di - file type
destruct: ds=0, ax, cx, bx, si
```
# File system
```
sector 0:
  SectorOS

sector 1:
  struct SFSDiskData {
    u16 last_free_sector;
  };

sector 2:
  struct FileHeader {
    char     file_name[11];	   // null-terminated name
    uint8_t  file_type;        // E - executable, F - text file, D - directory
    uint16_t data_start_sec;   // number of file sector
    uint16_t data_size; 	     // size of text
  } FileHeadersTable[];

sector 3-...:
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
     SFSDD        SFS Disk Data
    0x00800
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
