---
title: Allowing version independence in siteconfig
authors:
  - "@sabbir-47"
reviewers:
  - "@imiller0"
  - "@serngawy"
  - "@Iack"
  - "@serngawy" 
approvers:
  - "@imiller0"

api-approvers:
  - TBD
creation-date: 2023-06-02
last-updated: 2023-06-02
status: provisional
---


# Cluster Group Upgrade (CGU) conditions and their reason/messages enhancement

## Release Signoff Checklist

- [ ] Enhancement is `implementable`
- [ ] Design details are appropriately documented from clear requirements
- [ ] Test plan is defined
- [ ] Documentation is updated in the upstream
- [ ] Documentation is updated in the downstream


## Summary

Siteconfig allows customer to include custom extra manifests and list them in the siteconfig CR to be added during CR generation. It provides the flexibility to add additional CRs from the customer point of view during install time along with the CRs the RAN team provides. 

The enhancement seek to address the version independence of extra manifests, by putting version dependent manifests in version specific folder in git and pointing the directory via **extraManifestPath** and disabling the fetching builtIn RAN CRs provided from the ztp container 


## Motivation

* Currently customer can put custom manifests in the git repo and point them via **extraManifestPath**. 
* If they only want to include custom CRs to build site specific CRs, **inclusionDefault** must be set to *exclude*, and pass the list of file names under **filter.include**, but it does not allow to have the [same CR name](https://github.com/openshift-kni/cnf-features-deploy/blob/master/ztp/siteconfig-generator/siteConfig/siteConfigBuilder.go#L462-L464) for the custom CRs. 

To be able to add custom CRs, customer needs to change the name of the custom CR.


  ```yaml
  - cluster:
    extraManifestPath: mypath/
    extraManifests:
      filter:
        inclusionDefault: exclude
        include:
          - myCR.yaml					
  ```


### Goals

- Allow customer to include any custom CRs having same/different name than builtIn CRs residing in the container
- Provide a better control on how to enable and disable builtIn CRs
- Keep backward compatibility of the behavior corresponds to 4.13 version.

### Non-Goals

- TBD


### User Stories

- [EPIC LINK](https://issues.redhat.com/browse/CNF-7365) --> [User Story](https://issues.redhat.com/browse/CNF-8672)

## Proposal

* **Controllability:** The proposal is to introduce a parameter called  <span style="color:red">*extraManifests.builtinCRs*</span>. which can hold value "*include|exclude*", which provide the flexibility for the customer to include/exclude CRs that is provided via ztp-container. 

  * In this way, customer have full control of what CRs goes into the siteconfig. Until 4.13 release, customer couldn't put same named CR to the CR provided via ztp-container in the *extraManifestPath*. 


 ```yaml
  - cluster:
    extraManifestPath: mypath/
    extraManifests:
      builtinCRs: include | exclude   <----- New field
      filter:
        inclusionDefault: exclude
        include:
          - myCR.yaml					
  ```

* **Version Independence**: This change will allow customer to have version independence of extra-manifests having different versioned folder in their git repository. Customer can extract versioned extra-manifests and can push to their git repo. An example has shown below:


```yaml
siteconfig/
├── kustomization.yaml
├── version_4.12
│   ├── kustomization.yaml
│   ├── sno-extra-manifest/
│   ├── cnfde9.yaml
└── version_4.13
    ├── kustomization.yaml
    ├── sno-extra-manifest/
    ├── cnfde10.yaml    
```

### Workflow Description

- Due to the proposal, now we have different combination of *include|exclude* in extraManifests and the filter level. Overall 4 scenarios are briefly explained in the below table based on the proposal: 

<table>
<tr>
<th>
Scenario
</th>
<th>
Version Independence
</th>
<th>
Logical Flow
</th>
</tr>

<tr>

<td>
<pre>
 yaml
 [
    extraManifestPath: mypath/
    extraManifests:
      builtinCRs: exclude
      filter:
        inclusionDefault: exclude
        include:
          - myCR.yaml					
 ]
</pre>
</td>

<td>
yes (changes in 4.14)
</td>

<td>
  <li>if <span style="color:red">builtinCRs</span> is in <b>exclude</b>, Only CRs that will be included in site generation are the ones that reside under <i>extraManifestPath</i> in the git, no CR will be fetched from ztp-container</li>
  <li>if the default is <i>exclude</i>, only listed *.yaml files will be included in CR generationfrom extraManifestPath</li>
</td>

</tr>


<tr>
<td>
<pre>
 yaml
 [
    extraManifestPath: mypath/
    extraManifests:
      builtinCRs: exclude
      filter:
        inclusionDefault: include
        exclude:
          - myCR.yaml					
  ]
</pre>
</td>

<td>
yes (changes in 4.14)
</td>

<td>
  <li>if <span style="color:red">builtinCRs</span> is in <b>exclude</b>, Only CRs that will be included in site generation are the one that reside under <i>extraManifestPath</i> in the git, no CR will be fetched from ztp-container</li>
 <li>if the default is <i>include</i>, only listed *.yaml files will be excluded in CR generation from extraManifestPath</li>
</td>

</tr>
</tr>

<tr>
<td>
<pre>
 yaml
 [
    extraManifestPath: mypath/
    extraManifests:
      builtinCRs: include
      filter:
        inclusionDefault: include
        exclude:
          - myCR.yaml					
  ]
</pre>
</td>

<td>
No (Same as release 4.13)
</td>

<td>
<li> Current behavior is explained <a href="https://github.com/openshift-kni/cnf-features-deploy/blob/master/ztp/gitops-subscriptions/argocd/ExtraManifestsFilter.md">in the doc</a></li>

 <li>When <span style="color:red">builtinCRs</span> is in <b>include</b>, all the CRs resides under <i>extraManifestPath</i> and in the ztp-container will be allowed to be added in the interim list of CRs</li>
 <li> Then in the filter if the default is include, the interim list will be updated with the exclude list of CRs, which will be discarded from the final list</li>
 <li>Customer is not allowed to put same named CR in the extraManifestPath to the RAN CRs coming from ztp-container</li>
</td>

</tr>
</tr>

<tr>
<td>
<pre>
 yaml
 [
    extraManifestPath: mypath/
    extraManifests:
      builtinCRs: include
      filter:
        inclusionDefault: exclude
        include:
          - myCR.yaml					
  ]
</pre>
</td>

<td>
No (Same as release 4.13)
</td>

<td>
 <li> Current behavior is explained <a href="https://github.com/openshift-kni/cnf-features-deploy/blob/master/ztp/gitops-subscriptions/argocd/ExtraManifestsFilter.md">in the doc</a></li>

 <li>When <span style="color:red">builtinCRs</span> is in <b>include</b>, all the CRs resides under <i>extraManifestPath</i> and in the ztp-container will be allowed to be added in the interim list of CRs</li>
 <li> Then in the filter if the default is exclude, all the CRs will be excluded and the list will be updated with the listed CRs under include. </li>
 <li>Customer is not allowed to put same named CR in the extraManifestPath to the RAN CRs coming from ztp-container</li>

</td>

</tr>
</tr>

</table>
         
 
* The proposed way for customer to include all the CRs from manifest path and none from ztp-container will be:


   ```yaml
  - cluster:
     extraManifestPath: mypath/
     extraManifests:
      builtinCRs: exclude
  ```

    
* The better way for customer to exclude all the CRs both from ztp-container and manifest path is to just use inclusionDefault like below:


   ```yaml
  - cluster:
     extraManifests:
       filter:
         inclusionDefault: exclude
  ``` 


### Risks and Mitigations

N/A

## Implementation choices

N/A

### API Extensions

New parameter will be introduced named <span style="color:red">builtinCRs</span> which will hold value **include|exclude**

### Test Cases
- When <span style="color:red">builtinCRs</span> is **exclude**, only CRs that will be included or excluded are from the extraManifestPath directory.

- When <span style="color:red">builtinCRs</span> is **exclude**, same named CR in extraManifestPath to ztp-container is allowed.

- Ensure backward compatibitlity, if <span style="color:red">builtinCRs</span> is not defined, the behavior must corresponds to the last release(4.13)



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
