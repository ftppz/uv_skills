# =============================================================================
# probe_multi_clock.tcl template — DUAL / MULTI CLOCK DOMAIN
# Fill in the <...> parts. Add one block per extra clock domain.
#
# Rule (the #1 multi-domain mistake):
#   probe_net  may mix domains (each capture station keeps its own clock).
#   trigger_net MUST NOT — one group PER clock domain, unique group names.
# =============================================================================
#
# ---- Domain 1: <domain_1_name> ----
probe_net -clock { <top>.<inst_1>.<clock_1> } -add { \
    <top>.<inst_1>.<signal_1a> \
    <top>.<inst_1>.<signal_1b> \
}

trigger_net -add -group <group_1> \
    -clock <top>.<inst_1>.<clock_1> \
    -signal { \
    <top>.<inst_1>.<trigger_signal_1> \
}

# ---- Domain 2: <domain_2_name>  (DIFFERENT group name, its OWN clock) ----
probe_net -clock { <top>.<inst_2>.<clock_2> } -add { \
    <top>.<inst_2>.<signal_2a> \
    <top>.<inst_2>.<signal_2b> \
}

trigger_net -add -group <group_2> \
    -clock <top>.<inst_2>.<clock_2> \
    -signal { \
    <top>.<inst_2>.<trigger_signal_2> \
}

# ---- (optional) Domain 3, 4, ... copy the block above, new group name each ----
