#!/bin/bash
set -e

## Repository pinning

GOOSE_REPO=https://github.com/tchajed/goose/
GOOSE_COMMIT=master

STD_REPO=https://github.com/goose-lang/std
STD_COMMIT=master

MARSHAL_REPO=https://github.com/tchajed/marshal
MARSHAL_COMMIT=master

EXAMPLES_REPO=https://github.com/mit-pdos/perennial-examples
EXAMPLES_COMMIT=master

JOURNAL_REPO=https://github.com/mit-pdos/go-journal
JOURNAL_COMMIT=master

NFSD_REPO=https://github.com/mit-pdos/go-nfsd
NFSD_COMMIT=master

GOKV_REPO=https://github.com/mit-pdos/gokv
GOKV_COMMIT=main

MVCC_REPO=https://github.com/mit-pdos/go-mvcc
MVCC_COMMIT=main

## Actual test logic

echo && echo "Goose check: fetch all the repos"

function checkout {
  local REPO_VAR=$1_REPO
  local COMMIT_VAR=$1_COMMIT
  local DIR_VAR=$1_DIR

  git clone "${!REPO_VAR}" "${!DIR_VAR}"
  (cd "${!DIR_VAR}" && git reset --hard "${!COMMIT_VAR}")
}

GOOSE_DIR=/tmp/goose
checkout GOOSE

STD_DIR=/tmp/std
checkout STD

MARSHAL_DIR=/tmp/marshal
checkout MARSHAL

EXAMPLES_DIR=/tmp/examples
checkout EXAMPLES

JOURNAL_DIR=/tmp/journal
checkout JOURNAL

NFSD_DIR=/tmp/nfsd
checkout NFSD

GOKV_DIR=/tmp/gokv
checkout GOKV

MVCC_DIR=/tmp/mvcc
checkout MVCC

echo && echo "Goose check: re-run goose"
etc/update-goose.py --goose $GOOSE_DIR --compile \
  --goose-examples \
  --std $STD_DIR \
  --marshal $MARSHAL_DIR \
  --examples $EXAMPLES_DIR \
  --journal $JOURNAL_DIR \
  --nfsd $NFSD_DIR \
  --gokv $GOKV_DIR \
  --mvcc $MVCC_DIR
# Missing: --distributed-examples (not currently used)

echo && echo "Goose check: check if anything changed"
if [ -n "$(git status --porcelain)" ]; then
  echo 'ERROR: Goose files are not in sync with repositories pinned in `etc/ci-goose-check.sh`. `git diff` after re-goosing:'
  git diff
  exit 1
fi
