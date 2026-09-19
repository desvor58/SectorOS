# SectorOperationSystem
SOS - its an experimental OS, written at NASM.
SOS works **full at boot sector**

# Interrupts
## 0x21 GET FILE TEXT
```
in:       ds:si - name of file
          dx - segment to writing
out:      ah - err code
               0 - ok
       	       1 - fnf
       	       2 - de
          al - file type
          bx - file size in bytes
destruct: es=0, ds=0, si, di
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
destruct: es=0, ds=0, ax, bx, si, di
```

## 0x23 GET FILE HEADER
```
in:       ds:si - name of file
out:      ah - err code
               0 - ok
               1 - fnf
          es:di - file type
destruct: es=0, ax, cx, bx, si
```
# File system
```
sector 0:
  SectorOS

sector 1:
  struct SFSDiskData {
    u16  last_free_sector;      // number of last free sector on disk
    char start_prog[11];        // null-padded name of program with start first by SOS itself
    char curend_dir_path[60];   // not used by SOS? but reserved for terminals (sterm for example). null-terminated
  };

sector 2:
  struct FileHeader {
    char     file_name[11];	   // null-padded name
    uint8_t  file_type;        // E - executable, F - text file, D - directory, M - mount point
    uint16_t data_start_sec;   // number of file sector
    uint16_t data_size; 	     // size of text
  } FileHeadersTable[];

sector 3-...:
  files data...
```

## Directory
If file_type == D then data_start_sec point to sector of diractory FHT

## Mount points
If file_type == M then ((u8[2])data_start_sec)[0] contains number of disk

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
      SPL         start program loads here
    0x30000
      PLS         executable programs loads here
```
