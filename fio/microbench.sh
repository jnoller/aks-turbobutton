#!/usr/bin/env bash

# Micro/user-case benchmark script

# /os-disk
# /dev/sdf1        32895856 13632448   17569356  44% /32gb
# /dev/sde1       131979748    60984  125191548   1% /128gb
# /dev/sdd1      1056762036 13656352  989402260   2% /1024gb
# /dev/sdc1      2113655728 13655060 1992610156   1% /2048gb


DEBUG=${DEBUG:=0}
MAXRUNS=${MAXRUNS:=5}
BCCENABLED=${BCCON:=0}
WARMCACHE=${WARMCACHE:=1}

timestamp=$(date +%T)
resultsdir_base="$PWD/test_results"
resultsdir="${resultsdir_base}-${timestamp}"
diagdir="${resultsdir}/diagnostics"
testsdir="$PWD/micro_tests"
drive_dirs=("/os-disk" "/ephemeral" "/32gb" "/128gb" "/1024gb" "/2048gb")
PROCESS_FORKS=()

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
    target=$1
    echo "diagnostics dir: ${target}"


    bcc_cmds=("ext4slower 1 -j"
            "biosnoop -Q"
            "gethostlatency"
            "runqlat -m 5")
    base_cmds=("iotop -b --only")
    # add top cpu mem

    if [ "${BCCENABLED}" -eq 1 ]; then
        for comm in ${bcc_cmds[*]}; do
            precmd="sudo nohup bash"
            bccpath="/usr/share/bcc/tools"
            logn=$(echo "${comm}" | awk '{print $3}')
            echo $logn
            postcmd=">> ${target}/${logn}.log"
            # Execute tracked subshell
            echo "${precmd} ${bccpath}/${comm} ${postcmd}"
            new_pid=$!
            PROCESS_FORKS+=("${new_pid}")
        done
    fi
    for comm in ${base_cmds[*]}; do
        precmd="sudo bash"
        logn=$(echo "${comm}" | awk '{print $3}')
        postcmd=">> ${target}/${logn}.log"
        echo "${precmd} ${comm} ${postcmd}"
        new_pid=$!
        echo $new_pid
        PROCESS_FORKS+=("${new_pid}")
    done

}

function onexit() {
    for x in "${PROCESS_FORKS[@]}"; do
        kill "${x}"
    done
}



main () {

    trap onexit INT TERM ERR
    trap onexit EXIT
    echo "checking ${resultsdir}"

    mkdir -p "${resultsdir}"

    interrogate

    for directory in "${drive_dirs[@]}"; do
        dname=$(basename "${directory}")
        mkdir -p "${resultsdir}/${dname}"
        echo "moving to ${directory}"
        cd "${directory}" || exit 1
        rm -rf "${directory:?}/*"
        globber="${testsdir}/*.sh"
        for f in $globber; do
            echo "setting up for ${f}"
            scr="${directory}/scratch-temp"
            # Setup scratch directory for tests
            rm -rf "${scr}" && mkdir -p "${scr}"
            script=$(realpath "${f}")
            scriptpath=$(dirname "${script}")
            if [ "${DEBUG}" -eq 1 ]; then
                echo "  file: ${f}"
                echo "  scratch: ${scr}"
                echo "  script: ${script}"
                echo "  scriptpath: ${scriptpath}"
            fi
            if [ "${WARMCACHE}" -eq 1 ]; then
                # Execute the command without timing to warm the cache
                echo "warming the cache with initial ${f} execution"
                ${script} ${scr} >${scr}/cmd.out.log
                rm -rf "${scr}" && mkdir -p "${scr}"
            fi
            base=$(basename "${script}")
            diagdir="${resultsdir}/${directory}/diagnostics"
            mkdir -p "${diagdir}"
            # spawn_watchers "${diagdir}"
            # exit
            # Run a loop of $MAXRUNS iterations
            for (( c=1; c<=MAXRUNS; c++ )); do

                result="${resultsdir}${directory}.${base}.results"
                echo "[TEST] disk: ${directory} test: ${script} run: $c stamp: $(date)"
                /usr/bin/time -o "${result}" --append -f "%E real,%U user,%S sys" "${script}" "${scr}"
                echo "[RESULT] result ${c}: $(tail -n 1 ${result})"
                rm -rf "${scr}" && mkdir -p "${scr}"
            done

            rm -rf "${directory}/scratch-temp"
        done
    done
}

main
