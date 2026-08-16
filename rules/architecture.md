# 아키텍처 규칙

## 신뢰 경계

```
브라우저 / Slack
      │
      ▼
   web ──────────────┐   시크릿 없음. BFF 프록시.
                     │
                     ▼
                   api ─────► PayPal, Slack, Gemini(파싱)
                     │        Firestore, GCS
                     │
              Cloud Tasks
                     │
                     ▼
                  agent        ADK + Vertex AI
                                PayPal 접근 불가
```

## 서비스별 책임

### `web`
- 관리자 대시보드 화면, 승인 카드 UI.
- 서버 액션/route handler는 `api`로 넘기는 얇은 프록시만 담당한다.
- 비즈니스 로직을 두지 않는다. 금액 계산, 상태 전이, 이상 탐지 전부 `api` 소관.
- 어떤 시크릿도 갖지 않는다. `NEXT_PUBLIC_` 접두사가 붙은 값에 민감 정보 금지.

### `api`
- 유일하게 PayPal을 호출하는 서비스.
- Slack webhook 수신 및 서명 검증.
- 승인 토큰 발급/검증.
- 영수증 이미지 → 구조화 JSON (Gemini structured output 단발 호출, ADK 아님).
- 결정론적 매칭(금액 · 날짜 윈도우 · 가맹점명).
- Firestore 쓰기의 단일 창구.

### `agent`
- ADK 에이전트 하나. 툴 대여섯 개.
- 매칭이 실패한 애매한 건 판단, 이상 징후 설명, 재요청 문안 작성.
- 출력은 항상 draft 문서다. 실행 권한이 없다.
- Firestore는 `api`가 제공하는 툴을 통해서만 접근한다. SDK 직접 쓰기 금지.

## 호출 방향

**단방향이다.** `web → api → agent`. 역방향 동기 호출 금지.

`agent`가 결과를 돌려주는 경로는 Firestore 쓰기 + Cloud Tasks 콜백이다.
`agent`가 `web`이나 사용자에게 직접 말을 걸지 않는다. Slack 메시지 발송도
`api`가 한다.

이유: `agent` 출력이 외부로 나가는 경로가 하나뿐이어야 검열 지점을 한 곳에
둘 수 있다. 프롬프트 인젝션된 영수증이 Slack DM으로 새어나가는 걸 막는 게 이 규칙이다.

## 비동기

3초 넘게 걸리는 일은 전부 Cloud Tasks로 넘긴다. Slack webhook은 3초 안에 200을
돌려줘야 한다.

```
webhook → 서명검증 → Firestore raw 저장 → enqueue → 200   (목표 0.5s 이내)
```

지연 실행(재촉 루프)도 Pub/Sub이 아니라 Cloud Tasks `schedule_time`을 쓴다.

## 상태는 Firestore에 둔다

에이전트 세션을 재워서 사람을 기다리지 않는다. 대기 상태는 전부 Firestore
상태 머신이다.

```
claim_request.status: PENDING → REMINDED → RESPONDED | EXPIRED
```

예약된 태스크는 깨어나서 현재 status를 읽고 분기한다. 중복 실행돼도 안전해야 한다.

ADK 세션은 `InMemorySessionService`. 재시작 후 살아남을 필요가 없다.

## 하지 말 것

- `api`와 `agent`를 한 서비스로 합치기 — 신뢰 경계가 사라진다.
- `web`에서 Firestore 직접 읽기 — 규칙 관리 지점이 늘어난다.
- 멀티 에이전트 — 4분 데모에서 화면에 드러나지 않는다.
- Cloud SQL, GKE, VPC 커넥터 — 설정에 반나절 날아간다.
