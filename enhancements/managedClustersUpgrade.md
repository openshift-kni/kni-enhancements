---
title: Managed Clusters upgrade enhancement

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


# Managed Cluster upgrade (MCU) enhancement


## Summary

Managed Cluster Upgrade (MCU) provide aggregator  APIs for managed cluster upgrades. MCU uses ACM manifestwork APIs to upgrade ocp clusters and present the status of the upgrade process per managed cluster.

## Motivation

1. CGU uses ACM policy to upgrade an ocp cluster and its operators. The ACM policy provides a binary state for the upgrade process (Compliant/NonCompliant) while the upgrade process takes at least 40min to 2h and it has 5 different states; NotStarted, Initialized, InProgress (with gradual percentage), Complete or Failed. 

1. CGU status does not provide state per managed cluster. In case of failure to apply the ACM upgrade policies, the end user cannot identify which managed cluster failed through the CGU API he/she must get access to the managedCluster then check the cluster version APIs. 

The enhancement proposes MCU API to satisfy the above needs. MCU will use ACM manifest work API in order to provide better state report for the upgrade process as well as provides an upgrade state per cluster.

### User Stories

1. As an end user, I would like to upgrade a group of clusters and be able to track the upgrade process state per cluster.


### Goals

1. Provide a managed clusters upgrade APIs to present the upgrade process state per managed cluster


### Non-Goals


1. MCU does not apply or do the upgrade on the managed cluster. MCU only delivers the upgrade configuration to the managed cluster and reports the upgrade state.

1. MCU does not roll back the upgrade in case of failure.


## Proposal

#### ManagedClustersUpgrade (MCU)

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
      cacheImages: complete
      backup: complete
      clusterUpgradeStatus:
        message: Cluster version is 4.10.9
        state: Completed
        verified: true
      name: cnfdf02
      operatorsStatus:
        upgradeApproveState: Completed
  clusters:
    - clusterID: 84a94c75-08b6-4dfe-9138-654d94acc87
      cacheImages: complete
      backup: complete
      clusterUpgradeStatus:
        message: Cluster version is 4.10.9
        state: complete
        verified: true
      name: cnfde4
      operatorsStatus:
        upgradeApproveState: partial  
    - clusterID: 84a94c75-08b6-4dfe-9138-654d94a887cc
      cacheImages: complete
      backup: complete
      clusterUpgradeStatus:
        message: in progress 90% (105 of 130)
        state: partial
        verified: true
      name: cnfde3
      operatorsStatus:
        upgradeApproveState: NotStarted
    - clusterID: 464136c7-85c5-4437-a0ac-1d693e88685a
      cacheImages: complete
      backup: complete
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

MCU controller will use ACM manifestWork APIs to deliver the cluster upgrade configuration and apply the pre-caching, backup and operators upgrades. By using manifestWork APIs MCU controller will  have control over the upgrade configuration and upgrade process state.

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

Proposing new APIs requires QA test plan, training and documentation.
MCU API should be presented as the path to-do managed cluster upgrade for future releases with TALM that may require deprecate precache and backup functionality in CGU as they are moved to MCU.  


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

MCU API will be supported on the target release of TALM and it should not affect the TALM current APIs (CGU) functionalities or back compatibility.   

### Version Skew Strategy

### Operational Aspects of API Extensions

#### Failure Modes

#### Support Procedures

## Implementation History


## Alternatives


## Infrastructure Needed [optional]

