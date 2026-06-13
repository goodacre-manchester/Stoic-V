/* boardsupport.h — Embench board config for the custom RV32 core (Verilator).
 * GLOBAL_SCALE_FACTOR=1 matches the baseline-data scale, so measured cycles are
 * directly comparable to baseline-data/speed.json. WARMUP_HEAT=0: this core has
 * no caches, so cache-warming is a no-op (and warm runs *before* start_trigger,
 * so it never affects the measured count regardless). CPU_MHZ is informational.
 * SPDX-License-Identifier: GPL-3.0-or-later */
#ifndef BOARDSUPPORT_H
#define BOARDSUPPORT_H

#define CPU_MHZ 1
#define WARMUP_HEAT 0
#define GLOBAL_SCALE_FACTOR 1

#endif /* BOARDSUPPORT_H */
