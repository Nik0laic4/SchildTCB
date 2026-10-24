#!/usr/bin/env python3
import os
import json
import zlib
import base64
import hashlib

TARGET_DIR = os.path.expanduser('~/Desktop/Schild TCB')
OUTPUT_FILE = os.path.expanduser('~/Desktop/Schild TCB_Diagnostic_Kit/schild_b64_snapshot.txt')

def calculate_sha256(filepath):
    h = hashlib.sha256()
    try:
        with open(filepath, 'rb') as f:
            while chunk := f.read(8192):
                h.update(chunk)
        return h.hexdigest()
    except Exception:
        return "ERROR"

def get_file_content(filepath):
    try:
        with open(filepath, 'r', encoding='utf-8', errors='ignore') as f:
            return f.read()
    except Exception:
        return ""

def generate_snapshot():
    if not os.path.exists(TARGET_DIR):
        print(f"[-] Error: Directory {TARGET_DIR} not found.")
        return

    snapshot = {
        "project": "Schild TCB",
        "structure": {},
        "files_data": {}
    }

    for root, dirs, files in os.walk(TARGET_DIR):
        if any(ignored in root for ignored in ['obj', '.alire', '.git']):
            continue

        rel_path = os.path.relpath(root, TARGET_DIR)
        if rel_path == ".":
            rel_path = "root"

        valid_files = [f for f in files if f.endswith(('.ads', '.adb', '.gpr', '.md', '.ld', '.S', '.txt'))]
        
        if valid_files:
            snapshot["structure"][rel_path] = valid_files

            for file in valid_files:
                full_path = os.path.join(root, file)
                file_key = os.path.relpath(full_path, TARGET_DIR)
                snapshot["files_data"][file_key] = {
                    "sha256": calculate_sha256(full_path),
                    "content": get_file_content(full_path)
                }

    json_bytes = json.dumps(snapshot, ensure_ascii=False).encode('utf-8')
    compressed_bytes = zlib.compress(json_bytes, level=9)
    b64_encoded = base64.b64encode(compressed_bytes).decode('utf-8')

    with open(OUTPUT_FILE, 'w', encoding='utf-8') as out_f:
        out_f.write(b64_encoded)

    print(f"[+] Snapshot created successfully: {OUTPUT_FILE}")
    print(f"[+] Monolithic string size: {len(b64_encoded) / 1024:.2f} KB")

if __name__ == "__main__":
    generate_snapshot()
