#!/usr/bin/env bash
set -euo pipefail

repo_url="https://github.com/lee6583/tosub2api.git"
deploy_root="/opt/tosub2api"
container_name="tosub2api"
state_dir="$deploy_root/data"
mkdir -p "$deploy_root/releases" "$state_dir"
chown 1000:1000 "$state_dir"
chmod 700 "$state_dir"

target_sha="$(git ls-remote "$repo_url" refs/heads/main | cut -f1)"
if [[ ! "$target_sha" =~ ^[0-9a-f]{40}$ ]]; then
  echo "Could not resolve the GitHub main branch" >&2
  exit 1
fi
if [[ -f "$deploy_root/current-sha" && "$(cat "$deploy_root/current-sha")" == "$target_sha" ]] \
  && docker inspect -f '{{.State.Running}}' "$container_name" 2>/dev/null | grep -qx true; then
  exit 0
fi

if [[ "$(docker inspect -f '{{.State.Running}}' "$container_name" 2>/dev/null || true)" == true ]]; then
  health="$(curl -fsS --max-time 5 http://127.0.0.1:4399/api/bootstrap || true)"
  if [[ -z "$health" ]]; then
    echo "Existing console health check failed; leaving it untouched" >&2
    exit 1
  fi
  token="$(printf '%s' "$health" | python3 -c 'import json,sys; print(json.load(sys.stdin)["token"])')"
  jobs="$(curl -fsS --max-time 5 -H "x-console-token: $token" http://127.0.0.1:4399/api/jobs || true)"
  if [[ -z "$jobs" ]]; then
    echo "Could not check active jobs; leaving the console untouched" >&2
    exit 1
  fi
  if ! printf '%s' "$jobs" | python3 -c 'import json,sys; stats=json.load(sys.stdin)["stats"]; sys.exit(0 if not stats["active"] and not stats["queued"] else 1)'; then
    echo "Authorization jobs are active or queued; retrying deployment later"
    exit 0
  fi
fi

release="$deploy_root/releases/$target_sha"
if [[ ! -d "$release" ]]; then
  pending="$deploy_root/releases/.pending-$target_sha"
  rm -rf "$pending"
  git clone --quiet --depth 1 --branch main "$repo_url" "$pending"
  if [[ "$(git -C "$pending" rev-parse HEAD)" != "$target_sha" ]]; then
    rm -rf "$pending"
    echo "The main branch changed during checkout; retrying later" >&2
    exit 1
  fi
  mv "$pending" "$release"
fi

image="tosub2api:$target_sha"
docker build --quiet -t "$image" "$release"
previous_image="$(docker inspect -f '{{.Config.Image}}' "$container_name" 2>/dev/null || true)"

start_container() {
  docker run -d --name "$container_name" --restart unless-stopped \
    --log-opt max-size=10m --log-opt max-file=3 \
    -p 127.0.0.1:4399:4399 -v "$state_dir:/data" "$1" >/dev/null
}

docker rm -f "$container_name" >/dev/null 2>&1 || true
if ! start_container "$image"; then
  if [[ -n "$previous_image" ]]; then start_container "$previous_image"; fi
  exit 1
fi

for attempt in $(seq 1 30); do
  if curl -fsS --max-time 2 http://127.0.0.1:4399/api/bootstrap >/dev/null; then
    printf '%s\n' "$target_sha" > "$deploy_root/current-sha"
    echo "Deployed $target_sha"
    exit 0
  fi
  sleep 2
done

docker logs --tail 40 "$container_name" >&2 || true
docker rm -f "$container_name" >/dev/null 2>&1 || true
if [[ -n "$previous_image" ]]; then start_container "$previous_image"; fi
echo "New deployment did not become healthy; previous image restored when available" >&2
exit 1
