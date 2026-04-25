import json
import struct
import sys
import os

SECTOR_SIZE = 512
# Формат: 11 байт имя, 1 байт тип, 2 байта старт, 2 байта размер
ENTRY_FORMAT = "<11scHH" 
ENTRY_SIZE = struct.calcsize(ENTRY_FORMAT)

def build_disk(config_path, output_name):
    with open(config_path, 'r') as f:
        config = json.load(f)

    with open(output_name, 'wb') as disk:
        # 1. Записываем бут-код (sos.bin)
        if os.path.exists('sos.bin'):
            with open('sos.bin', 'rb') as boot_f:
                boot_code = boot_f.read(SECTOR_SIZE)
                disk.write(boot_code.ljust(SECTOR_SIZE, b'\x00'))
        else:
            print("Warning: sos.bin not found, filling with zeros")
            disk.write(b'\x00' * SECTOR_SIZE)

        # 2. Резервируем место под таблицу (сектор 1)
        table_offset = disk.tell()
        disk.write(b'\x00' * SECTOR_SIZE)

        # 3. Записываем файлы (начиная с сектора 2)
        current_sector = 2
        entries = []

        for item in config.get('disk', []):
            file_path = item['data']
            if not os.path.exists(file_path):
                print(f"Error: file {file_path} not found")
                exit(1)

            with open(file_path, 'rb') as f:
                data = f.read()
                data_size = len(data)

                # Переходим к началу нужного сектора
                disk.seek(current_sector * SECTOR_SIZE)
                disk.write(data)

                # Формируем запись для таблицы
                # Имя дополняется нулями до 11 байт
                name_bytes = item['name'].encode('ascii')[:10] + b'\x00'
                entry = struct.pack(
                    ENTRY_FORMAT,
                    name_bytes.ljust(11, b'\x00'),
                    item['type'].encode('ascii'),
                    current_sector,
                    data_size
                )
                entries.append(entry)

                # Считаем следующий свободный сектор (выравнивание)
                current_sector += (data_size + SECTOR_SIZE - 1) // SECTOR_SIZE

        # 4. Возвращаемся и записываем таблицу файлов
        disk.seek(table_offset)
        for entry in entries:
            disk.write(entry)
        
        # Нулевая структура в конце таблицы
        disk.write(b'\x00' * ENTRY_SIZE)

    print(f"Created '{output_name}' with {len(entries)} files.")

if __name__ == "__main__":
    if len(sys.argv) < 3:
        print("Usage: python3 script.py <config.json> <output_disk.img>")
    else:
        build_disk(sys.argv[1], sys.argv[2])
