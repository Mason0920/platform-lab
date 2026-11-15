# ALB Pod Readiness Gate

이 차트는 readiness gate 를 직접 넣지 않는다. 게이트는 AWS Load Balancer Controller(LBC)의 웹훅이 파드 생성 시점에 주입하고, 차트가 할 일은 그 조건이 잘 맞물리도록 Ingress 와 종료 설정을 갖추는 것뿐이다.

## 왜 필요한가

파드의 readinessProbe 가 통과해도 ALB 타깃 그룹에서는 아직 `initial` 상태일 수 있다. 롤링 업데이트가 빠르면 새 파드가 ALB 에서 healthy 가 되기 전에 기존 파드가 내려가서, 짧은 순간 정상 타깃이 부족해진다.

readiness gate 를 켜면 LBC 가 타깃이 ALB 에서 healthy 가 될 때까지 파드의 Ready 조건을 막는다. Deployment 는 이 Ready 를 기준으로 다음 파드를 교체하므로, ALB 기준으로 준비된 만큼만 롤링이 진행된다.

## 켜는 방법

1. 네임스페이스에 라벨을 단다.

   ```bash
   kubectl label namespace apps elbv2.k8s.aws/pod-readiness-gate-inject=enabled
   ```

2. Ingress 의 target-type 을 `ip` 로 둔다. `instance` 모드에서는 파드가 아니라 노드가 타깃이라 게이트가 의미 없다.

   ```yaml
   ingress:
     enabled: true
     className: alb
     annotations:
       alb.ingress.kubernetes.io/scheme: internet-facing
       alb.ingress.kubernetes.io/target-type: ip
       alb.ingress.kubernetes.io/healthcheck-path: /health
       alb.ingress.kubernetes.io/target-group-attributes: deregistration_delay.timeout_seconds=30
   ```

3. 파드를 다시 만든다. 게이트는 파드 생성 시점에만 주입되므로 라벨을 단 뒤 `kubectl rollout restart` 가 필요하다.

4. 확인한다.

   ```bash
   kubectl -n apps get pod <파드> -o jsonpath='{.spec.readinessGates}'
   kubectl -n apps get pod -o wide   # READINESS GATES 열이 1/1 이 되어야 Ready
   ```

## 종료 쪽과 함께 봐야 하는 값

게이트는 "새 파드가 언제 트래픽을 받기 시작하나"를 다룬다. "기존 파드가 언제 트래픽을 그만 받나"는 종료 설정이 다룬다.

| 값 | 위치 | 역할 |
|---|---|---|
| `shutdown.preStopSleepSeconds` | 차트 | 파드가 Terminating 이 된 뒤 엔드포인트와 타깃에서 빠지는 동안 요청을 계속 받는다 |
| `deregistration_delay.timeout_seconds` | Ingress 어노테이션 | ALB 가 타깃을 draining 상태로 두는 시간. 기본 300초 |
| `shutdown.terminationGracePeriodSeconds` | 차트 | preStop + 앱 종료 시간보다 커야 한다. 차트가 렌더링 단계에서 검사한다 |

## 알려진 문제: LBC 3.4.0 ~ 3.4.2

LBC 3.4.0, 3.4.1, 3.4.2 에는 파드의 readiness gate 조건 타입이 `/<TargetGroupBinding 이름>` 없이 정확히 `target-health.elbv2.k8s.aws` 인 경우 컨트롤러가 panic 하는 문제가 있다 (GHSA-8hm3-878p-6823). 웹훅이 넣는 정상적인 게이트에는 이름이 붙어 있지만, 파드를 만들 수 있는 사용자가 이 값을 직접 넣으면 컨트롤러 전체의 조정이 멈출 수 있다. v3.4.3 에서 고쳐졌다.

- 권고문: https://github.com/kubernetes-sigs/aws-load-balancer-controller/security/advisories/GHSA-8hm3-878p-6823
- 게이트 공식 문서: https://kubernetes-sigs.github.io/aws-load-balancer-controller/latest/deploy/pod_readiness_gate/

이 차트는 readinessGates 필드를 values 로 열어 두지 않는다. 게이트는 웹훅에 맡긴다.
