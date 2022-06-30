---
title: Managed Clusters status enhancement

authors:
  - @serngawy

reviewers:
  - TBD

approvers:
  - @ijolliffe

api-approvers:
  - TBD

creation-date: 2022-06-28

last-updated: 2022-06-28

see-also:
   - TBD

tracking-link:
   - TBD
---


# Cluster Group Upgrade (CGU) status enhancement


## Summary

TALM provides Cluster Group upgrade (CGU) API to enforce group of ACM policies to selected clusters. CGU status field present the policies that will be enforced with the created placement rules and placement binding while the selected clusters state does not exist. The enhancement proposes a changes to the CGU status to include policies state per managed cluster. 

## Motivation

1. Currently the CGU status field does not provide state per managed cluster. In case of failure to apply an ACM policy, the end user cannot identify which managed cluster failed through the CGU API. As well as, the CGU status field store the created placement rules and placemet binding info while they are meaning less to the end user.
The enhancement proposes changes to the CGU status to include policy state per managed cluster and remove the meaningless status info fields.


### User Stories

1. As an end user, I would like to enforce a set of ACM policies to a group of clusters and be able to track the policies state compliant/NonCompliant per cluster.

### Goals

1. Enhance the CGU status to present the state of ACM policies per managed clusters and remove unnecessary status data 


### Non-Goals

1. CGU status does not present the policies components state for the managed clusters.

1. CGU status does not provide a long life aggregator for the policies state with the selected clusters, its only present the policies state per cluster during the CGU policy enforcement process.  

## Proposal

#### ClusterGroupUpgrade (CGU) status

Currently the CGU status has  repetition and internal implementation data that is not useful for the CGU API description.
Below is a CGU example (cgu-upgrade-complete) applying 2 policies (cluster-version-policy and pao-sub-policy) into a group of clusters (spoke1,2,3).
The CGU example below has the status->managedPoliciesForUpgrade data repeated under status->managedPoliciesNs as well as the status->copiedPolicies data is repeated under status->safeResourceNames.
The status->remediationPlan is the same data defined by end user under spec->clusters. The Selected Clusters names list is repeated under the status remediationPlan, backup and precache.
Finally, the CGU status presents only the current remediation clusters under status->status->currentBatchRemediationProgress once it moves to the next batch,  previous batch data will be replaced by the new one under status->status->currentBatchRemediationProgress.

```
apiVersion: ran.openshift.io/v1alpha1
kind: ClusterGroupUpgrade
metadata:
  name: cgu-upgrade-complete
  namespace: default
spec:
  clusters:
  - spoke1
  - spoke2
  - spoke3
  enable: true
  managedPolicies:
  - policy1-common-cluster-version-policy
  - policy2-common-pao-sub-policy
  remediationStrategy:
    maxConcurrency: 1
    timeout: 240
status:
  conditions:
  - message: The ClusterGroupUpgrade CR has upgrade policies that are still non compliant
    reason: UpgradeNotCompleted
    status: "False"
    type: Ready
  copiedPolicies:
  - cgu-upgrade-complete-policy1-common-cluster-versi-kuttl
  - cgu-upgrade-complete-policy2-common-pao-sub-polic-kuttl
  managedPoliciesContent:
    policy1-common-cluster-version-policy: "null"
    policy2-common-pao-sub-policy: '[{"kind":"Subscription","name":"performance-addon-operator","namespace":"openshift-performance-addon-operator"}]'
  managedPoliciesForUpgrade:
  - name: policy1-common-cluster-version-policy
    namespace: default
  - name: policy2-common-pao-sub-policy
    namespace: default
  managedPoliciesNs:
    policy1-common-cluster-version-policy: default
    policy2-common-pao-sub-policy: default
  placementBindings:
  - cgu-upgrade-complete-policy1-common-cluster-version-policy-placement-kuttl
  - cgu-upgrade-complete-policy2-common-pao-sub-policy-placement-kuttl
  placementRules:
  - cgu-upgrade-complete-policy1-common-cluster-version-policy-placement-kuttl
  - cgu-upgrade-complete-policy2-common-pao-sub-policy-placement-kuttl
  remediationPlan:
  - - spoke1
  - - spoke2
  - - spoke3
  safeResourceNames:
    cgu-upgrade-complete-common-cluster-version-policy-config: cgu-upgrade-complete-common-cluster-version-policy-config-kuttl
    cgu-upgrade-complete-common-pao-sub-policy-config: cgu-upgrade-complete-common-pao-sub-policy-config-kuttl
    cgu-upgrade-complete-default-subscription-performance-addon-operator: cgu-upgrade-complete-default-subscription-performance-addon-operator-kuttl
    cgu-upgrade-complete-policy1-common-cluster-version-policy: cgu-upgrade-complete-policy1-common-cluster-versi-kuttl
    cgu-upgrade-complete-policy1-common-cluster-version-policy-placement: cgu-upgrade-complete-policy1-common-cluster-version-policy-placement-kuttl
    cgu-upgrade-complete-policy2-common-pao-sub-policy: cgu-upgrade-complete-policy2-common-pao-sub-polic-kuttl
    cgu-upgrade-complete-policy2-common-pao-sub-policy-placement: cgu-upgrade-complete-policy2-common-pao-sub-policy-placement-kuttl
  status:
    currentBatch: 1
    currentBatchRemediationProgress:
      spoke1:
        policyIndex: 0
        state: InProgress
  backup: 
    clusters: 
    - "spoke2"
    - "spoke1"
    - "spoke3"
    status:
     - "spoke1": "Succeeded"
     - "spoke2": "Succeeded"
     - "spoke3": "Succeeded"
 precaching: 
    clusters: 
    - "spoke2"
    - "spoke1"
    - "spoke3"
    spec:
      "platformImage": "quay.io/openshift-release-dev/ocp-release@sha256:b9ede044950f73730f00415a6fe8eb1b5afac34def872292fd0f9392c9b483f1"
    status:
    - "spoke1": "Active"
    - "spoke2": "Active"
    - "spoke3": "Active"

```

This enhancement proposes to change the CGU status APIs to be as the example below (cgu-upgrade-new). The CGU status contains lists of conditions, selected clusters and canary clusters if defined.
The cluster/canaryCluster list item present the cluster name, policies list and state. 
The policies list has the managed policies names and its state on the cluster. The policy state has 4 possible state;
  - **notApplied**: the policy does not apply to enforce remediation 
  - **nonCompliant**: the policy applied to enforce remediation but it did not get compliant.
  - **compliant**: the policy applied to enforce remediation and it is compliant.
  - **timeout**: the policy applied to enforce remediation but it does not become compliant during the timeout limits defined in the remediationStrategy.

The cluster state has 2 possible state;
  - **complete**: if all the policies has a compliant state on the cluster
  - **inProgress**: if all the policies are in compliant/nonCompliant or notApplied state.
  - **failed**: if at least 1 policy has timeout state.


```
apiVersion: cluster.open-cluster-management-extension.io/v1beta1
kind: ClusterGroupUpgrade
metadata:
  name: cgu-upgrade-new
  namespace: default
spec:
  enable: true
  clusters:
  - spoke2
  - spoke3
  - spoke4
  - spoke5
  managedPolicies:
    - policy1-common
    - policy2-group
    - policy3-site
  remediationStrategy:
    canaries:
    - prod1
    maxConcurrency: 2
    timeout: 240
status:
 conditions: 
   ...
 canaryClusters:
 - name: spoke1
   policies:
     policy1-common: compliant
     policy2-group: compliant
     policy3-site:  compliant
   state: complete
 clusters:
 - name: spoke2
   policies:
     policy1-common: compliant
     policy2-group: nonCompliant
     policy3-site:  notApplied
   state: inProgress
 - name: spoke3
   policies:
     policy1-common: compliant
     policy2-group: timeout
     policy3-site:  notApplied
   state: failed
 - name: spoke4
   policies:
     policy1-common: notApplied
     policy2-group: notApplied
     policy3-site:  notApplied
   state: inProgress
 - name: spoke5
   policies:
     policy1-common: notApplied
     policy2-group: notApplied
     policy3-site:  notApplied
   state: inProgress
```


### Implementation Details/Notes/Constraints [optional]

#### CGU status 

##### 1- copied policies, placement rules and placement binding names

The CGU controller copies the ACM policies defined under the CGU->managedPolicies field then change its remediation to enforce and create a placement rule and placement binding accordingly to the select clusters.
While storing the copied policies, placement rules and placement binding names in the CGU status is required by the current implementation of the reconcile process however its not mandatory. Having the copied policies names consist of the CGU name and policy index will make it unique for the reconciling loop.
Moreover, based on the [selective policy enhamcement](https://github.com/open-cluster-management-io/enhancements/pull/57) there is no needs to copies policies for future integration with ACM coming releases.  

##### 2- batches

The CGU status field store the current cluster batch number in order to iterate to the next batch after success/failed of the running batch.  The new proposed CGU status does not require that as all clusters with indies are stored under clusters list field.
The iteration of the batches can be determined by the maxConcurrency number defined under the remediationStrategy and the selected clusters list.

#### Deprecate backup & precache status fields

The backup and precaching both having there own status under the CGU status field as below
  
```
status:
 conditions: 
   ...
 backup: 
    clusters: 
    - "test-spoke2"
    - "test-spoke1"
    status:
     - "test-spoke1": "Succeeded"
     - "test-spoke2": "Succeeded"
 precaching: 
    clusters: 
    - "test-spoke2"
    - "test-spoke1"
    spec:
      "platformImage": "quay.io/openshift-release-dev/ocp-release@sha256:b9ede044950f73730f00415a6fe8eb1b5afac34def872292fd0f9392c9b483f1"
    status:
    - "test-spoke1": "Active"
    - "test-spoke2": "Active"
```

As we explained in the proposal section the cluster list is repeated for backup and precache status. Moreover, having the cluster upgrade and subscription upgrade defined by policies while precache and backup are defined as boolean flag made the CGU APIs neither transparent nor declarative for consumers APIs.
This enhancement propose to deprecate the precache and backup field under the CGU API for the target TALM release as they will be presented in the new MCU APIs. For more info regards MCU check [managedClusterUpgrade.md]()

### Workflow Description

#### Variation [optional]


### API Extensions

### Risks and Mitigations [optional]


### Drawbacks [optional]

### Open Questions [optional]

### Test Plan

### Graduation Criteria
**Note:** *Section not required until targeted at a release.*

#### Dev Preview -> Tech Preview

#### Tech Preview -> GA
**For non-optional features moving to GA, the graduation criteria must include
end to end tests.**

#### Removing a deprecated feature

The precache and backup fields will be stated as deprecated under the CGU APIs for the target TALM release.

### Upgrade / Downgrade Strategy

The proposed changes to the CGU status APIs will be supported for the target TALM release and it must maintain back compatibility with the previous CGU status APIs.


### Version Skew Strategy

### Operational Aspects of API Extensions

#### Failure Modes

#### Support Procedures

## Implementation History


## Alternatives

The proposed changes to the CGU status can be defined under a new APIs (ex; PolicyGroupUpgrade/PolicyGroupApply) with its own controller and group APIs name.  

## Infrastructure Needed [optional]

