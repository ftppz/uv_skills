# =============================================================================
# probe_bbox.tcl - blackbox (DCP) internal-signal probe [fe-stage declaration]
#
# Usage: in frontend.tcl, after create_working_space:
#     set_option signal.uhd.sampling_clock.allow_local_clock true
#     source ./user_script/probe_bbox.tcl
#
# Three iron rules (break any one and you capture nothing):
#   1. -blackbox_instance uses the full path (with top, .-separated),
#      e.g. xs_fpga_top_debug_1902.u_wrapper
#   2. paths in -clock / -add start from the blackbox's FIRST sub-hierarchy level,
#      WITHOUT the blackbox root, /-separated
#   3. when the sampling clock comes from inside the blackbox,
#      allow_local_clock MUST be enabled first
#
# Reference: UG Part2 §7.12 (incl. §7.12 Note1 for the sampling-clock option)
# =============================================================================

# ---- the user MUST change these three lines ----
set BBOX_INST   "xs_fpga_top_debug_1902.u_wrapper"          ;# blackbox instance full path (with top)
set BBOX_CLOCK  "ln_quad_i/in_mmcm/sys_clk"                 ;# blackbox-internal clock, relative path (no root)
# blackbox-internal signals to capture (bit-by-bit; fe supports the * wildcard):
set BBOX_PROBE  [list \
    ln_quad_i/<your_hierarchy>/<signal>[0] \
    ln_quad_i/<your_hierarchy>/<signal>[1] \
    ln_quad_i/<other_hierarchy>/<flag> \
]

# =============================================================================
# probe declaration (usually no need to change below)
# =============================================================================

probe_net -blackbox_instance $BBOX_INST \
          -clock $BBOX_CLOCK \
          -add $BBOX_PROBE

# optional: trigger group (only needed for conditional capture)
# trigger_net -add -group bbox_gp0 \
#             -blackbox_instance $BBOX_INST \
#             -clock $BBOX_CLOCK \
#             -signal $BBOX_PROBE
