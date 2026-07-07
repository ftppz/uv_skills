---
name: uv-multi-clock-probe
description: Capture waveforms across multiple clock domains on the UVHS-2 prototype platform. Extends uv-waveform-probe to the dual/multi-clock-domain case: split trigger_net groups by clock domain, declare each gated sampling clock (trigger -set -gatedclk, with -polarity), combine cross-domain trigger groups with UHD_FINAL_CONDITIONS_LOGIC (OR only), and verify both domains captured with query -trigger / query -capture.
---

# UVHS-2 Multi-Clock-Domain Waveform Probe & Trigger

When the signals you want to observe live in **two or more clock domains**, the single-domain flow in [`uv-waveform-probe`](../uv-waveform-probe) is not enough. This skill covers the extra rules multi-clock-domain probing adds on top:

```
① fe:     probe_net (per clock, OK to mix) + trigger_net (one group PER clock domain!)
② be:     trigger_probe -check / -group   (same as single-domain)
③ runtime: trigger -set -gatedclk FIRST (each gated clock + -polarity), then condition
④ trigger: cross-domain groups combined with UHD_FINAL_CONDITIONS_LOGIC (OR only)
⑤ verify: query -trigger (both groups) + query -capture (both domains)
```

> **Prerequisite:** read [uv-waveform-probe](../uv-waveform-probe) first. This skill only covers what *differs* in the multi-clock-domain case — capacity limits, single-domain commands, and the four-stage overview are all there.

---

## 0. The #1 mistake: one trigger group spanning two clock domains

The classic symptom: **probe two clock domains, but only one domain shows up in the waveform.**

The cause is almost always this:

```tcl
# ❌ WRONG — same group name, two different clocks
trigger_net -add -group test -clock ...u_peri.sys_clk -signal { ... }
trigger_net -add -group test -clock ...core.clock     -signal { ... }
```

UVHS-2 requires **one trigger group = one clock domain**:

> Runtime UG §5.1: *"the trigger signal data width of each trigger group cannot exceed 256 bits and **they share the same clock domain**"*

Two domains in the same group → the trigger logic honors only one clock, the other domain never arms → that domain's waveform never aligns/captures.

`probe_net` itself is fine across domains (each capture station has its own clock), so "half the waveform missing" specifically points at a **trigger-group** problem, not a probe problem.

---

## 1. What to confirm up front (before writing any script)

### 1.1 List every clock domain involved
For each domain, record:
- the **sampling clock** full path (e.g. `xs_fpga_top_debug_1902.u_peri.sys_clk`),
- whether that clock is a **global clock** (known to the runtime DB) or a **gated clock** (not in the DB — needs `trigger -set -gatedclk` at runtime),
- the **frequency** and **polarity** (high-active H / low-active L) if it's gated.

> How to tell if a clock is gated: run `trigger -set -condition` and watch the log — UVHS-2 prints the capture stations whose clock domain is unknown and prompts you to declare it via `trigger -set -gatedclk`.

### 1.2 Assign each signal to a domain
Every probe/trigger signal belongs to exactly one clock domain. Group them so you can write one `probe_net`/`trigger_net` block per domain.

### 1.3 Decide the cross-domain trigger relationship
- **Cross-domain = OR only** (Runtime UG §5.3). You cannot express "domain A AND domain B both fire" across clock domains with UHD. If you truly need AND, the signals must be in the **same** clock domain.
- Plan which domain's flag is the primary trigger; the others become OR contributors.

### 1.4 Same capacity budgets as single-domain (per FPGA)
- probe total ≤ **35 stations × 512 bit = 17920 bit**
- trigger total ≤ **16 groups × 256 bit**
Sum across **all** domains; the budget is per-FPGA, not per-domain. See [uv-waveform-probe §2.3](../uv-waveform-probe/SKILL.md).

---

## 2. fe stage: one `trigger_net` group per clock domain

`probe_net` may list signals from several domains (each capture station keeps its own clock). **`trigger_net` must NOT** — split groups by clock.

### 2.1 probe_net — multi-domain is fine
```tcl
# Domain 1 (peri / SoC interface) — gated clock
probe_net -clock {xs_fpga_top_debug_1902.u_peri.sys_clk} -add { \
    xs_fpga_top_debug_1902.S_AXI_MEM_awaddr \
    xs_fpga_top_debug_1902.cpu_setn_rflag \
}

# Domain 2 (processor core) — core clock
probe_net -clock {xs_fpga_top_debug_1902.u_XlnFpgaTop.sys.ci_0.cc_0.tile.core.clock} -add { \
    xs_fpga_top_debug_1902.u_XlnFpgaTop.sys.ci_0.cc_0.tile.core.backend.inner_ctrlBlock.rob.io_robMon_commitValid_0 \
    xs_fpga_top_debug_1902.u_XlnFpgaTop.sys.ci_0.cc_0.tile.core.frontend.io_backend_toFtq_redirect_valid \
}
```

### 2.2 trigger_net — one group per domain (the fix)
```tcl
# Domain 1 → group peri_axi
trigger_net -add -group peri_axi \
    -clock xs_fpga_top_debug_1902.u_peri.sys_clk \
    -signal { \
    xs_fpga_top_debug_1902.cpu_setn_rflag \
    }

# Domain 2 → group core_rob  (DIFFERENT name, matching its own clock)
trigger_net -add -group core_rob \
    -clock xs_fpga_top_debug_1902.u_XlnFpgaTop.sys.ci_0.cc_0.tile.core.clock \
    -signal { \
    xs_fpga_top_debug_1902.u_XlnFpgaTop.sys.ci_0.cc_0.tile.core.backend.inner_ctrlBlock.rob.io_robMon_commitValid_0 \
    }
```

- **Group name must be unique per clock domain.** Do not reuse a name across domains.
- Group names must be identical across `probe_net`'s `trigger_net -group`, the `[...]` section in `uhd_setting.ini`, and `query -trigger -name` in `hw_run.tcl` — **all three places**.

---

## 3. be stage: `trigger_probe` (unchanged from single-domain)

Still the two commands in `backend.tcl`, same positions:

```tcl
init_runtime_data
trigger_probe -check      # before sweep_design
sweep_design
...
transform_clock
trigger_probe -group      # before partition_design
sweep_design -remap
```

Nothing domain-specific here. See [uv-waveform-probe §3](../uv-waveform-probe/SKILL.md) for the full be-stage order.

---

## 4. `uhd_setting.ini` — one section per group + cross-domain OR

Each trigger group gets its own `[group_name]` section. Cross-domain combination goes in `UHD_FINAL_CONDITIONS_LOGIC` with **OR only**.

```ini
# ---- Domain 1 group ----
[peri_axi]
LOGIC = OR
xs_fpga_top_debug_1902.cpu_setn_rflag = 1

# ---- Domain 2 group ----
[core_rob]
LOGIC = OR
xs_fpga_top_debug_1902.u_XlnFpgaTop.sys.ci_0.cc_0.tile.core.backend.inner_ctrlBlock.rob.io_robMon_commitValid_0 = 1

# ---- Cross-domain convergence: OR ONLY ----
[UHD_FINAL_CONDITIONS_LOGIC]
LOGIC = OR
peri_axi
core_rob
```

### When can I use AND / ORDER?
- **Same clock domain** → `UHD_CLK_SYNC_GROUP_CONDITIONS_LOGIC_<n>` supports OR / AND / ORDER, up to 8 such groups.
- **Different clock domains** → only `UHD_FINAL_CONDITIONS_LOGIC` + OR. One per ini file.

> Runtime UG §5.3: *"Trigger groups of different clock domains support only the OR condition."*

If you need a cross-domain AND, you cannot express it directly — redesign so the relevant signals share one clock domain, or assert one side manually with `trigger -force`.

---

## 5. runtime (`hw_run.tcl`): gated clocks first, then condition

This is where multi-domain scripts most often go wrong. The order is **mandatory**.

### 5.1 Declare every gated clock BEFORE the condition

```tcl
trigger -clear

# ★ gated clocks FIRST — one per gated sampling clock, each with -polarity
trigger -set -gatedclk b0/f0/part_0/u_peri/sys_clk -frequency 49m -polarity H
# If core.clock is also gated, add another:
# trigger -set -gatedclk <gate_name_of_core_clock> -frequency <MHz> -polarity H

# then ini_check / condition
trigger -ini_check ./user_script/uhd_setting.ini
capture -enable
trigger -set -condition ./user_script/uhd_setting.ini -position 95
```

Why the order matters (Runtime CMD RfM):
> *"you must supply the clock information to the runtime software through the **trigger -set -gatedclk command first**, and then rerun the trigger -set -condition command"*

`-polarity` is **required** (not optional): `1|H|h` = high-active, `0|L|l` = low-active.

### 5.2 Check trigger status before uploading

```tcl
set r [trigger -status -wait 1 -timeout 120 -tclobj]
puts "trigger: $r"
# Conditions Triggered and Waveform Data Ready must both be true before upload
```

`upload_uhd` on an un-triggered / not-ready state uploads **invalid data** silently.

### 5.3 Upload with `-clock` and a sane depth

```tcl
# depth counts cycles of the given sampling clock; without -clock it counts TS (2 MHz) ticks
upload_uhd -depth 1000000 -clock b0/f0/part_0/u_peri/sys_clk -position 95 -out test_uhd -force_overwrite
```

- Start small (1 M cycles), confirm both domains are present, then increase.
- Total bandwidth ≤ **102 Gbps** / 16 GB DDR per FPGA — exceeding it **corrupts** the waveform (Runtime CMD RfM).

---

## 6. Verify both domains were captured (run on board)

```tcl
query -trigger                 # both groups must appear
query -trigger -name peri_axi
query -trigger -name core_rob
query -capture                 # per-station bit counts; sum vs. declared width
```

- A missing group → fe/be didn't register it (check `probe_net`'s `trigger_net -group` and `trigger_probe -group`).
- Per-station bits summing to less than declared width → signals silently dropped (over the 17920-bit budget); trim with bit-selects.

---

## 7. Troubleshooting (multi-clock-domain specific)

| Symptom | Cause | Fix |
|---|---|---|
| Only one domain shows in the waveform | two domains sharing one `trigger_net -group` name | split into one group per clock domain; rerun fe+be |
| One domain's waveform looks misaligned / never arms | that domain's clock is gated but not declared | add `trigger -set -gatedclk <name> -frequency <f> -polarity H` **before** the condition |
| `trigger -set -gatedclk` "ignored" / still no data | missing `-polarity`, or placed after `trigger -set -condition` | add `-polarity`; move gatedclk before condition |
| Need cross-domain AND but OR-only is allowed | UHD cannot AND across clock domains | move the relevant signals into one clock domain, or `trigger -force` one side |
| Gated-clock domain data looks wrong / sparse | gated clock not always running; documented limitation | Runtime CMD RfM: if `clk_dut` is off, `TS_CAPT_START`/`CLK_CAPT_CNT0` stay 0 — ensure the clock is running during capture |
| fe/be clean, some signals missing | over the 17920-bit probe budget | see [uv-waveform-probe §2.3](../uv-waveform-probe/SKILL.md) |

---

## 8. Checklist (multi-clock-domain probe)

- [ ] Each clock domain has its **own** `trigger_net -group` (unique names).
- [ ] Every **gated** sampling clock is declared with `trigger -set -gatedclk ... -frequency ... -polarity ...` **before** `trigger -set -condition`.
- [ ] `uhd_setting.ini` has one `[group]` per domain + `UHD_FINAL_CONDITIONS_LOGIC` (OR).
- [ ] Cross-domain trigger relationship is OR (not AND/ORDER).
- [ ] Group names match across `probe_net`, ini `[...]`, and `query -trigger -name`.
- [ ] `trigger -status` checked before `upload_uhd`.
- [ ] `upload_uhd -depth` is small first, with `-clock`; total bandwidth ≤ 102 Gbps.
- [ ] `query -trigger` shows all groups; `query -capture` bit sums match declared width.
