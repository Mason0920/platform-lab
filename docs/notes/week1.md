# 1주차 실습 기록 (블로그 1번 글 재료)

> 실습하면서 채우는 기록 템플릿. 블로그 글의 재료가 된다. 짧게 메모해도 된다.

## 환경
- Mac 칩 / macOS 버전:
- 컨테이너 런타임 (OrbStack / colima / Docker Desktop) + 버전:
- `kind version`:
- `terragrunt --version`:
- `terraform version`:

## 왜 Terragrunt 가 궁금했나 (내 말로 1~3줄)
- 기존 Terraform 저장소에서 불편했던 점:

## 1. Terragrunt 없이 실행해 본 결과
- stg 를 추가하려면 복사·수정해야 했던 것:

## 2. Terragrunt apply
- apply 소요 시간:
- .terragrunt-cache 안에서 본 것 (backend.tf / provider.tf 내용):
- .state 폴더 구조:
- render 로 본 inputs:

## 3. 클러스터 확인
- `kubectl get nodes -o wide` 결과 (붙여넣기):

## 4. worker_count 바꿔 본 결과
- plan 결과 (update / replace):
- 내가 이해한 이유:

## 에러와 해결 (가장 중요)
| # | 단계 | 에러 메시지 원문 | 원인 | 해결 방법 |
|---|---|---|---|---|
| 1 | | | | |

## 느낀 점 / 운영 환경에 적용한다면
- 

## 스크린샷 (선택)
- 터미널 캡처 파일명:
