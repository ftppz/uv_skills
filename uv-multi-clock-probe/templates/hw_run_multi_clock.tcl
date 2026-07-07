# =============================================================================
# hw_run_multi_clock.tcl template — trigger/capture section (multi clock domain)
# Add after initialize, before exit. Fill in <...>.
# This is ONLY the trigger/capture/upload section; keep your project's boot
# sequence (allocate / load_db / download / initialize / writemem) as-is.
# =============================================================================

trigger -clear

# ---- 1. Declare EVERY gated sampling clock FIRST (mandatory order).
#        One trigger -set -gatedclk per gated clock. -polarity is REQUIRED:
#          1|H|h = high-active,  0|L|l = low-active.
#        Global clocks (in the runtime DB) do NOT need this. ----
trigger -set -gatedclk <gate_name_1> -frequency <MHz> -polarity H
trigger -set -gatedclk <gate_name_2> -frequency <MHz> -polarity H
#   gate_name example: b0/f0/part_0/u_peri/sys_clk

# ---- 2. THEN ini_check + condition (gated clocks must already be known) ----
trigger -ini_check ./user_script/uhd_setting.ini
capture -enable
trigger -set -condition ./user_script/uhd_setting.ini -position 95
trigger -enable

# ---- 3. (your DUT kick-off: reset / run stimulus goes here) ----

# ---- 4. Wait for trigger; check status before upload ----
set r [trigger -status -wait 1 -timeout 120 -tclobj]
puts "trigger status: $r"
# Conditions Triggered AND Waveform Data Ready must be true before upload_uhd.

# ---- 5. Upload with -clock + small depth first; raise after verifying both domains.
#        Total bandwidth <= 102 Gbps / 16 GB DDR per FPGA or data corrupts. ----
upload_uhd -depth 1000000 -clock <gate_name_1> -position 95 -out test_uhd -force_overwrite

after 1000
wavegen -bindir ./UHD/test_uhd

# ---- 6. Verify both domains present ----
# query -trigger
# query -trigger -name <group_1>
# query -trigger -name <group_2>
# query -capture
