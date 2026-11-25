cd "$(dirname "$0")/.."
mkdir -p logs results
LOG="logs/$(basename "$0" .sh).log"
exec > >(tee "$LOG") 2>&1
trap 'echo "прервано"; exit 130' INT
export KUBECONFIG_CONTEXT=kind-hw5

if ! docker info >/dev/null 2>&1; then
  echo "Docker не запущен: открой Docker Desktop, дождись Engine running и запусти скрипт снова"
  exit 1
fi

run() {
  echo
  echo "\$ $*"
  "$@"
}

stamp() {
  echo
  echo "===== $(date '+%Y-%m-%d %H:%M:%S') $* ====="
}

pod_of() {
  kubectl -n "$1" get pods -l job-name="$2" -o jsonpath='{.items[0].metadata.name}'
}

save_job() {
  ns=$1; job=$2
  kubectl -n "$ns" logs "job/$job" --all-containers=true --prefix=false > "logs/job_$job.log" 2>&1 || true
  for p in $(kubectl -n "$ns" get pods -l job-name="$job" -o jsonpath='{.items[*].metadata.name}'); do
    kubectl -n "$ns" logs "$p" > "logs/pod_$p.log" 2>&1 || true
  done
  kubectl -n "$ns" describe job "$job" > "logs/describe_job_$job.txt" 2>&1 || true
  kubectl -n "$ns" get pods -l job-name="$job" -o wide > "logs/pods_$job.txt" 2>&1 || true
}
