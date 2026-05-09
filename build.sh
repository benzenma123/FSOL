#!/bin/bash
# Felix OS Build Script
set -e

echo "=== Felix OS Build System ==="
echo ""

echo "[1/5] Compiling FSOL source..."
cargo run mainOS.fsol

# patch 1: call fsol_tty and fsol_wm before halt
sed -i 's/; kernel halt loop/call fsol_wm\n    call fsol_tty\n    ; kernel halt loop/' mainOS.asm

# patch 2: add extern for fsol_cmd_dispatch and fsol_wm
sed -i '/^extern fsol_changedir$/a extern fsol_cmd_dispatch\nextern fsol_wm' mainOS.asm

# patch 3: replace fsol_commandfunction body with jmp
python3 - << 'PYEOF'
with open('mainOS.asm', 'r') as f:
    lines = f.readlines()

out = []
skip = False
for i, line in enumerate(lines):
    if line.strip() == 'fsol_commandfunction:':
        out.append(line)
        out.append('    jmp fsol_cmd_dispatch\n')
        skip = True
        continue
    if skip:
        if line.strip().startswith('fsol_commandfunction.done'):
            skip = False
        continue
    out.append(line)

with open('mainOS.asm', 'w') as f:
    f.writelines(out)
PYEOF

echo "      mainOS.asm patched"

echo "[2/5] Assembling..."
nasm -f bin   bootloader.asm -o bootloader.bin
nasm -f elf64 stubs.asm      -o stubs.o
nasm -f elf64 mainOS.asm     -o mainOS.o
echo "      all objects ready"

echo "[3/5] Linking kernel..."
ld -T linker.ld mainOS.o stubs.o -o kernel.elf
objcopy -O binary kernel.elf kernel.bin
echo "      kernel.bin created"

echo "[4/5] Building disk image..."
dd if=/dev/zero of=felixOS.img bs=512 count=65536 2>/dev/null
dd if=bootloader.bin of=felixOS.img bs=512 count=1 conv=notrunc 2>/dev/null
dd if=kernel.bin of=felixOS.img bs=512 seek=1 conv=notrunc 2>/dev/null
echo "      felixOS.img created"

echo ""
echo "[5/5] Build complete!"
ls -lh felixOS.img kernel.bin
echo ""
echo "Run: qemu-system-x86_64 -fda felixOS.img -m 256M -no-reboot"
