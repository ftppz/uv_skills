# =============================================================================
# probe.tcl template - fill in the <...> parts.
# Sourced automatically during the fe stage by frontend.tcl/fe_run.tcl to
# register probes and trigger groups.
# The top module name is NOT necessarily "top" - use the design's real module name.
# =============================================================================

# ---- 1. Probe: signals to observe ----
# -clock: full path to the sampling clock - must be visible, not inside a blackbox.
# -add:   full path to signals, <top_module>.<instance>.<signal>
probe_net -clock { <top_module>.<instance>.<clock> } -add { \
    <top_module>.<instance>.<signal_1> \
    <top_module>.<instance>.<signal_2> \
}

# ---- 2. Trigger group: which signal triggers the capture
#          (the trigger VALUE is written in uhd_setting.ini) ----
# -group: trigger group name - must match uhd_setting.ini / hw_run.tcl.
# -probe: optional - include to reuse signals already registered via probe_net.
trigger_net -add -group <trigger_group> \
    -clock <top_module>.<instance>.<clock> \
    -signal { \
    <top_module>.<instance>.<trigger_signal> \
}
