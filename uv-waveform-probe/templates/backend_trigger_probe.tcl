# =============================================================================
# Where to insert trigger_probe in backend.tcl / be_run.tcl
# (the most critical and most-missed step!)
#
# probe_net/trigger_net at fe only "register" - the be stage must use
# trigger_probe to instantiate them, otherwise fe/be report no errors but
# nothing is captured on board.
#
# The two lines marked ★ below are what you add; the rest is typical
# backend.tcl context.
# =============================================================================

read_netlist
link_design

instrument_design
sanitize_design
init_runtime_data
trigger_probe -check          ;# ★ verify all probe/trigger signals exist (before sweep_design)
sweep_design

# clock processing
config_clock ...
infer_clock
transform_clock

trigger_probe -group          ;# ★ package into a pseudo-IP (before partition_design)
sweep_design -remap           ;# ★ the reference project remaps right after -group

# ... then continue with partition_design / route / compile_fpga as usual
