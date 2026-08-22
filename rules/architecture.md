# 아키텍처 규칙

## 신뢰 경계

```
브라우저 / Slack
      │
      ▼
   web ──────────────┐   시크릿 없음. BFF 프록시.
                     │
                     ▼
                   api ─────► PayPal, Slack, Gemini(파싱·검증)
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
- 관리자 대시보드 화면, 승인 카드 UI, 집행자 Google 로그인.
- 서버 액션/route handler는 `api`로 넘기는 얇은 프록시만 담당한다.
- 비즈니스 로직을 두지 않는다. 금액 계산, 상태 전이, 이상 탐지 전부 `api` 소관.
- 어떤 시크릿도 갖지 않는다. `NEXT_PUBLIC_` 접두사가 붙은 값에 민감 정보 금지.
  Google OAuth **client ID**는 공개 값이라 예외지만, client **secret**은 절대
  두지 않는다 — 토큰 교환은 `api`가 대신한다(§"org 스코핑과 로그인" 참조).

### `api`
- 유일하게 PayPal을 호출하는 서비스.
- Slack webhook 수신 및 서명 검증.
- Google OAuth 토큰 교환, 세션 발급/검증.
- 승인 토큰 발급/검증.
- 영수증 이미지 → 구조화 JSON (Gemini structured output 단발 호출, ADK 아님).
- 영수증 이미지 ↔ 파싱 결과 검증. **정산 실행 시점**, 파싱과 별개인 Gemini 단발
  호출로 후보 receipt마다 재확인한다. 통과한 것만 정산 후보에 들어간다. 청구자
  에이전트의 인입 시점 검토와는 다른, 더 늦은 시점의 별도 게이트다. 상세는
  `docs/rules/schema-contract.md` "검증" 절.
- 결정론적 매칭(금액 · 날짜 윈도우 · 가맹점명).
- Firestore 쓰기의 단일 창구.

### `agent`
- ADK 에이전트 셋. 각 툴 2~4개.
  - **청구자** — 파싱 결과 검토, 업무용·개인용 분류, 재요청 문안 작성
  - **집행자** — 매칭 실패 건 판단, 이상 징후 설명, 자연어 요청 → 정산 필터 변환
  - **안전 확인** — 승인 직전 리스크 리포트. **조언자이지 게이트가 아니다**
- 출력은 항상 draft 문서다. 실행 권한이 없다.
- Firestore는 `api`가 제공하는 툴을 통해서만 접근한다. SDK 직접 쓰기 금지.
  **예외 하나 — `agent_sessions` 컬렉션.** 청구자·집행자 두 에이전트는 세션(대화)
  이어가기를 위해 이 컬렉션 하나에 한해 `agent/shared/memory.py`로 직접 읽고 쓴다.
  안전 확인 에이전트는 대상이 아니다(1회성 호출이라 이어갈 세션이 없다). IAM은
  컬렉션 단위로 못 좁히므로 이 경계는 코드 컨벤션으로만 지켜진다 — 상세와 근거는
  `schema-contract.md` §2 `agent_sessions` "IAM 한계" 참조.

셋 다 `api`가 파이프라인 단계마다 Cloud Tasks로 호출한다. 서로를 부르지 않는다.

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

**예외 하나 — `POST /settlements/runs`의 이미지 검증 호출.** 이 라우트는 webhook이
아니라 사람이 버튼을 눌러 트리거하는 동기 액션이라 300초 Cloud Run 타임아웃 안에서
인라인으로 돈다. 근거와 상세는 `docs/rules/schema-contract.md` "검증" 절 참조.

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

## org 스코핑과 로그인

여러 기관이 격리된 상태로 같은 배포를 쓴다. `org_id`는 두 경로로만 결정된다 —
그 외 경로(요청 바디, 쿼리 파라미터)로 들어온 org_id는 신뢰하지 않는다.

- **집행자(웹) 쪽**: Google 로그인 세션에서 나온다. `web`은 Google에서 받은
  authorization code를 `api`의 `POST /auth/google/callback`으로 그대로 넘기고,
  `api`가 코드 교환·세션 발급까지 전부 한다(`GOOGLE_CLIENT_SECRET`은 `api`만
  가진다). `web`은 발급된 세션 토큰을 httpOnly 쿠키로 저장할 뿐, 그 안의 org_id를
  직접 읽거나 조작하지 않는다.
- **청구자(Slack) 쪽**: 들어온 이벤트의 `team_id`에서 나온다. Slack signing
  secret은 워크스페이스가 아니라 **앱 하나**에 붙으므로(distributed OAuth app
  모델) 서명 검증 자체는 지금과 똑같이 전역 시크릿 하나로 한다. 서명을 통과한
  뒤 `team_id`로 `slack_workspaces`를 조회해 `org_id`와 그 워크스페이스의
  bot token을 얻는다. 등록되지 않은 `team_id`는 401.
- 모든 Firestore 쿼리 필터링은 **`api` 계층에서 끝난다.** `agent`와 `web`은
  org_id로 직접 쿼리를 만들지 않는다 — `agent`는 `api` 툴 호출 결과가 이미
  스코핑돼 있고, `web`은 Firestore를 아예 안 만진다.
- Slack "설치"는 새 워크스페이스를 만드는 게 아니라 **기관이 가진 기존
  워크스페이스**에 OAuth로 앱을 추가하는 것이다. Slack에는 서드파티가 워크스페이스
  자체를 생성하는 API가 없다.

## 하지 말 것

- `api`와 `agent`를 한 서비스로 합치기 — 신뢰 경계가 사라진다.
- `web`에서 Firestore 직접 읽기 — 규칙 관리 지점이 늘어난다.
- `agent`가 `agent_sessions` 외 다른 컬렉션에 직접 쓰기 — 예외는 저 하나뿐이다.
- **에이전트끼리 직접 호출하기** — 호출은 전부 `api`가 한다. 에이전트 간 프로토콜을
  만들면 통합 비용이 감당이 안 되고, 검열 지점이 여러 곳으로 흩어진다.
- 에이전트를 넷 이상으로 늘리기 — 셋이 트랙 경계와 1:1이다. 더 쪼갤 이유가 없다.
- Cloud SQL, GKE, VPC 커넥터 — 설정에 반나절 날아간다.
