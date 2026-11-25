#!/bin/bash
source "$(dirname "$0")/lib.sh"
stamp "шаг 1: кластер kind и образ"
run docker --version
run docker info --format 'CPUs={{.NCPU}} MemTotal={{.MemTotal}} Kernel={{.KernelVersion}} Cgroup={{.CgroupVersion}}'
run kind version
run kubectl version --client
if ! kind get clusters | grep -qx hw5; then
  run kind create cluster --config kind-config.yaml --wait 120s
fi
run kubectl cluster-info --context kind-hw5
run kubectl config use-context kind-hw5
run kubectl get nodes -o wide
run kubectl get node hw5-control-plane -o jsonpath='{"allocatable: "}{.status.allocatable}{"\n"}'
run docker build --provenance=false --sbom=false -t skills:1.0 app
run docker images skills:1.0
if ! run kind load docker-image skills:1.0 --name hw5; then
  echo "kind load не сработал, импортирую образ в узел через ctr"
  docker save skills:1.0 | docker exec -i hw5-control-plane ctr -n k8s.io images import --all-platforms -
fi
run docker exec hw5-control-plane crictl images
run kubectl apply -f k8s/00-namespace.yaml
run docker exec hw5-control-plane ls -la /hostdata
run docker images --format '{{.Repository}}:{{.Tag}} {{.Size}}'
stamp "шаг 1 готов"
