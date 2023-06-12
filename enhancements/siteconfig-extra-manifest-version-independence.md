---
title: Allowing version independence in siteconfig
authors:
  - "@sabbir-47"
reviewers:
  - "@imiller0"
  - "@serngawy"
  - "@lack"
  - "@pixelsoccupied" 
approvers:
  - "@imiller0"

api-approvers:
  - TBD
creation-date: 2023-06-06
last-updated: 2023-06-16
status: provisional
---


# Allowing version independence in siteconfig

## Release Signoff Checklist

- [x] Enhancement is `implementable`
- [x] Design details are appropriately documented from clear requirements
- [x] Test plan is defined
- [ ] Documentation is updated in the upstream
- [ ] Documentation is updated in the downstream


## Summary

Siteconfig allows customer to include custom extra manifests and list them in the siteconfig CR to be added during CR generation. It provides the flexibility to add additional CRs from the customer point of view during install time along with the CRs the RAN team provides. 

The enhancement seeks to address the version independence of extra manifests, by putting version dependent manifests in version specific folder in git and pointing the directories via `extraManifests.searchPaths`.


## Motivation

* Currently customer can put custom manifests in the git repo and point them via **extraManifestPath**. 
* **Current behavior:** If customer want to include custom CRs from git directory to build site specific CRs:

  * set the directory path of the custom manifests in **extraManifestPath**, siteGen will include all CRs from there.
  * to include selective CR files from the git directory, customer can use filtering. They must set **inclusionDefault: exclude** and pass the list of CR file names under **filter.include**, that will include listed CRs. But it has limitations:

    * does not allow to have the [same CR name](https://github.com/openshift-kni/cnf-features-deploy/blob/master/ztp/siteconfig-generator/siteConfig/siteConfigBuilder.go#L462-L464) for the custom CRs. 

    * to be able to add custom CRs, customer needs to change the name of the custom CR.

    * as a result, the user is not able to capture the full set of version-specific extra manifests in git along with the SiteConfig because they cannot override the default set because of the inability to have the same named file.

  * below is an example of how to include a CR called `myCR.yaml` from `extraManifestPath` in current configurability: 


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

* Customer can place the full set of version specific day-0 manifests (extra manifests) into git alongside the SiteConfig. This allows the user to deploy the correct version of manifests based on the version of OCP being deployed.

* Allow customer to include multiple directory path to look for extra-manifests in siteconfig, this way we are better prepared for 4.15+ features

* This will enable the customer to control what CRs get added in site generation

* Keep backward compatibility of the behavior corresponds to 4.13 version, meaning the new parameter is not mandatory to generate CRs through siteconfig.

### Non-Goals

* Refactoring of the extra manifest filtering feature.
### User Stories

- [EPIC LINK](https://issues.redhat.com/browse/CNF-7365) --> [User Story](https://issues.redhat.com/browse/CNF-8672)

## Proposal

* The proposal is to use a new field as the opt-in, eg. `extraManifests.searchPaths` which can include multiple directories

  ```bash
  extraManifests:
    searchPaths:
      - myPath1/
      - myPath2/
  ```


  * when `extraManifests.searchPaths` is defined in Siteconfig, the generated installation CRs will not include any builtin "extra manifest" CRs from the ztp-container.

  * we will deprecate `extraManifestPath` in the next release. If defined it will continue to function exactly as it does today, but customers will be recommended to use the new extraManifests.searchPaths field.

  * support multiple entries in the list in 4.14 – for example, recommended version specific extra-manifests in one directory and customer's custom extra manifests in another directory

  * multiple entries accumulate. All files from entry1 and all files from entry2 will be applied during site generation. Foe same named files, entry2 gets precedence. For example, if same file exists in `entry1/fileA` and  `entry2/fileA`, then `entry2/fileA` will take precedence.

  * when `extraManifests.searchPaths` is not declared, the implementation preserves backwards compatibility. In the case of a SiteConfig with only `extraManifestPath`, the behavior will be identical to the prior releases. If the user switches to the new (recommended) `extraManifests.searchPaths` they get the new behavior.


* How does templating work with the git based flows?

  * SiteGen will look for `.tmpl` files in specific directories as it currently does inside the ztp-container 


* How does this affect the existing extra manifest filtering feature?
 
  * We keep filtering and support as it is.
  * The `extraManifests.searchPaths` collects up all the content and then passes to the filtering subsystem as it is today.


* Do we support override of named files using the `extraManifests.searchPaths`?

  * Yes. There are multiple directories in the list. Each entry adds more content to the set. If there are overlapping names, we will overwrite the previous filename.

* Do we allow override of same named files in the old `extraManifestPath` field? 

  * No, we do not. The old behavior does not change when customer define old `extraManifestPath` path and not the new field `extraManifests.searchPaths`.

* What if customer include both `extraManifestPath` and `extraManifests.searchPaths` in the siteconfig?

  * The behavior of `extraManifests.searchPaths` will take precedence. We will neither generate any CR from `extraManifestPath` nor the builtin CRs from the ztp-container

* What if customer include `extraManifests.searchPaths` in the siteconfig, but `extraManifests.searchPaths` is empty, i.e. len == 0? 

  * In that case, we fall back to old behavior, meaning, will look for CRs inside the ztp-container.



### How does the proposal help


* **Controllability:** The proposal provides the flexibility for the customer to include/exclude any CRs from multiple directories from user Git repository. 

  * customer can put extra-manifests extracted from ztp-container at `myPath` and their own custom CRs in `myPath2` as shown below as an example 


    ```yaml
      - cluster:
        extraManifests:
          searchPaths:  <------ new field
            - myPath/
            - myPath2/
          filter:			
      ```

  * Any same named CR file in `myPath2` will override from `myPath`. Prior to this change, the customer couldn't put same named CR in the extraManifestPath. Now overriding is possible but they have to opt in for `extraManifests.searchPaths`. 



* **Version Independence**: 
  * What is version independence in this context?
    
    * The ability to exclude the built in content and the user can set their system up to only ever pull from git. This means they can have a set of 4.12, 4.13, 4.14, ... extra manifests in git and point to the correct set based on what they are deploying (one tool supporting multiple versions).

    * The decoupling of extra-manifests from ztp-container: current ztp-container only contain a single version of extra-manifests. Using the git approach, user doesn't need to launch different versioned ztp-container to deploy different versioned manifests, rather just point towards the correct git repo path.


  This change will allow customer to have version independence of extra-manifests having different versioned folder in their git repository, as an example:


```yaml
siteconfig/
├── kustomization.yaml
├── version_4.12
│   ├── kustomization.yaml
│   ├── sno-extra-manifest/
|   ├── custom-manifests/
│   ├── cnfde9.yaml
└── version_4.13
    ├── kustomization.yaml
    ├── sno-extra-manifest/
    ├── custom-manifests/
    ├── cnfde10.yaml    
```

### Workflow Description

Variable scenarios are briefly explained in the below table based on the proposal and the output list of CRs:

* Assumption: customers siteconfig consists 2 extra manifests paths which are in the user Git repository

  ```yaml
    - cluster:
      extraManifests:
        searchPaths:
          - sno-extra-manifest/
          - custom-manifests/
        filter:			
    ```

  
* Those path conatins below files:

  ```bash
  extra manifests in the sno-extra-manifest

  - A.yaml
  - B.yaml
  - C.yaml 
  ```

  ```bash
  extra manifests in the custom-manifests

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
Logical Flow
</th>
<th>
Output CR list
</th>
</tr>

<tr>
<td>
Include all files from the path
<pre>
 yaml
[
extraManifests:
  searchPaths:
    - sno-extra-manifest/
    - custom-manifests/	
]
</pre>
</td>



<td>
  <li>When <b>extraManifests.searchPaths</b> is defined all the CRs will be added in site generation</li>
 <li>In this example, all the CRs from user git will be added</li>
</td>

<td>
  [A.yaml B.yaml C.yaml D.yaml E.yaml] <-- C.yaml picked from <b>custom-manifests</b>
</td>
</tr>

<tr>
<td>
Siteconfig contains both parameter
<pre>
 yaml
[
extraManifestPath: custom-manifests/   
extraManifests:
  searchPaths:
    - sno-extra-manifest/
    - custom-manifests/
]
</pre>
</td>


<td>
  <li>Proposed 4.14 behavior will be applied. SiteGen will discard extraManifestPath, it will only add files from <b>extraManifests.searchPaths</b></li>

</td>

<td>
 [A.yaml B.yaml C.yaml D.yaml E.yaml] <-- C.yaml picked from <b>custom-manifests</b> of extraManifests.searchPaths path
</td>

</tr>
<td>
Exclude some files
<pre>
 yaml
[ 
extraManifests:
  searchPaths:
    - sno-extra-manifest/
    - custom-manifests/	
  filter:
    inclusionDefault: exclude
    include:
      - C.yaml
      - D.yaml                  
]
</pre>
</td>


<td>
  <li>The behavior of filter will not change</li>
  <li>if the default is <i>exclude</i>, only listed *.yaml files will be included in CR generation</li>
</td>

<td>
 [C.yaml D.yaml] <--C.yaml picked  <b>custom-manifests</b>
</td>

</tr>


<tr>
<td>
Include only mentioned files
<pre>
 yaml
[
extraManifests:
  searchPaths:
    - sno-extra-manifest/
    - custom-manifests/
  filter:
    inclusionDefault: include
    exclude:
      - C.yaml
      - D.yaml                                 
]
</pre>
</td>


<td>
  <li>The behavior of filter will not change</li>
  <li>if the default is <i>include</i>, only listed *.yaml files will be excluded in CR generation</li>
</td>

<td>
 [A.yaml B.yaml E.yaml]
</td>

</table>
         

### Risks and Mitigations

N/A

## Implementation choices

N/A

### API Extensions

New parameter will be introduced named `extraManifests.searchPaths` which will accept a `list[]` and by default the value of this parameter in `nil`

### Test Cases

* Add tests on the `extraManifests.searchPaths` behavior:
 
  * Single and multiple path can be passed
  * Generating correct list of CRs from correct files
  * File name override works as proposed
  * Builtin CRs are not applied to cluster if extraManifests.searchPaths is defined and len > 0 in SiteConfig


* An exact copy of a .tmpl file will be put in current working directory in the test to validate we can parse the template file in the git 

* Ensure all the existing tests (4.13 release) passes so that we keep supporting 4.13 behavior



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
