#
# This source file is part of the ENGAGE-HF-AI-Voice open source project
#
# SPDX-FileCopyrightText: 2022 Stanford University and the project authors (see CONTRIBUTORS.md)
#
# This file is based on the Vapor template found at https://github.com/vapor/template
#
# SPDX-License-Identifier: MIT
# 

#!/bin/bash

# Script to decrypt AES-GCM encrypted JSON files
# Usage: ./decrypt_files.sh <base64_encryption_key>

set -e  # Exit on any error

# Check if key argument is provided
if [ $# -eq 0 ]; then
    echo "Usage: $0 <base64_encryption_key>"
    echo "Example: $0 'your_base64_key_here'"
    exit 1
fi

ENCRYPTION_KEY="$1"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DECRYPTED_DIR="$SCRIPT_DIR/decrypted"

# Source folders to process
FOLDERS=("vital_signs" "kccq12_questionnairs" "q17")

# Check if Python3 and cryptography are available
if ! command -v python3 &> /dev/null; then
    echo "Error: python3 is required but not installed."
    exit 1
fi

# Check if cryptography library is available
python3 -c "from cryptography.hazmat.primitives.ciphers.aead import AESGCM" 2>/dev/null || {
    echo "Error: Python cryptography library is required."
    echo "Install it with: pip3 install cryptography"
    exit 1
}

# Create decrypted directory if it doesn't exist
mkdir -p "$DECRYPTED_DIR"

# Function to decrypt a single file
decrypt_file() {
    local input_file="$1"
    local output_file="$2"
    
    echo "Decrypting: $input_file -> $output_file"
    
    # Create output directory if it doesn't exist
    mkdir -p "$(dirname "$output_file")"
    
    # Decrypt using Python
    python3 -c "
import base64
import sys
from cryptography.hazmat.primitives.ciphers.aead import AESGCM

try:
    # Decode the encryption key
    key = base64.b64decode('$ENCRYPTION_KEY')
    
    # Read the encrypted file
    with open('$input_file', 'rb') as f:
        encrypted_data = f.read()
    
    # Check if file is empty
    if len(encrypted_data) < 28:  # minimum size for AES-GCM (12 byte nonce + 16 byte tag)
        print('Error: File too small to be valid AES-GCM encrypted data', file=sys.stderr)
        sys.exit(1)
    
    # Decrypt using AES-GCM
    aesgcm = AESGCM(key)
    nonce = encrypted_data[:12]  # First 12 bytes are the nonce
    ciphertext_and_tag = encrypted_data[12:]  # Rest is ciphertext + authentication tag
    
    decrypted = aesgcm.decrypt(nonce, ciphertext_and_tag, None)
    
    # Write decrypted content to output file
    with open('$output_file', 'w', encoding='utf-8') as f:
        f.write(decrypted.decode('utf-8'))
    
    print('Successfully decrypted: $input_file')
    
except Exception as e:
    print(f'Failed to decrypt $input_file: {e}', file=sys.stderr)
    sys.exit(1)
"
    
    if [ $? -ne 0 ]; then
        echo "Error: Failed to decrypt $input_file"
        return 1
    fi
}

# Main processing
total_files=0
processed_files=0
failed_files=0

echo "Starting decryption process..."
echo "Source directory: $SCRIPT_DIR"
echo "Output directory: $DECRYPTED_DIR"
echo ""

# Process each folder
for folder in "${FOLDERS[@]}"; do
    source_folder="$SCRIPT_DIR/$folder"
    dest_folder="$DECRYPTED_DIR/$folder"
    
    if [ ! -d "$source_folder" ]; then
        echo "Warning: Source folder '$source_folder' does not exist, skipping..."
        continue
    fi
    
    echo "Processing folder: $folder"
    
    # Find all JSON files in the source folder and its subfolders
    while IFS= read -r -d '' file; do
        # Get relative path from source folder
        rel_path="${file#$source_folder/}"
        
        # Create corresponding output path
        output_file="$dest_folder/$rel_path"
        
        total_files=$((total_files + 1))
        
        if decrypt_file "$file" "$output_file"; then
            processed_files=$((processed_files + 1))
        else
            failed_files=$((failed_files + 1))
        fi
        
    done < <(find "$source_folder" -name "*.json" -type f -print0)
done

echo ""
echo "Decryption complete!"
echo "Total files found: $total_files"
echo "Successfully processed: $processed_files"
echo "Failed: $failed_files"

if [ $failed_files -gt 0 ]; then
    echo "Some files failed to decrypt. Check the error messages above."
    exit 1
fi

echo "All files successfully decrypted to: $DECRYPTED_DIR"
