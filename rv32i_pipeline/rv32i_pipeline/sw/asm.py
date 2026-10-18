#!/usr/bin/env python3
"""Minimal RV32I assembler (no external toolchain needed - works on Windows).

Usage:  python sw/asm.py sw/test.s sw/test.hex
Supports: all RV32I integer instructions used by the core, labels,
          pseudo-instructions  nop, j label, mv rd,rs, li rd,imm(12-bit)
Registers: x0..x31 (ABI names not supported)
"""
import re, sys

R = {  # name: (funct7, funct3)
    'add': (0x00, 0), 'sub': (0x20, 0), 'sll': (0x00, 1), 'slt': (0x00, 2),
    'sltu': (0x00, 3), 'xor': (0x00, 4), 'srl': (0x00, 5), 'sra': (0x20, 5),
    'or': (0x00, 6), 'and': (0x00, 7)}
I = {'addi': 0, 'slti': 2, 'sltiu': 3, 'xori': 4, 'ori': 6, 'andi': 7}
SH = {'slli': (0x00, 1), 'srli': (0x00, 5), 'srai': (0x20, 5)}
LD = {'lb': 0, 'lh': 1, 'lw': 2, 'lbu': 4, 'lhu': 5}
ST = {'sb': 0, 'sh': 1, 'sw': 2}
BR = {'beq': 0, 'bne': 1, 'blt': 4, 'bge': 5, 'bltu': 6, 'bgeu': 7}


def reg(s):
    m = re.fullmatch(r'x(\d+)', s.strip())
    if not m or int(m.group(1)) > 31:
        raise ValueError(f'bad register {s!r}')
    return int(m.group(1))


def num(s):
    return int(s.strip(), 0)


def enc_i(imm, rs1, f3, rd, op):
    return ((imm & 0xFFF) << 20) | (rs1 << 15) | (f3 << 12) | (rd << 7) | op


def enc_r(f7, rs2, rs1, f3, rd, op):
    return (f7 << 25) | (rs2 << 20) | (rs1 << 15) | (f3 << 12) | (rd << 7) | op


def enc_s(imm, rs2, rs1, f3, op):
    return (((imm >> 5) & 0x7F) << 25) | (rs2 << 20) | (rs1 << 15) | (f3 << 12) | ((imm & 0x1F) << 7) | op


def enc_b(imm, rs2, rs1, f3, op):
    return (((imm >> 12) & 1) << 31) | (((imm >> 5) & 0x3F) << 25) | (rs2 << 20) | (rs1 << 15) | \
           (f3 << 12) | (((imm >> 1) & 0xF) << 8) | (((imm >> 11) & 1) << 7) | op


def enc_j(imm, rd, op):
    return (((imm >> 20) & 1) << 31) | (((imm >> 1) & 0x3FF) << 21) | (((imm >> 11) & 1) << 20) | \
           (((imm >> 12) & 0xFF) << 12) | (rd << 7) | op


def assemble(lines):
    # pass 1: strip comments, collect labels
    prog, labels, pc = [], {}, 0
    for raw in lines:
        line = re.split(r'#|//', raw)[0].strip()
        while ':' in line:
            lab, line = line.split(':', 1)
            labels[lab.strip()] = pc
            line = line.strip()
        if line:
            prog.append((pc, line, raw.rstrip()))
            pc += 4
    # pass 2: encode
    words = []
    for pc, line, raw in prog:
        parts = line.replace(',', ' ').split()
        mn, a = parts[0].lower(), parts[1:]
        if mn == 'nop':
            w = enc_i(0, 0, 0, 0, 0x13)
        elif mn == 'mv':
            w = enc_i(0, reg(a[1]), 0, reg(a[0]), 0x13)
        elif mn == 'li':
            w = enc_i(num(a[1]), 0, 0, reg(a[0]), 0x13)
        elif mn == 'j':
            w = enc_j(labels[a[0]] - pc, 0, 0x6F)
        elif mn in R:
            f7, f3 = R[mn]
            w = enc_r(f7, reg(a[2]), reg(a[1]), f3, reg(a[0]), 0x33)
        elif mn in I:
            w = enc_i(num(a[2]), reg(a[1]), I[mn], reg(a[0]), 0x13)
        elif mn in SH:
            f7, f3 = SH[mn]
            w = enc_i((f7 << 5) | (num(a[2]) & 0x1F), reg(a[1]), f3, reg(a[0]), 0x13)
        elif mn in LD:
            m = re.fullmatch(r'(-?\w+)\((x\d+)\)', a[1])
            w = enc_i(num(m.group(1)), reg(m.group(2)), LD[mn], reg(a[0]), 0x03)
        elif mn in ST:
            m = re.fullmatch(r'(-?\w+)\((x\d+)\)', a[1])
            w = enc_s(num(m.group(1)), reg(a[0]), reg(m.group(2)), ST[mn], 0x23)
        elif mn in BR:
            w = enc_b(labels[a[2]] - pc, reg(a[1]), reg(a[0]), BR[mn], 0x63)
        elif mn == 'jal':
            w = enc_j(labels[a[1]] - pc, reg(a[0]), 0x6F)
        elif mn == 'jalr':
            w = enc_i(num(a[2]), reg(a[1]), 0, reg(a[0]), 0x67)
        elif mn == 'lui':
            w = ((num(a[1]) & 0xFFFFF) << 12) | (reg(a[0]) << 7) | 0x37
        elif mn == 'auipc':
            w = ((num(a[1]) & 0xFFFFF) << 12) | (reg(a[0]) << 7) | 0x17
        else:
            raise ValueError(f'unknown instruction: {line}')
        words.append((pc, w & 0xFFFFFFFF, raw))
    return words, labels


if __name__ == '__main__':
    src, out = sys.argv[1], sys.argv[2]
    words, labels = assemble(open(src).read().splitlines())
    with open(out, 'w') as f:
        for pc, w, _ in words:
            f.write(f'{w:08x}\n')
    for pc, w, raw in words:
        print(f'{pc:04x}: {w:08x}   {raw.strip()}')
    print('labels:', {k: hex(v) for k, v in labels.items()})
