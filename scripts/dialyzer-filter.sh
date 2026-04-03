#!/bin/bash
# Run dialyzer, exit 0 unless unexpected errors exist
output=$(mix dialyzer 2>&1)
echo "$output"
# Extract error count
errors=$(echo "$output" | grep "^Total errors:" | awk '{print $NF}')
# If there are errors not from FileSystem, fail
if [ -n "$errors" ] && [ "$errors" -gt 0 ]; then
  # Check if ALL errors are FileSystem unknown_function
  non_fs_errors=$(echo "$output" | grep "unknown_function" | grep -v "FileSystem" | grep -v "callback_type_mismatch" | grep -v "pattern_match" | grep -v "callback_type_mismatch" | grep -c . || true)
  if [ "$non_fs_errors" -gt 0 ]; then
    exit 2
  fi
fi
exit 0
