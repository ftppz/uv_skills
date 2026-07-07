---
name: uv-waveform-probe
description: Capture and view the waveform of a module or signal on the UVHS-2 prototype platform. Covers the full four-stage flow: fe registration (probe_net/trigger_net) → be instantiation (trigger_probe -check/-group) → runtime acquisition (capture/upload_uhd) → viewing the .usdb waveform in uvgui/uvd.
---

# UVHS-2 Waveform Probe & Trigger (probe / trigger)

Capturing a waveform on the UVHS-2 prototype platform takes **four stages** before a signal finally appears in the waveform window:

```
① fe stage:     probe_net / trigger_net     → "register" the signal into the design
② be stage:     trigger_probe -check/-group → "instantiate" the registered signal as hardware pseudo-IP
③ runtime:      hw_run.tcl capture/upload   → trigger on board and capture
④ viewing:      uvgui / uvd                 → open the .usdb waveform
```

**The stage most often missed is ②** (`trigger_probe -check` and `trigger_probe -group` in the backend). Skip these and neither fe nor be will report an error, but you'll capture nothing on the board — because the signal never made it to hardware. A second silent failure: **exceeding the probe width budget (17920 bit/FPGA) drops overflow signals with no error** — see §1.6 and §2.3.

---

## 0. Prerequisites

- UVHS-2 V2025.06.P4 (or the same series), prototyping (APS) flow.
- The design already compiles through fe + be (`make uv_fe && make uv_be` produces a bitstream).
- The signal you want to observe is **visible** at the fe stage (top-level port, or an internal RTL signal inside a non-blackbox module).
  - For **signals inside a blackbox IP (DCP)**, this skill does not cover them — use the sibling skill [`uv-blackbox-probe`](../uv-blackbox-probe) (`probe_net -blackbox_instance` / `trigger_net -blackbox_instance -gate`), which is purpose-built for that.

---

## 1. What to ask the user up front (before doing anything)

### 1.1 Which signals to observe?
- The signal's **full path** (fe-stage format: `<top_module>.<instance>.<signal>`).
  - ⚠️ The top module name is **not** necessarily `top`! Use the design's real top module name.
    - e.g. `xs_fpga_top_debug_1902.S_AXI_MEM_awaddr` (top is `xs_fpga_top_debug_1902`).
    - e.g. `top.u_xdma.cfg_ltssm_state` (top is `top`).
- Multi-bit bus: `top.u.x.data[5:0]`, or use the wildcard `top.u.x.data[*]`.
- A blackbox internal signal? Use the sibling skill [`uv-blackbox-probe`](../uv-blackbox-probe) — this skill only handles non-blackbox (top-level / RTL-internal) signals.

### 1.2 Which clock samples it? (**critical**)
- Must be a **globally visible clock** at the fe stage.
- A blackbox internal clock is **not allowed by default** (the probe_net docs: `Specifying a blackbox internal clock as the sampling clock is not supported`) — but can be unlocked with `set_option signal.uhd.sampling_clock.allow_local_clock true`. If you need that, you're in blackbox-probing territory — see [`uv-blackbox-probe`](../uv-blackbox-probe).
- For slow-changing status signals (LTSSM, link_up, busy, done), sample with an external reference clock (e.g. 100 MHz sys_clk).
- The clock also uses a full path: `xs_fpga_top_debug_1902.u_wrapper.sys_clk` (not `top.xxx`).

### 1.3 Where to trigger?
- The trigger signal + the trigger value (capture the waveform when the signal becomes what? usually a flag going 0→1).
- e.g. `user_lnk_up = 1`, `tx_done = 1`, `awvalid = 1`.

### 1.4 The top module name
- Find `module <name>` in the design's top-level RTL; every path in probe/trigger is rooted there.
- It is not a fixed `top` — the reference project uses `xs_fpga_top_debug_1902`.

### 1.5 Where the project scripts live (confirm the fe/be script names)
- Common: `user_script/frontend.tcl` (fe) / `user_script/backend.tcl` (be) / `user_script/hw_run.tcl` (runtime).
- Could also be `fe_run.tcl` / `be_run.tcl`. Run `grep -l source.*probe user_script/*.tcl` to find the fe script first.

### 1.6 Probe/trigger capacity budget (**ask this, then check the math**)
When the user lists the signals they want to observe, **sum up the total bit-width and check it against the UHD budget before writing probe.tcl**:

| Resource | Per-FPGA limit (UHD) |
|---|---|
| Probe total width | **35 capture stations × 512 bit = 17920 bit** |
| Trigger total width | **16 trigger groups × 256 bit** |

- **If total probe width ≤ 17920 bit** → proceed.
- **If total probe width > 17920 bit** → **do NOT just write it and hope**. The compile will pass silently, but the overflow signals are dropped at `trigger_probe -group` and never show up in the waveform. Tell the user the budget is exceeded and **ask them to trim the list**:
  - Drop signals they don't strictly need.
  - Replace wide buses with bit-selects (e.g. `data[7:0]` instead of the full 1024-bit `data`).
  - Keep only the status/flag signals, defer wide data buses to a second capture run.
- Recompute the total after trimming; only write `probe_net` once it fits.
- Per-FPGA, not system-wide: if the design spans multiple FPGAs, each FPGA's probes are budgeted independently (≤17920 bit each).

---

## 2. fe stage: probe.tcl (register probes + trigger groups)

`probe.tcl` is sourced during the fe stage (frontend.tcl / fe_run.tcl contains `source ./user_script/probe.tcl`).

### 2.1 `probe_net` — add signals to the probe (required)

```tcl
# syntax
probe_net -clock { <full path to sampling clock> } -add { <full path to signals> ... }

# example: probe the AXI bus + a status signal
probe_net -clock {xs_fpga_top_debug_1902.u_wrapper.sys_clk} -add { \
    xs_fpga_top_debug_1902.S_AXI_MEM_awaddr \
    xs_fpga_top_debug_1902.S_AXI_MEM_awvalid \
    xs_fpga_top_debug_1902.S_AXI_MEM_arready \
    xs_fpga_top_debug_1902.cpu_setn_rflag \
}
```

- `-clock`: full path to the sampling clock — must be a globally visible clock (not a blackbox internal one; for blackbox-internal clocks use [`uv-blackbox-probe`](../uv-blackbox-probe)).
- `-add { ... }`: signal list using RTL full paths. Buses and `*` wildcards are supported.
- Use `\` for line continuation (that's how the reference project writes it).

### 2.2 `trigger_net` — define a trigger group (write this when you want to trigger)

```tcl
# syntax (-probe is optional)
trigger_net -add -group <group_name> \
    [-probe] \
    -clock <sampling clock> \
    -signal { <full path to trigger signals> ... }

# example
trigger_net -add -group test \
    -clock xs_fpga_top_debug_1902.u_wrapper.sys_clk \
    -signal { \
    xs_fpga_top_debug_1902.S_AXI_MEM_awready \
    xs_fpga_top_debug_1902.cpu_setn_rflag \
    }
```

- `-group <group_name>`: trigger group name — must match what's in uhd_setting.ini / hw_run.tcl.
- `-probe`: **optional**. Adds these trigger signals into the **probe** list as well, so they are captured/viewable in the waveform without a separate `probe_net`. (This is the trigger→probe direction; `probe_net` has no such link back to trigger.)
- `-clock`: sampling clock (same as probe_net's).
- `-signal { ... }`: trigger signal list (usually a 1-bit flag).

> **probe vs. trigger relationship.** `probe_net` and `trigger_net` are siblings, not nested:
> - `probe_net` = "what to **view**" (UHD-Probe, ≤35 capture stations × 512 bits).
> - `trigger_net` = "when to **stop capturing**" (UHD-Trigger, ≤16 trigger groups × 256 bits).
>
> A trigger is **not** required to also be a probe, and a probe **cannot** be turned into a trigger. The only link is the `-probe` flag, which pushes trigger signals into the probe list (so trigger ⊆ probe when `-probe` is used). The common real-world pattern is the opposite of "probe is a subset of trigger": probe a large set, then trigger on a subset of it — see the `uvhs_flow` reference project, where every `trigger_net` signal is already in `probe_net`.

### 2.3 Probe/Trigger capacity limits (and how to verify)

The UHD has **hard width walls** — exceeding them silently drops signals from the waveform.

| | Probe (UHD-Probe) | Trigger (UHD-Trigger) |
|---|---|---|
| **Groups / stations** | ≤ 35 capture stations / FPGA | ≤ 16 trigger groups / system |
| **Width per group** | 512 bit | ≤ 256 bit (same clock domain within a group) |
| **Total width (per FPGA)** | **35 × 512 = 17920 bit** | 16 × 256 = 4096 bit |

- **Where the wall comes from**: 35 capture stations is the number of UHD capture-IP instances physically instantiated per FPGA; 512 bit is the fixed channel width of each station (station → APCP → DDR). Both are hardware, **not configurable**.
- **Width vs. depth are orthogonal**: the **width** wall (17920 bit) is set by the capture IP; the **depth** (`upload_uhd -depth <N>`, how many cycles) is set by the 16 GB DDR4 dedicated to UHD per FPGA. Running out of width is **not** solved by more DDR — they are independent budgets.
- **`trigger_net -probe` eats the probe budget**: signals added with `-probe` count toward **both** the trigger budget (≤256 bit/group) and the probe budget (≤17920 bit). Account for both when summing.
- **Multi-FPGA**: each FPGA is budgeted independently (≤17920 bit each), not a shared system pool.

#### How to verify nothing was dropped (run on board)
```tcl
query -capture            ;# lists each station + the bit count actually packed into it
```
Sum the per-station bit counts and compare to the total width you declared in `probe_net`:
- **Equal** → all signals captured.
- **Less than declared** → overflow, some signals were dropped → trim the probe list (drop unneeded signals, or use bit-selects like `sig[7:0]` instead of full buses), then rerun fe + be.

> ⚠️ **Silent failure mode**: `probe_net` + `trigger_probe -check/-group` do **not** error when the budget is exceeded — fe/be both look clean, but the overflow signals are simply absent from the waveform. Always confirm with `query -capture`.

---

## 3. be stage: trigger_probe (**the most critical and most-missed step**!)

**probe_net/trigger_net at fe only "registers" — at the be stage you must use `trigger_probe` to instantiate them as hardware pseudo-IP, otherwise nothing is captured on board.**

Add these two commands to backend.tcl / be_run.tcl:

### 3.1 `trigger_probe -check` (before sweep_design)

```tcl
# check that all probe/trigger signals actually exist (missing, misspelled, or blackbox-internal signals are reported here)
init_runtime_data
trigger_probe -check      # ← add this
sweep_design
```
Docs verbatim: `Checks whether all specified trigger/probe signals exist or not. It is called before sweep_design.`

### 3.2 `trigger_probe -group` (before partition_design)

```tcl
# after clock handling, before partition — package the probe/trigger signals into a pseudo-IP
transform_clock
trigger_probe -group      # ← add this
sweep_design -remap       # ← the reference project remaps right after -group
# ... then partition_design / compile_fpga
```
Docs verbatim: `Groups all trigger/probe signals in one group to a pseudo-IP. It is called before partition_design.`

### 3.3 Full be-stage order (verified on the reference project)

```tcl
read_netlist
link_design
# (probe.tcl can also be sourced here in be, but is usually placed in fe)
instrument_design
sanitize_design
init_runtime_data
trigger_probe -check          # ← verify signals exist
sweep_design
config_clock ...
infer_clock
transform_clock
trigger_probe -group          # ← package into a pseudo-IP
sweep_design -remap
# ... partition_design, route, compile_fpga
```

⚠️ **If fe/be report no errors but you capture nothing on board**, 99% of the time you skipped `trigger_probe -check` / `-group`.

---

## 4. uhd_setting.ini — the trigger condition values

`trigger_net` only defines "which signals are in the group" — **the trigger value (signal = N) lives in this ini**.

```ini
# uhd_setting.ini
[<trigger_group_name>]
LOGIC = OR
<full path to trigger signal> = 1

[UHD_FINAL_CONDITIONS_LOGIC]
LOGIC = OR
<trigger_group_name>
```

Example (group `test`, trigger when cpu_setn_rflag=1):
```ini
[test]
LOGIC = OR
xs_fpga_top_debug_1902.cpu_setn_rflag = 1

[UHD_FINAL_CONDITIONS_LOGIC]
LOGIC = OR
test
```

- `[group name]` must **exactly match** the `trigger_net -group` name in probe.tcl.
- `signal = value`: trigger when the signal reaches this value (0/1, or multi-bit like `data = 5`).

---

## 5. runtime: the hw_run.tcl capture section

```tcl
# ===== hw_run.tcl trigger/capture section (add after initialize, before exit) =====
query -trigger
query -trigger -name <trigger_group_name>
trigger -set -condition ./user_script/uhd_setting.ini -position 5
capture -enable
trigger -enable
set trigger_tag [trigger -status -wait 1 -timeout 30 -tclobj]
puts "trigger_tag: $trigger_tag"
upload_uhd -depth 1000000 -out test_uhd -force
wavegen -bindir ./UHD/test_uhd
# waveform: ./UHD/test_uhd/UvData.usdb
#uvgui -u ./UHD/test_uhd/UvData.usdb   ;# comment out when running in batch
```

| Parameter | Meaning | Typical value |
|---|---|---|
| `-position 5` | position of the trigger point in the waveform | 5 |
| `-timeout 30` | max seconds to wait for a trigger | 30~120 for slow events |
| `-depth 1000000` | sample depth | 1,000,000; increase if not enough |
| `-out test_uhd` | raw data directory name | any |

**Keep the group name identical across all three files**: probe.tcl's `-group`, uhd_setting.ini's `[...]`, and hw_run.tcl's `query -trigger -name`.

---

## 6. End-to-end flow

```bash
cd <project_dir>

# 1. Edit probe.tcl (fe registration) + add trigger_probe -check/-group to backend.tcl + uhd_setting.ini + hw_run.tcl

# 2. Re-run fe + be (probe.tcl registers in fe, trigger_probe instantiates in be)
make clean && make uv_fe && make uv_be
# Note: after be, check the log to confirm trigger_probe -check has no "signal not found"

# 3. Run on board (runtime)
uv_shell -t runtime -d <platform> -workdir ./ -script user_script/hw_run.tcl | tee uv_run.log

# 4. Waveform artifact
ls ./UHD/test_uhd/UvData.usdb
```

---

## 7. Where the waveform is and how to view it

### 7.1 Waveform file location
```
<project_dir>/UHD/test_uhd/UvData.usdb
```
- `upload_uhd -out test_uhd` → raw data goes in `./UHD/test_uhd/`
- `wavegen -bindir ./UHD/test_uhd` → generates `UvData.usdb` (the UniVista waveform database) in that directory

### 7.2 Open with uvgui (needs X11)
```bash
uvgui -u ./UHD/test_uhd/UvData.usdb
```
- Path: `/nfs/tools/uvhs/uvd/2025.12.P2/bin/uvgui` (or a newer version directory).
- **Requires X11 forwarding** (graphical app). Log in via `ssh -X`, or use X-Win32/MobaXterm.

### 7.3 Use the uvd command line (no X11)
```bash
uvd -u ./UHD/test_uhd/UvData.usdb
```
For headless servers; query signal values via Tcl commands.

---

## 8. Daughter-card / Probe-Group resource check (do this before be partition, or you hit PAR-028 every time)

> This is the **most hidden prerequisite** of UHD probing: the probe's physical resource is not in the FPGA chip, but on a **DDR4 daughter card** plugged into the board.

**Root cause**: `Probe-Group` is not an FPGA-intrinsic resource like LUT/FF. It is a UHD-specific physical resource — waveform data captured by probes is stored on a **DDR4 DC** (`UV_FMCH_PDDR4DME`, an FMC-form-factor DDR4 card with a DME / Direct-Memory-Engine). Without this card, the `Probe-Group` quota is **0**, so even at 0.4% logic utilization the build reports "insufficient".

The platform default `assemble.tcl` states verbatim: **"it is mandatory to assemble DDR4 DC on FMC3 for each FPGA for UHD"**.

**Failure symptom** (be-stage `partition_design`):
```
[PAR-028] ERROR: DUT requires more resource than N FPGAs, insufficient resource Probe-Group.
[PAR-005] ERROR: Abort partition due to prelude failure: Resource manager checking failed.
```
At this point the resource table shows REG/LUT at only 0.x% (nowhere near full), but `report_system_resource` shows `Probe-Group = 0` on the active FPGA. **Logic isn't exceeded — the probe storage is just zero.**

**How to check** (after assemble, before partition):
```tcl
report_system_resource    ;# is Probe-Group Total > 0? (0 = DC not attached)
config_hw -report         ;# also confirm the daughter card is actually connected
```

**Fix**: in the assemble script, attach a DDR4 DC on the FMC3 slot of **every FPGA in use** (FMC3 is the dedicated UHD slot — DME pins are hard-wired to FMC3). Editing assemble only needs a `be` re-run:
```tcl
config_hw -create_daughter_card UV_FMCH_PDDR4DME -instance pddr4dme_inst2
config_hw -connect_daughter_card {b0.F2_FMC3 pddr4dme_inst2.FMC}
```
**Hardware prerequisite**: the physical FMC3 slot of the active FPGA **must actually have a PDDR4DME card plugged in**.

---

## 9. Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| fe reports `signal not found` | wrong path, or you're trying to probe a blackbox internal signal with the non-blackbox syntax | fix the full path; for blackbox-internal signals use [`uv-blackbox-probe`](../uv-blackbox-probe) |
| fe reports `clock ... not found / blackbox internal clock` | the sampling clock is inside a blackbox | switch to a globally visible top-level clock, or enable blackbox-internal clocks per [`uv-blackbox-probe`](../uv-blackbox-probe) |
| be `trigger_probe -check` errors | the signal got optimized away after fe, or the path is wrong | check the path; make sure the signal wasn't swept away |
| **fe/be both clean but nothing captured on board** | **missed `trigger_probe -group`** | add `trigger_probe -group` + `sweep_design -remap` after transform_clock in be |
| **fe/be both clean, but some signals missing in the waveform** | **probe width exceeded the 17920-bit (35×512) budget** — overflow is silently dropped | run `query -capture`, sum per-station bits vs. declared width; trim the probe list (drop unneeded signals, or use bit-selects like `sig[7:0]`) and rerun fe + be |
| hw_run.tcl reports `trigger group not found` | the group name differs across the three files | reconcile the group name spelling in probe.tcl/ini/hw_run.tcl |
| `trigger -status` times out / false | trigger condition never met | check the trigger value; extend timeout; confirm the DUT is running |
| `UvData.usdb` not generated | wrong wavegen path | `wavegen -bindir` must point at the `upload_uhd -out` directory |
| uvgui `cannot open display` | no X11 | `ssh -X`, or use `uvd` |
| be partition reports `PAR-028 insufficient resource Probe-Group` (logic at only 0.x%) | no DDR4 DC (`UV_FMCH_PDDR4DME`) attached on the active FPGA's FMC3 | attach a PDDR4DME on FMC3 of every active FPGA in the assemble script (see §8); editing assemble only needs a `be` re-run |

---

## 10. Reference docs & examples

| Content | Path |
|---|---|
| probe_net / trigger_net / **trigger_probe** command reference | `UVHS-2-Compile-CMD-RfM-...pdf` |
| wavegen / waveform viewing | `UVHS-2-Prototyping-Runtime-UG-...pdf`, chapters 9/10 |
| Official example (probe + ini + hw_run bundled) | `/nfs/tools/uvhs/p4_20260210/doc/UVHS-2/example/simple_uart/user_script/` |
| **Hands-on reference project** (nanhu4core, AXI + UART probe) | `/nfs/home/lufeifan/uvhs_test/uvhs_flow/user_script/probe.tcl` + `backend.tcl` |

**The most authoritative reference**: the `uvhs_flow` project (already working end-to-end) — its probe.tcl probes a full set of AXI signals, and backend.tcl shows exactly where `trigger_probe -check/-group` go. Just copy the pattern.
