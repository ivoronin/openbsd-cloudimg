#!/usr/bin/env -S uv run
# /// script
# requires-python = ">=3.11"
# ///
import argparse
import platform
from pathlib import Path


ARCHES = ("amd64", "arm64")


def first_existing(paths):
    for path in paths:
        if Path(path).exists():
            return path
    return ""


def host_arch():
    machine = platform.machine()
    if machine == "x86_64":
        return "amd64"
    if machine in ("aarch64", "arm64"):
        return "arm64"
    return machine


def efi_code_paths(arch):
    if arch == "arm64":
        return [
            "/opt/homebrew/share/qemu/edk2-aarch64-code.fd",
            "/usr/share/qemu/edk2-aarch64-code.fd",
            "/usr/share/AAVMF/AAVMF_CODE.fd",
        ]
    return [
        "/opt/homebrew/share/qemu/edk2-x86_64-code.fd",
        "/usr/share/qemu/edk2-x86_64-code.fd",
        "/usr/share/OVMF/OVMF_CODE_4M.fd",
        "/usr/share/OVMF/OVMF_CODE.fd",
    ]


def efi_vars_paths(arch):
    if arch == "arm64":
        return [
            "/opt/homebrew/share/qemu/edk2-arm-vars.fd",
            "/usr/share/qemu/edk2-arm-vars.fd",
            "/usr/share/AAVMF/AAVMF_VARS.fd",
        ]
    return [
        "/opt/homebrew/share/qemu/edk2-i386-vars.fd",
        "/usr/share/qemu/edk2-i386-vars.fd",
        "/usr/share/OVMF/OVMF_VARS_4M.fd",
        "/usr/share/OVMF/OVMF_VARS.fd",
    ]


def main(argv=None):
    parser = argparse.ArgumentParser()
    sub = parser.add_subparsers(dest="cmd", required=True)
    sub.add_parser("arch")

    for command in ("accel", "efi-code", "efi-vars"):
        command_parser = sub.add_parser(command)
        command_parser.add_argument("--arch", required=True, choices=ARCHES)

    args = parser.parse_args(argv)
    if args.cmd == "arch":
        print(host_arch())
    elif args.cmd == "accel":
        print("tcg" if args.arch != host_arch() else ("hvf" if platform.system() == "Darwin" else "kvm"))
    elif args.cmd == "efi-code":
        print(first_existing(efi_code_paths(args.arch)))
    elif args.cmd == "efi-vars":
        print(first_existing(efi_vars_paths(args.arch)))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
