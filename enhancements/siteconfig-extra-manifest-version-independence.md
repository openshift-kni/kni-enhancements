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

The enhancement seeks to address the version independence of extra manifests, by putting version dependent manifests in version specific folder in git and pointing the directory via **extraManifestPath** and disabling the fetching builtIn RAN CRs provided from the ztp container 


## Motivation

* **Currently** customer can put custom manifests in the git repo and point them via **extraManifestPath**. 
* **Current behavior:** If customer only want to include custom CRs from git directory to build site specific CRs:
  * **inclusionDefault** must be set to *exclude* which will exclude all the CRs from ztp-container
  * pass the list of CR file names under **filter.include**, that will include listed CRs. But it limits:

    * does not allow to have the [same CR name](https://github.com/openshift-kni/cnf-features-deploy/blob/master/ztp/siteconfig-generator/siteConfig/siteConfigBuilder.go#L462-L464) for the custom CRs. 

    * to be able to add custom CRs, customer needs to change the name of the custom CR.


    * as a result same named CR coming from user directory doesn't take precedent, rather siteconfig issues an error complaining same named CR is not allowed.


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

* Allow customer to include any custom CRs having same/different name than builtIn CRs residing in the container
* Same named CR take precedence over ztp-container's CR 
* Provide a better control on how to enable and disable builtIn CRs which will validate version independence
* Keep backward compatibility of the behavior corresponds to 4.13 version, meaning `builtinCRs` or the newly introduced parameter is not mandatory to generate CRs through siteconfig.

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

* **Version Independence**: 
  * What is version independence in this context?
    
    * The ability to exclude the built in content and the user can set their system up to only ever pull from git. This means they can have a set of 4.12, 4.13, 4.14, ... extra manifests in git and point to the correct set based on what they are deploying (one tool supporting multiple versions).

    * The decoupling of extra-manifests from ztp-container, cuurent ztp-container only contain a single version of extra-manifests. Using the git approach, user doesn't need to launch different versioned ztp-container to deploy different versioned manifests, rather just point towards the correct git repo path.


  This change will allow customer to have version independence of extra-manifests having different versioned folder in their git repository, as an example:


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

* Due to the proposal, now we have different combination of *include|exclude* in extraManifests and the filter level. Overall variable scenarios are briefly explained in the below table based on the proposal and the output list of CRs:

  
 ```bash
 extra manifests in the ztp-container

 - A.yaml
 - B.yaml
 - C.yaml 
```

```bash
 extra manifests in user git repo at extramManifestPath 

 - C.yaml
 - D.yaml
 - E.yaml 
```

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
<th>
Output CR list
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
  ]
</pre>
</td>

<td>
yes (changes in 4.14)
</td>

<td>
  <li>if <span style="color:red">builtinCRs</span> is in <b>exclude</b>, Only CRs from user git repo under <i>extraManifestPath</i>  will be included, none from ztp-container</li>
 <li>In this example, all the CRs from user git will be added</li>
</td>

<td>
 [C.yaml D.yaml E.yaml]
</td>
</tr>

<tr>
<td>
<pre>
 yaml
 [
    extraManifestPath: mypath/
    extraManifests:
     builtinCRs: include					
  ]
</pre>
</td>

<td>
No (Same as release 4.13)
</td>

<td>
  <li>if <span style="color:red">builtinCRs</span> is in <b>include</b>, both CRs from <i>extraManifestPath</i>  and from ztp-container will be included</li>
 <li>In this example, C.yaml takes precedence over ztp-container</li>
</td>

<td>
 [A.yaml B.yaml C.yaml D.yaml E.yaml] <-- C.yaml picked from user git, precedence applied
</td>

</tr>
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
          - C.yaml					
 ]
</pre>
</td>

<td>
yes (changes in 4.14)
</td>

<td>
  <li>if <span style="color:red">builtinCRs</span> is in <b>exclude</b>, Only CRs from user git repo under <i>extraManifestPath</i>  will be included, none from ztp-container</li>
  <li>if the default is <i>exclude</i>, only listed *.yaml files will be included in CR generationfrom extraManifestPath</li>
</td>

<td>
 [C.yaml] <--picked from user git
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
          - C.yaml					
  ]
</pre>
</td>

<td>
yes (changes in 4.14)
</td>

<td>
  <li>if <span style="color:red">builtinCRs</span> is in <b>exclude</b>, Only CRs from user git repo under <i>extraManifestPath</i>  will be included, none from ztp-container</li>
 <li>if the default is <i>include</i>, only listed *.yaml files will be excluded in CR generation from extraManifestPath</li>
</td>

<td>
 [D.yaml E.yaml]
</td>

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
          - C.yaml					
  ]
</pre>
</td>

<td>
No (Same as release 4.13)
</td>

<td>
<li> Current behavior is explained <a href="https://github.com/openshift-kni/cnf-features-deploy/blob/master/ztp/gitops-subscriptions/argocd/ExtraManifestsFilter.md">in the doc</a></li>

 <li>if <span style="color:red">builtinCRs</span> is in <b>include</b>, both CRs from <i>extraManifestPath</i>  and from ztp-container will be included</li>
 <li> the interim list will be updated with the exclude list of CRs, which will be discarded from the final list</li>
 
</td>

<td>
 [A.yaml B.yaml D.yaml E.yaml] 
</td>

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
          - A.yaml
          - B.yaml
          - c.yaml					
  ]
</pre>
</td>

<td>
No (Same as release 4.13)
</td>

<td>
 <li> Current behavior is explained <a href="https://github.com/openshift-kni/cnf-features-deploy/blob/master/ztp/gitops-subscriptions/argocd/ExtraManifestsFilter.md">in the doc</a></li>

  <li>if <span style="color:red">builtinCRs</span> is in <b>include</b>, both CRs from <i>extraManifestPath</i>  and from ztp-container will be included</li>
 <li> if the filter default is exclude, all the CRs will be excluded and the list will be updated with the listed CRs under include. </li>
 <li>same named CR from user git repo will take precedence</li>

</td>

<td>
 [A.yaml B.yaml C.yaml] <-- C.yaml picked from user git, precedence applied
</td>
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

- Ensure backward compatibility, if <span style="color:red">builtinCRs</span> is not defined, the behavior must correspond to the last release(4.13)



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
