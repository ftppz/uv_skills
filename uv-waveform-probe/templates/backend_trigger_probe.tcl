# =============================================================================
# backend.tcl / be_run.tcl 里 trigger_probe 的插入位置（最关键、最易漏！）
#
# fe 的 probe_net/trigger_net 只是"登记", be 阶段必须用 trigger_probe 落地,
# 否则 fe/be 都不报错但上板抓不到信号。
#
# 下面标 ★ 的两行是要加的, 其余是典型 backend.tcl 的上下文
# =============================================================================

read_netlist
link_design

instrument_design
sanitize_design
init_runtime_data
trigger_probe -check          ;# ★ 检查所有 probe/trigger 信号是否存在(sweep_design 之前)
sweep_design

# 时钟处理
config_clock ...
infer_clock
transform_clock

trigger_probe -group          ;# ★ 打包成 pseudo-IP(partition_design 之前)
sweep_design -remap           ;# ★ 参考工程在 -group 后立刻 remap

# ... 之后照常 partition_design / route / compile_fpga
