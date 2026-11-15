# platform-lab

Local Kubernetes lab (kind + Terragrunt) and a reusable Helm chart for stateless HTTP services, validated in CI.

EKS 를 운영하면서 서비스마다 반복해서 설정하던 배포 패턴을 개인 시간에 처음부터 다시 정리한 저장소다. 로컬 kind 클러스터에서 직접 띄워 보고, CI 에서 렌더링 결과를 검증한다.

## 저장소 역할

| 저장소 | 담는 것 |
|---|---|
| [k8s-lab](https://github.com/Mason0920/k8s-lab) | Terragrunt, Istio 실습을 진행하는 작업 저장소. 진행 중인 코드가 그대로 올라간다 |
| platform-lab (이 저장소) | 블로그 글이 공개된 뒤, 그 글에서 다룬 결과물(모듈, 차트, 가이드)만 정리해서 옮긴다. CI 로 검증된 상태만 유지한다 |

지금 들어 있는 Terragrunt 구성은 1주차 실습 결과다. 이후 단계는 블로그 글이 공개되는 순서대로 추가한다.

## 문제

서비스를 Kubernetes 에 올릴 때마다 같은 질문이 나온다.

- 배포할 때 잠깐씩 5xx 가 나는 이유는 무엇인가 (readiness 판단 시점, 종료 순서)
- 노드 정리나 spot 회수 때 한 노드에 몰린 파드가 같이 내려가지 않게 하려면 (분산 배치, PDB)
- HPA 가 트래픽이 출렁일 때마다 파드 수까지 출렁이게 하지 않으려면 (scale 정책)
- 서비스마다 YAML 을 복사해 쓰면 설정이 조금씩 달라지고, 복사한 설정이 실제로는 동작하지 않기도 한다. `labelSelector` 가 빠진 topologySpreadConstraints 는 적혀 있어도 아무것도 분산하지 않는다.

이 답을 서비스마다 따로 기억하는 대신 차트의 기본값으로 넣어 두면, 서비스 쪽은 이미지와 probe 경로만 신경 쓰면 된다.

## 접근

1. **기본값이 안전한 차트.** 값을 하나도 바꾸지 않아도 preStop 대기, PDB, zone/노드 분산, 비root 실행이 들어간다.
2. **잘못된 조합은 렌더링 단계에서 실패.** `values.schema.json` 과 템플릿 검사로 클러스터에 올리기 전에 막는다. 예: 종료 유예 시간이 preStop 보다 짧으면 실패한다.
3. **로컬에서도 같은 차트.** kind 클러스터를 Terragrunt 로 만들고, 운영과 같은 차트로 예제 앱을 띄운다.
4. **CI 에서 검증.** `helm lint --strict`, kubeconform (Kubernetes 1.34 스키마), `terraform fmt`, `terragrunt hcl fmt`.

## 구조

```
platform-lab/
├── Makefile                       # cluster-up/down, deploy, lint, fmt-check
├── root.hcl                       # Terragrunt 공통 설정: backend, provider 생성, 공통 inputs
├── modules/
│   └── kind-cluster/              # Terraform 모듈: kind 클러스터 1개
├── live/
│   └── dev/
│       ├── env.hcl                # dev 환경 값 (클러스터 이름, 노드 이미지, 워커 수)
│       └── cluster/terragrunt.hcl # unit: root.hcl include + 모듈 source
├── charts/
│   └── generic-app/               # 범용 Helm 차트
│       ├── values.yaml
│       ├── values.schema.json
│       ├── templates/
│       └── ci/                    # CI 에서 렌더링, 검증하는 values 조합
├── apps/
│   └── whoami/values-local.yaml   # 로컬 예제 앱
├── docs/
│   ├── week1-terragrunt.md        # 1주차 실습 가이드
│   ├── alb-readiness-gate.md      # ALB readiness gate 와 종료 설정
│   └── notes/week1.md             # 실습 기록 템플릿
└── .github/workflows/ci.yml
```

## 빠른 시작

준비물: Docker 런타임(OrbStack, colima, Docker Desktop 중 하나), kind, kubectl, helm, Terraform, Terragrunt. 버전은 [.tool-versions](.tool-versions) 참고.

```bash
make cluster-up                                  # kind 클러스터 생성 (control-plane 1, worker 1)
export KUBECONFIG=~/.kube/k8s-lab/k8s-lab-dev.yaml
kubectl get nodes

make deploy APP=whoami                           # helm upgrade --install + helm test
kubectl -n apps port-forward svc/whoami 8080:80
curl -s http://127.0.0.1:8080/

make cluster-down
```

kubeconfig 는 `~/.kube/k8s-lab/` 아래에 따로 만들어서 기본 `~/.kube/config` 를 건드리지 않는다.

새 앱을 올리려면 `apps/<이름>/values-local.yaml` 을 만들고 `make deploy APP=<이름>` 을 실행한다. 렌더링 결과만 보려면 `make template APP=<이름>`.

Terragrunt 가 하는 일을 단계별로 확인하는 실습은 [docs/week1-terragrunt.md](docs/week1-terragrunt.md) 에 있다.

## 차트 기능

| 기능 | 왜 필요한가 |
|---|---|
| startup / readiness / liveness probe 분리 | 기동이 느린 앱이 liveness 에 걸려 재시작되지 않게 하고, 트래픽은 readiness 기준으로만 받는다 |
| 네이티브 preStop `sleep` + terminationGracePeriodSeconds | 엔드포인트와 로드밸런서 타깃에서 빠지는 동안 들어오는 요청을 받는다. 쉘 없는 이미지에서도 동작 |
| 유예 시간 검사 | 유예 시간이 preStop 보다 짧으면 앱이 종료 처리 없이 강제 종료되므로 렌더링 단계에서 막는다 |
| HPA (autoscaling/v2) + behavior | 늘릴 때는 빠르게, 줄일 때는 5분 지켜본 뒤 천천히. 켜면 Deployment 에서 replicas 를 빼서 GitOps 도구와 다투지 않는다 |
| PDB (replica 2 이상일 때만) | drain, consolidation 때 한 번에 내려가는 파드 수를 제한한다. replica 1 에서는 drain 을 막지 않도록 만들지 않는다 |
| topologySpreadConstraints (zone + hostname) | 항상 `labelSelector` 를 채우고 `matchLabelKeys: [pod-template-hash]` 로 롤링 중에도 새 파드끼리 분산한다 |
| Karpenter spot 선호 | `karpenter.sh/capacity-type=spot` 을 preferred 로만 건다. spot 이 없으면 on-demand 에 뜬다 |
| nodeSelector / tolerations / affinity 전달 | 서비스별 배치 조건은 그대로 받고, spot 선호는 기존 affinity 와 병합한다 |
| ServiceAccount + IRSA 어노테이션 | 정적 액세스 키 대신 파드 단위 IAM 역할을 쓴다. API 를 안 쓰는 앱은 토큰을 마운트하지 않는다 |
| Service / Ingress (className, annotations) | ALB 등 컨트롤러별 설정은 어노테이션으로 그대로 전달한다 |
| OpenTelemetry 환경변수 | 서비스 이름, 수집기 주소, 샘플링, 파드/네임스페이스/노드 resource attribute 를 표준 env 로 넣는다. 인증 헤더는 Secret 에서만 읽는다 |
| 보안 기본값 | 비root, 읽기 전용 루트 FS, capability 전부 제거, seccomp RuntimeDefault. `/tmp` 는 emptyDir |
| values.schema.json | 오타 난 키나 잘못된 enum 을 렌더링 전에 잡는다 |

값 목록과 설계 메모는 [charts/generic-app/README.md](charts/generic-app/README.md), ALB readiness gate 는 [docs/alb-readiness-gate.md](docs/alb-readiness-gate.md) 에 정리했다.

## 검증 방법

CI 와 같은 검사를 로컬에서 그대로 돌린다.

```bash
make lint        # helm lint --strict + ci/*.yaml, apps/*/values-local.yaml 렌더링 후 kubeconform -strict
make fmt-check   # terraform fmt -check -recursive, terragrunt hcl fmt --check
make check       # 둘 다
```

`make lint` 는 values 파일마다 아래를 실행한다.

```bash
helm lint --strict charts/generic-app --kube-version 1.34.0 -f <values>
helm template ci charts/generic-app --kube-version 1.34.0 -f <values> \
  | kubeconform -strict -summary -kubernetes-version 1.34.0 -
```

`ci/` 의 values 조합:

| 파일 | 확인하는 것 |
|---|---|
| `default-values.yaml` | 필수값(image)만 넣었을 때 기본값 렌더링 |
| `full-values.yaml` | HPA, PDB(%), zone DoNotSchedule, spot 선호 + affinity 병합, IRSA, ALB Ingress, OTel 전부 켬 |
| `minimal-values.yaml` | replica 1 (PDB 미생성), probe 일부 끔, preStop 없음, digest 고정 |

실패해야 하는 경우도 직접 확인할 수 있다.

```bash
helm template t charts/generic-app --set image.repository=x \
  --set shutdown.preStopSleepSeconds=30 --set shutdown.terminationGracePeriodSeconds=30
# Error: ... terminationGracePeriodSeconds(30) 는 preStopSleepSeconds(30) 보다 커야 한다 ...
```

## 블로그

과정과 에러 기록은 블로그에 정리한다: https://thereisnotherway.tistory.com/

- [Karpenter 1.8.1 버전 업그레이드하기 (w. Terraform)](https://thereisnotherway.tistory.com/113)
- [Karpenter 1.0.1 -> 1.8.1 CRD 업그레이드 이슈](https://thereisnotherway.tistory.com/114)
- [readiness probe 로 파드 health check 하기](https://thereisnotherway.tistory.com/72)

Terragrunt + kind 실습 연재는 글이 공개되는 대로 여기에 추가한다.

## 라이선스

[MIT](LICENSE)
