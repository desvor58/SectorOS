import json
import struct
import sys
import os

SECTOR_SIZE = 512
# Формат заголовка файла: 11 байт имя, 1 байт тип, 2 байта старт, 2 байта размер
ENTRY_FORMAT = "<11scHH" 
ENTRY_SIZE = struct.calcsize(ENTRY_FORMAT)
# Формат SFSDiskData: u16 last_free_sector
DISK_DATA_FORMAT = "<H"

def build_disk(config_path, output_name):
    if not os.path.exists(config_path):
        print(f"Error: config {config_path} not found")
        return

    with open(config_path, 'r') as f:
        config = json.load(f)

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
        # Просто заполняем их нулями, чтобы переместить указатель на Сектор 3
        disk.write(b'\x00' * (SECTOR_SIZE * 2))

        # 3. Записываем данные файлов (начиная с сектора 3)
        current_sector = 3
        entries = []

        for item in config.get('disk', []):
            file_path = item['data']
            if not os.path.exists(file_path):
                print(f"Error: file {file_path} not found")
                exit(1)

            with open(file_path, 'rb') as f:
                data = f.read()
                data_size = len(data)

                # Переходим к началу нужного сектора и пишем данные
                disk.seek(current_sector * SECTOR_SIZE)
                disk.write(data)

                # Формируем запись для таблицы заголовков
                name_bytes = item['name'].encode('ascii')[:10] + b'\x00'
                entry = struct.pack(
                    ENTRY_FORMAT,
                    name_bytes.ljust(11, b'\x00'),
                    item['type'].encode('ascii'),
                    current_sector,
                    data_size
                )
                entries.append(entry)

                # Вычисляем следующий свободный сектор
                current_sector += (data_size + SECTOR_SIZE - 1) // SECTOR_SIZE

        # 4. Заполняем Сектор 1: SFSDiskData (last_free_sector)
        disk.seek(1 * SECTOR_SIZE)
        disk.write(struct.pack(DISK_DATA_FORMAT, current_sector))

        # 5. Заполняем Сектор 2: FileHeadersTable
        disk.seek(2 * SECTOR_SIZE)
        for entry in entries:
            disk.write(entry)
        
        # Маркер конца таблицы (нулевая структура), если влезет в сектор
        if (len(entries) + 1) * ENTRY_SIZE <= SECTOR_SIZE:
            disk.write(b'\x00' * ENTRY_SIZE)

    print(f"Created '{output_name}'")
    print(f"Files: {len(entries)}")
    print(f"Last free sector recorded: {current_sector}")

if __name__ == "__main__":
    if len(sys.argv) < 3:
        print("Usage: python3 script.py <config.json> <output_disk.img>")
    else:
        build_disk(sys.argv[1], sys.argv[2])