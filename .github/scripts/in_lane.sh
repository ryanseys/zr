#!/usr/bin/env bash
# Runs a command where this job's lane runs it (.github/workflows/lane.yml):
# on the runner, or, when LANE_CONTAINER is set, in the Alpine container
# that .github/actions/alpine started. The container gets the settings
# below that this step has. A step summary that the command writes in
# the container goes to the step's own summary.
#
#   .github/scripts/in_lane.sh COMMAND [ARGS...]
set -uo pipefail

if [ -z "${LANE_CONTAINER:-}" ]; then
  exec "$@"
fi

passed=(-e GITHUB_ACTIONS=true)
for name in ZR_TARGET ZR_JOBS ZR_VERIFY ZR_TIMING ZR_PROGRAMS ZR_TEST_SHARD ZR_TEST_SECONDS ZR_TEST_TIMEOUT ZR_MCACHE; do
  if [ -n "${!name:-}" ]; then passed+=(-e "$name=${!name}"); fi
done
summary=tmp/step-summary.md
# The container's root owns tmp (the cache must be its user's), so the
# container removes the summary of the step before.
docker exec alpine rm -f "$PWD/$summary"
passed+=(-e "GITHUB_STEP_SUMMARY=$PWD/$summary")

docker exec "${passed[@]}" alpine "$@"
status=$?
if [ -f "$summary" ] && [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
  cat "$summary" >> "$GITHUB_STEP_SUMMARY"
fi
exit "$status"
