#!/usr/bin/env bash

scheduler=${SCHEDULER:="mq-deadline"}
read_ahead_kb=${READ_AHEAD_KB:="4096"}
max_sectors_kb=${MAX_SECTORS_KB:="128"}
queue_depth=${MAX_SECTORS_KB:="64"} # Need to validate Azure guidance re: qdepth also kernel ver
transparent_hugepage=${TRANSPARENT_HUGEPAGE:="always"}



if [ ! "enabled" = "$(systemctl is-enabled ebpf_exporter.service)" ]; then
    systemctl daemon-reload
    systemctl enable ebpf_exporter.service
    systemctl restart ebpf_exporter.service
fi


# Set the scheduler and other block device tunables for all disks
for device in /sys/block/sd*;
do
    sudo echo ${scheduler} > $device/queue/scheduler
    sudo echo ${read_ahead_kb} > $device/queue/read_ahead_kb
    sudo echo ${max_sectors_kb} > $device/queue/max_sectors_kb
done

# Transparent huge pages
echo "${transparent_hugepage}" > /sys/kernel/mm/transparent_hugepage/enabled

# Disable protected kernel defaults - this is on for CIS compliance but enforces
# the OOMKiller settings
sed -i 's/--protect-kernel-defaults=true/--protect-kernel-defaults=false/g' /etc/default/kubelet

if [ ! "1" = "$(cat /proc/sys/vm/panic_on_oom)" ]; then
    sudo echo 1 > /proc/sys/vm/panic_on_oom
fi

if [ ! "0" = "$(cat /proc/sys/vm/swappiness)" ]; then
    sudo echo 0 > /proc/sys/vm/swappiness
fi

if [ ! "5" = "$(cat /proc/sys/kernel/panic)" ]; then
    sudo echo 5 > /proc/sys/kernel/panic
fi
