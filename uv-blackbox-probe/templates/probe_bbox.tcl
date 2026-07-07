# =============================================================================
# probe_bbox.tcl — 黑盒（DCP）内部信号探针 [fe 阶段声明]
#
# 用法: 在 frontend.tcl 里 create_working_space 之后:
#     set_option signal.uhd.sampling_clock.allow_local_clock true
#     source ./user_script/probe_bbox.tcl
#
# ★ 三条铁律 (违反一条就抓不到):
#   1. -blackbox_instance 用全路径 (带顶层, . 分隔), 如 xs_fpga_top_debug_1902.u_wrapper
#   2. -clock / -add 里的路径从黑盒【第一级子层次】起, 【不带黑盒根】, / 分隔
#   3. 采样时钟来自黑盒内部时, 必须先开 allow_local_clock
#
# 参考 UG Part2 §7.12 + 附录 B.11
# =============================================================================

# ---- 用户必须改这三行 ----
set BBOX_INST   "xs_fpga_top_debug_1902.u_wrapper"          ;# 黑盒实例全路径(带顶层)
set BBOX_CLOCK  "ln_quad_i/in_mmcm/sys_clk"                 ;# 黑盒内时钟相对路径(不带根)
# 要抓的黑盒内信号(逐位, fe 支持 * 通配):
set BBOX_PROBE  [list \
    ln_quad_i/<你的层次>/<信号>[0] \
    ln_quad_i/<你的层次>/<信号>[1] \
    ln_quad_i/<别的层次>/<flag> \
]

# =============================================================================
# 探针声明 (一般不用改下面)
# =============================================================================

probe_net -blackbox_instance $BBOX_INST \
          -clock $BBOX_CLOCK \
          -add $BBOX_PROBE

# 可选: 触发组 (条件采集时才需要)
# trigger_net -add -group bbox_gp0 \
#             -blackbox_instance $BBOX_INST \
#             -clock $BBOX_CLOCK \
#             -signal $BBOX_PROBE
