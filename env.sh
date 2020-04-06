# Environment / settings file for aks-turbobutton. Injected into the daemonset
# container via envFrom

TB_TUNEDEVS=1 # If true then we will drop in the tuned rc.local file
TB_REHOMEIO=1 # If true the docker/ and kubelet/ directories are moved to tmpfs
TB_SCHEDULER="noop"
TB_READ_AHEAD_KB="4096"
TB_MAX_SECTORS_KB="128"
TB_QUEUE_DEPTH ="64" # Need to validate Azure guidance re: qdepth
