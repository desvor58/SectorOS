import json
import struct
import sys
import os

SECTOR_SIZE = 512
ENTRY_FORMAT = "<11scHH" 
ENTRY_SIZE = struct.calcsize(ENTRY_FORMAT)
DISK_DATA_FORMAT = "<H11s"
ALIGN_COLUMN = 35  # Ширина колонки для имени с отступом (все стрелки будут тут)

def parse_size(size_str):
    units = {"K": 1024, "M": 1024*1024, "G": 1024*1024*1024}
    unit = size_str[-1].upper()
    if unit in units:
        return int(size_str[:-1]) * units[unit]
    return int(size_str)

def serialize_directory(items, current_sector, disk, indent=""):
    """
    Рекурсивно обрабатывает элементы, записывает их на диск
    и выводит информацию со строгим выравниванием стрелок.
    """
    entries = []
    
    for item in items:
        item_type = item['type']
        name = item['name']
        name_bytes = name.encode('ascii')[:10] + b'\x00'
        padded_name = name_bytes.ljust(11, b'\x00')
        
        if item_type == 'D':
            dir_sector = current_sector
            byte_offset = dir_sector * SECTOR_SIZE
            
            # Формируем красивую строку имени с иконкой и отступом
            display_name = f"{indent}📁 [{item_type}] {name}"
            # Добиваем пробелами до ALIGN_COLUMN для идеального выравнивания
            print(f"{display_name:<{ALIGN_COLUMN}} -> Смещение: 0x{byte_offset:06X} | Размер table: {SECTOR_SIZE} байт")
            
            current_sector += 1
            
            # Рекурсивный обход вложенных элементов
            dir_content, current_sector = serialize_directory(item['data'], current_sector, disk, indent + "    ")
            
            dir_content = dir_content.ljust(SECTOR_SIZE, b'\x00')
            disk.seek(dir_sector * SECTOR_SIZE)
            disk.write(dir_content)
            
            entry = struct.pack(
                ENTRY_FORMAT,
                padded_name,
                b'D',
                dir_sector,
                SECTOR_SIZE
            )
            entries.append(entry)
            
        else:
            file_path = item['data']
            if not os.path.exists(file_path):
                print(f"Error: file {file_path} not found")
                sys.exit(1)
                
            with open(file_path, 'rb') as f:
                content = f.read()
                data_size = len(content)
                
                byte_offset = current_sector * SECTOR_SIZE
                
                icon = "⚙️" if item_type == 'E' else "📄"
                display_name = f"{indent}{icon} [{item_type}] {name}"
                print(f"{display_name:<{ALIGN_COLUMN}} -> Смещение: 0x{byte_offset:06X} | Размер: {data_size} байт")
                
                disk.seek(current_sector * SECTOR_SIZE)
                disk.write(content)
                
                entry = struct.pack(
                    ENTRY_FORMAT,
                    padded_name,
                    item_type.encode('ascii'),
                    current_sector,
                    data_size
                )
                entries.append(entry)
                
                current_sector += (data_size + SECTOR_SIZE - 1) // SECTOR_SIZE
                
    serialized_headers = b"".join(entries)
    if len(serialized_headers) + ENTRY_SIZE <= SECTOR_SIZE:
        serialized_headers += b'\x00' * ENTRY_SIZE
        
    return serialized_headers, current_sector

def build_disk(config_path, output_name):
    if not os.path.exists(config_path):
        print(f"Error: config {config_path} not found")
        return

    with open(config_path, 'r') as f:
        config = json.load(f)

    total_size_bytes = parse_size(config.get('size', '0'))

    with open(output_name, 'wb') as disk:
        boot_path = config.get('boot', 'boot.bin')
        if os.path.exists(boot_path):
            with open(boot_path, 'rb') as boot_f:
                boot_code = boot_f.read(SECTOR_SIZE)
                disk.write(boot_code.ljust(SECTOR_SIZE, b'\x00'))
        else:
            print(f"Warning: {boot_path} not found, filling sector 0 with zeros")
            disk.write(b'\x00' * SECTOR_SIZE)

        disk.seek(1 * SECTOR_SIZE)
        disk.write(b'\x00' * (SECTOR_SIZE * 2))

        root_entries, last_free_sector = serialize_directory(config.get('data', []), 3, disk)

        disk.seek(1 * SECTOR_SIZE)
        start_prog_bytes = config.get('start_prog', 'help').encode('ascii')[:10] + b'\x00'
        disk.write(struct.pack(DISK_DATA_FORMAT, last_free_sector, start_prog_bytes.ljust(11, b'\x00')))

        disk.seek(2 * SECTOR_SIZE)
        disk.write(root_entries.ljust(SECTOR_SIZE, b'\x00'))

        if total_size_bytes > 0:
            disk.truncate(total_size_bytes)

    print("\n--- Итоговый статус ---")
    print(f"Образ '{output_name}' успешно создан ({config.get('size', 'auto')})")
    print(f"Последний свободный сектор: {last_free_sector} (Байт: {last_free_sector * SECTOR_SIZE})")

if __name__ == "__main__":
    if len(sys.argv) < 3:
        print("Usage: python3 script.py <config.json> <output_disk.img>")
    else:
        build_disk(sys.argv[1], sys.argv[2])