# ---------------- ALU / forwarding ----------------
    addi x1, x0, 5          # x1 = 5
    addi x2, x0, 10         # x2 = 10
    add  x3, x1, x2         # x3 = 15   (forwarding EX/MEM + MEM/WB)
    sub  x4, x2, x1         # x4 = 5
    and  x5, x3, x2         # x5 = 10
    or   x6, x3, x2         # x6 = 15
    xor  x7, x3, x2         # x7 = 5
    slli x8, x1, 4          # x8 = 80
    srli x9, x8, 2          # x9 = 20
    addi x10, x0, -16       # x10 = 0xFFFFFFF0
    srai x11, x10, 2        # x11 = 0xFFFFFFFC
    slt  x12, x10, x1       # x12 = 1  (signed)
    sltu x13, x10, x1       # x13 = 0  (unsigned)
    lui  x14, 0x12345
    addi x14, x14, 0x678    # x14 = 0x12345678
# ---------------- memory / load-use ----------------
    sw   x14, 0(x0)
    lw   x15, 0(x0)         # x15 = 0x12345678
    add  x16, x15, x1       # load-use stall -> x16 = 0x1234567D
    lb   x17, 0(x0)         # 0x78
    lbu  x18, 3(x0)         # 0x12
    sb   x10, 4(x0)         # byte 0xF0
    lb   x19, 4(x0)         # 0xFFFFFFF0 (sign-extended)
    lbu  x20, 4(x0)         # 0xF0
    sh   x10, 8(x0)         # half 0xFFF0
    lh   x21, 8(x0)         # 0xFFFFFFF0
    lhu  x22, 8(x0)         # 0x0000FFF0
# ---------------- loop: sum 1..10 ----------------
    addi x23, x0, 0
    addi x24, x0, 1
    addi x25, x0, 11
loop:
    add  x23, x23, x24
    addi x24, x24, 1
    bne  x24, x25, loop     # x23 = 55, x24 = 11
# ---------------- JAL / JALR ----------------
    jal  x26, func          # x26 = return address
    addi x27, x0, 99        # executed after return
    j    branches
func:
    addi x28, x0, 7
    jalr x0, x26, 0         # return
    addi x28, x0, 123       # must be flushed (never executes)
# ---------------- branches / flush ----------------
branches:
    auipc x29, 0
    addi x30, x0, 1
    beq  x30, x0, fail      # not taken
    bge  x30, x0, t1        # taken
    addi x31, x31, 1        # must be flushed
t1:
    bltu x0, x30, t2        # taken
    addi x31, x31, 1        # must be flushed
t2:
    j    end
fail:
    addi x31, x0, -1
end:
    j    end                # halt (jump to self)
