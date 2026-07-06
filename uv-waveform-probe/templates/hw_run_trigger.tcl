# =============================================================================
# hw_run.tcl trigger/capture section template
# Add this to hw_run.tcl after initialize and before exit.
# Just fill in the <trigger_group> and the waveform output name.
# =============================================================================

# ---- Trigger / capture section ----
# 1. Query the trigger group (confirms the probe.tcl registration worked)
query -trigger
query -trigger -name <trigger_group>

# 2. Load the trigger condition + enable capture
trigger -set -condition ./user_script/uhd_setting.ini -position 5
capture -enable
trigger -enable

# 3. Wait for the trigger (blocking, up to `timeout` seconds; 30~120 for slow events)
set trigger_tag [trigger -status -wait 1 -timeout 30 -tclobj]
puts "trigger_tag: $trigger_tag"

# 4. Export raw data + generate the waveform (.usdb)
#    The directory name for -out and -bindir must match (both use test_uhd below)
upload_uhd -depth 1000000 -out test_uhd -force
wavegen -bindir ./UHD/test_uhd
# Waveform file: ./UHD/test_uhd/UvData.usdb

# 5. Open the waveform GUI (needs X11 forwarding; comment out when running in batch):
#uvgui -u ./UHD/test_uhd/UvData.usdb
