---
title: Switch TALM to use Selective Policy Enforcement
authors:
  - "@Missxiaoguo"
reviewers:
  - "@imiller0"
  - "@jc-rh"
  - "@alosadagrande"
  - "@leo8a"
approvers:
  - "@imiller0"
  - "@jc-rh"

api-approvers:
  - TBD

creation-date: 2023-09-07
last-updated: 2023-12-06
---

# Switch TALM to use Selective Policy Enforcement

## Release Signoff Checklist

- [ ] Enhancement is `implementable`
- [ ] Design details are appropriately documented from clear requirements
- [ ] Test plan is defined
- [ ] Documentation is updated in the upstream
- [ ] Documentation is updated in the downstream

## Summary

The existing mechanism in Topology Aware Lifecycle Manager (TALM) for enforcing the policies defined in a ClusterGroupUpgrade (CGU)
CR is by creating an enforce copy for each of the inform policies. This proposal aims to modify the TALM backend to use [ACM Selective Policy Enforcement](https://github.com/open-cluster-management-io/enhancements/tree/main/enhancements/sig-policy/28-selective-policy-enforcment) (SPE) feature,
which will reduce the need for making copies and instead enforce policies by controlling the child policy’s remediationAction over the PlacementBinding. 

## Motivation

There are several benefits to utilizing the ACM SPE feature, including:
* Eliminating the need to manage the lifetime of copied policies
* Reducing the additional workload and resources on the hub cluster caused by copied enforce policies at scale
* Reducing the impact of status sync delay between the enforce and inform policies, which could result in longer completion times for a CGU
* Allowing users full access to all hub template functions without limitations

### Goals

* Leverage ACM SPE feature to improve efficiency/performance of TALM
* Allow users full access to hub side templating (eliminate TALM limitations)
* Reduce technical maintenance burden by using ACM features for existing functionality

### Non-Goals

None at this time

### User Stories

[Story link](https://issues.redhat.com/browse/CNF-6505)

## Proposal

This enhancement is to change TALM backend to use [Selective Policy Enforcement](https://github.com/open-cluster-management-io/enhancements/tree/main/enhancements/sig-policy/28-selective-policy-enforcment) for policy enforcement.

TALM will no longer create enforce copies for each inform policy defined in the CGU, but still create a PlacementRule/Placement and a PlacementBinding for each inform policy to control policy rollout on the target clusters.  The PlacementRule/Placement and PlacementBinding will be created in the policy namespace rather than the CGU namespace.

Under the new approach, the created PlacementBinding would have the fields `subFilter` and `bindingOverrides` added as follows:
```yaml
apiVersion: policy.open-cluster-management.io/v1
kind: PlacementBinding
metadata:
  name: cgu1-pb1
subFilter: restricted
bindingOverrides:
  remediationAction: enforce
```

The bindingOverrides.remediationAction field allows users to override the remediationAction of the bound policy to enforce for all clusters selected by this PlacementBinding.

The subFilter field allows users to select a subset of clusters from those that are already bound to this policy. The valid values for this field includes:
* unset(default): selects all clusters selected by this PlacementBinding
* restricted: selects only the clusters selected by this PlacementBinding are also selected by another PlacementBinding that has subFilter unset.
The `subFilter: restricted` option is intended to be used with `bindingOverrides` to ensure that the PlacementBinding used to enforce the policy will only affect the clusters that are
already bound. Without the `subFilter` option, it is possible for a user to mistakenly select additional clusters in the override PlacementBinding and accidentally enforce the policy on
those additional clusters.

When TALM starts remediating an inform policy for the bound clusters from the current batch, it adds the target clusters to the corresponding PlacementRule that is bound in the
associated PlacementBinding with remediationAction overrides defined. The remediationAction of the child policy on the target clusters will be overridden from inform to enforce. When the
current batch is complete, all clusters in this batch are removed from the PlacementRules associated with the inform policies. As a result, the remediationAction of the impacted child
policies is changed back to inform, indicating that TALM has completed the policies enforcement for the clusters in this batch.

### Policies watching

With SPE, TALM now needs to watch on the original inform policies status change and determine which CGUs are affected and require remediation.
The proposed solution is to filter out event updates on child policies and only process the events for root policies status update. A custom event handler will be defined in response to
an update event to transform the event for the root policy to the reconciliation of CGU. The event handler will compare status.status in the old policy with the updated policy to
identify all clusters with changed Compliant status. To find out which CGUs to reconcile, it then lists all CGUs, find and enqueue the CGUs that have that managed policy defined, as well
as the impacted clusters defined.  The LIST operation on a large number of CGUs (i.e.,~4000) does not have any performance issues. This is because the client initialized by the manager
retrieves results from cache by default, which saves connections to the API server. 

The approach of monitoring root policy status updates can effectively handle bursts of child policy status updates, regardless of whether it is a single CGU with a large number of
clusters (Upgrade case) or one CGU per cluster basis (ZTP case). It can handle a batch of changed clusters in one request, providing efficient and reliable monitoring of policy
compliance.

### Workflow Description

The proposed changes in this proposal only modify the internal mechanism for existing functionality on policy enforcement, but not impact the current workflow for using a CGU to roll out policies. The current workflow of CGU remains as follows: `ClustersSelected -> Validated -> Progressing -> Succeeded`.  However, the changes will impact how users observe the CGU process and policy enforcement.

The details are listed in the workflow.

1. Create a CGU CR on the hub cluster
  ``` yaml
  apiVersion: ran.openshift.io/v1alpha1
  kind: ClusterGroupUpgrade
  metadata:
    name: cgu-1
    namespace: default
  spec:
    managedPolicies: 
      - policy1-common-ptp-sub-policy
      - policy2-common-sriov-sub-policy
    enable: true
    clusters:
    - spoke1
    - spoke2
    - spoke5
    - spoke6
    remediationStrategy:
      maxConcurrency: 2 
      timeout: 240 
  ```

2. The CGU is validated and starts progressing the non-compliant policies for the first batch.

3. Check the status of the CGU when it’s in progress. The example output indicates that TALM is remediating the second policy for clusters in the first batch.
(*Change* -> status.copiedPolicies field is removed)
  ```json
  {
    "computedMaxConcurrency": 2,
    "conditions": [ 
      {
        "lastTransitionTime": "2023-02-25T15:33:07Z",
        "message": "All selected clusters are valid",
        "reason": "ClusterSelectionCompleted",
        "status": "True",
        "type": "ClustersSelected"
      },
      {
        "lastTransitionTime": "2023-02-25T15:33:07Z",
        "message": "Completed validation",
        "reason": "ValidationCompleted",
        "status": "True",
        "type": "Validated"
      },
      {
        "lastTransitionTime": "2023-02-25T15:34:07Z",
        "message": "Remediating non-compliant policies",
        "reason": "InProgress",
        "status": "True",
        "type": "Progressing"
      }
    ],
    "managedPoliciesContent": {
      "policy1-common-ptp-sub-policy": "[{\"kind\":\"Subscription\",\"name\":\"ptp-operator-subscription\",\"namespace\":\"openshift-ptp\"}]",
      "policy2-common-sriov-sub-policy": "[{\"kind\":\"Subscription\",\"name\":\"sriov-network-operator-subscription\",\"namespace\":\"openshift-sriov-network-operator\"}]"
    },
    "managedPoliciesForUpgrade": [
      {
        "name": "policy1-common-ptp-sub-policy",
        "namespace": "default"
      },
      {
        "name": "policy2-common-sriov-sub-policy",
        "namespace": "default"
      }
    ],
    "managedPoliciesNs": {
      "policy1-common-ptp-sub-policy": "default",
      "policy2-common-sriov-sub-policy": "default"
    },
    "placementBindings": [
      "cgu-1-policy1-common-ptp-sub-policy-wntb6",
      "cgu-1-policy2-common-sriov-sub-policy-p2cwh"
    ],
    "placementRules": [
      "cgu-1-policy1-common-ptp-sub-policy-wntb6",
      "cgu-1-policy2-common-sriov-sub-policy-p2cwh"
    ],
    "remediationPlan": [
      [
        "spoke1",
        "spoke2"
      ],
      [
        "spoke5",
        "spoke6"
      ]
    ],
    "status": {
      "currentBatch": 1,
      "currentBatchRemediationProgress": {
        "spoke1": {
            "policyIndex": 1,
            "state": "InProgress"
        },
        "spoke2": {
            "policyIndex": 1,
            "state": "InProgress"
        }
      },
      "currentBatchStartedAt": "2023-02-25T15:54:16Z",
      "startedAt": "2023-02-25T15:54:16Z"
    }
  }
  ```

4. Check the status of the policies. 
(*Change* -> No copied enforce policies in the list and the enforcing directly works on child policies, see the explanation in a,b,c)
  ``` bash
  NAMESPACE   NAME                                  REMEDIATION ACTION   COMPLIANCE STATE     AGE
  spoke1    default.policy1-common-ptp-sub-policy       enforce          Compliant            18m
  spoke1    default.policy2-common-sriov-sub-policy     enforce          NonCompliant         18m
  spoke2    default.policy1-common-ptp-sub-policy       enforce          Compliant            18m
  spoke2    default.policy2-common-sriov-sub-policy     enforce          NonCompliant         18m
  spoke5    default.policy1-common-ptp-sub-policy       inform           NonCompliant         18m
  spoke5    default.policy2-common-sriov-sub-policy     inform           NonCompliant         18m
  spoke6    default.policy1-common-ptp-sub-policy       inform           NonCompliant         18m
  spoke6    default.policy2-common-sriov-sub-policy     inform           NonCompliant         18m
  default   policy1-common-ptp-sub-policy               inform           Compliant            18m
  default   policy2-common-sriov-sub-policy             inform           NonCompliant         18m
  ```

  a. The spec.remediationAction of the child policies applied to the clusters from the current batch is changed to enforce
  b. The spec.remediationAction of the child policies for the rest of clusters remain inform
  c. After the batch is complete, the spec.remediationAction of the enforced child policies will change back to inform

5. After the CGU is succeeded, check the status of the policies.
  ``` bash
  NAMESPACE   NAME                                  REMEDIATION ACTION   COMPLIANCE STATE     AGE
  spoke1    default.policy1-common-ptp-sub-policy       inform           Compliant            25m
  spoke1    default.policy2-common-sriov-sub-policy     inform           Compliant            25m
  spoke2    default.policy1-common-ptp-sub-policy       inform           Compliant            25m
  spoke2    default.policy2-common-sriov-sub-policy     inform           Compliant            25m
  spoke5    default.policy1-common-ptp-sub-policy       inform           Compliant            25m
  spoke5    default.policy2-common-sriov-sub-policy     inform           Compliant            25m
  spoke6    default.policy1-common-ptp-sub-policy       inform           Compliant            25m
  spoke6    default.policy2-common-sriov-sub-policy     inform           Compliant            25m
  default   policy1-common-ptp-sub-policy               inform           Compliant            18m
  default   policy2-common-sriov-sub-policy             inform           Compliant            18m
  ```
  a. The spec.remediationAction of all child policies is changed back to inform


### API Extensions

No API extensions.
`copiedPolicies` field is removed from status.

### Implementation Details/Notes/Constraints [optional]

The changes proposed in this proposal will only be implemented in TALM 4.15 and will not be backported to previous versions. As the SPE feature is only available in ACM 2.9, it is important to note that older versions of ACM will not be supported for TALM 4.15.

### Risks and Mitigations

1. When there are cluster status updates in the root policy, the event handler calls a LIST request on CGU. The result of this request is stored in a variable for further processing.
When there is a large number of completed CGUs, it may cause unnecessary memory usage on the hub cluster for the CGUs that are not relevant. To mitigate it, the controller could filter
out all Completed CGUs with a fieldSelector based on a new field status.state.
2. Although it’s rare for a CGU to not be triggered due to a lost event for a policy, TALM will still requeue the CGU after 5 minutes. 

### Drawbacks

N/A

## Design Details

N/A

### Open Questions [optional]

N/A

### Test Plan

* kuttl tests in the upstream repo
* Performance testing in the scale lab

### Graduation Criteria

N/A

#### Dev Preview -> Tech Preview

N/A

#### Tech Preview -> GA

N/A

#### Removing a deprecated feature

N/A

### Upgrade / Downgrade Strategy

N/A

### Version Skew Strategy

N/A

### Operational Aspects of API Extensions

N/A

#### Failure Modes

N/A

#### Support Procedures

N/A

## Implementation History

N/A

## Alternatives

### Alternative 1

Filter out event updates on root policies and only process events for child policy `status.compliant` updates. The custom event handler will look through all CGUs and identify all CGUs
containing the managed policy and target cluster, which is the child policy namespace. 

Compared to watching root policy updates, this approach eliminates the need to determine which clusters' statues have been updated. However, this approach increases resource utilization
when there are bursts of child policy status updates at the same time for the same root policy, as each update event for a single child policy will trigger the event handler to process
the event. Another concern is the status sync delay between the child policy and the root policy, which could cause TALM to miss the chance and take longer to complete remediation.

### Alternative 2

Manage an annotation applied to the root policy to indicate which CGUs are referencing this policy.  When a CGU is enabled, append its name/namespace to the root policy annotation and
remove it from the root policy when it’s complete. The policy watcher continues to monitor the root policy and trigger reconciliation for all CGUs listed in the policy's annotation.
This approach looks so wrong because of several drawbacks:
* A long list of CGU names in the policy annotation could cause the policy object to exceed the maximum size supported by k8s
* The annotation will also be applied to child policies which is not accurate or relevant to them
* Multiple workers frequently working on updates for the same object could cause problems

## Infrastructure Needed [optional]

N/A
