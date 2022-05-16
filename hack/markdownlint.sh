#!/bin/bash -ex

markdownlint-cli2 '**/*.md'

$(dirname $0)/template-lint.sh

echo "skipping metadata lint until required"
#$(dirname $0)/metadata-lint.sh
