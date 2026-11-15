# generic-app

상태 없는 HTTP 서비스를 위한 범용 Helm 차트. 서비스별 values 파일에는 이미지, probe 경로, 리소스 정도만 쓰고 나머지 운영 기본값은 차트가 맡는다.

```bash
helm upgrade --install whoami charts/generic-app -n apps --create-namespace -f apps/whoami/values-local.yaml
```

리소스 이름은 릴리스 이름을 그대로 쓴다 (`whoami` 로 설치하면 Deployment, Service 모두 `whoami`).

## 주요 값

| 키 | 기본값 | 설명 |
|---|---|---|
| `image.repository` | `""` | 필수. 비어 있으면 렌더링이 실패한다 |
| `image.tag` / `image.digest` | `""` | digest 가 있으면 `repo@sha256:...` 로 고정 |
| `replicaCount` | `2` | `autoscaling.enabled=true` 이면 쓰지 않는다 |
| `containerPort` | `8080` | 포트 이름은 `http` 로 고정. probe 와 Service 가 이름으로 참조 |
| `probes.{startup,readiness,liveness}` | httpGet `/healthz` | 쿠버네티스 Probe 스펙 그대로. `enabled` 만 차트 전용 |
| `shutdown.preStopSleepSeconds` | `15` | 네이티브 `sleep` preStop. 0 이면 넣지 않는다 |
| `shutdown.terminationGracePeriodSeconds` | `45` | preStop 보다 작거나 같으면 렌더링 실패 |
| `resources` | req cpu 100m, mem 128Mi / limit mem 256Mi | CPU limit 은 기본으로 두지 않는다 |
| `autoscaling.*` | 꺼짐 | autoscaling/v2 HPA. 켜면 Deployment 에서 `replicas` 를 빼서 GitOps 도구와 다투지 않게 한다 |
| `autoscaling.behavior` | 늘릴 때 즉시, 줄일 때 300초 안정화 | 트래픽이 출렁일 때 파드 수가 같이 출렁이지 않게 한다 |
| `podDisruptionBudget.*` | maxUnavailable 1 | 최소 replica 가 2 이상일 때만 생성. `unhealthyPodEvictionPolicy: AlwaysAllow` |
| `topologySpread.*` | zone, hostname 모두 ScheduleAnyway | labelSelector 는 차트가 항상 채운다. `matchLabelKeys: [pod-template-hash]` |
| `karpenter.preferSpot.*` | 꺼짐 | `karpenter.sh/capacity-type=spot` 선호(preferred) nodeAffinity 추가 |
| `nodeSelector`, `tolerations`, `affinity` | 비어 있음 | 그대로 전달. preferSpot 은 affinity 의 preferred 목록 뒤에 병합 |
| `serviceAccount.irsaRoleArn` | `""` | 있으면 `eks.amazonaws.com/role-arn` 어노테이션 |
| `serviceAccount.automountToken` | `false` | 쿠버네티스 API 를 쓰는 앱만 켠다 |
| `ingress.*` | 꺼짐 | `className`, `annotations` 를 그대로 전달. ALB 예시는 `ci/full-values.yaml` |
| `otel.*` | 꺼짐 | OTel SDK 표준 환경변수 주입. 인증 헤더는 Secret 에서만 읽는다 |
| `podSecurityContext`, `securityContext` | 비root, 읽기 전용 루트 FS, capability 전부 제거 | `/tmp` 는 emptyDir 로 쓸 수 있다 |

전체 값과 주석은 [values.yaml](values.yaml), 허용 형식은 [values.schema.json](values.schema.json) 에 있다. 오타 난 키(예: `shutdwn`)는 스키마에서 걸린다.

## 설계 메모

**preStop sleep.** 파드가 Terminating 이 되는 것과 Service 엔드포인트, 로드밸런서 타깃에서 빠지는 것은 동시에 일어나지 않는다. 그 사이에 SIGTERM 을 받은 앱이 먼저 연결을 닫으면 요청이 실패한다. 그래서 preStop 에서 잠깐 기다린다. `exec: sleep` 은 이미지에 `sleep` 바이너리가 있어야 하지만, 네이티브 `sleep` 액션은 kubelet 이 처리하므로 distroless 이미지에서도 동작한다 (k8s 1.30 부터 기본 활성).

**topologySpreadConstraints.** `labelSelector` 가 없는 제약은 어떤 파드와도 매칭되지 않아서, 적어 두어도 분산이 일어나지 않는다. 다른 차트에서 복사한 스니펫에서 자주 빠지는 부분이라 차트가 항상 selector 라벨로 채운다. `matchLabelKeys: [pod-template-hash]` 는 롤링 업데이트 중 새 ReplicaSet 의 파드끼리만 skew 를 계산하게 해서, 기존 파드 배치 때문에 새 파드가 한쪽으로 몰리는 것을 막는다.

**zone 은 ScheduleAnyway 가 기본.** `DoNotSchedule` 은 분산은 확실하지만, 특정 zone 에 용량이 없거나 노드에 zone 라벨이 없으면(kind 등) 파드가 Pending 에 머문다. 운영에서 zone 분산을 강제하려면 서비스별로 `DoNotSchedule` 로 바꾼다.

**PDB 는 replica 2 이상에서만.** replica 1 에 `minAvailable: 1` 을 걸면 노드 drain 과 Karpenter consolidation 이 영원히 막힌다. 반대로 PDB 가 없으면 consolidation 때 같은 노드의 파드가 한꺼번에 내려갈 수 있다. `minAvailable` 을 쓰려면 `maxUnavailable: ""` 로 비운다.

**spot 은 선호만 한다.** `required` 로 걸면 spot 용량이 없을 때 파드가 뜨지 않는다. `preferred` 로 두고, 분산 배치와 PDB 로 spot 회수(2분 전 통보) 때의 영향을 줄인다.

**OTel 인증 헤더는 Secret 으로만.** `OTEL_EXPORTER_OTLP_HEADERS` 를 values 에 평문으로 두면 Git 과 렌더링 결과에 남는다. 그래서 values 로는 받지 않고 `otel.headersSecret` 으로 Secret 을 가리키게 했다.

## 렌더링 단계에서 막는 조합

| 조합 | 이유 |
|---|---|
| `image.repository` 비어 있음 | 배포할 이미지가 없다 |
| `terminationGracePeriodSeconds <= preStopSleepSeconds` | 앱이 SIGTERM 을 처리할 시간 없이 SIGKILL 된다 |
| PDB `minAvailable` 과 `maxUnavailable` 동시 지정 | API 가 거부한다 |
| HPA CPU 목표가 있는데 `resources.requests.cpu` 없음 | 사용률을 계산할 수 없다 |
| HPA 의 CPU, 메모리 목표가 모두 0 | 지표 없는 HPA |
| `otel.headersSecret` 의 name, key 중 하나만 지정 | secretKeyRef 가 불완전하다 |

## ALB readiness gate

[docs/alb-readiness-gate.md](../../docs/alb-readiness-gate.md) 참고. 게이트는 LBC 웹훅이 주입하므로 차트 값으로 다루지 않는다.
