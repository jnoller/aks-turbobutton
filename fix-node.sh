#!/usr/bin/env bash

# fix-node.sh

# This script is meant to be run on AKS worker nodes - technically it should work
# on any Ubuntu 16.04 Xenial worker node. This script installs:

# 1. IOVisor bcc tools / bpftrace
# 2. Clouderas eBPF exporter
# 3. Brendan Greggs flamegraph scripts
# 4. A customized rc.local that overrides the worker nodes IO settings
# TBD: 5. Moves all docker/ and kubelet/ data to the nodes tmpfs
# TBD: 6. Installs node problem detector in stand-alone mode so it's not trapped in
#         the main IO path mess (e.g. local kubelet & failure)
#
# TBD: 7. Uses the azure.json configuration to shut off caching on all disks

TB_TUNEDEVS=${TB_TUNEDEVS:=1} # If true then we will drop in the tuned rc.local file
TB_REHOMEIO=${TB_REHOMEIO:=1} # If true the docker/ and kubelet/ directories are moved to tmpfs
scheduler=${TB_SCHEDULER:="noop"}
read_ahead_kb=${TB_READ_AHEAD_KB:="4096"}
max_sectors_kb=${TB_MAX_SECTORS_KB:="128"}
queue_depth=${TB_MAX_SECTORS_KB:="64"} # Need to validate Azure guidance re: qdepth


TMPD='/tmp/turbobutton-tmp'
EXPORTER="https://github.com/cloudflare/ebpf_exporter/releases/download/v1.2.2/ebpf_exporter-1.2.2.tar.gz"
SVCFILE="https://raw.githubusercontent.com/jnoller/aks-turbobutton/master/ebpf_exporter.service"
BIOLATENCY="https://raw.githubusercontent.com/cloudflare/ebpf_exporter/master/examples/bio.yaml"
NPD="https://github.com/kubernetes/node-problem-detector/releases/download/v0.8.1/node-problem-detector-v0.8.1.tar.gz"

USRMNT="/usrmnt"
PYTHONMNT="/pythonmnt"
ETCMNT="/etcmnt"
USRLOCALMNT="/usrlocalmnt"
CLOUDMNT="/cloudmnt"


# Install options
INST_BPFTRACE=${TB_INST_BPFTRACE:=1}
INST_EBPF_EXPORTER=${EBPF_EXPORTER:=1}
INST_FLAMEGRAPH=${FLAMEGRAPH:=1}



if [ "${INST_BPFTRACE}" -eq 1 ]; then
    apt update && apt install python libelf-dev -y
    # inject pre-compiled bcc tools into the host (xenial only, yolo)
    rm -rf ${USRLOCALMNT}/share/bpftrace && cp -r /usr/local/share/bpftrace ${USRLOCALMNT}/share/
    rm -rf ${USRLOCALMNT}/share/bcc && cp -r /usr/local/share/bcc ${USRLOCALMNT}/share/
    rm -rf ${USRLOCALMNT}/usr/lib/libbcc* && cp -r /usr/lib/libbcc* ${USRMNT}/lib/
    rm -rf ${PYTHONMNT}/dist-packages/bcc && cp -r /usr/lib/python2.7/dist-packages/bcc ${PYTHONMNT}/dist-packages/
    chmod +x ${USRLOCALMNT}/share/bpftrace/tools/*.bt

cat <<EOF >${ETCMNT}/profile.d/bpftrace.sh
    PATH=\$PATH:/usr/local/share/bpftrace/tools:/usr/local/share/bcc/tools/
EOF

fi

if [ ! -e "${USRMNT}/local/bin" ]; then
    echo "node problem detector "
fi

if [ "${INST_EBPF_EXPORTER}" -eq 1 ]; then
    apt-get install -y wget

    # add in the bpf exporter -> sends IO latency metrics to prom
    wget -c ${EXPORTER} || exit 1
    tar -xzf ebpf_exporter*.tar.gz
    mv ebpf_exporter-*/ebpf_exporter ${USRMNT}/bin || exit 1
    wget -c ${SVCFILE} || exit 1
    mv ebpf_exporter.service ${ETCMNT}/systemd/system/ebpf_exporter.service

    mkdir -p ${ETCMNT}/ebpf_exporter
    #################################################
    # Install the biolatency configuration (https://github.com/cloudflare/ebpf_exporter/blob/master/examples/bio.yaml)
    # See: https://github.com/cloudflare/ebpf_exporter#block-io-histograms-histograms

    wget -c ${BIOLATENCY} || exit 1
    mv bio.yaml ${ETCMNT}/ebpf_exporter/config.yaml || exit 1
fi

# Install Brendan Gregg's flamegraph tools
if [ ${INST_FLAMEGRAPH} -eq 1 ]; then
    rm -rf ${USRMNT}/flamegraph ${USRMNT}/heatmap
    mv /flamegraph ${USRMNT}/flamegraph && chmod +x ${USRMNT}/flamegraph/*.pl
    mv /heatmap ${USRMNT}/heatmap && chmod +x ${USRMNT}/heatmap/*.pl

cat <<EOF >${ETCMNT}/profile.d/flamegraph.sh
    PATH=\$PATH:/heatmap:/flamegraph
EOF

fi

# Inject a custom rc.local generated from the values above. Variables are
# expanded automatically by the `cat <<EOF` if they are ${} style - $\{} should
# pass through into the script, but that would be silly.
if [ $TB_TUNEDEVS -eq 1 ]; then

cat <<EOF >${ETCMNT}/rc.local
#!/bin/sh -e
#
# rc.local
#
# This script is executed at the end of each multiuser runlevel.
# Make sure that the script will "exit 0" on success or any other
# value on error.
#
# In order to enable or disable this script just change the execution
# bits.
#
# By default this script does nothing.

if [ -e "/systemd/system/ebpf_exporter.service" ]; then
    systemctl is-active --quiet ebpf_exporter.service || systemctl daemon-reload
    systemctl is-active --quiet ebpf_exporter.service || systemctl enable ebpf_exporter.service
fi

# Set the scheduler and other block device tunables for all disks
for device in \$(ls /sys/block/sd?/);
do
    echo "${scheduler}" > \${device}/queue/scheduler
    echo "${read_ahead_kb}" > \${device}/queue/read_ahead_kb
    echo "${max_sectors_kb}" > \${device}/queue/max_sectors_kb
    echo "${queue_depth}" > \${device}/queue/queue_depth


    cat \${device}
done

# rc.local always wants a 0
exit 0
EOF

fi




cat <<EOF >${ETCMNT}/profile.d/turbobutton.sh
    echo "==========================================="
    echo "  aks-turbobutton applied"
    echo "  missing linux tunings: /etc/rc.local
    echo "  bpf tools: /usr/local/share/bcc/tools/"
    echo "             https://iovisor.github.io/bcc/"
    echo "==========================================="
EOF
