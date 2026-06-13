// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 John Goodacre
/* firmware.c — example bare-metal M-mode app demonstrating the core's only
 * control-flow contract: idle on wfi; wake on the single machine-external
 * interrupt (mip.MEIP); the ISR clears the source at a memory-mapped W1C
 * register and stores to a memory-mapped peripheral. The peripheral addresses
 * below are illustrative placeholders — substitute the host SoC's real map.
 */
#include <stdint.h>

#define MMIO(addr)      (*(volatile uint32_t *)(addr))

/* Illustrative host memory-mapped layout (replace with the integrator's map). */
#define PERIPH_BASE     0x40000000u           /* example MMIO peripheral block   */
#define IRQ_STATUS      (PERIPH_BASE + 0x00)  /* interrupt status (write-1-clear)*/
#define IRQ_PENDING     (PERIPH_BASE + 0x04)  /* interrupt pending               */
#define OUT_PORT        (PERIPH_BASE + 0x10)  /* example output register         */

volatile uint32_t g_irq_count = 0;

/* Called from _trap_entry (start.S). The only trap source is the machine
 * external interrupt; the level deasserts when we W1C the source. */
void isr_handler(void) {
    uint32_t pending = MMIO(IRQ_PENDING);
    g_irq_count++;
    MMIO(OUT_PORT)   = 0xC0DE0000u | (g_irq_count & 0xFFFF);  /* example work */
    MMIO(IRQ_STATUS) = pending;                               /* write-1-clear */
}

int main(void) {
    /* application idles; all work is interrupt-driven. Returns to start.S's
     * wfi idle loop. */
    return 0;
}
