#!/bin/bash

set -e

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )

buck run fbcode//hphp/hack/src/hh_manual:hh_manual extract "$SCRIPT_DIR/../../manual/hack"

CHANGED_FILES="$(hg st)"
if [[ -z "$CHANGED_FILES" ]]
then
  echo "No files changed!"
else
  echo ""
  echo "ERROR: Files have changed!"
  echo "$CHANGED_FILES"
  echo ""
  echo "Please run:"
  echo "$ buck run fbcode//hphp/hack/src/hh_manual:hh_manual extract hphp/hack/manual/hack/"
  echo "and amend the generated files into your diff."
  exit 1
fi