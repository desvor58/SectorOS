import json
import struct
import sys
import os

SECTOR_SIZE = 512
ENTRY_FORMAT = "<11scHH" 
ENTRY_SIZE = struct.calcsize(ENTRY_FORMAT)
DISK_DATA_FORMAT = "<H"

def parse_size(size_str):
    """Преобразует строку типа '5K' или '1M' в байты."""
    units = {"K": 1024, "M": 1024*1024, "G": 1024*1024*1024}
    unit = size_str[-1].upper()
    if unit in units:
        return int(size_str[:-1]) * units[unit]
    return int(size_str)

def build_disk(config_path, output_name):
    if not os.path.exists(config_path):
        print(f"Error: config {config_path} not found")
        return

    with open(config_path, 'r') as f:
        config = json.load(f)

    # Определяем итоговый размер диска
    total_size_bytes = parse_size(config.get('size', '0'))

    with open(output_name, 'wb') as disk:
        # 1. Сектор 0: Записываем бут-код (SectorOS)
        if os.path.exists('sos.bin'):
            with open('sos.bin', 'rb') as boot_f:
                boot_code = boot_f.read(SECTOR_SIZE)
                disk.write(boot_code.ljust(SECTOR_SIZE, b'\x00'))
        else:
            print("Warning: sos.bin not found, filling sector 0 with zeros")
            disk.write(b'\x00' * SECTOR_SIZE)

        # 2. Резервируем Сектор 1 (SFSDiskData) и Сектор 2 (FileHeadersTable)
        disk.write(b'\x00' * (SECTOR_SIZE * 2))

        # 3. Записываем данные файлов (начиная с сектора 3)
        current_sector = 3
        entries = []

        # Изменено: теперь берем данные из ключа 'data' вместо 'disk'
        for item in config.get('data', []):
            file_path = item['data']
            if not os.path.exists(file_path):
                print(f"Error: file {file_path} not found")
                sys.exit(1)

            with open(file_path, 'rb') as f:
                content = f.read()
                data_size = len(content)

                disk.seek(current_sector * SECTOR_SIZE)
                disk.write(content)

                name_bytes = item['name'].encode('ascii')[:10] + b'\x00'
                entry = struct.pack(
                    ENTRY_FORMAT,
                    name_bytes.ljust(11, b'\x00'),
                    item['type'].encode('ascii'),
                    current_sector,
                    data_size
                )
                entries.append(entry)

                current_sector += (data_size + SECTOR_SIZE - 1) // SECTOR_SIZE

        # 4. Заполняем Сектор 1: SFSDiskData
        disk.seek(1 * SECTOR_SIZE)
        disk.write(struct.pack(DISK_DATA_FORMAT, current_sector))

        # 5. Заполняем Сектор 2: FileHeadersTable
        disk.seek(2 * SECTOR_SIZE)
        for entry in entries:
            disk.write(entry)
        
        if (len(entries) + 1) * ENTRY_SIZE <= SECTOR_SIZE:
            disk.write(b'\x00' * ENTRY_SIZE)

        # 6. Устанавливаем фиксированный размер диска, если он указан
        if total_size_bytes > 0:
            disk.truncate(total_size_bytes)

    print(f"Created '{output_name}' ({config.get('size', 'auto')})")
    print(f"Files: {len(entries)}")
    print(f"Last free sector recorded: {current_sector}")

if __name__ == "__main__":
    if len(sys.argv) < 3:
        print("Usage: python3 script.py <config.json> <output_disk.img>")
    else:
        build_disk(sys.argv[1], sys.argv[2])