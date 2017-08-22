#!/usr/bin/env bash

sleep 60

while true; do \
  sleep 30
  # only run on the first live node in the cluster
  FIRSTNODE=$(vmq-admin cluster show | grep true | awk  'BEGIN { FS = "|" } ; {print $2}' | sort | head -n 1)
  cat /etc/vernemq/vm.args | grep -q ${FIRSTNODE} || continue;

  DEAD_NODE=$(vmq-admin cluster show | grep false | awk  'BEGIN { FS = "|" } ; {print $2}' | head -n 1)
  if [ -n "$DEAD_NODE" ]; then
    vmq-admin cluster leave node=${DEAD_NODE}
  fi
done