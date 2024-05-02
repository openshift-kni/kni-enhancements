---
title: Update reference configuration to use hub side templating
authors:
  - "@irinamihai"
reviewers:
  - "@imiller0"
  - "@serngawy"
  - "@sabbir-47"
  - "@Missxiaoguo"
approvers:
  - "@imiller0"

creation-date: 2023-08-17
last-updated: 2023-11-14
---


# Update reference configuration to use hub side templating

## Release Signoff Checklist

- [ ] Enhancement is `implementable`
- [ ] Design details are appropriately documented from clear requirements
- [ ] Test plan is defined
- [ ] Documentation is updated in the upstream
- [ ] Documentation is updated in the downstream


## Summary

* The current ZTP reference configuration includes examples of common, group and site policies.
* As per their names
  * site policies contain configuration specific to one specific cluster
  * group policies configuration common to a group of clusters
  * common policies contain configuration common to all sites.
* The group and site policies generally have an identical structure, with the cluster specific configuration being different.
* To reduce the number of policies one has to maintain and keep track of for a certain deployment, we can make use of a general purpose policy and have its per-cluster values substituted into a [hub side template](https://access.redhat.com/documentation/en-us/red_hat_advanced_cluster_management_for_kubernetes/2.8/html-single/governance/index#template-processing).


## Motivation

* With large fleets of clusters, it can quickly become hard to maintain per-site configurations.

* Offer users an example for how to reduce the number of policies on their hub clusters. This would make the cluster’s deployment and maintenance process a lot less cumbersome.

* Customers are already making use of hub side templating, so we should cover this scenario in our reference configuration.


### Goals

* Update the existing reference configuration with the following:
  * hub side template examples and references to its documentation
  * PolicyGenTemplates that use templates instead of hard-coded configuration
  * ConfigMaps that contain the configuration needed for the used PGTs
* Update the reference configuration with hub templating examples for SNO, three-node cluster and standard cluster
* The user can include the desired configuration data in SiteConfig and SiteConfig Generator will create the needed ConfigMaps
* Explain if and how the ZTP workflow is impacted by switching to using hub side templates

### Non-Goals
* hub side templating for SiteConfig
* replacing all the content of PGT with templates
* cluster side templating for PGT

### User Stories

- [EPIC LINK](https://issues.redhat.com/browse/CNF-9171)

## Proposal

* Define configuration groups (Ex: hardware, network, ...)

* Add configMap examples for the above defined groups

* Include examples of hub side template with both per-cluster and per-group values being substituted

* Update one of the SNO development validation repos to use the hub side templating reference configuration

* Update the siteConfig CRD to include the desired configuration under a new optional **siteConfigMap** section.
  * with this new addition, SiteConfig will support maintaining per-site data that will be used in hub side templating.
  * an alternative to populating the **siteConfigMap** section in the SiteConfig CR is to hold site-specific template data in the ZTP GitOps repo, as ConfigMap(s) (this template data will be synced to the hub cluster).
    * using the new **siteConfigMap** section enables the user to keep all the site specific configuration in one CR rather than maintaining SiteConfig and per-site ConfigMaps in Git.
  * if the user wants to update any site specific configuration, they can do so by modifying the corresponding data under the **siteConfigMap**.
    * the SiteConfig Generator will update the ConfigMap on the hub cluster with the new configuration
  ```yaml
  apiVersion: ran.openshift.io/v1
  kind: SiteConfig
  metadata:
    name: "cluster-001"
    namespace: "cluster-001"
  spec:
    ...
    clusters:
    - cluster-name: sno-1
      siteConfigMap:
        name: <ConfigMap name>
        namespace: <ConfigMap namespace>
        data:
          # group value - hardware type
          dell-poweredge-xr12-cpu-isolated: "2-31,34-63"
          # group value - zone
          zone-1-cluster-log-fwd-inputs: "[{\"name\": \"my-app-logs\", \"application\": {\"namespaces\": [\"my-project\"]}}]"
          # site specific value
          sno-1-sriov-network-vlan-1: "140"
      nodes:
        - hostName: sno-1-node-0
          ...

    ...
  ```

* Update the SiteConfig Generator to create the corresponding ConfigMap.
  * By default, the generated ConfigMap will be named as ztp-site-<cluster_name> and will be created under the **ztp-site** namespace
  * The **siteConfigMap** section can override the default name and namespace.
    ```yaml
    siteConfigMap:
      name: abcd
      namespace: zzz
    ```
  * The **siteConfigMap.namespace** should be the same as the namespace used by the PolicyGenTemplate resources
  * If **siteConfigMap.data** is missing from siteConfig, but at least one of **siteConfigMap.name** or **siteConfigMap.namespace** is present, the ConfigMap will be created empty with the possibility of updating it in the future.

## Template examples
* Template using a label from the ManagedCluster
  ```yaml
  isolated: '{{hub fromConfigMap "" (printf "ztp-site-%s" .ManagedClusterName) (printf "%s-cpu-isolated" (index .ManagedClusterLabels "hardware-type")) hub}}'
  ```
* Template using site specific configuration from a ConfigMap
  ```yaml
  networkNamespace: '{{hub fromConfigMap "" (printf "ztp-site-%s" .ManagedClusterName) (printf "%s-hwevent-transportHost" (index .ManagedClusterLabels "group-du-sno-zone")) hub}}'
  ```

### Documentation impact
The OCP PGT documentation should have the following updates:
* update at least one SiteConfig example to include the new optional **siteConfigMap** section
  * suggestion: under [*Example single-node OpenShift cluster SiteConfig CR*](https://docs.openshift.com/container-platform/4.13/scalability_and_performance/ztp_far_edge/ztp-deploying-far-edge-sites.html#ztp-deploying-a-site_ztp-deploying-far-edge-sites)
* include at least one PGT example that includes templating
  * suggestion: new note or paragraph under [*Recommendations when customizing PolicyGenTemplate CRs*](https://docs.openshift.com/container-platform/4.13/scalability_and_performance/ztp_far_edge/ztp-configuring-managed-clusters-policies.html#ztp-pgt-config-best-practices_ztp-configuring-managed-clusters-policies)
  * add reference to the hub side templating documentation

### Workflow Description
None of the existing workflows is impacted by this.

### Risks and Mitigations

N/A

## Implementation choices

N/A

### API Extensions


### Test Cases

* Run end to end ZTP installs and deployments with the examples from the updated reference configuration
  * All existing tests should run as before without any extra changes


### Drawbacks

N/A
## Design Details

N/A

### Test Plan

N/A

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

N/A
