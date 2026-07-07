# =============================================================================
# backend_blackbox_probe.tcl - where to place the blackbox probe's [-gate
# instantiation] at the be stage
#
# This is NOT a complete backend.tcl - it only marks where the blackbox probe
# MUST appear. Insert the ★ fragments into the corresponding spots in your
# backend.tcl.
#
# Three differences between be and fe:
#   1. -blackbox_instance uses the gate path (/ -separated, no top),
#      of the form <parent>/<bbox_inst>:
#        fe's xs_fpga_top_debug_1902.u_wrapper -> be's u_wrapper
#      (the top is flattened at be, so only the instance name remains; if the
#       blackbox hangs under a sub-level, write parent/blackbox)
#   2. the command MUST end with -gate
#   3. the * wildcard is NOT supported - signals must be expanded bit-by-bit
# =============================================================================
# Note: <parent>/<bbox_inst> below must match the actual netlist hierarchy
# after link_design. If unsure, query it in uv_shell (see the end of this file).
# =============================================================================

read_netlist
link_design                     ;# ★ must link first, otherwise the blackbox instance isn't resolved

# ─────────────────────────────────────────────────────────────────
# ★ re-declare the blackbox probe at the be stage
#   (after link_design, before trigger_probe -check)
# ─────────────────────────────────────────────────────────────────
probe_net -blackbox_instance {<parent>/<bbox_inst>} \
          -clock {<sub>/clk_name} \
          -add {
              <sub>/<hierarchy>/<signal>[0]
              <sub>/<hierarchy>/<signal>[1]
          } -gate                                          ;# ★ -gate!

# trigger_net -add -group bbox_gp0 \
#             -blackbox_instance {<parent>/<bbox_inst>} \
#             -clock {<sub>/clk_name} \
#             -signal {
#               <sub>/<hierarchy>/<trigger>[0]
#               <sub>/<hierarchy>/<trigger>[1]
#             } -gate
# ─────────────────────────────────────────────────────────────────

instrument_design
sanitize_design
init_runtime_data
trigger_probe -check          ;# ★ validates blackbox signals here; "not found" means the path above is wrong
sweep_design

# ... config_clock / infer_clock / transform_clock ...

trigger_probe -group          ;# ★ package into a pseudo-IP
sweep_design -remap

# then continue with partition_design / route_design / compile_fpga ...

# =============================================================================
# How to confirm the blackbox instance's real path at the be stage:
#   after link_design, run in uv_shell:
#     get_cells -hier -filter {IS_PRIMITIVE==false} | grep wrapper
#   or:
#     report_resource -depth 3
# =============================================================================
