---
title: cluster-configuration-validation-tool
authors:
  - Ian Miller
  - Nahian Pathan
reviewers:
  - Martin Sivak
  - Benny Rochwerger
approvers:
  - TBD
api-approvers:
  - N/A
creation-date: 2023-07-04
last-updated: 2023-07-12
tracking-link:
  - [TELCOSTRAT-148](https://issues.redhat.com/browse/TELCOSTRAT-148)
see-also:
  - None
replaces:
  - None
superseded-by:
  - None
---

# Cluster Configuration Validation Tool

## Summary

Provide a tool which is capable of comparing cluster configuration CRs against a known reference and
report on drift/deviations. The input cluster configuration may be provided in a variety of forms
ranging from an "offline" set of CRs (eg support archive, directory tree, etc) or pulled via API
access against a live cluster. In addition to the tooling to perform this comparison, this
enhancement defines the structure and method of capturing known user variation, optional components,
and required content in the reference configuration.

## Motivation

Many cluster deployments are based on engineered and validated reference configurations. These
reference configurations have been designed to ensure a cluster will meet the functional, feature,
performance and resource requirements for specific use cases. When a cluster, or deployment of
clusters, deviates from the reference configuration the impacts may be subtle, transient, or delayed
for some period of time. When working with these clusters across their lifetimes it is important to
be able to validate the configuration against the known working reference configuration to identify
potential issues before they impact end users, service level agreements, or cluster uptime.

This enhancement describes a tool capable of doing an "intelligent" diff between a reference
configuration and a set of CRs representative of a deployed "production" cluster. These CRs may
derive from many potential sources such as being pulled from a live cluster, read from a git
repository, or extracted from a support archive. The reference configuration is sufficiently
annotated to describe expected user variations versus required content.

Existing tools meet some of this need but fall short of the goals
- kubectl/oc diff: This tool allows comparison of a live cluster against a known configuration.
  There are two shortcomings we need to address:
  - Ability to handle expected user variation vs required content.
  - Consumption of an offline representation of the cluster configuration.
- `<get cr> | <key sorting> | diff` : There are various ways of chaining together existing tools
  to obtain, correlate, and compare/diff two YAML objects. These methods fall short in 1) Ability
  to handle expected user variation vs required content.

The proposal describes both the representational format of the reference configuration as well as
the functionality of the tool which will perform the comparison.

### User Stories

As an end customer I want to be able to compare the configuration of my clusters against the
validated reference configuration. I want the tool to report significant drift and to suppress
"diffs" which are expected user variations and runtime variable fields (eg status/metadata). I want
the tool to report drift in deployed CRs as well as required CRs which are missing. I want to be
able to run the tool at various points in the deployment lifecycle including against:
* my live production clusters
* source (eg generic/templated) CRs in my planning labs
* reference CRs provided by partner

As a support engineer helping to triage/debug issues with a customer or partner I want to be able to
compare the configuration of a cluster as captured in a support archive against a validated
reference configuration.

As a provider of reference configurations I want to be able to provide a new or updated validated
reference configuration without the need to rebuild the validation tool.

### Goals

The following goals apply to the validation (diff) tool:
1. Data driven. New and updated reference configurations do not require a new release of the tool.
1. Can be used with new and updated reference configurations
1. Can consume input configuration CRs from live cluster
1. Can consume input configuration CRs from a support archive
1. Can consume input from local filesystem (files, directories, etc)
1. Will suppress diffs (not report as a drift) for runtime variable fields (status, managed
   metadata, etc)
1. Will suppress diffs (not report as a drift) for know user variable content as described by the
   reference configuration
1. Will show diffs (report as drift) for content in input configuration which does not match
   reference
1. Will show diffs (report as drift) for reference configuration content missing from input
   configuration
1. Will show diffs (informational) for content in input configuration which is not contained in
   reference
1. Allows comparison against one-of-several in reference configuration (ie an input configuration CR
   compared against one of several optional implementations in the reference configuration)

### Non-Goals

1. Validation which goes beyond what is available in the configuration CRs – deeper
   inspection/analysis is the domain of other tools such as Insights – see
   [CNF-9064](https://issues.redhat.com/browse/CNF-9064).
1. Validation of configuration CRs against CRD (ie validation of their correctness or ability to be
   successfully applied to a cluster)

## Proposal

### Terminology

* **drift** -- A significant delta/difference which needs to be brough into compliance or undergo further review/assessment
* **deviation** -- A delta/difference which has been deemed acceptable through some approval process

### Validation Tool Implementation

The validation tool will operate similarly to a standard Linux `diff` tool which operates across a
set of inputs (eg directory trees). The left hand side of the diff will be the selected reference
configuration (see below for structure/contents of the reference) and the right hand side will be a
collection of the user’s configuration CRs. For each file in the user’s configuration the tool will
find the best match CR in the reference configuration to perform the comparison. The tool will
display to any drift which consists of differences considered outside the expected set of
variability as defined by the reference configuration. The tool will highlight this drift which
needs to be brought into compliance with the reference. In addition to the CR comparison output the
tool will output a report detailing:
* Input configuration CRs with no match in the reference
* Required reference CRs with no match in the input configuration
* Number of drifts found

#### Categorization of differences
When comparison of a field in the input vs the reference shows a difference the tool categorizes it
into one of these outcomes:
1. Expected user variation – the tool output does not indicate this as drift
1. Missing required content – the reference contains required items not found in the input
   configuration. This is a drift.
1. Extra content – the input configuration contains content not included in the reference
   configuration. The tool displays this as informational output. This is not a drift.
1. Drift – the input configuration does not match or is outside expected user variation compared to
   the reference. This is a highlighted drift.

#### Inputs

The tool consumes two mandatory inputs and may support additional options to control the comparison,
output, etc.

The reference configuration is a required input. The structure of the reference is described
below. The minimum requirement is that the reference can be located on the local filesystem (eg
directory). Optionally the reference may be sourced via URL, container image, or other source.

The input configuration is a required input. The minimum requirement is that this configuration can
be located on the local filesystem. Optionally the input configuration may be pulled from a live
cluster (access credentials required), a support archive, etc. If pulling from a live cluster is a
supported method for the tool to get the input configuration, the tool may infer this behavior when
supplied with only a reference configuration as input. This allows the tool to work as a kubectl/oc
plugin.

All input formats and options must be implemented to allow the tool to operate as a kubectl/oc plugin.

#### Correlating CRs

The tool must correlate CRs between reference and input configurations to perform the
comparisons. The tool will use the input configuration apiVersion, kind, namespace and CR name to
perform the correlation to one or more reference configuration CRs. For cluster scoped CRs the
namespace will be nil.
1. Exact match of apiVersion-kind-namespace-name
1. Match kind-namespace
	1. If single result in reference, comparison will be done
	1. If multiple results in reference, user will select
1. Match kind
	1. If single result in reference, comparison will be done
	1. If multiple results in reference, user will select
1. No match – comparison cannot be made and the file is flagged as unmatched.

#### Output

The tool will generate standard diff output highlighting content as described in "Categorization of
differences". Note in this example the cpusets and hugepage count are not highlighted as these are
expected user variations. The hugepage node is indicated as extra content and the realtime kernel
setting is indicated as a drift

```diff
---
apiVersion: performance.openshift.io/v2                          apiVersion: performance.openshift.io/v2
kind: PerformanceProfile                                         kind: PerformanceProfile
metadata:                                                        metadata:
  annotations:                                                     annotations:
    ran.openshift.io/ztp-deploy-wave: "10"                           ran.openshift.io/ztp-deploy-wave: "10"
  name: openshift-node-performance-profile                         name: openshift-node-performance-profile
spec:                                                            spec:
  additionalKernelArgs:                                            additionalKernelArgs:
    - rcupdate.rcu_normal_after_boot=0                               - rcupdate.rcu_normal_after_boot=0
  cpu:                                                             cpu:
    isolated: 2-19,22-39                                             isolated: 2-31,34-63
    reserved: 0-1,20-21                                              reserved: 0-1,32-33
  hugepages:                                                       hugepages:
    defaultHugepagesSize: 1G                                         defaultHugepagesSize: 1G
    pages:                                                           pages:
      - count: 32                                                      - count: 32
                                                              >          node: 0
        size: 1G                                                         size: 1G
  machineConfigPoolSelector:                                       machineConfigPoolSelector:
    pools.operator.machineconfiguration.openshift.io/master:         pools.operator.machineconfiguration.openshift.io/master:
  nodeSelector:                                                    nodeSelector:
    node-role.kubernetes.io/master: ""                               node-role.kubernetes.io/master: ""
  numa:                                                            numa:
    topologyPolicy: restricted                                       topologyPolicy: restricted
  realTimeKernel:                                                  realTimeKernel:
    enabled: true                                             |      enabled: false

---
<next CR>
...

Summary
  Missing required CRs
    someCR
    anotherCR
  Unmatched CRs
    unknownCR
    anotherUnknownCR
  Total CRs with drift: 2
```

#### Tool delivery

The tool will be a standalone binary executable suitable for direct use by customers, developers,
support engineering, etc. The tool may be installed as a kubectl/oc plugin.

### Reference Configuration Specification

The reference configuration consists of a set of CRs (yaml files with one CR per file) with
annotations/metadata to describe expected variability. The reference configuration CRs conform to
these criteria:
1. Each CR may be annotated as a required (ie a compliant cluster must contain at least one of that
   CR) or optional CR.
1. Each CR may contain annotations to indicate fields which have expected user variation or which
   are optional.
1. Any field of a reference configuration CR which is not otherwise annotated is required and the
   value must be as specified in order to be compliant.

#### Reference CR Annotations

Annotations attached to the CRs are used for providing additional data used during validation. In
the initial version of this tool the annotation is used in making two determinations:
1. The `component-name` is used to group together related CRs in order to capture optional groups of
   CRs (eg combination of optional Operator subscription and configuration CRs). If any of the
   required CRs (see `required` next) are included in the input configuration then all required CRs
   in the group are expected to be included and any which are missing will be reported. If none of
   the required CRs in the group are included then no report of "missing content" for the group will
   be generated. Optionally the tool may allow for explicit include/exclude of a component-name by
   command line argument.
1. The `required` field indicates if the CR must be present in the input configuration. Any required
   CR which is not included is reported in the summary as "missing content". The required field has
   a scope of "within the component-name". If a specfici component-name is not included in the
   analysis then any required CRs within that component are not flagged as missing content.

| key | value | default |
| --- | ---- | --- |
| part-of | the highest level that the CR is part-of e.g DU. | "" |
| required | must be available. | true |
| component-name | bundle up sibling CRs. E.g ref PerformaceProfile and TuneD. | "" |

```yaml
metadata:
  annotations:
    reference-config.openshift.io/attributes: |
      {"part-of": "sample.reference.config",
       "required": true,
       "component-name": "someSubComponent"
       }
```

#### Example Reference Configuration CR
User variable content is handled by golang formatted templating within the reference configuration
CRs. This templating format allows for simple "any value", complex validation, and conditional
inclusion/exclusion of content. The following types of user variation are expected to be handled:
1. Mandatory user-defined fields. Examples are marked #1.
1. Optional user-defined fields. Examples are marked #2
1. Validation of user defined fields. Examples are marked with #3-n

```yaml
# PerformanceProfile.yaml with Validation
apiVersion: performance.openshift.io/v2
kind: PerformanceProfile
metadata:
  name: openshift-node-performance-profile
  labels:
    # legacy label. This may be obsoleted by the new annotation below.
    ran.openshift.io/reference-configuration: "du"
  annotations:
    # new annotation. describe in a previous section
    reference-config.openshift.io/attributes: |
      {"part-of": "telco.ran.du",
       "required": true,
       "component-name": "performance"}
spec:
  additionalKernelArgs: # This entire block is an example of required "fixed" content
    - "rcupdate.rcu_normal_after_boot=0"
    - "efi=runtime"
    - "module_blacklist=irdma"
  cpu:
    isolated: {{ .spec.cpu.isolated  }} # #1 mandatory user variable content
    reserved: {{ .spec.cpu.reserved  }} # #1 mandatory user variable content
  hugepages:
    defaultHugepagesSize: {{ .spec.hugepages.defaultHugepagesSize  }} # #1 mandatory
    pages:
      {{- maxListLength 1   .spec.hugepages.pages }} #3-1 defined in Go
        {{- range .spec.hugepages.pages }}
      - size:  {{block "validatesize" .}} {{ .size  }} {{end}} #3-2 can be defined later during runtime or falls back to .size
        count: {{ .count }} {{ if eq "float64" (printf "%T" .count) }}is a float64 {{ else }} is not a float64{{ end }}
        {{ if .node }} # #2 Optional user defined field with validation
        node: {{ if eq .node nil }}you can't do that...must initialize!{{ else }}{{ .node }}{{ end }}
        {{ end }}
      {{- end }}
  machineConfigPoolSelector:
    pools.operator.machineconfiguration.openshift.io/{{ .mcp }}: ""
  nodeSelector:
    node-role.kubernetes.io/{{ .mcp }}: ""
  numa:
    topologyPolicy: "restricted"
  realTimeKernel:
    enabled: true
  {{- if .spec.workloadHints }} #2 optional chunk of CR
  # user turned off workloadHints
  workloadHints:
    realTime: true
    highPowerConsumption: false
    perPodPowerManagement: false
  {{- else }}
  # consider using workloadHints
  {{- end }}


# a template func
{{define "pasteArbitraryToYaml"}}
{{ . | RanToYaml}}
{{end}}
```

Golang supports handling of these types through template processing:
- Mandatory defined variables. See #1 for more
  - The engine can be configured to have catch-all error e.g
    ```go
    files := template.Must(template.New(srcCr).
              ...
              Option("missingkey=error"). // catch all
              ...
    ```
  - or specific checks with custom error
    ```yaml
    {{ if eq .node nil }{{ fail "MUST HAVE NODE!" }}}{{ end }}
    ```
- Using templating allows use of built-in/3pp (e.g Sprig)/custom functions and be implemented/called using different techniques. Examples #3-n show some of these functions.


#### Diff

Once the validations are complete we run a diff between the user's input configuration (now
validated) CR vs the resolved template (user variable input is pulled from input config into the
resolved template). This final step is needed to error/warn user of remaining drift that validation
steps may not catch
- E.g use case: reference may have a hardcoded field such as a namespace name and the user must comply.

The primary output of this step is a side-by-side diff as shown in the output section above. To
achieve this meaningful diff the tool must do perform two operations:
1. Render the CRs into a comparable format. This involves doing a hierarchical sorting of the keys
   to ensure consistent ordering when the CRs are rendered.
1. Perform the diff

There are several methods of implementation which can be considered. As part of an initial spike two
options were looked at:
* the golang custom `Reporter`
* the K8s built-in `diff` command which combines patching and an external diff tool via
  `KUBECTL_EXTERNAL_DIFF`. This existing functionality targets a live cluster and would need to be
  copied/updated for local diff.

A combination of both methods may be used to produce the final CRA and CRB ready to be diff and then
run in through logic similar to the K8s diff module (modified for local use)


#### Relationship to PolicyGen and ACM PolicyGenerator

The initial reference configuration will be for the RAN DU use case for which there is an existing
set of CRs serving as both the reference configuration and the baseline set of CRs used in
deployment of compliant clusters. Any modifications done to these CRs in support of use as a
reference configuration for this tool must not prevent their use in deployment.

To ensure that both tool flows (validation and deployment) are supported by a single set of
reference configuration CRs the work under this enhancement will define a translation (separate
tool/function from validation tool) from templated reference configuration (as defined above) into a
rendered set of "source CRs" which can be used for deployment. This translation is a simple process
which consumes the reference configuration and the appropriate set of default values for all
required templated fields. The proposed template syntax is defined to pull values from the user
specified files which makes the translation a trivial process of providing a default set of inputs
into the normal execution. The resulting generated CRs will identically match the existing "source
CRs" in use today.

The process of generating source CRs from the reference configuration will be done by developers
when any changes are made to the reference configuration. A CI job will verify and enforce that the
derived source-CRs are always in sync with changes to the reference. This ensures that the upstream
repository continues to contain valid and current reference configuration and source CRs.

#### Other non-selected options for Reference Configuration Specification
We looked into using `$val` syntax used by PolicyGenTemplate binary and found in source-cr files. It
is somewhat "custom" (the words used after $ is arbitrary) and generally used only as a marker for
search-replace commands. This syntax does not support any specification of required vs optional, nor
does it allow for validation of allowable range/values.

### Workflow Description

When deployed as a command-line plugin:
`kubectl/oc compare <referenceConfiguration> <inputConfiguration>`

#### Variation [optional]

None

### API Extensions

None

### Implementation Details/Notes/Constraints [optional]

The reference configuration CRs serve two purposes

1. The source reference for this comparison tool
1. The baseline CRs used when customers deploy a cluster compliant with the reference The format and
structure of annotations introduced in support of this tool must be compatible with the second
(deployment) use case. See "Relationship to PolicyGen and ACM PolicyGenerator" above.

### Risks and Mitigations

1. Risk of false negatives when performing comparisons – Giving the user a false indication that a
   cluster is compliant will lead to degraded performance or functionality. These could be
   introduced by bugs in the tool or reference configuration. Leveraging standard templating syntax
   and libraries for performing the analysis (parsers, template handling, comparison) mitigates the
   risk.

### Drawbacks

Existing tools can perform a diff of two CRs – This tool extends that functionality to allow for
expected variations, optional content, and detection of missing/unmatched content.

## Design Details

### Open Questions [optional]

None (yet)

### Test Plan

Primary testing will be through automated upstream CI. The tool is a standalone executable which can
be exercised through a set of inputs with deterministic outputs. The CI will cover both positive and
negative test scenarios.

### Graduation Criteria

Initial development will be done with beta versioning (0.x)

#### Dev Preview -> Tech Preview
Initial feedback on the diff tool will be taken from use of the tool in validation of existing test
environments.

Initial feedback on the reference configuration format will be derived from conversion of the RAN DU
reference configuration.

As discussed under "Test Plan" a significant portion of testing can be done as automated tests in
the upstream CI.

#### Tech Preview -> GA

TBD

#### Removing a deprecated feature

First implementation. No deprecations.

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

- 2023-07-04 Initial enhancement proposal

## Alternatives

### kubectl/oc diff
The existing kubectl/oc diff works well for validation of a CR (or set of CRs) on a cluster against
a known valid configuration. This tool does a good job of suppressing diffs in known managed fields
(eg metadata, status, etc), however it is lacking in several critical features for the use cases in
this enhancement:
* Suppression of expected user variations
* Handling of one-to-many matches
* Comparison of two offline files

### Command line utilities
diff -t -y -w <(yq 'sort_keys(..)' /path/to/reference/config/cr) <(yq 'sort_keys(..)' /path/to/input/cr )

## Infrastructure Needed [optional]

Upstream github repository in openshift-kni project.
