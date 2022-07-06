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


# Cluster Group Upgrade (CGU) and Managed Cluster upgrade (MCU) status enhancement


## Summary

Cluster Group upgrade (CGU) and Managed Cluster Upgrade (MCU) provide aggregator  APIs for managed cluster upgrades and configuration change. CGU uses ACM policy APIs to apply cluster configuration changes and present the status of the policies per managed cluster. MCU uses ACM manifestwork APIs to upgrade ocp clusters and present the status of the upgrade process per managed cluster.

## Motivation

1. Currently The CGU status does not provide state per managed cluster. In case of failure to apply the ACM policies, the end user cannot identify which managed cluster failed. The enhancement proposes a change to the CGU status to include policy state per managed cluster.

1. CGU uses ACM policy to upgrade an ocp cluster and operators. The ACM policy provides a binary state (Compliant/NonCompliant) while the upgrade process takes at least 40min to 2h and it has 5 different states; NotStarted, Initialized, InProgress (with gradual percentage), Complete or Failed. MCU will use ACM manifest work API in order to provide better state report for the upgrade process while the CGU will continue to use ACM policy API to apply cluster configuration changes.

### User Stories

1. As an end user, I would like to enforce a set of ACM policies to a group of clusters and be able to track the policies state compliant/NonCompliant per cluster.

1. As an end user, I would like to upgrade a group of clusters and be able to track the upgrade process state per cluster.


### Goals

1. Enhance the CGU status to present the state of ACM policies per managed clusters

1. Provide a managed clusters upgrade APIs to present the upgrade process state per managed cluster


### Non-Goals

1. CGU status does not present the policy components state for the managed clusters. CGU status presents the policies states per managed cluster (Complaint/NonCompliant)


1. MCU does not apply or do the upgrade on the managed cluster. MCU delivers the upgrade configuration to the managed cluster and reports the upgrade state.


## Proposal

#### 1- ClusterGroupUpgrade

Currently the CGU status contains repeated data and internal implementation data that is not useful for the CGU API description.
Below is a CGU example (cgu-upgrade-complete) applying 2 policies (cluster-version-policy and pao-sub-policy) into a group of clusters (spoke1,2,3).
The CGU example below has the status->managedPoliciesForUpgrade data repeated under status->managedPoliciesNs as well as the status->copiedPolicies data is repeated under status->safeResourceNames.
The status->remediationPlan is the same data defined by end user under spec->clusters.
Finally, the CGU status presents only the current remediation clusters under status->status->currentBatchRemediationProgress.
Once it moves to the next batch,  spoke1 data will be replaced by spoke2 data under status->status->currentBatchRemediationProgress.

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
```

This enhancement proposes to change the CGU status APIs to be as the example below (cgu-upgrade-new). The CGU status contains lists of conditions, selected clusters and canary clusters if defined.
The cluster/canaryCluster list item present the cluster name, policies list and state. 
The policies list has the managed policies names and its state on the cluster. The policy state has 4 possible state;
  - **notApplied**: the policy does not apply to enforce remediation 
  - **nonCompliant**: the policy applied to enforce remediation but it did not get compliant.
  - **compliant**: the policy applied to enforce remediation and it is compliant.
  - **timeout**: the policy applied to enforce remediation but it does not become compliant during the timeout limits defined in the remediationStrategy.

The cluster state has 2 possible state;
  - **complaint**: if all the policies has a compliant state on the cluster
  - **nonCompliant**: if at least 1 policy has any other state than compliant.


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
   state: compliant
 clusters:
 - name: spoke2
   policies:
     policy1-common: compliant
     policy2-group: nonCompliant
     policy3-site:  notApplied
   state: nonCompliant
 - name: spoke3
   policies:
     policy1-common: compliant
     policy2-group: timeout
     policy3-site:  notApplied
   state: nonCompliant
 - name: spoke4
   policies:
     policy1-common: notApplied
     policy2-group: notApplied
     policy3-site:  notApplied
   state: nonCompliant
 - name: spoke5
   policies:
     policy1-common: notApplied
     policy2-group: notApplied
     policy3-site:  notApplied
   state: nonCompliant
```

#### 2- ManagedClustersUpgrade

As it explained in the motivation section above, using ACM policy cannot properly report cluster upgrade state plus the CGU CR does not have a declarative API definition to create clusters upgrade state.
The ManagedClustersUpgrade CR (MCU) provides a declarative definition for the cluster's upgrade APIs as well as provides a cluster's upgrade states per managed cluster.

The example below (mcu-upgrade) shows the spec and status of the MCU CR. The MCU spec has the following fields 
1. `clusterSelector` that allows to select group of clusters based on match expression.
1. `clusterVersion` contains the required upgrade configurations.
1. `ocpOperators` that allows to select ocp operators to upgrade or upgrade all operators.
1. `upgradeStrategy` that allows to select canary clusters and set timeout for upgrade process.
1. `createBackup`  boolean for creating backup before starting the upgrade.
1. `cacheUpgradeImages` boolean for downloading all the required upgrade container images before starting the upgrade.
  
The MCU status contains lists of conditions, selected clusters and canary clusters if defined.
The cluster/canaryCluster list item presents the cluster name, cluster ID, cluster Upgrade Status and operators Status.
The cluster Upgrade status has `message` field that presents the upgrade progress, `verified` field present the that upgrade has been verified and the `state` field that has 4 possible states;
  - **NotStart** state indicates the upgrade is not started yet. 
  - **Initialized** state indicates the upgrade has been initialized for the managed cluster. 
  - **Partial** state indicates the upgrade is not fully applied.
  - **Completed** state indicates the upgrade was successfully rolled out at least once.
  - **Failed** state indicates the upgrade did not successfully apply to the managed cluster.
The operators Status has the `upgradeApproveState` and its similar to the cluster upgrade state.

The MCU status condition list has the following conditions;
  - **Selected** condition state is true when the cluster Selector has identified at least 1 cluster to upgrade. 
  - **Applied** condition state is true when at least 1 cluster has the upgrade configuration applied to it.
  - **InProgress** condition state is true when at least 1 cluster upgrade is in progress. 
  - **Complete** condition state is true when all the clusters upgrade state is complete.
  - **Failed** condition state is true when at least 1 cluster upgrade state is failed
  - **CanaryComplete** condition state is true when all the canary clusters upgrade state is complete
  - **CanaryFailed** condition state is true when at least 1 canary cluster upgrade state is failed

```
apiVersion: cluster.open-cluster-management-extension.io/v1beta1
kind: ManagedClustersUpgrade
metadata:
  name: mcu-upgrades
  namespace: default
spec:
  clusterSelector:
    matchExpressions:
      - key: name
        operator: In
        values:
          - cnfde3
          - cnfde6
          - cnfde4
  clusterVersion:
    channel: stable-4.10
    version: 4.10.9
    upstream: ""
    image: ""
  ocpOperators:
    approveAllUpgrades: false
    include:
      - name: sriov-network-operator-subscription
        namespace: openshift-sriov-network-operator
  createBackup: true
  cacheUpgradeImages: true
  upgradeStrategy:
    canaryClusters:
      clusterSelector:
        matchExpressions:
          - key: name
            operator: In
            values:
              - cnfdf02
    clusterUpgradeTimeout: 2h
    maxConcurrency: 2
    operatorsUpgradeTimeout: 10m
status:
  canaryClusters:
    - clusterID: 94e170c1-7a3c-4ae1-a85d-8bd904ad783f
      clusterUpgradeStatus:
        message: Cluster version is 4.10.9
        state: Completed
        verified: true
      name: cnfdf02
      operatorsStatus:
        upgradeApproveState: Completed
  clusters:
    - clusterID: 84a94c75-08b6-4dfe-9138-654d94acc87
      clusterUpgradeStatus:
        message: Cluster version is 4.10.9
        state: complete
        verified: true
      name: cnfde4
      operatorsStatus:
        upgradeApproveState: partial  
    - clusterID: 84a94c75-08b6-4dfe-9138-654d94a887cc
      clusterUpgradeStatus:
        message: in progress 90% (105 of 130)
        state: partial
        verified: true
      name: cnfde3
      operatorsStatus:
        upgradeApproveState: NotStarted
    - clusterID: 464136c7-85c5-4437-a0ac-1d693e88685a
      clusterUpgradeStatus:
        state: NotStarted
        verified: false
      name: cnfde6
      operatorsStatus:
        upgradeApproveState: NotStarted
  conditions:
    - lastTransitionTime: '2022-06-02T15:20:08Z'
      message: ManagedClsuters upgrade select 3 clusters
      reason: ManagedClustersSelected
      status: 'True'
      type: Selected
    - lastTransitionTime: '2022-06-02T15:20:08Z'
      message: ManagedClsuters upgrade applied
      reason: ManagedClustersUpgradeApplied
      status: 'True'
      type: Applied
    - lastTransitionTime: '2022-06-02T15:20:08Z'
      message: ManagedClsuters upgrade InProgress
      reason: ManagedClustersUpgradeComplete
      status: 'True'
      type: InProgress
    - lastTransitionTime: '2022-06-02T15:20:38Z'
      message: ManagedClsuters upgrade Complete
      reason: ManagedClustersUpgradeComplete
      status: 'False'
      type: Complete
    - lastTransitionTime: '2022-06-02T15:20:38Z'
      message: ManagedClsuters canary upgrade Complete
      reason: ManagedClustersCanaryUpgradeComplete
      status: 'True'
      type: CanaryComplete
```


### Implementation Details/Notes/Constraints [optional]

#### Cluster upgrade manifestWork

MCU controller will use ACM manifestWork APIs to deliver the cluster upgrade configuration. By using manifestWork APIs MCU controller will  have control over the upgrade configuration that is delivered to the managed clusters and upgrade process state.

The manifesWork CR example below (spoke1-cluster-upgrade) will be created for each cluster to apply the upgrade configurations.

The manifestWork manifests contain the clusterVersion that is created based on MCU->spec->clusterVersion.
The manifestWork feedback Rules report back the upgrade version, state, verified and progress message. 

```
apiVersion: work.open-cluster-management.io/v1
kind: ManifestWork
metadata:
  name: spoke1-cluster-upgrade
  namespace: spoke1
spec:
  deleteOption:
    propagationPolicy: SelectivelyOrphan
    selectivelyOrphans:
      orphaningRules:
        - group: ''
          name: version
          namespace: ''
          resource: ClusterVersion.config.openshift.io
  manifestConfigs:
    - feedbackRules:
        - jsonPaths:
            - name: version
              path: '.status.history[0].version'
            - name: state
              path: '.status.history[0].state'
            - name: verified
              path: '.status.history[0].verified'
            - name: message
              path: '.status.history[0].message'
          type: JSONPaths
      resourceIdentifier:
        group: config.openshift.io
        name: version
        namespace: ''
        resource: clusterversions
  workload:
    manifests:
      - apiVersion: config.openshift.io/v1
        kind: ClusterVersion
        metadata:
          name: version
        spec:
          clusterID: 94e170c1-7a3c-4ae1-a85d-8bd904ad783f
          channel: stable-4.9
          desiredUpdate:
            force: false
            image: ''
            version: 4.9.22
      - apiVersion: rbac.authorization.k8s.io/v1
        kind: ClusterRoleBinding
        metadata:
          annotations:
            rbac.authorization.kubernetes.io/autoupdate: 'true'
          name: admin-ocm
        roleRef:
          apiGroup: rbac.authorization.k8s.io
          kind: ClusterRole
          name: cluster-admin
        subjects:
          - kind: ServiceAccount
            name: klusterlet-work-sa
            namespace: open-cluster-management-agent
```

#### Operators upgrade manifestWork

The operator upgrade must happen after the cluster platform upgrade. MCU controller will deliver a Job that approves the installPlan for the selected operators to upgrade or all of them based on the user input.
The manifesWork CR example below (spoke1-operators-upgrade) will be created for each cluster to approve the operators installPlans.
The manifesWork feedback rules report the job state that indicate the operators installplan has been approved or failed.

```
apiVersion: work.open-cluster-management.io/v1
kind: ManifestWork
metadata:
  name: spoke1-operators-upgrade
  namespace: spoke1
spec:
  deleteOption:
    propagationPolicy: Foreground
  manifestConfigs:
    - feedbackRules:
        - jsonPaths:
            - name: succeeded
              path: .status.succeeded
            - name: active
              path: .status.active
            - name: failed
              path: .status.failed              
          type: JSONPaths
      resourceIdentifier:
        group: batch
        name: installplan-approver
        namespace: installplan-approver
        resource: jobs
  workload:
    manifests:
      - apiVersion: v1
        kind: Namespace
        metadata:
          name: installplan-approver
      - apiVersion: rbac.authorization.k8s.io/v1
        kind: ClusterRole
        metadata:
          name: installplan-approver
        rules:
          - apiGroups:
              - operators.coreos.com
            resources:
              - installplans
              - subscriptions
            verbs:
              - get
              - list
              - patch
      - apiVersion: rbac.authorization.k8s.io/v1
        kind: ClusterRoleBinding
        metadata:
          name: installplan-approver
        roleRef:
          apiGroup: rbac.authorization.k8s.io
          kind: ClusterRole
          name: installplan-approver
        subjects:
          - kind: ServiceAccount
            name: installplan-approver
            namespace: installplan-approver
      - apiVersion: v1
        kind: ServiceAccount
        metadata:
          name: installplan-approver
          namespace: installplan-approver
      - apiVersion: batch/v1
        kind: Job
        metadata:
          name: installplan-approver
          namespace: installplan-approver
        spec:
          manualSelector: true
          activeDeadlineSeconds: 630
          selector:
            matchLabels:
              job-name: installplan-approver
          template:
            metadata:
              labels:
                job-name: installplan-approver
            spec:
              containers:
                - command:
                    - /bin/bash
                    - '-c'
                    - >
                      echo "Continue approving operator installPlan for
                      ${WAITTIME}sec ."

                      end=$((SECONDS+$WAITTIME))

                      while [ $SECONDS -lt $end ]; do
                        echo "continue for " $SECONDS " - " $end
                        oc get subscriptions.operators.coreos.com -A
                        for subscription in $(oc get subscriptions.operators.coreos.com -A -o jsonpath='{range .items[*]}{.metadata.name}{","}{.metadata.namespace}{"\n"}')
                        do
                          if [ $subscription == "," ]; then
                            continue
                          fi
                          echo "Processing subscription '$subscription'"
                          n=$(echo $subscription | cut -f1 -d,)
                          ns=$(echo $subscription | cut -f2 -d,)
                          installplan=$(oc get subscriptions.operators.coreos.com -n ${ns} --field-selector metadata.name=${n} -o jsonpath='{.items[0].status.installPlanRef.name}')
                          installplanNs=$(oc get subscriptions.operators.coreos.com -n ${ns} --field-selector metadata.name=${n} -o jsonpath='{.items[0].status.installPlanRef.namespace}')
                          echo "Check installplan approved status"
                          oc get installplan $installplan -n $installplanNs -o jsonpath="{.spec.approved}"
                          if [ $(oc get installplan $installplan -n $installplanNs -o jsonpath="{.spec.approved}") == "false" ]; then
                            echo "Approving Subscription $subscription with install plan $installplan"
                            oc patch installplan $installplan -n $installplanNs --type=json -p='[{"op":"replace","path": "/spec/approved", "value": false}]'
                          else
                            echo "Install Plan '$installplan' already approved"
                          fi
                        done
                      done
                  env:
                    - name: WAITTIME
                      value: '600'
                  image: 'registry.redhat.io/openshift4/ose-cli:latest'
                  imagePullPolicy: IfNotPresent
                  name: installplan-approver
              dnsPolicy: ClusterFirst
              restartPolicy: OnFailure
              serviceAccount: installplan-approver
              serviceAccountName: installplan-approver
              terminationGracePeriodSeconds: 60
```

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

### Upgrade / Downgrade Strategy

If applicable, how will the component be upgraded and downgraded? Make sure this
is in the test plan.

### Version Skew Strategy

### Operational Aspects of API Extensions

#### Failure Modes

#### Support Procedures

## Implementation History


## Alternatives


## Infrastructure Needed [optional]

