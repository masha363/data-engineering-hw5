#!/bin/bash
source "$(dirname "$0")/lib.sh"
stamp "шаг 5.1: квота пространства имён hw5-quota"
kubectl -n hw5-quota delete job big-request skills-parts-quota skills-merge-quota --ignore-not-found --wait=true
kubectl -n hw5-quota delete pod no-resources --ignore-not-found
run cat k8s/30-quota.yaml
run kubectl apply -f k8s/30-quota.yaml
run kubectl -n hw5-quota describe resourcequota hw5-quota

stamp "шаг 5.2: под без заявок и пределов"
run kubectl apply -f k8s/31-pod-no-resources.yaml

stamp "шаг 5.3: задание просит 2 CPU при квоте 1 CPU"
run kubectl apply -f k8s/32-job-big-request.yaml
sleep 8
run kubectl -n hw5-quota get pods
run kubectl -n hw5-quota describe job big-request
kubectl -n hw5-quota describe job big-request > logs/describe_job_big-request.txt
kubectl -n hw5-quota delete job big-request --wait=true

stamp "шаг 5.4: расчёт пар по 4 частям под квотой (4 x 400m > 1 CPU)"
run kubectl apply -f k8s/33-job-parts-quota.yaml
for i in 1 2 3 4 5 6; do
  sleep 3
  echo "--- $(date '+%H:%M:%S')"
  kubectl -n hw5-quota get pods -o wide
  kubectl -n hw5-quota get resourcequota hw5-quota -o jsonpath='{"used: "}{.status.used}{"\n"}'
done
run kubectl -n hw5-quota wait --for=condition=Complete job/skills-parts-quota --timeout=600s || exit 1
save_job hw5-quota skills-parts-quota
run kubectl -n hw5-quota get events --sort-by=.lastTimestamp
kubectl -n hw5-quota get events --sort-by=.lastTimestamp > logs/events_quota.txt
run kubectl -n hw5-quota get pods -l job-name=skills-parts-quota -o custom-columns=POD:.metadata.name,INDEX:.metadata.annotations.batch\\.kubernetes\\.io/job-completion-index,CREATED:.metadata.creationTimestamp,START:.status.startTime
run kubectl apply -f k8s/34-job-merge-quota.yaml
run kubectl -n hw5-quota wait --for=condition=Complete job/skills-merge-quota --timeout=300s || exit 1
save_job hw5-quota skills-merge-quota
run cat logs/job_skills-merge-quota.log
run kubectl -n hw5-quota describe resourcequota hw5-quota
stamp "шаг 5 готов"
