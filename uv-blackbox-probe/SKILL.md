---
name: uv-blackbox-probe
description: Capture the waveform of signals **inside a blackbox IP (DCP)** on the UVHS-2 prototype platform — the case uv-waveform-probe does not cover. Uses probe_net/trigger_net with -blackbox_instance (fe, full path) and -gate (be, gate-level / path), unlocks blackbox-internal sampling clocks via allow_local_clock, and constrains the sampling clock to the same FPGA as the probed signals. Covers fe registration → be -gate instantiation → runtime acquisition → uvd/uvgui viewing.
---

# UVHS-2 Blackbox (DCP) Internal-Signal Probe

Capture signals **inside a blackbox IP**. Prerequisite: the blackbox is hooked in via `set_blackbox -source_file xxx.dcp` (the DCP holds a real netlist, not an empty stub).

> To capture **top-level / non-blackbox** signals → use the sibling skill `uv-waveform-probe`, not this one.
> This skill implements UG Part2 §7.12 "Defining UHD probe and trigger for black boxes".

## 0. Key facts (read this first, or you will hit every pitfall)

Blackbox-internal probes differ from normal probes in **three ways** — get any one wrong and you capture nothing:

| Difference | Normal signal (top / non-blackbox) | Blackbox-internal signal (this skill) |
|---|---|---|
| **Signal path format** | RTL full path `top.a.b.sig` (`.`-separated, with top) | **gate-level**, starting from the blackbox's **first sub-hierarchy level**, **without the blackbox root**, `/`-separated: `ins1/sub/sig` |
| **Sampling clock** | any global clock | if using a blackbox-internal clock, **must** `set_option signal.uhd.sampling_clock.allow_local_clock true` |
| **be instantiation** | `probe_net ...` / `trigger_net ...` | must append **`-gate`**, placed after `link_design` and before `trigger_probe -check` |

There is also a **hard constraint**: the sampling clock and the probed blackbox signals must end up on **the same FPGA**. A single-FPGA design (`set_fpga_count -number 1`) satisfies this naturally; in a multi-FPGA design, confirm partitioning didn't split them across FPGAs.

## 1. Three things to confirm up front

### 1.1 What is the hierarchical path of the blackbox instance?
Format: `<top_module>.<...>.<blackbox_instance_name>` (fe stage, with top, `.`-separated).

How to find it:
- Inspect the instantiation in the top-level RTL: `grep "<module_name> <inst_name>" rtl/*.sv`
- e.g. in this repo's `xs_fpga_top_debug_1902.sv`, `ln_quad_wrapper u_wrapper` → fe instance path = `xs_fpga_top_debug_1902.u_wrapper`
- In uv_shell, run `report_resource -depth 5` after `link_design` and read the hierarchy tree.

### 1.2 What is the relative path of the target signal inside the blackbox?
Format: starting from the blackbox's **first sub-hierarchy level**, **without the blackbox root**, `/`-separated.
- Wrong: `u_wrapper/ln_quad_i/foo/reg` (includes the blackbox root `u_wrapper`)
- Right: `ln_quad_i/foo/reg` (starts from `u_wrapper`'s first inner level `ln_quad_i`)
- **Specify bit-by-bit**: blackbox signals don't support whole-bus names — split into `sig[0] sig[1]` (fe supports the `sig[*]` wildcard; be does not).
- How to find the path: in the frontend Vivado project run `report_hierarchy`, or open the DCP and query with `get_cells`/`get_nets`.

### 1.3 Which clock samples it?
- A blackbox **internal** clock (e.g. an MMCM output like `u_wrapper.sys_clk`) → must enable the §0 option, and write `-clock` as the **blackbox-relative path** (`<sub>/clk_name`, without the blackbox root).
- A top-level **global** clock (e.g. `debug_clk`) → no option needed; write `-clock` as the normal full path.
- In most cases the CPU/SoC clock lives inside the wrapper (MMCM), so **the option is on by default**.

## 2. fe stage: register the probes

### 2.1 Enable the sampling-clock option first (if using a blackbox-internal clock)

Place this in `frontend.tcl` after `create_working_space` and before `source probe.tcl`:

```tcl
set_option signal.uhd.sampling_clock.allow_local_clock true
```

> Default is false. Without it, sampling on a blackbox-internal clock errors out or captures nothing.

### 2.2 Write probe_net / trigger_net (fe syntax)

```tcl
# === blackbox-internal probe ===
# -blackbox_instance: full path of the blackbox instance (with top, .-separated)
# -clock:            sampling clock. If it comes from inside the blackbox, write the
#                    blackbox-relative path (without the blackbox root).
# -add:              target signals, blackbox-relative path (without the root, /-separated),
#                    bit-by-bit or with the * wildcard.
probe_net -blackbox_instance {<top>.<...>.<blackbox_instance>} \
          -clock {<blackbox-internal clock relative path>} \
          -add {
              <sub>/path/sig[0]
              <sub>/path/sig[1]
              <sub>/other/flag
          }

# === blackbox-internal trigger (optional) ===
trigger_net -add -group <group_name> \
            -clock {<blackbox-internal clock relative path>} \
            -blackbox_instance {<top>.<...>.<blackbox_instance>} \
            -signal {
              <sub>/path/trig_sig[0]
              <sub>/path/trig_sig[1]
            }
```

**fe supports the `*` wildcard**: `-add {sub/data[*]}` expands all bits. be does not — it requires bit-by-bit.

### 2.3 Concrete example from this repo

Blackbox `ln_quad_wrapper`, instance `u_wrapper`, sampling clock `sys_clk` (an MMCM output inside the blackbox):

```tcl
# in frontend.tcl
set_option signal.uhd.sampling_clock.allow_local_clock true
source ./user_script/probe_bbox.tcl   ;# put the block below in its own file

# probe_bbox.tcl
probe_net -blackbox_instance {xs_fpga_top_debug_1902.u_wrapper} \
          -clock {ln_quad_i/in_mmcm/sys_clk} \
          -add {
              ln_quad_i/.../<your target signal>
          }
```
> The clock path `ln_quad_i/in_mmcm/sys_clk` is a blackbox-relative path — because `sys_clk` lives inside `u_wrapper`'s sub-level `ln_quad_i/in_mmcm`. Adjust the prefix to your DCP's real hierarchy.

## 3. be stage: instantiate with -gate (the most-missed step!)

A blackbox probe **must append `-gate`** at the be stage, and the position matters: after `link_design`, before `trigger_probe -check`.

```tcl
read_netlist
link_design                     ;# ★ must link first so the blackbox instance is resolved

# --- re-declare the blackbox probes at the be stage (with -gate) ---
probe_net -blackbox_instance {<parent>/<bbox_inst>} \
          -clock {<sub>/clk_name} \
          -add {<sub>/sig[0] <sub>/sig[1]} -gate    ;# ★ -gate, and no * wildcard
trigger_net -add -group <group_name> \
            -blackbox_instance {<parent>/<bbox_inst>} \
            -clock {...} \
            -signal {<sub>/trig[0] <sub>/trig[1]} -gate

instrument_design
sanitize_design
init_runtime_data
trigger_probe -check            ;# ★ validates that blackbox signals resolved (most "not found" errors surface here)
sweep_design
# ... transform_clock ...
trigger_probe -group            ;# ★ package into a pseudo-IP
sweep_design -remap
```

**The blackbox instance path format differs at the be stage**: gate-level, `/`-separated, **without the top**, of the form `<parent>/<bbox_inst>`.
- fe: `xs_fpga_top_debug_1902.u_wrapper` (`.`-separated, with top)
- be: `u_wrapper` (the top is flattened at be; if the blackbox hangs under a sub-level, write `parent/blackbox`, e.g. `inst0/bbox1`)

> The be path is whatever the netlist shows after `link_design`. If unsure, query with `get_cells -hier *<blackbox_instance_name>*`.

## 4. runtime stage: capture on board

Identical to a normal probe — see sibling skill `uv-waveform-probe` §5. Core flow:

```tcl
query -trigger
query -trigger -name <group_name>          ;# confirm the blackbox trigger group was set up
trigger -set -condition ./user_script/uhd_setting.ini -position 5   ;# trigger values live in the ini
capture -enable
trigger -enable
set r [trigger -status -wait 1 -timeout 30 -tclobj]   ;# wait for trigger; confirm it hit before uploading
upload_uhd -depth 1000000 -out test_uhd -force
wavegen -bindir ./UHD/test_uhd       ;# produces ./UHD/test_uhd/UvData.usdb
#uvgui -u ./UHD/test_uhd/UvData.usdb
```

- `probe_net` captures without a trigger, but `trigger_net` is required for conditional triggering (the trigger value is written in `uhd_setting.ini`).
- **Group name must match in three places**: `probe.tcl`'s `trigger_net -group`, `uhd_setting.ini`'s `[...]`, and `hw_run.tcl`'s `query -trigger -name`.

> Blackbox signals carry an extra path prefix, so in the runtime GUI / ini file the signal name is prefixed with the blackbox instance — locate it via the hierarchy.

## 5. Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| fe reports `cannot find blackbox instance` | wrong `-blackbox_instance` path (missing top, or wrong instance name) | `report_resource -depth 5` to see the real hierarchy; include top, `.`-separated |
| fe reports `blackbox internal clock not allowed` | `allow_local_clock` not enabled | add `set_option signal.uhd.sampling_clock.allow_local_clock true` at the fe head |
| fe reports `signal not found in blackbox` | wrong signal relative path (includes the blackbox root, or wrong level) | drop the blackbox root, start from the first sub-level; write bit-by-bit, no bus name |
| be `trigger_probe -check` reports `gate signal not found` | be missing `-gate`, or wrong be instance path format (includes top) | in be use the `/` format without top for `-blackbox_instance`, and append `-gate` to the command |
| be reports `wildcard not supported in backend` | be used `sig[*]` | expand bit-by-bit at be: `sig[0] sig[1] ...` |
| fe/be both pass but nothing captured on board | the sampling clock and signals were partitioned onto different FPGAs | single-FPGA designs (this repo uses `set_fpga_count -number 1`) are naturally fine; multi-FPGA needs a constraint pinning them to the same FPGA |
| Signals show X / all-0 in the waveform | the blackbox DCP isn't actually running / clock not up | first confirm the blackbox's top-level ports have activity; retry with a top-level global clock |

## 6. Re-run decisions

| What changed | Re-run |
|---|---|
| add/remove blackbox probes, change signals | `fe` → `be` (probes register in fe, instantiate in be) |
| add the `allow_local_clock` option | `fe` → `be` (option takes effect in fe) |
| only change the be `-gate` path | just `be` |
| change the DCP itself (re-synthesize in frontend Vivado) | frontend synth → `make links` → `fe` → `be` |

## 7. Authoritative references

| Content | Path / section |
|---|---|
| **Blackbox probe syntax (core)** | `UVHS-2-Compiler-UG-Part2-Proto-Setup-...pdf` **§7.12** |
| Sampling-clock option | same, **§7.12 Note1** `signal.uhd.sampling_clock.allow_local_clock` |
| Normal probe syntax (for contrast) | same, §7.11 |
| probe_net / trigger_net command reference | `UVHS-2-Compile-CMD-RfM-...pdf` |
| runtime capture / wavegen | `UVHS-2-Prototyping-Runtime-UG-...pdf` |

UG path: `/nfs/tools/uvhs/p4_20260602/doc/UVHS-2/user_guide/`

## 8. Template files (bundled with this skill)

- `templates/probe_bbox.tcl` — fe blackbox probe declaration (can be `source`d directly)
- `templates/backend_blackbox_probe.tcl` — shows where to place the be `-gate` instantiation
