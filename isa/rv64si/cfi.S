# See LICENSE for license details.

#*****************************************************************************
# dirty.S
#-----------------------------------------------------------------------------
#
# Test VM referenced and dirty bits.
#

#include "riscv_test.h"
#include "test_macros.h"

#if (DRAM_BASE >> 30 << 30) != DRAM_BASE
# error This test requires DRAM_BASE be SV39 superpage-aligned
#endif 

#define REG_T0 5
#define REG_T1 6
#define REG_T2 7

#define SSLOAD_X1   .word 0b10000001110000000100000011110011
#define SSLOAD_X5   .word 0b10000001110000000100001011110011
#define SSLOAD_T0   SSLOAD_X5
#define SSPOPCHK_X1 .word 0b10000001110000001100000001110011
#define SSPOPCHK_X5 .word 0b10000001110000101100000001110011
#define SSPOPCHK_T0 SSPOPCHK_X5
#define SSPINC(imm) .word (0b10000001110100000100000001110011 | (imm << 15))
#define SSPUSH_X1   .word 0b10000010000100000100000001110011
#define SSPUSH_X5   .word 0b10000010010100000100000001110011
#define SSPUSH_T0   SSPUSH_X5
#define SSAMOSWAP(rd, rs1, rs2) \
  .word (0b10000010000000000100000001110011 | \
         (rs2 << 20) | (rs1 << 15 ) | (rd << 7) \
        )

#define CSR_SSP 0x50

RVTEST_RV64M
RVTEST_CODE_BEGIN

  # Turn on VM
  li a0, (SATP_MODE & ~(SATP_MODE<<1)) * SATP_MODE_SV39
  la a1, page_table_1
  srl a1, a1, RISCV_PGSHIFT
  or a1, a1, a0
  csrw sptbr, a1
  sfence.vma

  # Set up MPRV with MPP=S, so loads and stores use S-mode
  li a1, ((MSTATUS_MPP & ~(MSTATUS_MPP<<1)) * PRV_S) | MSTATUS_MPRV
  csrs mstatus, a1

  # start CFI testing here
  li a1, ((MSTATUS_MPP & ~(MSTATUS_MPP<<1)) * PRV_S) | MSTATUS_SUM
  csrs mstatus, a1
  
  # Setup a PTE entry as SS i.e. xwr=010, ssload/sspopchk/sspush/ssamoswap should success to that page
  
  # Store value in entry
  li t0, 13
  sw t0, dummy - DRAM_BASE, a0

  # Leave MPRV
  li t0, MSTATUS_MPRV
  csrc mstatus, t0
  
  # Set PTE as SS
  lw t0, page_table_1
  andi t0, t0, ~(PTE_R | PTE_X)
  sw t0, page_table_1, a0
  sfence.vma

#if __riscv_xlen == 64
  li t0, MENVCFG_CFIE
  csrs menvcfg, t0
#else
  li t0, MENVCFGH_CFIE
  csrs menvcfgh, t0
#endif
	
  # Set ssp
  la t0, dummy - DRAM_BASE
  csrw CSR_SSP, t0

  # Enter MPRV again
  li t0, MSTATUS_MPRV
  csrs mstatus, t0

  # read from ssp
  SSLOAD_T0
  li t1, 13
  bne t0, t1, die

  SSPOPCHK_T0
  li t0, 14
  SSPUSH_T0
  
  lw t1, dummy - DRAM_BASE
  bne t0, t1, die
  li t1, 15
  la t2, dummy - DRAM_BASE
  SSAMOSWAP(REG_T0, REG_T2, REG_T1)
  li t1, 14
  bne t0, t1, die
  lw t0, dummy - DRAM_BASE
  li t1, 15
  bne t0, t1, die

  # Store to SS page should cause access fault
	li t4, CAUSE_STORE_ACCESS  # Set expected fault
  sw t0, dummy - DRAM_BASE, a0
	bnez t4, die  # should be cleared to 0 by handler
	
  # Leave MPRV
  li t0, MSTATUS_MPRV
  csrc mstatus, t0
	
  # ssload/sspopchk/sspush/ssamoswap should cause access fault if done to non SS page
  
  # Set PTE as non-SS
  lw t0, page_table_1
  ori t0, t0, (PTE_R | PTE_X)
  sw t0, page_table_1, a0
  sfence.vma
	
  # Enter MPRV again
  li t0, MSTATUS_MPRV
  csrs mstatus, t0
	
  la t0, dummy - DRAM_BASE
  csrw CSR_SSP, t0
	li t4, CAUSE_LOAD_ACCESS  # Set expected fault
  SSLOAD_T0
	bnez t4, die  # should be cleared to 0 by handler

	li t4, CAUSE_STORE_ACCESS  # Set expected fault
  SSPUSH_T0
	bnez t4, die  # should be cleared to 0 by handler

	li t4, CAUSE_LOAD_ACCESS  # Set expected fault
	SSPOPCHK_T0
	bnez t4, die  # should be cleared to 0 by handler

	li t4, CAUSE_STORE_ACCESS  # Set expected fault
  SSAMOSWAP(REG_T0, REG_T2, REG_T1)
	bnez t4, die  # should be cleared to 0 by handler

;;   # Try a faulting store to make sure dirty bit is not set
;;   li TESTNUM, 2
;;   li t2, 1
;;   sw t2, dummy - DRAM_BASE, a0

;;   # Set SUM=1 so user memory access is permitted
;;   li TESTNUM, 3
;;   # set HADE to 0
;; #if __riscv_xlen == 64
;;   csrr a1, menvcfg
;;   li t0, 1
;;   sll t0, t0, 61
;;   not t0, t0
;;   and a1, a1, t0
;;   csrw menvcfg, a1
;; #else
;;   csrr a1, menvcfgh
;;   li t0, 1
;;   sll t0, t0, (61 - 32)
;;   not t0, t0
;;   and a1, a1, t0
;;   csrw menvcfgh, a1
;; #endif

;;   # We do this test twice (as 3 and again as 4). For the second run,
;;   # we'll have toggled HADE and branch to here:
;; 1:
;;   li a1, ((MSTATUS_MPP & ~(MSTATUS_MPP<<1)) * PRV_S) | MSTATUS_SUM
;;   csrs mstatus, a1

;;   # Make sure SUM=1 works
;;   lw t0, dummy - DRAM_BASE
;;   bnez t0, die

;;   # Try a non-faulting store to make sure dirty bit is set
;;   sw t2, dummy - DRAM_BASE, a0

;;   # Make sure it succeeded
;;   lw t0, dummy - DRAM_BASE
;;   bne t0, t2, die

;;   # Leave MPRV
;;   li t0, MSTATUS_MPRV
;;   csrc mstatus, t0

;;   # Make sure D bit is set
;;   lw t0, page_table_1
;;   li a0, PTE_A | PTE_D
;;   and t0, t0, a0
;;   bne t0, a0, die

;;   # Enter MPRV again
;;   li t0, MSTATUS_MPRV
;;   csrs mstatus, t0

;;   addi TESTNUM, TESTNUM, 1
;;   li t0, 5
;;   beq TESTNUM, t0, 1f

;;   # reset this value:
;;   sw zero, dummy - DRAM_BASE, a0

;;   # set HADE to 1
;; #if __riscv_xlen == 64
;;   csrr a1, menvcfg
;;   li t0, 1
;;   sll t0, t0, 61
;;   or a1, a1, t0
;;   csrw menvcfg, a1
;; #else
;;   csrr a1, menvcfgh
;;   li t0, 1
;;   sll t0, t0, (61 - 32)
;;   or a1, a1, t0
;;   csrw menvcfgh, a1
;; #endif

;;   j 1b
;; 1:
;;   # Make sure that superpage entries trap when PPN LSBs are set.
;;   li TESTNUM, 5
;;   lw a0, page_table_1 - DRAM_BASE
;;   or a0, a0, 1 << PTE_PPN_SHIFT
;;   sw a0, page_table_1 - DRAM_BASE, t0
;;   sfence.vma
;;   sw a0, page_table_1 - DRAM_BASE, t0
;;   j die
  
  RVTEST_PASS

  TEST_PASSFAIL

  .align 2
  .global mtvec_handler
mtvec_handler:
  csrr t0, mcause
	sub t0, t0, t4
  bnez t0, die   # Got unexpected fault
  li t4, 0   # Zero-out to show we handled the fault
  j skip  # skip over this instruction and continue

  add t0, t0, -CAUSE_STORE_PAGE_FAULT
  bnez t0, die

  li t1, 2
  bne TESTNUM, t1, 1f
  # Make sure D bit is clear
  lw t0, page_table_1
  and t1, t0, PTE_D
  bnez t1, die
skip:
  csrr t0, mepc
  add t0, t0, 4
  csrw mepc, t0
  mret

1:
  li t1, 4
  bgt TESTNUM, t1, 1f
  # The implementation doesn't appear to set D bits in HW.
  # Verify that HADE is 0.
#if __riscv_xlen == 64
  csrr a1, menvcfg
  srli a1, a1, 62
  andi a1, a1, 1
  bnez a1, die
#else
  csrr a1, menvcfgh
  srli a1, a1, (62 - 32)
  andi a1, a1, 1
  bnez a1, die
#endif
  # Make sure the D bit really is clear.
  lw t0, page_table_1
  and t1, t0, PTE_D
  bnez t1, die
  # Set the D bit.
  or t0, t0, PTE_D
  sw t0, page_table_1, t1
  sfence.vma
  mret

1:
  li t1, 5
  bne TESTNUM, t1, 1f
  j pass

1:
die:
  RVTEST_FAIL

RVTEST_CODE_END

  .data
RVTEST_DATA_BEGIN

  TEST_DATA
.align 12
non_ss: .dword 0x21

.align 12
page_table_1: .dword (DRAM_BASE/RISCV_PGSIZE << PTE_PPN_SHIFT) | PTE_V | PTE_U | PTE_R | PTE_W | PTE_X | PTE_A
dummy: .dword 0

RVTEST_DATA_END
