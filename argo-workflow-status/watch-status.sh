#!/bin/sh -e
git_sha="$1"
pull_request="$2"

if [ -z "$git_sha" ]; then
  echo "Usage $0 GIT_SHA [PULL_REQUEST]"
  exit 1
fi

if [ -z "$pull_request" ]; then
  pull_request="master"
fi

export workflow_name="${pull_request}-${git_sha}"

while true; do
  workflow_status=$(
    kubectl get -n e2e-tests workflow/$workflow_name -o json 2>/dev/null |
    jq -r .status.phase
  )
  if [ -z "$workflow_status" ]; then
    echo "Waiting for e2e workflow for $workflow_name to appear..."
  elif [ "$workflow_status" = "Pending" ] ||
       [ "$workflow_status" = "Running" ] ||
       [ "$workflow_status" = "null" ]; then
    echo "Waiting for e2e workflow for $workflow_name to complete..."
  else
    break
  fi
  sleep 5
done

echo "E2E workflow for $workflow_name finished with status $workflow_status"
if [ "$workflow_status" = "Succeeded" ]; then
  exit 0
fi

while true; do
  e2e_pod=$(
    kubectl get pods -n e2e-tests -l pod_function=e2e-tests --sort-by=.status.startTime --no-headers |
    perl -ne 'next unless /$ENV{workflow_name}/; s/^\s*(\S+).*/$1/; print;' |
    tail -n 1
  )
  if [ -z "$e2e_pod" ]; then
    echo "Unable to find the e2e-test pod for $workflow_name"
    sleep 5
  else
    break
  fi
done

echo "Showing log for pod: $e2e_pod"
kubectl -n e2e-tests logs "$e2e_pod" -c main

exit 1
