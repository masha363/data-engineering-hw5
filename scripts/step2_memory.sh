#!/bin/bash
source "$(dirname "$0")/lib.sh"
stamp "шаг 2.1: задание с пределом памяти 64Mi"
kubectl -n hw5 delete job skills-oom skills-measure skills-fit --ignore-not-found
run cat k8s/01-job-oom.yaml
run kubectl apply -f k8s/01-job-oom.yaml
run kubectl -n hw5 wait --for=condition=Failed job/skills-oom --timeout=180s || exit 1
POD=$(pod_of hw5 skills-oom)
run kubectl -n hw5 get pod "$POD" -o jsonpath='{"reason: "}{.status.containerStatuses[0].state.terminated.reason}{"  exitCode: "}{.status.containerStatuses[0].state.terminated.exitCode}{"\n"}'
run kubectl -n hw5 describe pod "$POD"
run kubectl -n hw5 get events --field-selector involvedObject.name=skills-oom
save_job hw5 skills-oom
kubectl -n hw5 describe pod "$POD" > logs/describe_pod_skills-oom.txt

stamp "шаг 2.2: замер пика памяти с пределом 1Gi"
run kubectl apply -f k8s/02-job-measure.yaml
run kubectl -n hw5 wait --for=condition=Complete job/skills-measure --timeout=300s || exit 1
save_job hw5 skills-measure
run cat logs/job_skills-measure.log
PEAK=$(grep -o 'PEAK_RSS_MB=[0-9.]*' logs/job_skills-measure.log | cut -d= -f2)
REQ=$(awk -v p="$PEAK" 'BEGIN{print int((p+15)/16)*16}')
LIM=$(awk -v p="$PEAK" 'BEGIN{print int((p*1.25+15)/16)*16}')
echo
echo "измеренный пик RSS: $PEAK МБ -> requests.memory=${REQ}Mi (пик, округлён вверх до 16Mi), limits.memory=${LIM}Mi (пик x 1.25)"
echo "peak_rss_mb=$PEAK request_mi=$REQ limit_mi=$LIM" > results/memory_fit.txt

stamp "шаг 2.3: задание с подобранным пределом"
sed -e "s/@REQ@/${REQ}Mi/" -e "s/@LIM@/${LIM}Mi/" k8s/03-job-fit.yaml.in > k8s/03-job-fit.yaml
run cat k8s/03-job-fit.yaml
run kubectl apply -f k8s/03-job-fit.yaml
run kubectl -n hw5 wait --for=condition=Complete job/skills-fit --timeout=300s || exit 1
save_job hw5 skills-fit
run cat logs/job_skills-fit.log
run kubectl -n hw5 get jobs
run kubectl -n hw5 get pods -o wide
stamp "шаг 2 готов"
