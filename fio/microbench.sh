#!/usr/bin/env bash

# Micro/user-case benchmark script

# /os-disk
# /dev/sdf1        32895856 13632448   17569356  44% /32gb
# /dev/sde1       131979748    60984  125191548   1% /128gb
# /dev/sdd1      1056762036 13656352  989402260   2% /1024gb
# /dev/sdc1      2113655728 13655060 1992610156   1% /2048gb


DEBUG=${DEBUG:=0}
MAXRUNS=${MAXRUNS:=5}
BCCON=${BCCON:0}
timestamp=$(date +%T)
resultsdir_base="$PWD/test_results"
resultsdir_base="${resultsdir_base}-${timestamp}"
testsdir="$PWD/micro_tests"
drive_dirs=("/os-disk" "/32gb" "/128gb" "/1024gb" "/2048gb")
forks=()

interrogate () {
    fn="${resultsdir}/system-info"
    echo "$(uname -a)" >>$fn
    sudo echo "$(echo "cpu:    ")" "$(cat /proc/cpuinfo  | grep "model name" | head -1 | cut -d":" -f2)" >>$fn
    sudo echo "$(echo "cores:    ")" "$(cat /proc/cpuinfo  | grep processor | wc -l)" >>$fn
    echo "===========================================================" >> $fn
    for device in /sys/block/sd*;
    do
        echo "Device:     ${device}"

        sudo echo "$(echo "scheduler:    ")" "$(cat $device/queue/scheduler)" >>$fn
        sudo echo "$(echo "read_ahead_kb:    ")" "$(cat $device/queue/read_ahead_kb)" >>$fn
        sudo echo "$(echo "max_sectors_kb:    ")" "$(cat $device/queue/max_sectors_kb)" >>$fn
    done
    sudo echo "$(echo "transparent_hugepage:    ")" "$(cat /sys/kernel/mm/transparent_hugepage/enabled)" >>$fn
    sudo echo "$(echo "panic_on_oom:    ")" "$(cat /proc/sys/vm/panic_on_oom )">>$fn
    sudo echo "$(echo "swappiness:    ")" "$(cat /proc/sys/vm/swappiness)" >>$fn
    sudo echo "$(echo "kernel panic:    ")" "$(cat /proc/sys/kernel/panic)" >>$fn
    sudo echo "\n\n" >> $fn
    sudo echo "$(df -h)" >>$fn
    chmod a+rw ${fn}
}

spawn_watchers () {
    iottop_cmd="iotop --only -b >${resultsdir}/iotop.log"
    iostat_cmd="iostat --only -b >${resultsdir}/iostat.log"
    ext4slower_cmd="ext4slower 1 -j >${resultsdir}/ext4slower.log"
    biosnoop_cmd="biosnoop -Q >${resultsdir}/biosnoop.log"
    gethostlatency_cmd="gethostlatency >${resultsdir}/hostlatency.log"
    schedulerlat_cmd="runqlat -m 5 >${resultsdir}/scheduler-latency.log"
    if [ "${BCCON}" -eq 1 ]; then
    # command_list=(iottop_cmd iostat_cmd ext4slower_cmd biosnoop_cmd gethostlatency schedulerlat_cmd)
    # command_list=(ext4slower_cmd biosnoop_cmd)
        command_list=(ext4slower_cmd biosnoop_cmd gethostlatency schedulerlat_cmd)
    else
        command_list=(iottop_cmd iostat_cmd)
    fi
    for comm in "${command_list[@]}"; do
        ${comm} &
        new_pid=$!
        forks+=("${new_pid}")
    done

}

function onexit() {
    for x in "${forks[@]}"; do
        kill "${x}"
    done
}



main () {
    trap onexit 0 # Havest/sigquit all subshells - forks() array
    echo "checking ${resultsdir}"

    mkdir -p "${resultsdir}"

    interrogate

    for directory in "${drive_dirs[@]}"; do
        echo "moving to ${directory} ============ \n"
        cd "${directory}" || exit 1
        rm -rf "${directory:?}/*"
        globber="${testsdir}/*.sh"
        for f in $globber; do
            echo "setting up for ${f}"
            scr="${directory}/scratch-temp"
            # Setup scratch directory for tests
            rm -rf "${scr}" && mkdir -p "${scr}"
            echo "made ${scr}"
            # Execute the command without timing to warm the cache
            echo "warming the cache with initial ${f} execution"
            script=$(realpath "${f}")
            scriptpath=$(dirname "${script}")
            if [ "${DEBUG}" -eq 1 ]; then
                echo "  file: ${f}"
                echo "  scratch: ${scr}"
                echo "  script: ${script}"
                echo "  scriptpath: ${scriptpath}"
            fi
            ${script} ${scr} > ${scr}/cmd.out.log
            rm -rf "${scr}" && mkdir -p "${scr}"

            # Run a loop of $MAXRUNS iterations
            for (( c=1; c<=MAXRUNS; c++ )); do
                base=$(basename "${script}")
                result="${resultsdir}/${base}.time.out"
                echo "============ ${script} iteration $c ============ "
                /usr/bin/time -o "${result}" --append -f "%E real,%U user,%S sys" "${script}" "${scr}"
                cat "${result}"
                rm -rf "${scr}" && mkdir -p "${scr}"
            done

            rm -rf "${directory}/scratch-temp"
        done
    done
}

main
