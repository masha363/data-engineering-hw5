#!/bin/bash
source "$(dirname "$0")/lib.sh"
kubectl -n hw5 delete job cpu-low cpu-waiter cpu-high --ignore-not-found --wait=true
ALLOC=$(kubectl get node hw5-control-plane -o jsonpath='{.status.allocatable.cpu}')
USED=$(kubectl get pods -A --field-selector=status.phase=Running -o json | python3 -c '
import json, sys
def m(v):
    return int(v[:-1]) if v.endswith("m") else int(float(v) * 1000)
total = 0
for p in json.load(sys.stdin)["items"]:
    for c in p["spec"]["containers"]:
        total += m(c.get("resources", {}).get("requests", {}).get("cpu", "0"))
print(total)')
ALLOC_M=$(python3 -c "v='$ALLOC'; print(int(v[:-1]) if v.endswith('m') else int(float(v)*1000))")
FREE=$((ALLOC_M - USED))
HOG=$((FREE - 500))
BIG=1500
echo "allocatable cpu: ${ALLOC_M}m, уже запрошено подами: ${USED}m, свободно: ${FREE}m"
echo "cpu-low запросит ${HOG}m (останется 500m), cpu-waiter и cpu-high запросят по ${BIG}m"
echo "alloc_m=$ALLOC_M used_m=$USED free_m=$FREE hog_m=$HOG big_m=$BIG" > results/cpu_plan.txt
for f in 21-job-cpu-low 22-job-cpu-waiter 23-job-cpu-high; do
  sed -e "s/@HOG_CPU@/${HOG}m/" -e "s/@BIG_CPU@/${BIG}m/" k8s/$f.yaml.in > k8s/$f.yaml
done

stamp "шаг 4.1: классы приоритета"
run kubectl apply -f k8s/20-priority-classes.yaml
run kubectl get priorityclass

stamp "шаг 4.2: ожидание при нехватке процессора"
run kubectl apply -f k8s/21-job-cpu-low.yaml
run kubectl -n hw5 wait --for=condition=Ready pod -l job-name=cpu-low --timeout=120s || exit 1
run kubectl apply -f k8s/22-job-cpu-waiter.yaml
sleep 10
run kubectl -n hw5 get pods -l exp=scheduling -o wide
W=$(pod_of hw5 cpu-waiter)
run kubectl -n hw5 describe pod "$W"
kubectl -n hw5 describe pod "$W" > logs/describe_pod_cpu-waiter_pending.txt
run kubectl describe node hw5-control-plane
kubectl describe node hw5-control-plane > logs/describe_node_cpu_full.txt
stamp "освобождаю процессор: удаляю cpu-low"
run kubectl -n hw5 delete job cpu-low --wait=true
run kubectl -n hw5 wait --for=condition=Ready pod -l job-name=cpu-waiter --timeout=120s || exit 1
run kubectl -n hw5 get pods -l exp=scheduling -o wide
run kubectl -n hw5 get events --field-selector involvedObject.name="$W" --sort-by=.lastTimestamp
kubectl -n hw5 get events --field-selector involvedObject.name="$W" --sort-by=.lastTimestamp > logs/events_cpu-waiter.txt
kubectl -n hw5 delete job cpu-waiter --wait=true

stamp "шаг 4.3: вытеснение низкого приоритета высоким"
run kubectl apply -f k8s/21-job-cpu-low.yaml
run kubectl -n hw5 wait --for=condition=Ready pod -l job-name=cpu-low --timeout=120s || exit 1
L=$(pod_of hw5 cpu-low)
run kubectl -n hw5 get pods -l exp=scheduling -o wide
run kubectl apply -f k8s/23-job-cpu-high.yaml
sleep 15
run kubectl -n hw5 get pods -l exp=scheduling -o wide
run kubectl -n hw5 get events --sort-by=.lastTimestamp
kubectl -n hw5 get events --sort-by=.lastTimestamp > logs/events_preemption.txt
run kubectl -n hw5 get pod "$L" -o jsonpath='{range .status.conditions[*]}{.type}={.status} {.reason} {.message}{"\n"}{end}'
run kubectl -n hw5 describe job cpu-low
kubectl -n hw5 describe job cpu-low > logs/describe_job_cpu-low.txt
kubectl -n hw5 describe job cpu-high > logs/describe_job_cpu-high.txt
run kubectl -n hw5 wait --for=condition=Complete job/cpu-high --timeout=120s || exit 1
sleep 10
stamp "cpu-high закончился, cpu-low снова получает процессор"
run kubectl -n hw5 get pods -l exp=scheduling -o wide
run kubectl -n hw5 get events --sort-by=.lastTimestamp
kubectl -n hw5 get events --sort-by=.lastTimestamp > logs/events_after_high.txt
kubectl -n hw5 delete job cpu-low cpu-high --wait=true
stamp "шаг 4 готов"
