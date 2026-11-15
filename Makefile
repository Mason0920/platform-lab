SHELL := /bin/bash
.SHELLFLAGS := -eu -o pipefail -c
.DEFAULT_GOAL := help

CHART        := charts/generic-app
CLUSTER_DIR  := live/dev/cluster
K8S_VERSION  ?= 1.34.0
APP          ?= whoami
NAMESPACE    ?= apps
KUBECONFIG_PATH ?= $(HOME)/.kube/k8s-lab/k8s-lab-dev.yaml
# 스키마를 미리 받아 둔 경우(오프라인):
#   make lint KUBECONFORM_SCHEMA_LOCATION='/path/{{ .NormalizedKubernetesVersion }}-standalone{{ .StrictSuffix }}/{{ .ResourceKind }}{{ .KindSuffix }}.json'
KUBECONFORM_SCHEMA_LOCATION ?=

VALUES_FILES := $(wildcard $(CHART)/ci/*.yaml) $(wildcard apps/*/values-local.yaml)

.PHONY: help
help: ## 타깃 목록
	@grep -E '^[a-zA-Z_-]+:.*?## ' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  %-14s %s\n", $$1, $$2}'

## 클러스터 ---------------------------------------------------------------

.PHONY: cluster-up
cluster-up: ## kind 클러스터 생성 (Terragrunt)
	cd $(CLUSTER_DIR) && terragrunt run -- apply -auto-approve
	@echo "export KUBECONFIG=$(KUBECONFIG_PATH)"

.PHONY: cluster-down
cluster-down: ## kind 클러스터 삭제 (Terragrunt)
	cd $(CLUSTER_DIR) && terragrunt run -- destroy -auto-approve

## 배포 -------------------------------------------------------------------

.PHONY: deploy
deploy: ## 앱 배포. 예: make deploy APP=whoami
	@test -f apps/$(APP)/values-local.yaml || { echo "apps/$(APP)/values-local.yaml 이 없다"; exit 1; }
	KUBECONFIG=$(KUBECONFIG_PATH) helm upgrade --install $(APP) $(CHART) \
		--namespace $(NAMESPACE) --create-namespace \
		-f apps/$(APP)/values-local.yaml \
		--wait --timeout 3m
	KUBECONFIG=$(KUBECONFIG_PATH) helm test $(APP) --namespace $(NAMESPACE)

.PHONY: undeploy
undeploy: ## 앱 삭제. 예: make undeploy APP=whoami
	KUBECONFIG=$(KUBECONFIG_PATH) helm uninstall $(APP) --namespace $(NAMESPACE)

.PHONY: template
template: ## 앱 매니페스트를 렌더링만 해서 출력. 예: make template APP=whoami
	helm template $(APP) $(CHART) --kube-version $(K8S_VERSION) -f apps/$(APP)/values-local.yaml

## 검증 -------------------------------------------------------------------

.PHONY: lint
lint: ## helm lint --strict + 렌더링 결과 kubeconform 검증
	helm lint --strict $(CHART) --kube-version $(K8S_VERSION)
	@for f in $(VALUES_FILES); do \
		echo "==> $$f"; \
		helm lint --strict $(CHART) --kube-version $(K8S_VERSION) -f $$f; \
		helm template ci $(CHART) --kube-version $(K8S_VERSION) -f $$f \
			| kubeconform -strict -summary -kubernetes-version $(K8S_VERSION) \
				$(if $(KUBECONFORM_SCHEMA_LOCATION),-schema-location '$(KUBECONFORM_SCHEMA_LOCATION)') -; \
	done

.PHONY: fmt-check
fmt-check: ## terraform fmt, terragrunt hcl fmt 검사
	terraform fmt -check -recursive
	terragrunt hcl fmt --check

.PHONY: fmt
fmt: ## 포맷 적용
	terraform fmt -recursive
	terragrunt hcl fmt

.PHONY: check
check: lint fmt-check ## CI 와 같은 검사 전체
