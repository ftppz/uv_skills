# =============================================================================
# hw_run.tcl 触发采集段模板 - 加到 hw_run.tcl 的 initialize 之后、exit 之前
# 改 <触发组名> 和波形输出名即可
# =============================================================================

# ---- 触发采集段 ----
# 1. 查询触发组(确认 probe.tcl 注册成功)
query -trigger
query -trigger -name <触发组名>

# 2. 加载触发条件 + 开启采集
trigger -set -condition ./user_script/uhd_setting.ini -position 5
capture -enable
trigger -enable

# 3. 等待触发(阻塞, 最多等 timeout 秒; 慢事件给 30~120)
set trigger_tag [trigger -status -wait 1 -timeout 30 -tclobj]
puts "trigger_tag: $trigger_tag"

# 4. 导出原始数据 + 生成波形(.usdb)
#    -out 和 -bindir 的目录名要一致(下面都用 test_uhd)
upload_uhd -depth 1000000 -out test_uhd -force
wavegen -bindir ./UHD/test_uhd
# 波形文件: ./UHD/test_uhd/UvData.usdb

# 5. 打开波形 GUI(需要 X11 转发; batch 跑时注释掉):
#uvgui -u ./UHD/test_uhd/UvData.usdb
