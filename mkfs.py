# этот скрипт был безжалостно навайбкожен, прошу онять и простить,
# мне было жесть как лень писать его самому

import json
import struct
import sys
import os

SECTOR_SIZE = 512
# 11 байт имя, 1 байт тип, 2 байта старт, 2 байта размер
ENTRY_FORMAT = "<11scHH" 
ENTRY_SIZE = struct.calcsize(ENTRY_FORMAT)
DISK_DATA_FORMAT = "<H"

def build_disk(config_path, output_name):
    if not os.path.exists(config_path):
        print(f"Error: config {config_path} not found")
        return

    with open(config_path, 'r') as f:
        config = json.load(f)

    with open(output_name, 'wb') as disk:
        # Предварительно расширяем файл, чтобы можно было использовать seek()
        disk.write(b'\x00' * (SECTOR_SIZE * 3))
        
        current_sector = 3

        def process_items(items):
            nonlocal current_sector
            local_entries = []

            for item in items:
                name = item['name']
                f_type = item['type']
                
                if f_type == 'D':
                    # 1. Резервируем сектор под таблицу этой директории
                    dir_table_sector = current_sector
                    current_sector += 1
                    
                    # 2. Рекурсивно собираем содержимое папки
                    # Данные файлов внутри папки будут писаться в сектора начиная с current_sector
                    sub_entries = process_items(item['data'])
                    
                    # 3. Записываем таблицу этой директории в зарезервированный сектор
                    saved_pos = disk.tell()
                    disk.seek(dir_table_sector * SECTOR_SIZE)
                    for e in sub_entries:
                        disk.write(e)
                    # Маркер конца таблицы внутри папки
                    if len(sub_entries) * ENTRY_SIZE < SECTOR_SIZE:
                        disk.write(b'\x00' * ENTRY_SIZE)
                    
                    disk.seek(saved_pos)
                    
                    start_sec = dir_table_sector
                    data_size = 0 # Для директорий размер обычно 0 или игнорируется
                else:
                    # Обычный файл
                    file_path = item['data']
                    if not os.path.exists(file_path):
                        print(f"Error: file {file_path} not found")
                        sys.exit(1)
                        
                    with open(file_path, 'rb') as f:
                        content = f.read()
                        data_size = len(content)
                        start_sec = current_sector
                        
                        disk.seek(start_sec * SECTOR_SIZE)
                        disk.write(content)
                        
                        # Вычисляем сколько секторов занял файл
                        current_sector += (data_size + SECTOR_SIZE - 1) // SECTOR_SIZE

                # Формируем структуру заголовка
                name_bytes = name.encode('ascii')[:10] + b'\x00'
                entry = struct.pack(
                    ENTRY_FORMAT,
                    name_bytes.ljust(11, b'\x00'),
                    f_type.encode('ascii'),
                    start_sec,
                    data_size
                )
                local_entries.append(entry)
            
            return local_entries

        # Собираем все, начиная с корня
        root_entries = process_items(config.get('disk', []))

        # Записываем системные сектора
        # Сектор 0: Bootloader
        disk.seek(0)
        if os.path.exists('sos.bin'):
            with open('sos.bin', 'rb') as boot_f:
                disk.write(boot_f.read(SECTOR_SIZE).ljust(SECTOR_SIZE, b'\x00'))

        # Сектор 1: SFSDiskData
        disk.seek(1 * SECTOR_SIZE)
        disk.write(struct.pack(DISK_DATA_FORMAT, current_sector))

        # Сектор 2: Корневая таблица (Root FHT)
        disk.seek(2 * SECTOR_SIZE)
        for entry in root_entries:
            disk.write(entry)
        if len(root_entries) * ENTRY_SIZE < SECTOR_SIZE:
            disk.write(b'\x00' * ENTRY_SIZE)

    print(f"Образ '{output_name}' готов.")
    print(f"Всего занято секторов: {current_sector}")

if __name__ == "__main__":
    if len(sys.argv) < 3:
        print("Использование: python script.py config.json disk.img")
    else:
        build_disk(sys.argv[1], sys.argv[2])