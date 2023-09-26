# See LICENSE for license details.

#*****************************************************************************
# smcsrind.S
#-----------------------------------------------------------------------------
#
# Test that Smcsrind are read-only zeros
#

#include "riscv_test.h"
#include "test_macros.h"

RVTEST_RV64M
RVTEST_CODE_BEGIN

  TEST_CASE( 2, t0, 0, csrrs t0, siselect, x0);
  li t0, -1
  csrw siselect, t0
  TEST_CASE( 3, t0, 0xfff, csrrs t0, siselect, x0);
	
  TEST_CASE( 4, t0, 0, csrrs t0, 0x151,    x0);
  TEST_CASE( 5, t0, 0, csrrs t0, 0x152,   x0);
  TEST_CASE( 6, t0, 0, csrrs t0, 0x153,   x0);
  TEST_CASE( 7, t0, 0, csrrs t0, 0x155,   x0);
  TEST_CASE( 8, t0, 0, csrrs t0, 0x156,   x0);
  TEST_CASE( 9, t0, 0, csrrs t0, 0x157,   x0);

2:
  TEST_PASSFAIL

  .align 2
  .global mtvec_handler
mtvec_handler:
  j fail

RVTEST_CODE_END

  .data
RVTEST_DATA_BEGIN

  TEST_DATA

RVTEST_DATA_END
