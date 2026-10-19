#!/usr/bin/env bash
set -euo pipefail

if [[ ! "${SSH_ORIGINAL_COMMAND:-}" =~ ^deploy\ [0-9a-f]{40}$ ]]; then
  echo "Only deploy <commit-sha> is allowed" >&2
  exit 1
fi

expected_sha="${SSH_ORIGINAL_COMMAND#deploy }"
sudo -n /usr/bin/systemctl start tosub2api-update.service
running_sha="$(cat /opt/tosub2api/current-sha)"
printf 'Server running commit: %s\n' "$running_sha"
if [[ "$running_sha" != "$expected_sha" ]]; then
  echo "Deployment deferred because authorization jobs are active or queued; the server timer will retry automatically"
  exit 0
fi
