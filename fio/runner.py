#!/usr/bin/env python3

numjobs=[1, 8, 16, 32, 64]
size='22gb' # Noted from fdatasync timings - see: https://www.ibm.com/cloud/blog/using-fio-to-tell-whether-your-storage-is-fast-enough-for-etcd

"""
| Premium SSD sizes | P1 | P2 | P3 | P4 | P6 | P10 | P15 | P20 | P30 | P40 | P50 | P60 | P70 | P80 |
|-------------------|----|----|----|----|----|-----|-----|-----|-----|-----|-----|------|------|------|
| Disk size in GiB | 4 | 8 | 16 | 32 | 64 | 128 | 256 | 512 | 1,024 | 2,048 | 4,096 | 8,192 | 16,384 | 32,767 |
| Provisioned IOPS per disk | 120 | 120 | 120 | 120 | 240 | 500 | 1,100 | 2,300 | 5,000 | 7,500 | 7,500 | 16,000 | 18,000 | 20,000 |
| Provisioned Throughput per disk | 25 MiB/sec | 25 MiB/sec | 25 MiB/sec | 25 MiB/sec | 50 MiB/sec | 100 MiB/sec | 125 MiB/sec | 150 MiB/sec | 200 MiB/sec | 250 MiB/sec | 250 MiB/sec| 500 MiB/sec | 750 MiB/sec | 900 MiB/sec |
| Max burst IOPS per disk | 3,500 | 3,500 | 3,500 | 3,500 | 3,500 | 3,500 | 3,500 | 3,500 |
| Max burst throughput per disk | 170 MiB/sec | 170 MiB/sec | 170 MiB/sec | 170 MiB/sec | 170 MiB/sec | 170 MiB/sec | 170 MiB/sec | 170 MiB/sec |
| Max burst duration | 30 min  | 30 min  | 30 min  | 30 min  | 30 min  | 30 min  | 30 min  | 30 min  |
| Eligible for reservation | No  | No  | No  | No  | No  | No  | No  | No  | Yes, up to one year | Yes, up to one year | Yes, up to one year | Yes, up to one year | Yes, up to one year | Yes, up to one year |
"""

az_disk_limits = { # do burst iops
                '4': {'class': 'P1', 'iops':120, 'throughput': '25MB', 'burst_iops': 3500, 'burst_throughput': '170MB', 'burst_duration': '30'},
                '8': {'class': 'P2', 'iops':120, 'throughput': '25MB', 'burst_iops': 3500, 'burst_throughput': '170MB', 'burst_duration': '30'},
                '16': {'class': 'P3', 'iops':120, 'throughput': '25MB', 'burst_iops': 3500, 'burst_throughput': '170MB', 'burst_duration': '30'},
                '32': {'class': 'P4', 'iops':120, 'throughput': '25MB', 'burst_iops': 3500, 'burst_throughput': '170MB', 'burst_duration': '30'},
                '64': {'class': 'P6', 'iops':240, 'throughput': '50MB', 'burst_iops': 3500, 'burst_throughput': '170MB', 'burst_duration': '30'},
                '128': {'class': 'P10', 'iops':500, 'throughput': '100MB', 'burst_iops': 3500, 'burst_throughput': '170MB', 'burst_duration': '30'},
                '256': {'class': 'P15', 'iops':1100, 'throughput': '125MB', 'burst_iops': 3500, 'burst_throughput': '170MB', 'burst_duration': '30'},
                '512': {'class': 'P20', 'iops':2300, 'throughput': '150MB', 'burst_iops': 3500, 'burst_throughput': '170MB', 'burst_duration': '30'},
                '1024': {'class': 'P30', 'iops':5000, 'throughput': '200MB', 'burst_iops': 3500, 'burst_throughput': '170MB', 'burst_duration': '30'},
                '2048': {'class': 'P40', 'iops':7500, 'throughput': '250MB', 'burst_iops': 3500, 'burst_throughput': '170MB', 'burst_duration': '30'},
                '4096': {'class': 'P50', 'iops':7500, 'throughput': '250MB', 'burst_iops': 3500, 'burst_throughput': '170MB', 'burst_duration': '30'},
                '8192': {'class': 'P60', 'iops':16000, 'throughput': '500MB', 'burst_iops': 3500, 'burst_throughput': '170MB', 'burst_duration': '30'},
                '16384': {'class': 'P70', 'iops':18000, 'throughput': '750MB', 'burst_iops': 3500, 'burst_throughput': '170MB', 'burst_duration': '30'},
                '32767': {'class': 'P70', 'iops':20000, 'throughput': '900MB', 'burst_iops': 3500, 'burst_throughput': '170MB', 'burst_duration': '30'},
                }

'128': {iops: 500}}


disks={ '/dev/sdc1', {'iops': 120, 'bandwidth': "20MB", "mount": '/twotb',
        '/dev/sdd1', {'iops': 120, 'bandwidth': "20MB", "mount": '/onetb',


    '/dev/sdf1', {'iops': 120, 'bandwidth': "20MB", "mount": '/dev/sdf1'
    '/dev/sde1', {}}}


/dev/sdc1      2113655728    71704 2006193512   1% /twotb
/dev/sdd1      1056762036    72984 1002985628   1% /onetb
/dev/sde1       131979748    60984  125191548   1% /128gb
/dev/sdf1        32895856 31514284          0 100% /32gb




declare -A drivemap
drivemap[foo]=bar


disks = { '/dev/sdc'
          /dev/sdd
          /dev/sde
          /dev/sdf }


benchmark_script/bench_fio --target /32gb/ --type directory --mode randwrite --numjobs=30 --iodepth=64 --size=1G --output=d2v3-30gb-notune-noatime --extra-opts rate_iops=120
