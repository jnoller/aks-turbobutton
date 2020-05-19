#!/usr/bin/env bash
for device in /sys/block/sd*;
do
    sudo echo ${scheduler} > \$device/queue/scheduler
    sudo echo ${read_ahead_kb} > \$device/queue/read_ahead_kb
    sudo echo ${max_sectors_kb} > \$device/queue/max_sectors_kb
done

echo "${transparent_hugepage}" > /sys/kernel/mm/transparent_hugepage/enabled
sudo echo 1 > /proc/sys/vm/panic_on_oom
sudo echo 0 > /proc/sys/vm/swappiness
sudo echo 5 > /proc/sys/kernel/panic
