/* boardsupport.c — Embench board hooks for the custom RV32 core.
 * initialise_board is a no-op; start_trigger/stop_trigger (the mcycle/minstret
 * snapshots) live in crt0.S so they are leaf, non-inlined, and counted precisely.
 * SPDX-License-Identifier: GPL-3.0-or-later */
#include <support.h>

void
initialise_board (void)
{
  __asm__ volatile ("" : : : "memory");
}
