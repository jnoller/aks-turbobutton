# aks-turbobutton

> **WARNING**: This tool is not officially supported by Microsoft, Azure or AKS
> applying these changes can result in broken clusters, nodes or otherwise
> remove the official support for your AKS cluster.

`aks-turbobutton` applies fixes and configuration settings to resolve many
common AKS issues. Many of the issue are related to one another, sharing
a common set of basic root causes.

Issues `aks-turbobutton` resolves or partially mitigates:

* Cluster nodes going NotReady (intermittent/under load, periodic tasks)
* Performance and stability issues when using istio or complex operator
  configurations.
* Networking Errors (intermittent/under load) and Latency (intermittent) (Pod,
  container, networking, latency inbound or outbound) including high latency
  when reaching other azure services from worker nodes.
* API server timeouts, disconnects, tunnelfront and kube-proxy failures under
  load.
* Connection timed out accessing the Kubernetes API server
* Slow pod, docker container, job execution
* Slow DNS queries / core-dns latency spikes
* "GenericPLEG" / Docker PLEG errors on worker nodes
* RPC Context deadline exceeded in kubelet/docker logs
* Slow PVC attach/detach time at container start or under load / fail over
* Unable to schedule workloads to expected VM limits
* Failed/timed out `helm install` commands
* Slow docker image pulls / frequent ImagePullBackoff

## Other settings included

* Watches and re-applies needed annotations or labels to enable kube-proxy,
CoreDNS metrics reporting.

## Scaffolding / Metrics collection

`values.yaml` and `turbobutton.yaml`:

In order to facilitate user re-creation and identification of these issues as
well as the root-cause of the issues a trimmed-down deployment of the
[prometheus-operator][prop] is included.

The deployment of the operator is modified to:

1. Enable [eBPF][ebpf] disk IO latency metrics collection.
2. Remove extra options and configuration from the operator
3. Includes the Cluster and Node USE (Utilization and Saturation) grafana dashboards
4. Adds in the needed re-labelling of metrics for AKS
5. Forces metrics persistence
6. Installs Brendan Gregg's IO flamegraph tools

# Installation

Pre reqs:

1. Bash compatible shell
2. Installed & configured `azure cli`
3. git
4. kubectl configured with context set to target cluster
5. Priviliged containers enabled on the target cluster

```shell
git clone git@github.com:jnoller/aks-turbobutton.git
./autotune
```

# Overview

`aks-turbobutton` is a set of (hopefully) clear and concise bash scripts as well
as a kubernetes daemonset to deploy and manage those scripts and the metrics
collection and reporting needed for issue identification.

Simply; `aks-turbobutton` applies a set of Linux best practices to the AKS
worker nodes as well as any other supporting tools.

## Settings changed or modified

* The Docker (moby) and kubelet working directories are moved to the node's
  ephemeral tempfs disk located in `/mnt`.
* Disables (sort of) the Linux OOMKiller
  * `vm.panic_on_oom=1`
  * `vm.swappiness=1`
  * `kernel.panic=5`
* Sets common Linux tuning values for higher IO performance including changing
  the Linux IO scheduler on worker nodes:
  * scheduler: "mq-deadline"
  * read_ahead_kb: "4096"
  * max_sectors_kb: "128"
  * queue_depth: "64"
  * transparent_hugepage: "always"

# TODO:

* Node Problem Detector installation (stand alone mode)
* Auto-disable the Azure disk write cache on all drives
* Disable or re-home OMS Agent process IO


[ebpf]: http://www.brendangregg.com/blog/2019-01-01/learn-ebpf-tracing.html
[aksbug]: https://github.com/Azure/AKS/issues/1373
