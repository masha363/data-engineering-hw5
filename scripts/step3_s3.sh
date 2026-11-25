#!/bin/bash
source "$(dirname "$0")/lib.sh"
stamp "шаг 3.1: RustFS внутри кластера"
IMG=$(docker images --format '{{.Repository}}:{{.Tag}}' | grep -m1 '^rustfs/rustfs:' || true)
[ -z "$IMG" ] && IMG=rustfs/rustfs:latest
echo "образ RustFS: $IMG (узел kind скачивает его сам)"
sed "s#@RUSTFS_IMAGE@#$IMG#" k8s/10-rustfs.yaml > k8s/10-rustfs.applied.yaml
kubectl -n hw5 delete job s3-upload skills-parts skills-merge --ignore-not-found --wait=true
run kubectl apply -f k8s/10-rustfs.applied.yaml
kubectl -n hw5 delete pod rustfs-0 --ignore-not-found --wait=true
if ! run kubectl -n hw5 rollout status statefulset/rustfs --timeout=300s; then
  kubectl -n hw5 logs rustfs-0 > logs/pod_rustfs-0.log 2>&1
  tail -n 20 logs/pod_rustfs-0.log
  echo "RustFS не поднялся, дальше не иду"
  exit 1
fi
run kubectl -n hw5 get statefulset,pods,svc,pvc -o wide
sleep 5
kubectl -n hw5 logs rustfs-0 > logs/pod_rustfs-0.log 2>&1
run tail -n 30 logs/pod_rustfs-0.log

stamp "шаг 3.2: загрузка данных в s3://hh-lake/raw/hh_analysts_2024.csv"
kubectl -n hw5 delete job s3-upload skills-parts skills-merge --ignore-not-found
run kubectl apply -f k8s/11-job-upload.yaml
run kubectl -n hw5 wait --for=condition=Complete job/s3-upload --timeout=300s || exit 1
save_job hw5 s3-upload
run cat logs/job_s3-upload.log

stamp "шаг 3.3: параллельный расчёт по 4 частям объекта (Indexed Job)"
run kubectl apply -f k8s/12-job-parts.yaml
sleep 3
run kubectl -n hw5 get pods -l job-name=skills-parts -o wide
run kubectl -n hw5 wait --for=condition=Complete job/skills-parts --timeout=600s || exit 1
save_job hw5 skills-parts
run kubectl -n hw5 get pods -l job-name=skills-parts -o custom-columns=POD:.metadata.name,INDEX:.metadata.annotations.batch\\.kubernetes\\.io/job-completion-index,START:.status.startTime,PHASE:.status.phase
run cat logs/job_skills-parts.log

stamp "шаг 3.4: слияние частей и сверка с ДЗ 3"
run kubectl apply -f k8s/13-job-merge.yaml
run kubectl -n hw5 wait --for=condition=Complete job/skills-merge --timeout=300s || exit 1
save_job hw5 skills-merge
run cat logs/job_skills-merge.log
cp logs/job_skills-merge.log results/top10_k8s.txt
run kubectl -n hw5 get jobs
stamp "шаг 3 готов"
