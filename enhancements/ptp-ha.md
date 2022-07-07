---
title: ptp_multi-nic_ha_support
authors:
  - "@danielmellado"
reviewers:
  - "@zshi-redhat"
  - "@SchSeba"
  - "@aneeshkp"
  - "@imiller0"
approvers:
  - "@ijolliffe"
creation-date: 2022-06-15
last-updated: 2022-06-15
tracking-link: TBD
status: provisional
---

# PTP multi-nic HA Support

## Release Signoff Checklist

- [ ] Enhancement is `implementable`
- [ ] Design details are appropriately documented from clear requirements
- [ ] Test plan is defined
- [ ] Graduation criteria for dev preview, tech preview, GA
- [ ] User-facing documentation is created in [openshift-docs](https://github.com/openshift/openshift-docs/)

## Summary

Multi-nic support for PTP operator [1] seems to be already built-in. In
enterprise telco environments, there's often a need to load balance two
different signals from different PTP IEEE 1588-2008 sources.

PTP uses best master clock (BMC) algorithm to perform a selection of the
candidate clock based on a series of parameters such as accuracy, quality,
stratum and uuid. The HA support should also consider these ones and perform
the change when needed.

In Telco environments, where an specific profile, such as G.8275.1[] is needed,
ABMC (Alternate BMC is required).

## Scenarios

### Multiple NICs

This case assumes that over the that the Virtual Distributed Unit (vDU) hosts
several NICs supporting Boundary Clock Function. The synchronization source is
selected by *ptp4l*

On Openshift 4.10 the PTP operator supports running multiple NICs with the
following dual nic with two ptp4l configurations, but no HA on failure.

```text
        ┌─────────────────────────┐
        │                         │
        │                         │
        │    Grand Master         │
        │                         │
        │                         │
        └───────┬───────────┬─────┘
                │           │
                │           │
                │           │
         ┌──────┼───────────┼────┐
         │ vDU  │           │    │
         │ ┌────┴───┐  ┌────┴──┐ │
         │ │        │  │       │ │
         │ └─────┬──┘  └────┬──┘ │
         │  NIC1 │      NIC2│    │
         └───────┼──────────┼────┘
                 │          │
                 │          │
          ┌──────┼──────────┼───┐
          │      │          │   │
          │      │       ┌──┘   │
          │      │       │      │
         ┌┼┬────┬┼┐     ┌┼┬────┬┼┐
         ├─┘    └─┤     ├─┘    └─┤
         │        │     │        │
         │        │     │        │
         │        │     │        │
         │        │     │        │
         │        │     │        │
         │        │     │        │
         │        │     │        │
         │        │     │        │
         │ RU#0   │     │ RU#1   │
         └────────┘     └────────┘
```

HA on failure would require several NICs connection at the Remote Unit (RU)
level as well, so they would be able to load balance between the two boundary
clocks within the boundary clock.

### Multiple interfaces on one NIC

- Should this be covered?

## Motivation

### Goals

- Support multiple PTP sources within the PTP operator
- Add an additional field in the CR regarding stratum priority

### Non-Goals

## Proposal

### Reconcile Loop

The PTP Operator's reconcile loop would also take care of checking whether the
PTP clock has failed, should the HA field be on the CRD.

#### What does failure mean?

Failure would mean that the sync with the upstream clock is lost, and that the
local ptp daemon is on freerun. It would have its sync lost bit by bit, even
though it may still be working for some time.

Once such situation is identified, We would need to kill the phc2sys daemon.
The secondary nic will configured with its `phc2sys` crd config set to zero
so it doesn't start with any config.

Would this be a new controller on the operator? Some new parameter on the
reconcile loop? Opening this EP so we can iterate on this.

### Workflow Description

### API Extensions

### User Stories

## Design Details

The linuxptp package includes ptp4l and phc2sys programs for clock
synchronization. The PTP Operator runs these two programs into a
linuxptp-daemon pod on each node which belongs to the cluster.

### ptp4l

It implements the PTP boundary clock and ordinary clock. It synchronizes the
PTP hardware clock (PHC) from the NIC to the source clock with hardware time
stamping and synchronizes the system clock to the source clock with *software*
time stamping.

### phc2sys

phc2sys is used for hardware time stamping to synchronize the system clock to
the PTP hardware clock on the network interface controller (NIC).

### pmc

It's an utility to configure ptp4l in runtime. It's also available within the
linuxptp-daemon pod.

## Alternatives

Using `boundary_clock_jbod` option within the profiles allows a node acting as
a BC using two different NICs to have their PHCs synced via `phc2sys`. That
said, this would go over the max time error (30 ns) due to the increased
offset of having such synchronization via software (as it used `phc2sys`).

This error (Max. Absolute Time Error (max|TE|)) would only apply to the
fronthaul transport network.
### Telecom profiles

Following up with what was described in the above section,  we would need to
decided whether to use one of these profiles:

* G.8275.1

The G.8275.1 profile is designed to provide the most accurate time
synchronization solution within the constraints of +-1.5us from the Primary
Reference Time Clock (PRTC)

* G.8275.2

As G.8275.1 implies that every node has to support aBC with a certain level of
accuracy and this is not always possible. G.8275 allows PTP packets to be
distributed using IPv4/IPv6 unicast rather L2 multicast as used in G.8275.1

This enables PTP packets to be distributed over non-PTP networks and across L"
boundaries.

As each node in the network does not have a physical clock, this is referred as
partial timing support. Accuracy is lower but still acceptable.

|                	|         G.8275.1 (Full Timing Support)         	|                   G.8752.2 (Partial Timing Support)                  	|
|----------------	|:----------------------------------------------:	|:--------------------------------------------------------------------:	|
| Transport      	| PTP over Ethernet Multicast                    	| PTP over IPv4 or IPv6 Unicast. IP QoS with DiffServ for sync packets 	|
| BMCA Algorithm 	| Alternate BMCA (A-BMCA), as specified by ITU-T 	| Alternate BMCA (A-BMCA), as specified by ITU-T                       	|

### ptpConfig to set up boundary clock using multiple interface with HA

```console
NOTE: following ptp4l/phc2sys opts required when events are enabled
ptp4lOpts: "-2 --summary_interval -4"
phc2sysOpts: "-a -r -m -n 24 -N 8 -R 16"
```

```yaml
apiVersion: ptp.openshift.io/v1
kind: PtpConfig
metadata:
  name: boundary-clock-ptpconfig
  namespace: ptp
spec:
  profile:
  - name: "profile1"
    ptp4lOpts: "-s -2"
    phc2sysOpts: "-a -r"
    boundary-clock-ha: true
    ptp4lConf: |
      [ens7f0]
      masterOnly 1
      [ens7f1]
      masterOnly 1
  recommend:
  - profile: "profile1"
    priority: 4
    match:
    - nodeLabel: "node-role.kubernetes.io/worker"
```

Taking the original model for setting up a boundary clock using multiple
interfaces, we'll add an additional field, `boundary-clock-ha`, which would
trigger the above graph model, in which the VDU would connect with the
multi-nic RU in order to be able to deal with the two different upstream
clocks.

### Risks and Mitigations

### Drawbacks

### Test Plan

### Graduation Criteria

#### Dev Preview -> Tech Preview

#### Tech Preview -> GA

#### Removing a deprecated feature

- Announce deprecation and support policy of the existing feature
- Deprecate the feature

### Upgrade / Downgrade Strategy

### Version Skew Strategy

### Operational Aspects of API Extensions

#### Failure Modes

#### Support Procedures

## Implementation History
---
[1] https://github.com/openshift/ptp-operator
[2] G.8275.1 : Precision time protocol telecom profile for phase/time synchronization with full timing support from the network
    https://www.itu.int/rec/T-REC-G.8275.1-202003-I/en
[3] G.8275.2 : Precision time protocol telecom profile for time/phase synchronization with partial timing support from the network
    https://www.itu.int/rec/T-REC-G.8275.2-202003-I/en
