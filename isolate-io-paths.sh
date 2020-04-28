#!/usr/bin/env bash

# Script that when run on AKS worker nodes will:

# * Isolate all docker/container IO away from the OS disk
# * Isolate all Kubelet IO away from the OS disk
#
# This resolves one of the largest drivers of workload instability and outages
# on AKS related to the primary OS disk being network-attached with limited IOPS
# shared with the OS, managed components and the users workload, containers and
# logs. Lack of isolation on the data paths leads to starvation and saturation
# of the disks/IO paths leading to systemic node failure and orphaned
# containers.
#
# Below is the output from `ext4slower` (bcc tool) on an idle AKS worker node
# - this script is reporting the measured latency from the view of the caller
# as you can see, the average call latency is 10ms+ for critical calls:
#
#
# root@aks-agentpool-27227011-vmss000000:/var/lib# /usr/local/share/bcc/tools/ext4slower 1
# Tracing ext4 operations slower than 1 ms
# TIME     COMM           PID    T BYTES   OFF_KB   LAT(ms) FILENAME
# 17:06:39 kubectl        22649  S 0       0          18.21 409299351
# 17:06:39 kubectl        22649  S 0       0          13.49 202833418
# 17:06:39 kubectl        22649  S 0       0          11.21 519796705
# 17:06:39 kubectl        22649  S 0       0           9.45 260984268
# 17:06:39 kubectl        22649  S 0       0          18.58 952019166
# 17:06:39 kubectl        22649  S 0       0          11.61 841594021
# 17:06:39 kubectl        22649  S 0       0          14.82 802337311
# 17:06:39 kubectl        22649  S 0       0          11.87 244274418
# 17:06:39 kubectl        22649  S 0       0          14.90 811413748
# 17:06:39 kubectl        22649  S 0       0          14.00 508746310
# 17:06:39 kubectl        22649  S 0       0          14.68 568583016
# 17:06:39 kubectl        22649  S 0       0          12.82 140391642
# 17:06:39 kubectl        22649  S 0       0          11.50 284264049
# 17:06:39 kubectl        22649  S 0       0          13.69 536487883
# 17:06:39 kubectl        22649  S 0       0          10.16 000606894
# 17:06:39 kubectl        22649  S 0       0          16.58 456063504
# 17:06:39 kubectl        22649  S 0       0          10.26 777799727
# 17:06:39 kubectl        22649  S 0       0          12.55 259306553
# 17:06:39 kubectl        22649  S 0       0           9.56 515625028
# 17:06:39 kubectl        22649  S 0       0          17.23 137672726
# 17:06:39 kubectl        22649  S 0       0           9.66 936605821
# 17:06:39 kubectl        22649  S 0       0          15.07 887467447
# 17:06:39 kubectl        22649  S 0       0           9.16 714335658
# ...
# 17:26:43 dockerd        3282   O 0       0           5.65 cc4d8e8c6169c7ff13f4178ff2915cbd
# 17:26:47 kubectl        61785  S 0       0         184.92 336094563
# 17:26:47 kubectl        61785  S 0       0          11.36 520242534
# 17:27:27 systemd-journa 4102   S 0       0         143.72 system.journal
# 17:27:27 systemd-journa 4102   S 0       0          10.45 system.journal
# 17:27:27 systemd-journa 4102   S 0       0           6.28 system.journal
# 17:30:01 logrotate      68166  S 0       0          31.61 status.tmp
# 17:30:01 logrotate      68168  S 0       0          36.89 status
# 17:31:43 in_cadvisor_pe 38280  W 19206   0           1.27 out_oms_cadvisorperf.b5a2f31b5f1
# 17:32:28 systemd-journa 4102   S 0       0         100.98 system.journal
# 17:32:28 systemd-journa 4102   S 0       0           9.63 system.journal
# 17:32:28 systemd-journa 4102   S 0       0           7.67 system.journal
# 17:32:34 dockerd        3282   R 4552    0           1.02 35f2e0af01bea901869569cc06f35f65
# 17:33:33 cat            75031  R 5777    0           2.45 tunnelfront.json
# 17:35:01 logrotate      77940  S 0       0          14.01 status.tmp
# 17:35:53 sh             79623  R 128     0           2.86 ebtables
#
# Please note, this is not just on AKS Linux nodes, all VM defaults will result
# in the same behavior across OSes / VM SKUs on Azure
#
#
# Currently on Azure Linux VMs the VM SKU tempfs is mounted to /mnt:
#
#   /dev/sdb1        14G   35M   13G   1% /mnt
#
# Note: cloud-config defines the mount path of the ephemeral storage
# https://cloudinit.readthedocs.io/en/latest/topics/examples.html#adjust-mount-points-mounted
#
# While unsupported, users could inject custom configuration into
# /var/lib/cloud/scripts/per-boot
#
#
# Why do I use the VM SKU ephemeral tempfs vs some other device?
#
# Currently, every VM SKU on Azure is assigned an ephemeral temp disk of a set
# size - this size varies by SKU, but that drive has some key characterisitics we
# want:
#
# 1. Its IOPS count against the VM SKU - ephemeral has hard limits, but those are
#    bounded and enforced at the vm/device. Removing the storage system means we
#    get a much faster (and stable) IO path for our containers
#
# 2. Users pay for VM cores and resources - in order to maximize that usage you
#    need to be able to maximize (and saturate) the VM. Using tempfs for the
#    data directory and isolating (one day, read only) the OS disk means that
#    your workload / containers can consume the VM totally.
#
# 3. The size of the SKU temp sets a known maxium amount of IOPS (the VM's)- therefore
#    the number of IO intensive containers users will run will be capped to the
#    __ relative ability __ of the VM SKU.
#
#
# TBD:
#     For machines/skus that have on-board NVMe or other storage, the tool will
#     format, mount and expose the local storage for users to local mount while
#     also offloading the container load to those devices.


TARGET=${WORKDIR_TARGET:="/mnt"}
DOCKER_DATA_ROOT=${TARGET}/docker
KUBELET_DATA_ROOT=${TARGET}/kubelet
LOGS_DATA_ROOT=${TARGET}/logs
DOCKER_ORIG_ROOT=/var/lib/docker
KUBELET_ORIG_ROOT=/var/lib/kubelet
LOGS_ORIG_ROOT=/var/logs
STAMP=$(date "+%Y.%m.%d-%H.%M.%S")


check_kube_bindmount () {
    if [ ! $(grep -qs '${KUBELET_DATA_ROOT}' /proc/mounts) ]; then
        return 1
    fi
    return 0
}

check_docker_bindmount () {
    if [ ! $(grep -qs '${DOCKER_DATA_ROOT}' /proc/mounts) ]; then
        return 1
    fi
    return 0
}

check_logs_bindmount () {
    if [ ! $(grep -qs '${LOGS_DATA_ROOT}' /proc/mounts) ]; then
        return 1
    fi
    return 0
}

move_and_fstab_kubelet () {
    mv -f ${KUBELET_ORIG_ROOT} ${KUBELET_DATA_ROOT} || exit 1
    echo "/mnt/kubelet /var/lib/kubelet       none    bind,nobootwait 0 0" >>/etc/fstab
}

move_and_fstab_docker () {
    mv -f ${DOCKER_ORIG_ROOT} ${DOCKER_DATA_ROOT} || exit 1
    echo "/mnt/docker /var/lib/docker       none    bind,nobootwait 0 0" >>/etc/fstab
}

move_and_fstab_logs () {
    mv -f ${LOGS_ORIG_ROOT} ${LOGS_DATA_ROOT} || exit 1
    echo "/mnt/logs /var/logs       none    bind,nobootwait 0 0" >>/etc/fstab
}

add_kube_bindmount () {
    mount --bind ${KUBELET_DATA_ROOT} ${KUBELET_ORIG_ROOT} || exit 1 # fail hard.
}

add_docker_bindmount () {
    mount --bind ${DOCKER_DATA_ROOT} ${DOCKER_ORIG_ROOT} || exit 1 # fail hard.
}

add_logs_bindmount () {
    mount --bind ${LOGS_DATA_ROOT} ${LOGS_ORIG_ROOT} || exit 1 # fail hard.
}

mutate_docker_config () {
    cp -f /etc/docker/daemon.json /etc/docker/daemon.json-${STAMP}.bak
    cat /etc/docker/daemon.json | jq --arg data_root "${DOCKER_DATA_ROOT}" '. + {"data-root": $data_root' > /etc/docker/daemon.json.new
    mv -f /etc/docker/daemon.json.new /etc/docker/daemon.json

}

restart_services() {
    systemctl is-enabled --quiet docker || systemctl enable docker
    systemctl is-enabled --quiet kubelet || systemctl enable kubelet

    systemctl is-active --quiet docker || systemctl restart docker
    systemctl is-active --quiet kubelet || systemctl restart kubelet
}

shutdown_node_services () {
    systemctl is-active --quiet docker || docker stop $(docker ps -a -q)
    systemctl is-active --quiet docker || systemctl stop docker
    systemctl is-active --quiet kubelet || systemctl stop kubelet
}

main () {

    # 1. Use mv rather than copy and rsync - the latter are not atomic which
    #    means that if the node / disk fails, we're screwed and the node may
    #    not come back. `mv` only changes the *pointer*
    # 2. Using lots of logging, or - file operations (cp, rsync) is enough
    #    to saturate most node configurations leading to IO throttling and
    #    fatal latency.
    # 3. The write cache is on for the majority of the disks / configurations
    #    in Azure, this means if 2 ^ occurs, the write cache will rapidly
    #    explode potentially losing in-flight writes
    if [ ! $(check_kube_bindmount) ]; then
        cp /etc/fstab /etc/fstab.akstb.${stamp}-prekube.bak
        shutdown_node_services || exit 1
        move_and_fstab_kubelet || exit 1
        # Two actions for atomicity - move and and add to fstab, this way if
        # the cache or the node die the mount should come back on reboot
        # then we add the bindmount.
        # thot: removing the additional function call and bindmounting in the
        # same func might be safer.
        add_kube_bindmount || exit 1
    fi
    if [ ! $(check_docker_bindmount) ]; then
        cp /etc/fstab /etc/fstab.akstb.${stamp}-predocker.bak
        shutdown_node_services || exit 1
        move_and_fstab_docker || exit 1
        # Two actions for atomicity - move and and add to fstab, this way if
        # the cache or the node die the mount should come back on reboot
        # then we add the bindmount.
        add_docker_bindmount || exit 1
        # Finally change the config files - if this fails, the system should
        # still function. I feel like a naughty god.
        mutate_docker_config || exit 1
    fi
    if [ ! $(check_logs_bindmount) ]; then
        cp /etc/fstab /etc/fstab.akstb.${stamp}-prelogs.bak
        #shutdown_node_services || exit 1
        #move_and_fstab_logs || exit 1
        # Two actions for atomicity - move and and add to fstab, this way if
        # the cache or the node die the mount should come back on reboot
        # then we add the bindmount.
        #add_logs_bindmount || exit 1
    fi
    restart_services
    exit $?
}

main "$@"
