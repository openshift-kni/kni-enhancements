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
last-updated: 2023-08-25
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

* Update the siteConfig CRD to include the desired configuration under a new optional **site-data** section.
  * with this new addition, SiteConfig will support maintaining per-site data that will be used in hub side templating.
  * an alternative to populating the **site-data** section in the SiteConfig CR is to hold site-specific template data in the ZTP GitOps repo, as ConfigMaps (this template data will be synced to the hub cluster).
    * using the new **site-data** section enables the user to keep all the site specific configuration in one CR rather than maintaining SiteConfig and per-site ConfigMaps in Git.
  * if the user wants to update any site specific configuration, they can do so by modifying the corresponding data under the **site-data**.
    * the SiteConfig Generator will update the ConfigMaps on the hub cluster with the new configuration
  ```yaml
  apiVersion: ran.openshift.io/v1
  kind: SiteConfig
  metadata:
    name: "cluster-001"
    namespace: "cluster-001"
  spec:
    ...
    site-data:
      node0-networkNamespace: "aaaaa"
      node0-vlan-1: 140
      node1-networkNamespace: "bbbbb"
      node1-vlan-1: 120
    ...
  ```

* Update the SiteConfig Generator to create the corresponding ConfigMaps. The generated ConfigMaps will be named as ztp-site-<cluster_name>-configMap and will be created under the same namespace as the policy resource.
  * The **site-data** section will include the namespace where the ConfigMap will be created.
    ```yaml
    site-data:
      configMapNamespace: abcd
    ```
  * The **site-data.configMapNamespace** must be the same as the namespace used by the PolicyGenTemplate resources
  * If **site-data.configMapNamespace** is not specified, it will default to **ztp-site**

## Template examples
* Template using a label from the ManagedCluster
  ```yaml
  isolated: {{hub fromConfigMap "" "myMapName" (printf "%s-isolcpus" .ManagedClusterLabels.myLabelName) hub}}
  ```
* Template using site specific configuration from a ConfigMap
  ```yaml
  networkNamespace: '{{hub fromConfigMap "" "site-data" (printf "%s-app-namespace" .ManagedClusterName) hub}}'
  ```

### Documentation impact
The OCP PGT documentation should have the following updates:
* update at least one SiteConfig example to include the new optional **site-data** section
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
