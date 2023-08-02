---
title: cnf-tests-split
authors:
  - "@liornoy"
reviewers:
  - "@cnf-network-team"
  - "@cnf-ci-team"
  - "@cnf-compute-team"
approvers:
  - "@cnf-network-team"
  - "@cnf-ci-team"
  - "@cnf-compute-team"
creation-date: 2023-06-01
last-updated: 2023-06-01
tracking-link:
  - https://issues.redhat.com/browse/CNF-7583
---

# CNF-tests split

The cnf tests suite aims to validate various openshift features necessary to run CNF workloads on a cluster.
The cnf-tests are running on upstream and downstream CI in a periodic and nightly manner in order to verify that the workloads are functioning as intended.

## Summary

The purpose of this enhancement is to decouple the cnf-tests from the test suites of the features hosted in external projects. Additionally, as this change affects the way tests are run, we propose rewriting the cnf-tests container image, which is a supported product for running the latency tests.

## Motivation

In the cnf-tests, all three test suites (configsuite, e2esuite, valdiationsuite) are importing
external test suites (outside of the cnf-feauters-deploy repository) with a [blank identifier](https://golangbyexample.com/blank-identifier-import-golang/). This is done to compile their tests into one binary. For example, in the e2esuite, we import the following:

```go
import (
    _ "github.com/k8snetworkplumbingwg/sriov-network-operator/test/conformance/tests"
    _ "github.com/metallb/metallb-operator/test/e2e/functional/tests"
    _ "github.com/openshift/cluster-node-tuning-operator/test/e2e/performanceprofile/functests/1_performance" 
    _ "github.com/openshift/cluster-node-tuning-operator/test/e2e/performanceprofile/functests/4_latency" 
    _ "github.com/openshift/ptp-operator/test/conformance/serial"
)
```

To prevent conflicts due to the numerous dependencies in the test suites, we want to decouple the external test suites by cloning them independently via git-submodules and have a script that invokes them.


### Note

We will still have some dependencies in the external test suites as there are integration tests that combine multiple features.

For detailed information about the changes in the cnf-tests container, please refer to the section titled [Rewrite the cnf-tests container](#rewrite-the-cnf-tests-container).

### Goals

1. Make it possible to run the cnf-tests solely by cloning the repo.
2. Instead of vendoring external test suites, clone the external projects and run the tests locally.
3. Continue to use the same API, report output, and testing scope.
4. Restructure the cnf-tests container so that it only contains latency-tests.

### Non-Goals

1. Rename existing tests to a certain standard.
2. Change the scope of the tests being run.

## Proposal

### User Stories

#### Story 1

As a developer, I want to run the cnf-tests suites so that I can validate my CNF feature works properly.

#### Story 2

As an Openshift administrator, I want to run the latency tests so that
I can benchmark different CNF features.

#### Story 3

As a CI engineer, I want to ensure the whole specific set of CNF features is working properly with latest OCP release.

### The way to run the tests

We'll use the same `Makefile` targets as before to run the cnf-tests. For example, `functests`, `functests-on-ci-no-index-build`, `functests-on-ci`, `feature-deploy-on-ci`, and so on. Moreover, the deployment mechanism remains the same.

### Workflow Description

This change will not affect the current API, including parameters/environment variables used to invoke the cnf-tests: `TEST_SUITES`, `FEATURES`, `FOCUS_TESTS`, `SKIP_TESTS`, `GINKGO_PARAMS`, `FAIL_FAST`, `DISCOVERY_MODE` and `TESTS_REPORTS_PATH`. 
However, with this proposal, instead of running test binaries that combine all the external test suites,  we will introduce an **optional** parameter named `EXTERNAL_SUITES` to control what external test suites to run.
By default, the test will execute all of the suites that were previously run.

Consider the following example to better understand this new variable:
Running the `e2esuite` test suite, with an empty `EXTERNAL_SUITES` and `FEATURES=metallb`, results in
ginkgo's test being run in all of the suites: sriov, metallb, nto-performance, nto-latency, ptp and integration, adding the flag `-ginkgo.focus=metallb`.
In other words, the `FEATURES` var functionality remains unchanged.

When running the `e2esuite` test suite with `EXTERNAL_SUITES=metallb` it will invoke only the metallb suite
of the e2esuite, i.e.: `cnf-tests/submodules/metallb-operator/test/e2e/functional/tests`
and for the validation suite, it will run: `cnf-tests/submodules/metallb-operator/test/e2e/validation/tests`

The mapping of the test_suite + external_suite to the desired suite path is done by:

```bash
declare -A TESTS_PATHS=\
(["configsuite nto"]="cnf-tests/submodules/cluster-node-tuning-operator/test/e2e/performanceprofile/functests/0_config"\
 ["validationsuite integration"]="cnf-tests/testsuites/validationsuite"\
 ["validationsuite metallb"]="cnf-tests/submodules/metallb-operator/test/e2e/validation"\
 ["cnftests integration"]="cnf-tests/testsuites/e2esuite"\
 ["cnftests metallb"]="cnf-tests/submodules/metallb-operator/test/e2e/functional"\
 ["cnftests sriov"]="cnf-tests/submodules/sriov-network-operator/test/conformance"\
 ["cnftests nto-performance"]="cnf-tests/submodules/cluster-node-tuning-operator/test/e2e/performanceprofile/functests/1_performance"\
 ["cnftests nto-latency"]="cnf-tests/submodules/cluster-node-tuning-operator/test/e2e/performanceprofile/functests/4_latency"\
 ["cnftests ptp"]="cnf-tests/submodules/ptp-operator/test/conformance/serial")
```

The new `init-git-submodules` target, which inits and updates the git submodules, will be required to run those rules.
The `init-git-submodules` command will checkout the external repositories into desried commits, defaults to latest, taken from the env vars: `METALLB_OPERATOR_TARGET_COMMIT`, `SRIOV_NETWORK_OPERATOR_TARGET_COMMIT`, `PTP_OPERATOR_TARGET_COMMIT`, `CLUSTER_NODE_TUNING_OPERATOR_TARGET_COMMIT`.
To make it clear what we're consuming, we'll print the commit hash of each suite on the test execution.
Also, for ease of use in case of testing old releases, we'll introduce a variable named `TARGET_RELEASE` to set a specific release branch name (e.g. `release-4.13`), and this will be applied to all of the external repositories.

As for the documentation of the tests list (i.e. docgen and the TESTLIST.md), we'll pin
against commits and have it updated manually occasionally. Thus avoid forcing PR contributors to fix the docs in case the latest commit brings changes to the tests.

Instead of `cnf-tests/entrypoint/test-run.sh`, the underlining script responsible for executing the tests will be `run-functests.sh`.

### Reports

In order to maintain the same reporting capabilities, we need to:
1. Add the k8s reporter to each external test suite that doesn't have it already.
2. Use Ginkgo's built-in junit generator so that we don't have to add the `-junit` flag to each repo.
3. Create a local junit merger program to aggregate all of the junit reports under the same test suite.

### Rewrite the cnf-tests container

In the past Red Hat delivered the various cnf-tests as a product,
however today we support only the latency tests within it.
see [Performing latency tests for platform verification](https://docs.openshift.com/container-platform/4.13/scalability_and_performance/cnf-performing-platform-verification-latency-tests.html)

In this refactoring we include changes to the cnf-tests container because
currently the interface for the latency tests is not user-friendly.
e.g. we currently tell the users to run it by:
```bash
$ podman run -v $(pwd)/:/kubeconfig:Z -e KUBECONFIG=/kubeconfig/kubeconfig \
-e LATENCY_TEST_RUN=true -e DISCOVERY_MODE=true -e FEATURES=performance registry.redhat.io/openshift4/cnf-tests-rhel8:v4.13 \
/usr/bin/test-run.sh -ginkgo.focus="\[performance\]\ Latency\ Test"
```

In the command above the inputs: `LATENCY_TEST_RUN`, `DISCOVERY_MODE`, `FEATURES`, and the `-ginkgo.focus`.
can be hidden from the user if we write the container image to include only the latency tests, making a cleaner entrypoint.
Moreover, the current container can be disruptive if you don't pass the
`DISCOVERY_MODE` var or misspell it.  
Because when it's not set to true,
the binary will apply a different configuration to the cluster and may
cause a reboot - something severe and not acceptable on the client's production cluster.

The rewrite will alter the cnf-tests's Dockerfile, the `cnf-tests/entrypoint/test-run.sh` script
and the `build-test-bin.sh` hack script. Making the container image include only the latency
tests, and hardcoding the required parameters into the scripts.
The documentation for this product will be updated to reflect the changes.

### API Extensions

N/A

### Risks and Mitigations

The most major risk here revolves around changing the cnf-tests container.
That is because it's delivered as a product supported by Red Hat, and
We should make sure to keep backward compatibility and provide the relevant documentation explaining the new interface for the latency tests.

### Drawbacks

In order to implement this, we will have to touch other code bases and
add the k8s reporter, which can be rejected or unwelcomed by the upstream community.
Also, the k8s reporter flag we introduce in the external repositories
is a must-have for the tests to run. i.e., if in the future someone
will remove or change this flag it may cause the test run to fail and it is out of our control.
We can mitigate this by always running all the tests with a dry run this will tell us if some suite broke with regards to our API.
Additionally, we might break some internal users' pipelines in case they don't migrate and keep building and using the cnf-tests container for running the tests.

## Design Details

### Test Plan

1. Validate that the cnf-tests are passing on CI.
2. Ensure that the set of tests we expect to run remains the same.
3. Validate that the cnf-tests container image is built successfully and run all the necessary tests while keeping backward compatibility.

### Migration Actions

The changes mostly affect users who use the cnf-tests container to run the
e2e tests. For example:
```bash
podman run --name cnf-container-tests \
        --net=host \
        -v cnf_test_dir:/kubeconfig:Z \
        -v cnf_test_dir/junit:/junit:Z \
        -v cnf_test_dir/report:/report:Z \
        -e KUBECONFIG=/kubeconfig/kubeconfig \
        -e NODES_SELECTOR=node-role.kubernetes.io/workercnf= \
        -e ROLE_WORKER_CNF=workercnf \
        -e DISCOVERY_MODE=true \
        -e IS_OPENSHIFT=true \
        -e XT_U32TEST_HAS_NON_CNF_WORKERS=false \
        -e SCTPTEST_HAS_NON_CNF_WORKERS=false \
        registry.redhat.io/openshift4/cnf-tests-rhel8:latest \
        /usr/bin/test-run.sh  \
        -ginkgo.focus="performance ptp sctp xt_u32 ovn ovs_qos metallb fec sriov s2i dpdk multinetworkpolicy"
        -ginkgo.skip "28466|28467" \
        -ginkgo.timeout=24h \
```
This way will not be supported anymore, to re-worked it:
1. Clone the cnf-features-deploy repo.
2. Export the enviourment variables:
```bash
export KUBECONFIG=/kubeconfig/kubeconfig \
export NODES_SELECTOR=node-role.kubernetes.io/workercnf= \
export ROLE_WORKER_CNF=workercnf \
export DISCOVERY_MODE=true \
export IS_OPENSHIFT=true \
export XT_U32TEST_HAS_NON_CNF_WORKERS=false \
export SCTPTEST_HAS_NON_CNF_WORKERS=false \ 
```
2. Export and set parameters for the test:
```bash
export FOCUS_TESTS="performance ptp sctp xt_u32 ovn ovs_qos metallb fec sriov s2i dpdk multinetworkpolicy"
export SKIP_TESTS="28466|28467"
export GINKGO_PARAMS="-ginkgo.timeout=24h"
export TESTS_REPORTS_PATH="cnf_test_dir"
```
3. Invoke the tests: `make functests`

### Graduation Criteria

N/A

#### Dev Preview -> Tech Preview

N/A

#### Tech Preview -> GA

N/A

#### Removing a deprecated feature

- This proposal removes the option of running the cnf-tests in a containerized way.

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

## Alternatives

N/A

## Implementation History

Open draft PRs are open for this proposal:  
1. The cnf-tests split part: https://github.com/openshift-kni/cnf-features-deploy/pull/1501  
2. The cnf-tests container rewrite part: https://github.com/openshift-kni/cnf-features-deploy/pull/1510
3. Add the k8s reporter to sriov: https://github.com/k8snetworkplumbingwg/sriov-network-operator/pull/448
4. Add the k8s reporter to nto: https://github.com/openshift/cluster-node-tuning-operator/pull/666
5. Add the k8s reporter to ptp: https://github.com/openshift/ptp-operator/pull/353
