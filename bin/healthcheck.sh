#!/usr/bin/env bash

#give it 60 seconds to start up before testing
if [ "$(($(date +%s) - $(date +%s -r /proc/1/cmdline)))" -lt "90" ]; then
  exit 0;
fi

vernemq ping
exit $?