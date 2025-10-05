#!/bin/bash
#
# This source file is part of the ENGAGE-HF-AI-Voice open source project
#
# SPDX-FileCopyrightText: 2022 Stanford University and the project authors (see CONTRIBUTORS.md)
#
# This file is based on the Vapor template found at https://github.com/vapor/template
#
# SPDX-License-Identifier: MIT
#

# Script to decrypt Twilio call recording files
# Usage: ./decrypt_recordings.sh <path to private_key.pem>

set -e  # Exit on any error

# Check if key argument is provided
if [ $# -eq 0 ]; then
    echo "Usage: $0 <private_key.pem>"
    echo "Example: $0 'private_key.pem'"
    exit 1
fi

if [ ! -f "$1" ]; then
    echo "Encryption key file does not exist."
    exit 1
fi

ENCRYPTION_KEY=$(awk '{printf "%s\\n", $0}' "$1")
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DECRYPTED_DIR="$SCRIPT_DIR/decrypted"

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
    local input_wav="$1"
    local output_file="$2"
    
    # Create output directory if it doesn't exist
    mkdir -p "$(dirname "$output_file")"
    
    input_json="${input_wav%.wav}.json"
    
    if [ ! -f "$input_json" ]; then
        cp "$input_wav" "$output_file"
        return
    fi
    
    local cek=$(jq -r '.cek' "$input_json")
    local iv=$(jq -r '.iv' "$input_json")
    
    echo "Decrypting: $input_wav -> $output_file"
    
    
    
    # Decrypt using Python
    python3 -c "
import base64
import sys
from cryptography.hazmat.backends import default_backend
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import padding
from cryptography.hazmat.primitives.ciphers import Cipher, algorithms, modes

try:

    # https://www.twilio.com/docs/voice/tutorials/call-recording-encryption#per-recording-decryption-steps-customer

    # 1) Obtain encrypted_cek, iv parameters within EncryptionDetails via recordingStatusCallback or
    # by performing a GET on the recording resource

    encrypted_cek = '$cek'
    iv = '$iv'

    # 2) Retrieve customer private key corresponding to public_key_sid and use it to decrypt base 64 decoded
    # encrypted_cek via RSAES-OAEP-SHA256-MGF1

    key_bytes = '$ENCRYPTION_KEY'.encode('utf-8')
    key = serialization.load_pem_private_key(key_bytes, password=None, backend=default_backend())

    encrypted_recording_file_path = '$input_wav'
    decrypted_recording_file_path = '$output_file'

    decrypted_cek = key.decrypt(
        base64.b64decode(encrypted_cek),
        padding.OAEP(
            mgf=padding.MGF1(algorithm=hashes.SHA256()),
            algorithm=hashes.SHA256(),
            label=None
        )
    )

    # 3) Initialize a AES256-GCM SecretKey object with decrypted CEK and base 64 decoded iv

    decryptor = Cipher(
        algorithms.AES(decrypted_cek),
        modes.GCM(base64.b64decode(iv)),
        backend=default_backend()
    ).decryptor()

    # 4) Decrypt encrypted recording using the SecretKey

    decrypted_recording_file = open(decrypted_recording_file_path, 'wb')
    encrypted_recording_file = open(encrypted_recording_file_path, 'rb')

    for chunk in iter(lambda: encrypted_recording_file.read(4 * 1024), b''):
        decrypted_chunk = decryptor.update(chunk)
        decrypted_recording_file.write(decrypted_chunk)

    decrypted_recording_file.close()
    encrypted_recording_file.close()
    
except Exception as e:
    print(f'Failed to decrypt $input_wav: {e}', file=sys.stderr)
    sys.exit(1)
"
    
    if [ $? -ne 0 ]; then
        echo "Error: Failed to decrypt $input_wav"
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
source_folder="$SCRIPT_DIR/recordings"
dest_folder="$DECRYPTED_DIR/recordings"

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

done < <(find "$source_folder" -name "*.wav" -type f -print0)

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
