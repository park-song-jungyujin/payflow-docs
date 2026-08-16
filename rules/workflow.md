# 작업 흐름

## 브랜치

해커톤 기간에는 `main` 직접 푸시를 허용한다. PR 리뷰를 기다릴 시간이 없다.

예외 — 아래는 반드시 브랜치를 파고 다른 사람이 한 번 본다.

- 송금 실행 경로 (`api`의 payout 관련 전부)
- 승인 토큰 발급/검증
- 상태 전이 CAS 로직

돈이 나가는 코드만 게이트를 건다.

## 커밋 메시지

```
<type>: <요약>

type: feat | fix | schema | infra | docs | chore
```

`schema:`는 특별 취급이다. 다른 레포가 따라와야 한다는 신호이므로,
커밋 본문에 영향받는 레포를 적는다.

```
schema: settlement item에 currency 필드 추가

affects: web(타입 재생성), agent(핀 갱신 → v0.4.2)
```

## 크로스레포 변경 순서

```
api → agent → web
```

스키마 규칙과 동일하다. 역순 금지. 자세한 내용은 `schema-contract.md`.

## 환경변수

각 레포 루트에 `.env.example`을 두고 실제 값과 동기화한다. 새 변수를 추가하면
`.env.example`에도 같은 커밋에서 추가한다.

시크릿은 Secret Manager. `.env`는 커밋하지 않는다.
`agent` 레포의 `.env.example`에 PayPal 관련 키가 등장하면 잘못된 것이다.

## 데모용 스위치

시간 압축을 위한 별도 가짜 시계 추상화를 만들지 않는다. 환경변수 하나로 끝낸다.

```
REMINDER_DELAY_SECONDS=20      # 데모
REMINDER_DELAY_SECONDS=86400   # 실제
```

Cloud Tasks `schedule_time`에 그대로 들어간다. 동일 코드가 실제 값으로 GCP에서
돈 로그를 따로 확보해둔다.

## 배포

Terraform은 `infra` 디렉터리를 `api` 레포에 둔다. 별도 레포로 빼지 않는다.
Cloud Run 서비스 3개, Firestore, Cloud Tasks 큐, Secret Manager, IAM 바인딩.

**IAM 바인딩이 이 프로젝트의 발표 자료다.** `agent` 서비스 계정에 PayPal
시크릿 접근 권한이 없다는 걸 Terraform 코드로 보여줄 수 있어야 한다.
주석을 달아둔다.

## 검증 순서

기능을 쌓는 순서가 아니라 리스크가 큰 순서로 뚫는다.

```
1. PayPal 샌드박스 payout 성공 + 동일 sender_batch_id 재시도 무해
2. 승인 토큰 없이 /payouts 호출 → 403        (데모 5초 장면)
3. Slack 서명검증 → enqueue → 3s 내 ack
4. 영수증 이미지 → 구조화 JSON → Firestore
5. 결정론적 매칭 + LLM 이상탐지 → draft
6. 재촉 루프 E2E (delay=20)
7. Cloud Run 배포 + IAM 분리 콘솔 확인
```

1번과 2번을 첫날에 끝낸다. 1번은 유일한 외부 의존성이고, 2번은 구현 30분에
발표 임팩트가 가장 크다.
