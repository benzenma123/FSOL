# Felix OS

A real bootable x86-64 operating system written in **FSOL** (Felix OS Language) — a programming language designed specifically for OS development.

> Built from scratch: custom language, custom compiler, custom bootloader, bare metal kernel.

![License](https://img.shields.io/badge/license-MIT-blue)
![Language](https://img.shields.io/badge/language-FSOL-green)
![Platform](https://img.shields.io/badge/platform-x86--64-orange)
<img width="1920" height="1080" alt="20260509_17h46m49s_grim" src="https://github.com/user-attachments/assets/921ea2a5-6cf1-424f-b4fb-1a5ed114fb5d" />

---

## What is FSOL?

FSOL (Felix OS Language) is a programming language built for writing operating systems. Unlike C or Rust, FSOL uses plain English-like keywords that describe hardware behavior directly:

```
broadcast os1 -> tty       # start the terminal
rei os1 from OS() { ... }  # receive signal and run
dis VGA 0x100              # write to display
call insp-load check()     # inspect if hardware loaded
```

FSOL compiles to real x86-64 assembly — no runtime, no garbage collector, no OS underneath it.

---

## Features

- **FSOL Compiler** — full lexer, parser, and x86-64 code generator written in Rust
- **Custom Bootloader** — hand-written 16-bit → 32-bit → 64-bit mode transition, no GRUB needed
- **Bare Metal Kernel** — compiled directly from FSOL source code
- **Working Shell** — `ls`, `pwd`, `lsblk`, `cd` commands
- **PS/2 Keyboard Driver** — reads directly from hardware port `0x60`
- **Window Manager** — tiling WM layout with workspaces (aesthetic mode)
- **VGA Text Mode** — 80×25 character display with box-drawing borders

---

## Project Structure

```
felix-os/
├── src/
│   ├── main.rs       # compiler entry point
│   ├── lexer.rs      # tokenizer — turns .fsol into tokens
│   ├── parser.rs     # parser — turns tokens into AST
│   └── codegen.rs    # code generator — AST → x86-64 NASM assembly
├── Cargo.toml        # Rust project config
├── bootloader.asm    # BIOS bootloader (16/32/64-bit mode switch)
├── stubs.asm         # hardware driver implementations
├── linker.ld         # linker script — places kernel at 0x100000
├── build.sh          # one-command build script
├── mainOS.fsol       # main OS source in FSOL
├── wm.fsol           # window manager source in FSOL
└── examples/
    └── hello.fsol    # minimal hello world example
```

---

## Getting Started

### Requirements

- Rust + Cargo
- NASM
- QEMU
- Python 3
- GNU ld (binutils)

On Gentoo/Arch:
```bash
sudo emerge nasm qemu
# or
sudo pacman -S nasm qemu
```

On Ubuntu/Debian:
```bash
sudo apt install nasm qemu-system-x86 binutils python3
```

### Build and Run

```bash
git clone https://github.com/benzenma123/FSOL
cd FSOL
chmod +x build.sh
./build.sh
qemu-system-x86_64 -fda felixOS.img -m 256M -no-reboot
```

That's it. Felix OS boots in QEMU.

---

## How It Works

### Boot sequence

```
BIOS loads bootloader.bin at 0x7C00
  → bootloader switches 16-bit real mode → 32-bit protected mode → 64-bit long mode
    → kernel copied to 0x100000 (1MB)
      → _start runs (compiled from mainOS.fsol)
        → drivers load via i915
          → insp-load checks all modules
            → TTY starts, WM draws borders
              → shell prompt appears
                → keyboard loop reads PS/2 port 0x60
```

### Compiler pipeline

```
mainOS.fsol
  → Lexer  (262 tokens)
  → Parser (AST)
  → CodeGen (x86-64 NASM assembly)
  → NASM assembler → .o object file
  → GNU ld + linker.ld → kernel.elf
  → objcopy → kernel.bin
  → cat bootloader.bin + kernel.bin → felixOS.img
```

---

## FSOL Language Reference

### Keywords

| Keyword | Meaning |
|---------|---------|
| `int` | Initiate/open a function or module block |
| `call` | Invoke a module or driver |
| `rei` | Receive a broadcast signal (one time) |
| `broadcast` | Send a one-time startup signal |
| `wait` | Keep listening for signals |
| `dis` | Display/write to VGA address |
| `export` | Push something to another module |
| `imp` | Import a module into a context |
| `insp` | Inspector — validates hardware |
| `check` | Validation tool, child of insp |
| `take` | Grab and pipe to another module |
| `run` | Execute directly |
| `import` | Load a module from another file |
| `command` | TTY-only shell command registry |
| `func` | Declare a function mapping |
| `broadcast` | One-time startup handshake |

### Example program

```fsol
import VGA, Panic, UI, OS, i915, tty

int main() {
    call i915() {
        func: imp UI -> OS
        func: imp Panic -> OS
        func: imp VGA -> OS
    }
    int OS() {
        rei main func() {
            call insp-load check() {
                if:
                    all func: load = false
                try:
                    call Panic() { dis VGA 0x7 }
                else if:
                    all func: load = true
                    broadcast os1 -> tty
            }
        }
        int TTY() {
            rei os1 from OS() {
                dis VGA 0x100
                func(print{"User >"})
            }
        }
    }
}
```

---

## Shell Commands

| Command | Description |
|---------|-------------|
| `ls` | List files |
| `lsblk` | List disk devices |
| `pwd` | Print current directory |
| `cd` | Change directory |

---

## Window Manager

Felix OS includes a tiling window manager inspired by Hyprland/i3.

**Keybinds** (Super = Windows key):

| Keybind | Action |
|---------|--------|
| `Super` | Cycle window focus |
| `Super + Enter` | Open terminal |
| `Super + Q` | Close window |
| `Super + Shift + 2` | Switch to workspace 2 |
| `Super + Shift + 3` | Switch to workspace 3 |

**Tiling layouts:**

```
1 window:   full screen
2 windows:  50/50 split
3 windows:  two left + one right (layout A)
4 windows:  four equal quadrants
```

---

## Roadmap

- [ ] Fix codegen to remove manual build patches
- [ ] Shell text constrained inside window borders
- [ ] Multiple terminal instances in separate windows
- [ ] FAT12 filesystem (real ls/pwd/cd)
- [ ] Mouse support
- [ ] Shift/Caps Lock keyboard support
- [ ] VESA framebuffer (graphics mode)
- [ ] Intel/AMD native display drivers
- [ ] More shell commands (clear, echo, help)

---

## Learn FSOL

A beginner course document is included in the repo (`FSOL_Course.docx`) covering:

- What is FSOL and why it exists
- All 18 FSOL keywords explained
- Program structure and module hierarchy  
- The signal system (broadcast/rei/wait)
- Building a shell from scratch
- Writing your first FSOL program

---

## Contributing

Felix OS and FSOL are early stage projects. Contributions welcome!

- Found a bug? Open an issue at [github.com/benzenma123/FSOL](https://github.com/benzenma123/FSOL)
- Want to add a command? Fork and PR
- Writing FSOL programs? Share them!

---

## License

MIT License — do whatever you want with it, just give credit.

---

*Built with FSOL — Felix OS Language. Bare metal, designed for humans.*
