# SectorOperationSystem
SOS - its an experimental OS, writen at nasm.
SOS works **full at boot sector**

# Interupts
## 0x21 GET FILE TEXT
```
in:       ds:si - name of file
          dx - segment to writing
out:      ah - err code
               0 - ok
       	       1 - fnf
       	       2 - de
          al - file type
destruct: es=0, bx, si, di
```

## 0x22 SET FILE TEXT
```
in:       ds:si - name of file
          dx - segment for writing
          cx - size of text in bytes
out:      ah - err code
               0 - ok
               1 - fnf
               2 - de
          al - file type
destruct: es=0, ax, bx, si, di
```

## 0x23 GET FILE HEADER
```
in:       ds:si - name of file
out:      ah - err code
               0 - ok
               1 - fnf
          0x0000:di - file type
destruct: es=0, ax, cx, bx, si
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
    char     file_name[11];	   // null-padded name
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
