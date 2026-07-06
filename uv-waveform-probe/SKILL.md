---
name: uv-waveform-probe
description: 在 UVHS-2 原型平台上抓取并查看某个模块/信号的波形。涵盖完整四阶段流程：fe 注册（probe_net/trigger_net）→ be 落地（trigger_probe -check/-group）→ runtime 采集（capture/upload_uhd）→ uvgui/uvd 查看 .usdb 波形。
---

# UVHS-2 波形探针与触发（probe / trigger）

在 UVHS-2 原型平台上抓波形，信号要经过**四个阶段**才能最终在波形窗口里看到：

```
① fe 阶段:  probe_net / trigger_net    → 把信号"登记"进设计
② be 阶段:  trigger_probe -check/-group → 把登记的信号"落地"成硬件 pseudo-IP
③ runtime:  hw_run.tcl capture/upload   → 上板触发并采集
④ 查看:     uvgui/uvd                   → 打开 .usdb 波形
```

**最容易漏的是第 ② 阶段**（backend 里的 `trigger_probe -check` 和 `trigger_probe -group`）。漏了这两步，fe 不报错、be 也不报错，但上板后抓不到信号——因为信号根本没落到硬件。

---

## 0. 适用前提

- UVHS-2 V2025.06.P4（或同系列），原型（prototyping / APS）流程。
- 设计已能 fe + be 编译通过（`make uv_fe && make uv_be` 出 bitstream）。
- 想观察的信号在 fe 阶段**可见**（顶层端口、或非黑盒的内部 RTL 信号）。
  - 黑盒 IP（DCP）**内部信号不可探**，只能探它的顶层端口或 port-to-top 的连线。

---

## 1. 用户需要提供什么（动手前必须先问清）

### 1.1 要观察哪些信号？
- 信号**全路径**（fe 阶段格式：`<顶层模块>.<实例>.<信号名>`）。
  - ⚠️ 顶层模块名不一定是 `top`！要看设计的真实顶层 module 名。
    - 例：`xs_fpga_top_debug_1902.S_AXI_MEM_awaddr`（顶层叫 xs_fpga_top_debug_1902）。
    - 例：`top.u_xdma.cfg_ltssm_state`（顶层叫 top）。
- 多位 bus：`top.u.x.data[5:0]`，或用通配 `top.u.x.data[*]`。
- 黑盒内部信号？**不行**——只能探黑盒顶层端口或它到 top 的连线。

### 1.2 用哪个时钟采样？（**关键**）
- 必须是 fe 阶段**可见的全局时钟**。
- **不能用黑盒内部时钟**（probe_net 文档明令：`Specifying a blackbox internal clock as the sampling clock is not supported`）。
- 慢变化状态信号（LTSSM、link_up、busy、done）用外部参考时钟采样即可（如 100MHz sys_clk）。
- 时钟也用全路径：`xs_fpga_top_debug_1902.u_wrapper.sys_clk`（不是 `top.xxx`）。

### 1.3 要在哪里触发（trigger）？
- 触发信号 + 触发值（信号变成几时抓波形？通常是 flag 0→1）。
- 例：`user_lnk_up = 1`、`tx_done = 1`、`awvalid = 1`。

### 1.4 顶层模块名
- 从设计的顶层 RTL 找 `module <名字>`，probe/trigger 里所有路径都以此为根。
- 不是固定的 `top`——参考工程用的是 `xs_fpga_top_debug_1902`。

### 1.5 工程脚本位置（确认 fe/be 脚本名）
- 常见：`user_script/frontend.tcl`（fe）/ `user_script/backend.tcl`（be）/ `user_script/hw_run.tcl`（runtime）。
- 也可能叫 `fe_run.tcl` / `be_run.tcl`。先 `grep -l source.*probe user_script/*.tcl` 找到 fe 脚本。

---

## 2. fe 阶段：probe.tcl（注册探针 + 触发组）

`probe.tcl` 在 fe 阶段被 source（frontend.tcl / fe_run.tcl 里有 `source ./user_script/probe.tcl`）。

### 2.1 `probe_net` —— 把信号加入探针（必写）

```tcl
# 语法
probe_net -clock { <采样时钟全路径> } -add { <信号全路径> ... }

# 例子：探 AXI 总线 + 状态信号
probe_net -clock {xs_fpga_top_debug_1902.u_wrapper.sys_clk} -add { \
    xs_fpga_top_debug_1902.S_AXI_MEM_awaddr \
    xs_fpga_top_debug_1902.S_AXI_MEM_awvalid \
    xs_fpga_top_debug_1902.S_AXI_MEM_arready \
    xs_fpga_top_debug_1902.cpu_setn_rflag \
}
```

- `-clock`：采样时钟全路径，**必须可见、非黑盒内部**。
- `-add { ... }`：信号列表，用 RTL 全路径。bus 和 `*` 通配都支持。
- 行尾用 `\` 续行（参考工程就是这么写的）。

### 2.2 `trigger_net` —— 定义触发组（想触发时写）

```tcl
# 语法（-probe 可选，看是否复用已注册探针）
trigger_net -add -group <组名> \
    [-probe] \
    -clock <采样时钟> \
    -signal { <触发信号全路径> ... }

# 例子
trigger_net -add -group test \
    -clock xs_fpga_top_debug_1902.u_wrapper.sys_clk \
    -signal { \
    xs_fpga_top_debug_1902.S_AXI_MEM_awready \
    xs_fpga_top_debug_1902.cpu_setn_rflag \
    }
```

- `-group <组名>`：触发组名，要和 uhd_setting.ini / hw_run.tcl 里一致。
- `-probe`：**可选**。加上表示信号来自已注册的 probe_net（必须先注册过）；不加则 trigger_net 自己列信号。
- `-clock`：采样时钟（和 probe_net 的一致）。
- `-signal { ... }`：触发信号列表（通常 1 位 flag）。

---

## 3. be 阶段：trigger_probe（**最关键、最易漏**！）

**fe 的 probe_net/trigger_net 只是"登记"，be 阶段必须用 `trigger_probe` 把它们落地成硬件 pseudo-IP，否则上板抓不到。**

在 backend.tcl / be_run.tcl 里加这两条命令：

### 3.1 `trigger_probe -check`（在 sweep_design 之前）

```tcl
# 检查所有 probe/trigger 信号是否真实存在（漏写、拼错、黑盒内部信号都会在这里报出来）
init_runtime_data
trigger_probe -check      # ← 加这条
sweep_design
```
文档原话：`Checks whether all specified trigger/probe signals exist or not. It is called before sweep_design.`

### 3.2 `trigger_probe -group`（在 partition_design 之前）

```tcl
# 时钟处理后、partition 之前，把 probe/trigger 信号打包成 pseudo-IP
transform_clock
trigger_probe -group      # ← 加这条
sweep_design -remap       # ← 参考工程在 -group 后立刻 remap
# ... 然后 partition_design / compile_fpga
```
文档原话：`Groups all trigger/probe signals in one group to a pseudo-IP. It is called before partition_design.`

### 3.3 be 阶段完整顺序（参考工程实测）

```tcl
read_netlist
link_design
# (probe.tcl 也可在 be 这里 source，但通常放 fe)
instrument_design
sanitize_design
init_runtime_data
trigger_probe -check          # ← 检查信号存在
sweep_design
config_clock ...
infer_clock
transform_clock
trigger_probe -group          # ← 打包成 pseudo-IP
sweep_design -remap
# ... partition_design, route, compile_fpga
```

⚠️ **如果 fe/be 都不报错但上板抓不到信号**，99% 是漏了 `trigger_probe -check` / `-group`。

---

## 4. uhd_setting.ini —— 触发条件值

`trigger_net` 只定义"组里有哪些信号"，**触发值（信号=几）写在这个 ini 里**。

```ini
# uhd_setting.ini
[<触发组名>]
LOGIC = OR
<触发信号全路径> = 1

[UHD_FINAL_CONDITIONS_LOGIC]
LOGIC = OR
<触发组名>
```

例子（触发组 `test`，当 cpu_setn_rflag=1 时触发）：
```ini
[test]
LOGIC = OR
xs_fpga_top_debug_1902.cpu_setn_rflag = 1

[UHD_FINAL_CONDITIONS_LOGIC]
LOGIC = OR
test
```

- `[组名]` 要和 probe.tcl 里 `trigger_net -group` 的名字**完全一致**。
- `信号 = 值`：信号变成这个值时触发（0/1，或多位 `data = 5`）。

---

## 5. runtime：hw_run.tcl 采集段

```tcl
# ===== hw_run.tcl 触发采集段（加在 initialize 之后、exit 之前）=====
query -trigger
query -trigger -name <触发组名>
trigger -set -condition ./user_script/uhd_setting.ini -position 5
capture -enable
trigger -enable
set trigger_tag [trigger -status -wait 1 -timeout 30 -tclobj]
puts "trigger_tag: $trigger_tag"
upload_uhd -depth 1000000 -out test_uhd -force
wavegen -bindir ./UHD/test_uhd
# 波形: ./UHD/test_uhd/UvData.usdb
#uvgui -u ./UHD/test_uhd/UvData.usdb   ;# batch 跑时注释掉
```

| 参数 | 含义 | 典型值 |
|---|---|---|
| `-position 5` | 触发点在波形里的位置 | 5 |
| `-timeout 30` | 等触发最多秒数 | 慢事件 30~120 |
| `-depth 1000000` | 采样深度 | 100万，不够再加 |
| `-out test_uhd` | 原始数据目录名 | 任意 |

**触发组名三文件一致**：probe.tcl 的 `-group`、uhd_setting.ini 的 `[...]`、hw_run.tcl 的 `query -trigger -name`。

---

## 6. 完整流程（端到端）

```bash
cd <工程目录>

# 1. 改 probe.tcl（fe 注册）+ backend.tcl 加 trigger_probe -check/-group + uhd_setting.ini + hw_run.tcl

# 2. 重跑 fe + be（probe.tcl 在 fe 注册，trigger_probe 在 be 落地）
make clean && make uv_fe && make uv_be
# 注意: be 跑完看日志, 确认 trigger_probe -check 没有 "signal not found"

# 3. 上板 runtime
uv_shell -t runtime -d <平台> -workdir ./ -script user_script/hw_run.tcl | tee uv_run.log

# 4. 波形产物
ls ./UHD/test_uhd/UvData.usdb
```

---

## 7. 波形在哪、怎么查看

### 7.1 波形文件位置
```
<工程目录>/UHD/test_uhd/UvData.usdb
```
- `upload_uhd -out test_uhd` → 原始数据在 `./UHD/test_uhd/`
- `wavegen -bindir ./UHD/test_uhd` → 在该目录生成 `UvData.usdb`（UniVista 波形数据库）

### 7.2 用 uvgui 打开（需要 X11）
```bash
uvgui -u ./UHD/test_uhd/UvData.usdb
```
- 路径：`/nfs/tools/uvhs/uvd/2025.12.P2/bin/uvgui`（或更新版本目录）。
- **需要 X11 转发**（图形程序）。`ssh -X` 登录或用 X-Win32/MobaXterm。

### 7.3 用 uvd 命令行（无 X11）
```bash
uvd -u ./UHD/test_uhd/UvData.usdb
```
适合无图形界面的服务器，用 Tcl 命令查信号值。

---

## 8. 常见问题排查

| 现象 | 原因 | 解决 |
|---|---|---|
| fe 报 `signal not found` | 路径写错，或黑盒内部信号 | 改对全路径；黑盒内部不可探 |
| fe 报 `clock ... not found / blackbox internal clock` | 采样时钟是黑盒内部 | 换顶层可见全局时钟 |
| be `trigger_probe -check` 报错 | 信号在 fe 后被优化掉，或路径错 | 检查路径；确认信号没被 sweep 掉 |
| **fe/be 都不报错但上板抓不到** | **漏了 `trigger_probe -group`** | be 里 transform_clock 后加 `trigger_probe -group` + `sweep_design -remap` |
| hw_run.tcl 报 `trigger group not found` | 组名三文件不一致 | 核对 probe.tcl/ini/hw_run.tcl 的组名拼写 |
| `trigger -status` 超时 false | 触发条件没满足 | 查触发值；延长 timeout；确认 DUT 在跑 |
| `UvData.usdb` 没生成 | wavegen 路径错 | `wavegen -bindir` 指向 `upload_uhd -out` 的目录 |
| uvgui `cannot open display` | 没 X11 | `ssh -X` 或用 `uvd` |

---

## 9. 参考文档与 example

| 内容 | 路径 |
|---|---|
| probe_net / trigger_net / **trigger_probe** 命令参考 | `UVHS-2-Compile-CMD-RfM-...pdf` |
| wavegen / 查看波形 | `UVHS-2-Prototyping-Runtime-UG-...pdf` 第 9/10 章 |
| 官方 example（probe+ini+hw_run 配套） | `/nfs/tools/uvhs/p4_20260210/doc/UVHS-2/example/simple_uart/user_script/` |
| **实战参考工程**（nanhu4core，AXI+UART 探针） | `/nfs/home/lufeifan/uvhs_test/uvhs_flow/user_script/probe.tcl` + `backend.tcl` |

**最权威参照**：`uvhs_flow` 工程（已跑通）——它的 probe.tcl 探了一整套 AXI 信号，backend.tcl 完整演示了 `trigger_probe -check/-group` 的位置，照抄模式即可。
