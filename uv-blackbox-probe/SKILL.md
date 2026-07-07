---
name: uv-blackbox-probe
description: 抓取 UVHS-2 工程里 DCP 黑盒（black box，如预综合 IP ln_quad_wrapper / DW_axi_dmac）**内部**信号的波形。这是 uv-waveform-probe 的姊妹 skill——后者只能探顶层/非黑盒信号。本 skill 用 probe_net / trigger_net 的 -blackbox_instance（fe）与 -gate（be）语法，把探针伸进黑盒内部网表。涵盖：fe 登记信号 → be 用 -gate 落地 → runtime 采集 → uvd/uvgui 查看。
---

# UVHS-2 黑盒（DCP）内部信号探针

抓**黑盒 IP 内部**的信号。前提是黑盒以 `set_blackbox -source_file xxx.dcp` 形式挂入（DCP 里有真实网表，不是空壳 stub）。

> 抓**顶层 / 非黑盒**信号 → 用姊妹 skill `uv-waveform-probe`，不要用本 skill。
> 本 skill 是对 UG Part2 §7.12「Defining UHD probe and trigger for black boxes」的落地。

## 0. 关键认知（先读这段，不然一定踩坑）

黑盒内部信号探针和普通探针**三处不同**，错一处就抓不到：

| 不同点 | 普通信号（顶层/非黑盒） | 黑盒内部信号（本 skill） |
|--------|------------------------|--------------------------|
| **信号路径格式** | RTL 全路径 `top.a.b.sig`（`.` 分隔，带顶层） | **gate 级**，从黑盒**第一级子层次**起，**不带黑盒根**，用 `/` 分隔：`ins1/sub/sig` |
| **采样时钟** | 可用任意全局时钟 | 若用黑盒内部时钟，**必须** `set_option signal.uhd.sampling_clock.allow_local_clock true` |
| **be 落地** | `probe_net ...` / `trigger_net ...` | 后面**必须加 `-gate`**，且在 `link_design` 之后、`trigger_probe -check` 之前 |

还有一个**硬约束**：采样时钟和被采的黑盒信号必须落到**同一片 FPGA**。单 FPGA 工程（`set_fpga_count -number 1`）天然满足；多 FPGA 工程要确认 partition 后两者没被切到不同片。

## 1. 动手前必须问清的三件事

### 1.1 黑盒实例的层次路径是什么？
格式：`<顶层模块>.<...>.<黑盒实例名>`（fe 阶段，带顶层、`.` 分隔）。

怎么找：
- 看顶层 RTL 的实例化：`grep "<module_name> <inst_name>" rtl/*.sv`
- 例：本仓库 `xs_fpga_top_debug_1902.sv` 里 `ln_quad_wrapper u_wrapper` → fe 实例路径 = `xs_fpga_top_debug_1902.u_wrapper`
- 在 uv_shell 里 `report_resource -depth 5` / `link_design` 后看层次树

### 1.2 目标信号在黑盒内的相对路径是什么？
格式：从黑盒**第一级子层次**起，**不带黑盒根**，`/` 分隔。
- 错：`u_wrapper/ln_quad_i/foo/reg`（带了黑盒根 `u_wrapper`）
- 对：`ln_quad_i/foo/reg`（从 `u_wrapper` **里面第一层** `ln_quad_i` 起）
- **逐位写**：黑盒信号不支持 bus 整体，要拆成 `sig[0] sig[1]`（fe 支持 `sig[*]` 通配，be 不支持）
- 怎么找路径：在前端 Vivado 工程里 `report_hierarchy`，或打开 DCP 用 `get_cells`/`get_nets` 查

### 1.3 用哪个时钟采样？
- 黑盒**内部**时钟（如 `u_wrapper.sys_clk` 这种 MMCM 输出）→ 必须开 §0 那个开关，且 `-clock` 写**黑盒内相对路径**（`<sub>/clk_name`，不带黑盒根）
- 顶层**全局**时钟（如 `debug_clk`）→ 不用开开关，`-clock` 写正常全路径
- 多数情况 CPU/SoC 的时钟都在 wrapper 里（MMCM），所以**默认要开开关**

## 2. fe 阶段：登记探针

### 2.1 先开采样时钟开关（若用黑盒内时钟）

放在 `frontend.tcl` 里 `create_working_space` 之后、`source probe.tcl` 之前：

```tcl
set_option signal.uhd.sampling_clock.allow_local_clock true
```

> 默认 false。不开的话，用黑盒内时钟采样会报错或抓不到。

### 2.2 写 probe_net / trigger_net（fe 语法）

```tcl
# === 黑盒内部探针 ===
# -blackbox_instance: 黑盒实例全路径（带顶层、. 分隔）
# -clock:            采样时钟。若来自黑盒内部，写黑盒内相对路径（不带黑盒根）
# -add:              目标信号，黑盒内相对路径（不带黑盒根，/ 分隔），逐位写或用 *
probe_net -blackbox_instance {<顶层>.<...>.<黑盒实例>} \
          -clock {<黑盒内时钟相对路径>} \
          -add {
              <sub>/path/sig[0]
              <sub>/path/sig[1]
              <sub>/other/flag
          }

# === 黑盒内部触发（可选）===
trigger_net -add -group <组名> \
            -clock {<黑盒内时钟相对路径>} \
            -blackbox_instance {<顶层>.<...>.<黑盒实例>} \
            -signal {
              <sub>/path/trig_sig[0]
              <sub>/path/trig_sig[1]
            }
```

**fe 支持通配符 `*`**：`-add {sub/data[*]}` 会展开所有位。be 不支持，只能逐位。

### 2.3 本仓库的具体例子

黑盒 `ln_quad_wrapper` 实例 `u_wrapper`，采样时钟 `sys_clk`（黑盒内 MMCM 输出）：

```tcl
# frontend.tcl 里
set_option signal.uhd.sampling_clock.allow_local_clock true
source ./user_script/probe_bbox.tcl   ;# 把下面这段单独放一个文件

# probe_bbox.tcl
probe_net -blackbox_instance {xs_fpga_top_debug_1902.u_wrapper} \
          -clock {ln_quad_i/in_mmcm/sys_clk} \
          -add {
              ln_quad_i/.../<你的目标信号>
          }
```
> 时钟路径 `ln_quad_i/in_mmcm/sys_clk` 是黑盒内相对路径——因为 `sys_clk` 在 `u_wrapper` 的子层 `ln_quad_i/in_mmcm` 里。具体前缀要照你 DCP 里的真实层次改。

## 3. be 阶段：用 -gate 落地（最易漏！）

黑盒探针在 be 阶段**必须加 `-gate`**，且位置有讲究：在 `link_design` 之后、`trigger_probe -check` 之前。

```tcl
read_netlist
link_design                     ;# ★ 必须先 link，把黑盒实例解析出来

# --- 黑盒探针在 be 阶段重声明一遍（带 -gate）---
probe_net -blackbox_instance {<parent>/<bbox_inst>} \
          -clock {<sub>/clk_name} \
          -add {<sub>/sig[0] <sub>/sig[1]} -gate    ;# ★ -gate，且不能有 *
trigger_net -add -group <组名> \
            -blackbox_instance {<parent>/<bbox_inst>} \
            -clock {...} \
            -signal {<sub>/trig[0] <sub>/trig[1]} -gate

instrument_design
sanitize_design
init_runtime_data
trigger_probe -check            ;# ★ 校验黑盒信号是否解析到（最常在这里报 not found）
sweep_design
# ... transform_clock ...
trigger_probe -group            ;# ★ 打包 pseudo-IP
sweep_design -remap
```

**be 阶段黑盒实例路径格式不同**：gate-level，用 `/` 分隔，**不带顶层**，形如 `<parent>/<bbox_inst>`（父层/黑盒名）。
- fe：`xs_fpga_top_debug_1902.u_wrapper`（`.` 分隔，带顶层）
- be：`u_wrapper`（顶层在 be 已展平；若黑盒挂在某个子层下，则写 `父层/黑盒名`，如 `inst0/bbox1`）

> be 路径以 `link_design` 后的网表为准，不确定时用 `get_cells -hier *<黑盒实例名>*` 查。

## 4. runtime 阶段：上板采集

与普通探针**完全一样**，参见姊妹 skill `uv-waveform-probe` 的第 5 节。核心流程：

```tcl
query -trigger
query -trigger -name <组名>          ;# 确认黑盒触发组建立成功
trigger -set -condition ./user_script/uhd_setting.ini -position 5   ;# 触发条件值写在 ini 里
capture -enable
trigger -enable
set r [trigger -status -wait 1 -timeout 30 -tclobj]   ;# 等触发, 确认命中后再 upload
upload_uhd -depth 1000000 -out test_uhd -force
wavegen -bindir ./UHD/test_uhd       ;# 生成 ./UHD/test_uhd/UvData.usdb
#uvgui -u ./UHD/test_uhd/UvData.usdb
```

- `probe_net` 不需要触发也能采，但 `trigger_net` 才能条件触发（触发值写在 `uhd_setting.ini`）。
- **组名三处一致**：`probe.tcl` 的 `trigger_net -group`、`uhd_setting.ini` 的 `[...]`、`hw_run.tcl` 的 `query -trigger -name`。

> 黑盒信号多了一层路径前缀，在 runtime GUI / ini 文件里信号名会带上黑盒实例前缀，按层次找。

## 5. 常见问题排查

| 现象 | 原因 | 解决 |
|---|---|---|
| fe 报 `cannot find blackbox instance` | `-blackbox_instance` 路径错（漏了顶层 / 写错实例名） | `report_resource -depth 5` 看真实层次；带顶层、`.` 分隔 |
| fe 报 `blackbox internal clock not allowed` | 没开 `allow_local_clock` | fe 头部加 `set_option signal.uhd.sampling_clock.allow_local_clock true` |
| fe 报 `signal not found in blackbox` | 信号相对路径写错（带了黑盒根 / 层次不对） | 去掉黑盒根，从第一级子层起；逐位写别用 bus 名 |
| be `trigger_probe -check` 报 `gate signal not found` | be 没加 `-gate`，或 be 实例路径格式错（带了顶层） | be 里 `-blackbox_instance` 用 `/` 格式不带顶层，命令尾加 `-gate` |
| be 报 `wildcard not supported in backend` | be 用了 `sig[*]` | be 逐位展开：`sig[0] sig[1] ...` |
| fe/be 都过但上板抓不到 | 采样时钟和信号被 partition 切到不同 FPGA | 看单 FPGA 工程（本仓库是 `set_fpga_count -number 1`，天然 OK）；多 FPGA 要加约束 pin 在同片 |
| 波形里信号是 X / 全 0 | 黑盒 DCP 实际没工作 / 时钟没起来 | 先确认黑盒顶层端口有信号；用顶层全局时钟重试一次 |

## 6. 重跑决策

| 改了什么 | 重跑 |
|---|---|
| 加/删黑盒探针、改信号 | `fe` → `be`（探针在 fe 登记、be 落地） |
| 加 `allow_local_clock` 开关 | `fe` → `be`（option 在 fe 生效） |
| 只改 be 的 `-gate` 路径 | 仅 `be` |
| 改 DCP 本身（前端 Vivado 重新 synth） | 前端 synth → `make links` → `fe` → `be` |

## 7. 权威出处

| 内容 | 路径 / 章节 |
|---|---|
| **黑盒探针语法（核心）** | `UVHS-2-Compiler-UG-Part2-Proto-Setup-...pdf` **§7.12** |
| 采样时钟开关 | 同上 **§7.12 Note1** `signal.uhd.sampling_clock.allow_local_clock` |
| 普通探针语法（对照） | 同上 §7.11 |
| probe_net / trigger_net 命令行参考 | `UVHS-2-Compile-CMD-RfM-...pdf` |
| runtime 采集 / wavegen | `UVHS-2-Prototyping-Runtime-UG-...pdf` |

UG 路径：`/nfs/tools/uvhs/p4_20260602/doc/UVHS-2/user_guide/`

## 8. 模板文件（本 skill 附带）

- `templates/probe_bbox.tcl` — fe 阶段黑盒探针声明（可直接 `source`）
- `templates/backend_blackbox_probe.tcl` — be 阶段 `-gate` 落地位置示意
