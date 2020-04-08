#!/usr/bin/env bash

# fix-node.sh

# This script is meant to be run on AKS worker nodes - technically it should work
# on any Ubuntu 16.04 Xenial worker node. This script installs:

# 1. IOVisor bcc tools / bpftrace
# 2. Cloudflare's eBPF exporter
# 3. Brendan Greggs flamegraph scripts
# 4. A customized rc.local that overrides the worker nodes IO settings
# TBD: 5. Moves all docker/ and kubelet/ data to the nodes tmpfs
# TBD: 6. Installs node problem detector in stand-alone mode so it's not trapped in
#         the main IO path mess (e.g. local kubelet & failure)
#
# TBD: 7. Uses the azure.json configuration to shut off caching on all disks

# Additional parameters to test:
#
# nf_conntrack_hashsize=131072
# kernel.pid_max=131072
# net.netfilter.nf_conntrack_max=1048576
# small / sparse db disk read ahead: 4096 /dev/sdb
# logging disk read ahead Disk (need to test with docker tempfs) 256 /dev/sd*
# vm.min_free_kbytes = 1048576 - raises kernel reserved for higher buffer counts
# kernel.numa_balancing = 0 vs 1 (depends on the kernel version)
# /queue/rq_affinity 2 (nr_requests 256, readahead 256)
#



TB_TUNEDEVS=${TB_TUNEDEVS:=1} # If true then we will drop in the tuned rc.local file
TB_REHOMEIO=${TB_REHOMEIO:=1} # If true the docker/ and kubelet/ directories are moved to tmpfs
scheduler=${TB_SCHEDULER:="noop"}
read_ahead_kb=${TB_READ_AHEAD_KB:="4096"}
max_sectors_kb=${TB_MAX_SECTORS_KB:="128"}
queue_depth=${TB_MAX_SECTORS_KB:="64"} # Need to validate Azure guidance re: qdepth also kernel ver
transparent_hugepage=${TRANSPARENT_HUGEPAGE:="always"}


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
PROCMNT="/procmnt"


# Install options
INST_BPFTRACE=${TB_INST_BPFTRACE:=1}
INST_EBPF_EXPORTER=${EBPF_EXPORTER:=1}
INST_FLAMEGRAPH=${FLAMEGRAPH:=1}
OOMKILLER_OFF=${OOMKILLER_OFF:=1}


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
    rm -f ${ETCMNT}/rc.local.backup && cp ${ETCMNT}/rc.local ${ETCMNT}/rc.local.backup
    echo "" >${ETCMNT}/rc.local

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
for device in /sys/block/sd*;
do
    sudo echo ${scheduler} > \$device/queue/scheduler
    sudo echo ${read_ahead_kb} > \$device/queue/read_ahead_kb
    sudo echo ${max_sectors_kb} > \$device/queue/max_sectors_kb
done
echo "${transparent_hugepage}" > /sys/kernel/mm/transparent_hugepage/enabled

# rc.local always wants a 0
exit 0
EOF

# echo "${queue_depth}" > /sys/block/\${device}/queue/nr_queue -> need to check kernel rev

fi


cat <<EOF >${ETCMNT}/profile.d/turbobutton.sh
    echo "==========================================="
    echo "  aks-turbobutton applied"
    echo "  missing linux tunings: /etc/rc.local"
    echo "      IO scheduler:           ${scheduler}"
    echo "      Read Ahead kb:          ${read_ahead_kb}"
    echo "      Max Sector kb:          ${max_sectors_kb}"
    echo "      "
    echo "  bpf tools: /usr/local/share/bcc/tools/"
    echo "             https://iovisor.github.io/bcc/"
    echo "==========================================="
EOF

#
# At this point the script (and container) would exit. However, in later
# versions of Kubernetes the Linux OOMKiller is forcefully re-enabled. The
# negative behavior/lack of control with the OOMKiller system ultimately leaving
# worker nodes, critical pods and services in an unknown and broken state.
#
# As this is forced on, we will loop forever watching the settings and restoring
# sane defaults to the system. (Panic on oom, 5 second wait till panic)
#
# https://sysdig.com/blog/troubleshoot-kubernetes-oom/
# https://medium.com/@zhimin.wen/memory-limit-of-pod-and-oom-killer-891ee1f1cad8
# https://stackoverflow.com/questions/57855013/why-would-kubernetes-oom-kill-a-pause-container
#
# https://github.com/kubernetes/kubernetes/issues/74151
#
# "... the system is prone to return to an unstable state since the containers
#  that are killed due to OOM are either restarted or a new pod is scheduled
#  on to the node."
# https://github.com/kubernetes/kubernetes/issues/74151#issuecomment-481750191
#
# Also - since we are in a watch-loop, we add the requires taints/labels to
# expose the other metrics endpoints AKS does not:

while :
do
    if [ ${OOMKILLER_OFF} -eq 1 ]; then
        # TBD use inotifywait
        if [ ! "1" = "$(cat ${PROCMNT}/sys/vm/panic_on_oom)" ]; then
            sudo echo 1 > ${PROCMNT}/sys/vm/panic_on_oom
        fi

        if [[ "$(grep -c "vm.panic_on_oom=" ${ETCMNT}/sysctl.conf)" -eq 0 ]]; then
            echo "vm.panic_on_oom=1" >> ${ETCMNT}/sysctl.conf
        fi

        if [ ! "0" = "$(cat ${PROCMNT}/sys/vm/swappiness)" ]; then
            sudo echo 0 > ${PROCMNT}/sys/vm/swappiness
        fi

        if [[ "$(grep -c "vm.swappiness=" ${ETCMNT}/sysctl.conf)" -eq 0 ]]; then
            echo "vm.swappiness=1" >> ${ETCMNT}/sysctl.conf
        fi

        if [ ! "5" = "$(cat ${PROCMNT}/sys/kernel/panic)" ]; then
            sudo echo 5 > ${PROCMNT}/sys/kernel/panic
        fi

        if [[ "$(grep -c "kernel.panic=" ${ETCMNT}/sysctl.conf)" -eq 0 ]]; then
            echo "kernel.panic=5" >> ${ETCMNT}/sysctl.conf
        fi
    fi
    sleep 1

done


# TBD: Explore
# vm.overcommit_memory = 2
# vm.overcommit_kbytes = 0
# Then also run the commands sysctl vm.overcommit_memory=2 and sysctl vm.overcommit_kbytes=0 to avoid the need to reboot.
#https://superuser.com/questions/1150215/disabling-oom-killer-on-ubuntu-14-04


# TODO:

# Re factor away from using the rc.local file where possible - instead add the
# loading into the loop above - this avoids the need to reboot to run experiments
#
# while :
# for setting in setting
# echo > /proc (live)
# alter sysctl.conf (persistent)
#
