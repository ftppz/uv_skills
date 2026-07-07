# =============================================================================
# backend_blackbox_probe.tcl — 黑盒探针在 be 阶段的【-gate 落地】位置示意
#
# ★ 这不是完整 backend.tcl, 只标出黑盒探针必须出现的位置。
#   把标 ★ 的片段插到你 backend.tcl 的对应位置。
#
# be 阶段和 fe 阶段有三处不同:
#   1. -blackbox_instance 用 gate 路径 (不带顶层, / 分隔): fe 的 xs_fpga_top_debug_1902.u_wrapper → be 的 u_wrapper
#   2. 命令结尾必须加 -gate
#   3. 不支持通配符 *, 信号必须逐位展开
# =============================================================================

read_netlist
link_design                     ;# ★ 必须先 link, 否则黑盒实例没解析出来

# ─────────────────────────────────────────────────────────────────
# ★ 黑盒探针在 be 阶段重声明 (link_design 之后, trigger_probe -check 之前)
# ─────────────────────────────────────────────────────────────────
probe_net -blackbox_instance {u_wrapper} \
          -clock {ln_quad_i/in_mmcm/sys_clk} \
          -add {
              ln_quad_i/<层次>/<信号>[0]
              ln_quad_i/<层次>/<信号>[1]
          } -gate                                          ;# ★ -gate!

# trigger_net -add -group bbox_gp0 \
#             -blackbox_instance {u_wrapper} \
#             -clock {ln_quad_i/in_mmcm/sys_clk} \
#             -signal {
#               ln_quad_i/<层次>/<触发>[0]
#               ln_quad_i/<层次>/<触发>[1]
#             } -gate
# ─────────────────────────────────────────────────────────────────

instrument_design
sanitize_design
init_runtime_data
trigger_probe -check          ;# ★ 在这里校验黑盒信号, 报 not found 就是上面路径写错
sweep_design

# ... config_clock / infer_clock / transform_clock ...

trigger_probe -group          ;# ★ 打包 pseudo-IP
sweep_design -remap

# 之后照常 partition_design / route_design / compile_fpga ...

# =============================================================================
# 怎么确认 be 里黑盒实例的真实路径:
#   link_design 之后, 在 uv_shell 里跑:
#     get_cells -hier -filter {IS_PRIMITIVE==false} | grep wrapper
#   或:
#     report_resource -depth 3
# =============================================================================
