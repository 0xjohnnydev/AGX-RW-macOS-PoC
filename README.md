# AGX R/W macOS PoC

AGX firmware read/write on select Macs running macOS 27.0.1 build 26A434.
KextRW drives the command path. Published in case it helps with an SPTM bypass.

## PoCs

| Executable | What it does |
| --- | --- |
| `gfx-read-poc` | Reads aligned 64-bit values from mapped AGX firmware addresses. |
| `gfx-write-poc` | Writes through DropMDSID. [Panic](evidence/panics/panic-full-2026-10-26-030748.0002.panic) |
| `gfx-auth-call-poc` | Calls an existing PAC-signed firmware callback with a controlled object. [Panic](evidence/panics/panic-full-2026-10-26-164043.0002.panic) |
| `gfx-pac-reuse-poc` | Reuses two existing PAC-signed pointers through compatible `BLRAAZ` call sites. |
| `micro-ppl-ttbr1-probe` | Changes a protected GFX leaf PTE. SAPT blocks the selected physical transaction. [Panic](evidence/panics/panic-full-2026-10-26-135909.0002.panic) |

KextRW prepares and drives the command path, then reads the result back. AGX
firmware performs the source reads and target writes. This is GFX virtual
read/write, not standalone KRW or an SPTM bypass.

## Hardware

Among the build 26A434 firmware reviewed, DropMDSID appeared only on:

| Hardware | Status |
| --- | --- |
| M4 Max MacBook Pro and Mac Studio | Static only |
| M4 Pro MacBook Pro and Mac mini | Static only |
| M5 MacBook Pro and MacBook Air | Static only |
| MacBook Neo | Works on hardware |

`Static only` means the primitive was found and a profile was built, but the
PoC has not run on that hardware. `gfx-read-poc` is profiled for every row.
The other binaries are currently MacBook Neo-only.

No matching primitive was found in the base M4 Mac mini, the reviewed M2
families, or the M3 Ultra Mac Studio. Other macOS 27 builds are not covered.

## Build

Build [KextRW](https://github.com/0xjohnnydev/KextRW), then place this
repository next to it and run:

```sh
make
```

For another KextRW location:

```sh
make KEXTRW=/path/to/KextRW
```

Executables are written to `build/`.

## Run

Core modes:

```sh
./build/gfx-read-poc control
./build/gfx-read-poc marker
./build/gfx-read-poc read 0xfffffc000008c320
```

MacBook Neo-only modes:

```sh
./build/gfx-write-poc
./build/gfx-auth-call-poc check
./build/gfx-auth-call-poc control
./build/gfx-auth-call-poc treatment
./build/gfx-pac-reuse-poc control
./build/gfx-pac-reuse-poc treatment
```

Protected GFX PTE modes:

```sh
./build/micro-ppl-ttbr1-probe --page-a
./build/micro-ppl-ttbr1-probe --cleanup
./build/micro-ppl-ttbr1-probe --page-b
./build/micro-ppl-ttbr1-probe --cleanup
./build/micro-ppl-ttbr1-probe --map-41410000
./build/micro-ppl-ttbr1-probe --unmap
./build/micro-ppl-ttbr1-probe --touch-41410000
```

`gfx-write-poc` and `--touch-41410000` panic and reboot the Mac. Reboot after
either authenticated-callback `control` or `treatment` run.

## Credit

[AlfieCG](https://github.com/alfiecg24) for
[KextRW](https://github.com/alfiecg24/KextRW) and the original DropMDSID
implementation in [Titan](https://github.com/alfiecg24/Titan).
