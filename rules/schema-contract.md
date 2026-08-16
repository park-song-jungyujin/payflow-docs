# 스키마 계약

PayFlow 세 레포(`payflow-backend` · `payflow-agent` · `payflow-frontend`)가 공유하는
데이터 계약이다. 컬렉션 구조, ID 체계, 금액·환율 표현, 상태 전이, API 라우트, 에이전트
입출력, 환경변수, 테스트 fixture를 정의한다.

**이 문서가 단일 소스다.** 여기 정의된 필드명·상태값·형식과 다르게 구현하면 통합 시점에
조용히 실패한다. 변경이 필요하면 코드를 먼저 고치지 말고 이 문서를 고친 뒤
`schema:` 커밋 + 태그 + 전원 통보 순서를 지킨다.

---

## 0. 시스템 개요

### 서비스 3개

| 서비스 | 레포 | 공개 여부 | 역할 |
|---|---|---|---|
| `web` | `payflow-frontend` | 공개 | 집행자 대시보드 |
| `api` | `payflow-backend` | 공개 | 오케스트레이션, **실행 권한 독점** |
| `agent` | `payflow-agent` | **비공개** | 에이전트 3개. Cloud Tasks OIDC로만 호출 |

호출 방향은 `web → api → agent` 단방향이다. 역방향과 우회 경로는 없다.

### 절대 규칙

1. **에이전트는 게이트가 아니다.** 한도 초과 차단, 토큰 검증, CAS 전이, 중복 실행 차단은
   전부 `api/src/guards/`의 코드가 한다. 에이전트는 리스크를 *서술*만 한다. 에이전트 출력이
   비어 있거나 틀려도 코드 게이트는 독립적으로 동작해야 한다.
2. **에이전트끼리 직접 호출하지 않는다.** 셋 다 `api`가 Cloud Tasks로 부르고, 결과는
   `agent_drafts` 컬렉션으로만 돌려준다. 에이전트 간 프로토콜은 존재하지 않는다.
3. **돈이 나가는 경로에 LLM 판단이 개입하지 않는다.** 금액 합산, 인당 분배, 매칭,
   환율 적용은 전부 결정론적 코드다.

### 트랙과 디렉터리 소유권

| 트랙 | 범위 |
|---|---|
| **A** | 청구자 경험 — Slack 인입, 파싱, 청구 항목 확정, 재촉 루프 |
| **B** | 집행자 경험 — 매칭, 정산 배치, 대시보드, 승인 카드 |
| **C** | 돈과 안전 — 토큰, 게이트, 송금, 인프라 |

| 경로 | 소유 |
|---|---|
| `api/src/schemas/` | **공유** — 변경 시 `schema:` 커밋 + 태그 + 전원 통보 |
| `api/src/ingest/`, `api/src/parsing/` | A |
| `api/src/matching/`, `api/src/settlements/` | B |
| `api/src/guards/`, `api/src/payouts/`, `api/infra/` | C |
| `api/tests/fixtures/` | **공유** — 추가만, 수정 금지 |
| `agent/claimant/` | A |
| `agent/executor/` | B |
| `agent/safety/` | C |
| `web/` 전체 | B |

`api/src/payouts/`와 `api/src/guards/`는 main 직푸시 금지. 브랜치 + 리뷰 1회.

`recipients` 컬렉션은 소유가 갈린다. **등록·조회·Slack ID 매핑은 A**,
**`monthly_paid_minor` 갱신은 C**가 한다. 다른 필드를 쓰지 않는다.

---

## 1. 공통 규약

### 명명

- 상태 필드 이름은 전 컬렉션 **`status`**. `state` 금지.
- **상태 값은 전부 `UPPER_SNAKE`.** 예외 없다.
- 시각 필드는 `created_at` / `updated_at`. 이벤트 시각은 `{동사}_at`.
- 컬렉션 이름은 복수형 snake_case.

### 시각

- Firestore `Timestamp` 타입으로 저장한다. 문자열 금지.
- 저장은 **UTC**. KST 변환은 `web`이 표시할 때만 한다. 서버는 변환 책임이 없다.
- 예외는 `receipts.transaction_date` 하나다. 영수증에 찍힌 달력 날짜이고 타임존이 없다.
  Python `date`, Firestore에는 `YYYY-MM-DD` 문자열로 저장한다.
  Timestamp로 저장하면 KST/UTC 경계에서 하루가 밀린다.

### 금액

모든 금액은 `{amount_minor: int, currency: str}`이다. float 금지.
`currency`는 ISO-4217 3글자 대문자.

---

## 2. Firestore 컬렉션

컬렉션은 9개다.

### `recipients`

영수증을 올리고 정산을 받는 사람. Slack user ID와 PayPal 이메일을 잇는 유일한 지점이다.
집행자는 여기 없다 — 집행자는 송금 대상이 아니라 대시보드 인증 주체이고,
`audit_logs.actor` 문자열로 충분하다.

| 필드 | 타입 | 비고 |
|---|---|---|
| `recipient_id` | str | `rcp_{ulid}` |
| `slack_user_id` | str | `U0123ABC`. DM 발송에 쓴다 |
| `paypal_email` | str | 송금 수취 주소 |
| `display_name` | str | |
| `monthly_paid_minor` | int | **기준통화 환산 누적액.** 예약분 포함 |
| `monthly_period` | str | `2026-08`. 달이 바뀌면 누적을 0으로 리셋 |
| `verified` | bool | 이메일 확인 여부 |
| `status` | enum | `ACTIVE` / `DISABLED` |
| `created_at`, `updated_at` | Timestamp | |

`monthly_paid_minor` 갱신 규칙:
- `/payouts` enqueue 시점에 해당 배치분을 **더한다**(예약).
- `/tasks/reconcile`에서 `SUCCESS`가 아닌 종결 상태로 확정되면 그만큼 **뺀다**.
- `monthly_period`가 현재 달과 다르면 읽는 쪽이 0으로 간주하고 갱신 시 함께 갱신한다.

### `receipts`

| 필드 | 타입 | 비고 |
|---|---|---|
| `receipt_id` | str | `rct_{ulid}` |
| `recipient_id` | str | |
| `image_gcs_uri` | str | 원본 이미지 |
| `raw_text_gcs_uri` | str | 파싱 원문. 에이전트의 비신뢰 입력이 여기서 온다 |
| `merchant_name` | str \| None | 마스킹 후 값. 결정론적 매칭이 쓴다 |
| `transaction_date` | date \| None | **결제일.** `created_at`(업로드 시각)과 다르다 |
| `parsed_amount_minor` | int \| None | |
| `currency` | str | |
| `account_category_code` | enum \| None | §5 |
| `category_source` | enum | `LLM_PARSE` / `DETERMINISTIC_FALLBACK` / `EXECUTOR_AGENT` / `HUMAN` |
| `parse_signals` | map | §5 |
| `llm_confidence` | float \| None | 0.0~1.0 |
| `status` | enum | `RECEIVED` / `PARSED` / `NEEDS_REQUERY` / `FAILED` |
| `created_at`, `updated_at` | Timestamp | |

**PII 마스킹은 Firestore 쓰기 전에 한다.** Firestore에 들어가는 값은 전부 마스킹 후이고,
원문은 `image_gcs_uri`와 `raw_text_gcs_uri`로만 접근한다.

상태 의미:

| 값 | 뜻 |
|---|---|
| `RECEIVED` | Slack 인입 완료, 파싱 전 |
| `PARSED` | 파싱 성공. 청구 항목 생성 가능 |
| `NEEDS_REQUERY` | 파싱은 됐으나 청구자 에이전트가 영수증과 불일치 판단. 재요청 대상 |
| `FAILED` | 파싱 자체 실패 |

### `claim_requests`

| 필드 | 타입 | 비고 |
|---|---|---|
| `claim_request_id` | str | `crq_{ulid}` |
| `recipient_id`, `receipt_id` | str | |
| `slack_dm_ts` | str | 버튼 응답을 원 메시지에 붙일 때 쓴다 |
| `reminded_at` | Timestamp \| None | |
| `expires_at` | Timestamp | 생성 시각 + `CLAIM_REQUEST_TTL_SECONDS` |
| `status` | enum | `PENDING` / `REMINDED` / `RESPONDED` / `EXPIRED` |
| `created_at`, `updated_at` | Timestamp | |

전이: `PENDING → REMINDED → RESPONDED | EXPIRED`.
`PENDING → RESPONDED`도 가능하다(재촉 전에 응답).

### `claims`

| 필드 | 타입 | 비고 |
|---|---|---|
| `claim_id` | str | `clm_{ulid}` |
| `recipient_id`, `receipt_id` | str | |
| `amount_minor` | int | |
| `currency` | str | |
| `account_category_code` | enum | §5 |
| `is_business` | bool | |
| `settlement_run_id` | str \| None | **점유 필드** |
| `settled_at` | Timestamp \| None | |
| `status` | enum | `DRAFT` / `CONFIRMED` / `IN_RUN` / `SETTLED` / `VOID` |
| `created_at`, `updated_at` | Timestamp | |

**claim 점유는 CAS 트랜잭션이다.** 한 claim이 두 배치에 들어가면 이중 지급이다.
`SettlementFilter.exclude_claim_ids`는 에이전트가 채우는 필드라 방어선이 아니다.

배치 생성 시 하나의 Firestore 트랜잭션에서 `CONFIRMED → IN_RUN` 전이와
`settlement_run_id` 기록을 함께 한다. 이미 `IN_RUN`인 claim은 전이 실패로 배치에서 빠진다.
배치가 `FAILED`로 끝나면 `IN_RUN → CONFIRMED`로 되돌리고 `settlement_run_id`를 비운다.

이 전이는 `api/src/guards/`(C)가 담당한다.

### `settlement_runs`

| 필드 | 타입 | 비고 |
|---|---|---|
| `settlement_run_id` | str | `run_{yymmdd}_{ULID 앞 12자}`. §3 |
| `filter` | SettlementFilter | §6 |
| `base_currency` | str | 캡 검사와 총액 표시의 기준통화 |
| `total_amount_minor` | int | 기준통화 환산 총액 |
| `fx_rates` | map[str, str] | §4 |
| `fx_locked_at` | Timestamp \| None | 승인 시점 |
| `approval_amount_hash` | str \| None | §7 |
| `approval_token_hash` | str \| None | 토큰 원문은 저장하지 않는다 |
| `approval_token_expires_at` | Timestamp \| None | 발급 시각 + `APPROVAL_TOKEN_TTL_SECONDS` |
| `approval_token_used_at` | Timestamp \| None | **소각 표시.** non-null이면 재사용 거부 |
| `approved_by` | str \| None | 집행자 식별자 |
| `approved_at` | Timestamp \| None | |
| `retry_seq` | int | 재발송 회차. 최초 0 |
| `status` | enum | `DRAFT` / `APPROVED` / `EXECUTING` / `SETTLED` / `FAILED` |
| `created_at`, `updated_at` | Timestamp | |

### `sender_items`

| 필드 | 타입 | 비고 |
|---|---|---|
| `sender_item_id` | str | §3 |
| `settlement_run_id`, `recipient_id` | str | |
| `receiver_email` | str | 송금 시점의 이메일 스냅샷 |
| `amount_minor` | int | 원통화 금액 |
| `currency` | str | |
| `paypal_value` | str | PayPal에 실제로 보낸 문자열. §8 |
| `payout_item_id` | str \| None | PayPal이 준 ID |
| `paypal_transaction_status` | str \| None | **PayPal 원문 그대로** |
| `status` | enum | `PENDING` / `SUCCESS` / `FAILED` / `UNCLAIMED` / `OTHER` |
| `retry_of` | str \| None | 재발송이면 원 `sender_item_id` |
| `created_at`, `updated_at` | Timestamp | |

PayPal은 위 4개 외에 `RETURNED`, `ONHOLD`, `BLOCKED`, `REVERSED`, `REFUNDED` 등도 반환한다.
**미매핑 값은 전부 `OTHER`로 떨어뜨리고 원문을 `paypal_transaction_status`에 남긴다.**
돈 경로에서 조용한 누락이 최악이다. 대조 로직은 `OTHER`를 사람이 확인해야 하는 건으로
처리한다.

### `agent_drafts`

에이전트 출력이 도착하는 유일한 장소. **`api`만 읽는다.** 에이전트가 이 컬렉션을 통해
서로 간접 통신하는 것도 금지다.

| 필드 | 타입 | 비고 |
|---|---|---|
| `draft_id` | str | `drf_{ulid}` |
| `agent` | enum | `CLAIMANT` / `EXECUTOR` / `SAFETY` |
| `target_type` | enum | `RECEIPT` / `SETTLEMENT_RUN` |
| `target_id` | str | |
| `task_id` | str | 멱등성 키. 같은 Cloud Tasks 재시도는 덮어쓴다 |
| `payload` | map | §9 |
| `created_at` | Timestamp | |

### `audit_logs`

append-only. 상태 없음. 수정·삭제하지 않는다.

| 필드 | 타입 | 비고 |
|---|---|---|
| `ts` | Timestamp | |
| `actor` | str | 사람 식별자 / 에이전트 이름 / 서비스 이름 |
| `actor_type` | enum | `HUMAN` / `AGENT` / `SYSTEM` |
| `action` | str | `RUN_CREATED`, `RUN_APPROVED`, `PAYOUT_ENQUEUED`, `PAYOUT_REJECTED` 등 |
| `run_id` | str \| None | |
| `before`, `after` | map \| None | 전이 전후 상태 |
| `reason` | str \| None | 안전 확인 에이전트 출력 원문 |

`reason`에 들어가는 값은 **PII 마스킹 이후**다. 원문 영수증 텍스트를 여기 흘리지 않는다.

---

## 3. ID 체계

ULID를 쓴다. 시간순 정렬이 되고 Firestore 문서 ID로도 무난하다. Firestore는 단조 증가하는
문서 ID에서 쓰기 핫스팟이 생길 수 있다고 권고하지만, 이 규모에서는 무시해도 되는 수준이고
정렬 이득이 더 크다.

| ID | 형식 |
|---|---|
| `recipient_id` | `rcp_{ulid}` |
| `receipt_id` | `rct_{ulid}` |
| `claim_id` | `clm_{ulid}` |
| `claim_request_id` | `crq_{ulid}` |
| `settlement_run_id` | `run_{yymmdd}_{ULID 앞 12자}` |
| `draft_id` | `drf_{ulid}` |

### PayPal 연동 ID

| ID | 최초 발송 | 재발송 (n회차) |
|---|---|---|
| `sender_batch_id` | `{settlement_run_id}` | `{settlement_run_id}:r{n}` |
| `sender_item_id` | `{settlement_run_id}:{recipient_id}` | `{settlement_run_id}:r{n}:{recipient_id}` |
| `PayPal-Request-Id` 헤더 | `{sender_batch_id}` | `{sender_batch_id}` |

`sender_batch_id`와 `PayPal-Request-Id`를 **둘 다** 보낸다. 전자는 PayPal의 배치 중복 방지,
후자는 HTTP 요청 단위 멱등성이라 계층이 다르다. 값은 같게 두어 추적을 단순화한다.

**PayPal 멱등성에는 30일 창이 있다.** 동일 `sender_batch_id`에 대한 단일 결제 보장은
30일 이내 사용분에 한한다. 이 기간을 넘겨 같은 배치를 재전송하지 않는다.

**ID 길이 결정 완료 (8/17).** 전체 ULID(26자)로 `settlement_run_id`를 만들면
`run_20260816_{26자 ULID}` = 39자, `sender_item_id`는 `{settlement_run_id}:{recipient_id}`
(`recipient_id`도 `rcp_{26자 ULID}` = 30자)까지 합쳐 70자로, PayPal `sender_item_id` 상한
63자를 넘는다. **`settlement_run_id`는 처음부터 아래 축약형만 쓴다.**

```
run_{yymmdd}_{ULID 앞 12자}     예) run_260816_01K3M9XQ7B2F
```

이러면 `sender_item_id` = `run_{yymmdd}_{ULID 앞 12자}:{recipient_id}` = 23 + 1 + 30 = 54자,
재발송(`:r{n}`)을 붙여도 63자 안에 들어온다. 형식만 바뀌고 다른 계약은 그대로다.

---

## 4. 금액과 환율

### minor unit 변환

`amount_minor`를 실제 금액으로 되돌리려면 통화별 소수 자릿수가 필요하다.
KRW는 0, USD·EUR는 2, JPY는 0, TND는 3이다.

PayPal Payouts는 금액을 `{"value": "10.00", "currency": "USD"}` **문자열 소수**로 받는다.
JPY처럼 통상 소수를 쓰지 않는 통화는 정수로, TND처럼 1000분의 1로 나뉘는 통화는
소수 분수로 보내야 한다.

**통화별 지수 테이블과 변환 함수는 `api/src/payouts/`(C)가 단독으로 갖는다.**
다른 어디에서도 문자열 금액을 만들지 않는다. 실제로 보낸 문자열은
`sender_items.paypal_value`에 남긴다 — 대조할 때 무엇을 보냈는지 추측하지 않기 위해서다.

```python
CURRENCY_EXPONENT: dict[str, int] = {
    "KRW": 0, "JPY": 0,
    "USD": 2, "EUR": 2, "GBP": 2,
    "TND": 3,
}

def to_paypal_value(amount_minor: int, currency: str) -> str:
    exp = CURRENCY_EXPONENT[currency]          # KeyError는 그대로 터뜨린다
    return str(Decimal(amount_minor).scaleb(-exp).quantize(Decimal(1).scaleb(-exp)))
```

미등록 통화는 예외로 터뜨린다. 기본값 2로 추측하지 않는다.

### 환율

```python
fx_rates: dict[str, str] = {
    "USD/KRW": "1382.50",
    "JPY/KRW": "9.12",
}
```

- 키는 `{FROM}/{TO}` 대문자. `TO`는 항상 `base_currency`.
- 값은 **문자열**이다. float 금지. 코드에서는 `Decimal`로 다룬다.
  `amount_minor`를 int로 못 박아놓고 환율만 float면 반올림 오차가 그 지점으로 새어나온다.
- `base_currency`와 같은 통화는 맵에 넣지 않는다(환산 계수 1).

**환산 순서** — 항목별로 환산한 뒤 합산한다. 합산 후 환산하면 항목 합과 총액이 안 맞는다.

```
amount_minor (원통화)
  → Decimal 실금액 = amount_minor × 10^(-exp[원통화])
  → × Decimal(fx_rates["원통화/기준통화"])
  → 기준통화 minor = round_half_up(실금액 × 10^(exp[기준통화]))
```

**환율은 승인 시점에 고정한다.** `POST /settlements/runs/{run_id}/approve`에서 조회해
`fx_rates`와 `fx_locked_at`에 기록하고, `total_amount_minor`를 이 환율로 다시 계산한다.
배치 생성 시점의 총액은 잠정치다.

`fx_rates`는 `approval_amount_hash`에 포함되므로 승인 후 환율이 바뀌면 토큰이 깨진다.

### 한도 캡

**캡 3종은 전부 `base_currency`의 minor 단위다.** 환산 후 검사한다.

| 캡 | 검사 대상 | 검사 시점 |
|---|---|---|
| `MAX_AMOUNT_PER_ITEM_MINOR` | 항목별 환산액 | approve, `/payouts` |
| `MAX_AMOUNT_PER_BATCH_MINOR` | `total_amount_minor` | approve, `/payouts` |
| `MAX_AMOUNT_MONTHLY_MINOR` | `recipients.monthly_paid_minor` + 이번 배치 해당분 | approve, `/payouts` |

**두 시점 모두에서 검사한다.** approve에서 통과했더라도 `/payouts` 직전에 다시 본다.
그 사이에 다른 배치가 월간 누적을 올렸을 수 있다.

---

## 5. 계정과목

### 코드값과 표시명

Firestore에는 **코드값만** 저장한다. 표시명이 바뀌어도 저장된 데이터를 건드리지 않는다.

| 코드값 | 표시명 |
|---|---|
| `PAYMENT_FEE` | 지급수수료 |
| `EMPLOYEE_BENEFIT` | 복리후생비 |
| `TRAVEL` | 여비교통비 |
| `SUPPLIES` | 소모품비 |
| `ADVERTISING` | 광고선전비 |
| `RENT` | 지급임차료 |
| `UNCLASSIFIED` | 미분류 |

매핑 테이블은 `api/src/schemas/`(공유)에 둔다. **서버도 표시명이 필요하다** — XLSX를 서버가
생성하고 그 파일은 세무사가 읽는다. `web`은 OpenAPI 생성 타입으로 코드값을 받고 자체 매핑
상수로 렌더한다.

### 분류 라우팅 — 2단계

결정론적 신호와 LLM confidence를 둘 다 쓴다. **순서가 핵심이다.**

**1단계 — 결정론적 신호 (게이트).** 아래 중 하나라도 걸리면 LLM confidence를 **보지 않고**
즉시 `UNCLASSIFIED`, `category_source = DETERMINISTIC_FALLBACK`.

```python
parse_signals = {
    "merchant_name_present": bool,
    "transaction_date_present": bool,
    "amount_parsed": bool,
    "currency_detected": bool,
    "injection_suspected": bool,   # True이면 즉시 UNCLASSIFIED
}
```

앞 4개 중 하나라도 `False`이거나 `injection_suspected`가 `True`이면 걸린다.
가맹점명이 없는데 계정과목을 자신 있게 찍었다면 그 자신감에 근거가 없다.
LLM이 자기 보고하는 confidence는 캘리브레이션이 안 되므로 혼자서는 게이트가 못 된다.

**2단계 — LLM confidence.** 1단계 신호가 전부 깨끗할 때만 적용한다.
`llm_confidence < PARSING_CONFIDENCE_THRESHOLD`이면 `UNCLASSIFIED`,
아니면 파싱이 낸 코드값을 그대로 쓰고 `category_source = LLM_PARSE`.

임계값 초기값은 **0.7**이다. A가 fixture 8종으로 돌려보고 조정한다.
`injection_suspected` 판정 규칙도 A가 정한다.

`UNCLASSIFIED`로 떨어진 건은 집행자 에이전트가 재판단하고, 반영 시
`category_source = EXECUTOR_AGENT`가 된다. 대시보드에서 사람이 지정하면 `HUMAN`.

---

## 6. Pydantic 스키마

`api/src/schemas/`에 둔다. `agent`는 의존성으로 핀해서 import하고, `web`은 OpenAPI에서
타입을 생성한다. 변경 순서는 `api → agent → web`이고 역순은 금지다.

```python
from datetime import date, datetime
from enum import StrEnum
from pydantic import BaseModel, ConfigDict, Field


class AccountCategory(StrEnum):
    PAYMENT_FEE = "PAYMENT_FEE"
    EMPLOYEE_BENEFIT = "EMPLOYEE_BENEFIT"
    TRAVEL = "TRAVEL"
    SUPPLIES = "SUPPLIES"
    ADVERTISING = "ADVERTISING"
    RENT = "RENT"
    UNCLASSIFIED = "UNCLASSIFIED"


CATEGORY_DISPLAY: dict[AccountCategory, str] = {
    AccountCategory.PAYMENT_FEE: "지급수수료",
    AccountCategory.EMPLOYEE_BENEFIT: "복리후생비",
    AccountCategory.TRAVEL: "여비교통비",
    AccountCategory.SUPPLIES: "소모품비",
    AccountCategory.ADVERTISING: "광고선전비",
    AccountCategory.RENT: "지급임차료",
    AccountCategory.UNCLASSIFIED: "미분류",
}


class Money(BaseModel):
    model_config = ConfigDict(extra="forbid")
    amount_minor: int
    currency: str = Field(pattern=r"^[A-Z]{3}$")


class SettlementFilter(BaseModel):
    """집행자 에이전트가 자연어에서 만들 수 있는 유일한 객체."""
    model_config = ConfigDict(extra="forbid")

    period_start: date | None = None      # receipts.transaction_date 기준
    period_end: date | None = None
    recipient_ids: list[str] | None = None
    account_categories: list[AccountCategory] | None = None
    exclude_claim_ids: list[str] | None = None
```

**기간 필터는 `receipts.transaction_date`를 본다.** *"8월 외주 개발 건만 정산해줘"*의 8월은
결제일이지 Slack 업로드일이 아니다. B의 결정론적 매칭도 같은 필드를 기준으로 한다.

**`SettlementFilter`에 없는 것은 애초에 만들 수 없다** — 한도, 승인 토큰, 송금 실행,
수취인 계좌, 금액 조건. 자연어로 *"100만원 이하만"*을 요청해도 표현할 수단이 없다.
`extra="forbid"`이므로 에이전트가 없는 필드를 지어내면 조용히 무시되는 대신 검증 에러가
난다.

`include_claim_ids`는 의도적으로 없다. 에이전트가 claim ID를 직접 고르는 경로를 만들지
않기 위해서다. 개별 선택이 필요하면 대시보드에서 사람이 체크박스로 한다.

### 나가는 필드 최소화

`api → web` 응답에 Firestore 문서를 통째로 실어보내지 않는다. 응답 모델을
따로 정의한다. 내부 필드(승인 토큰, 원본 PII, 내부 상태 플래그)가 브라우저까지
가는 걸 막는 게 목적이다.

`api → agent` 툴 응답도 마찬가지다. 에이전트가 알 필요 없는 필드는 빼고 준다.
컨텍스트 절약이 아니라 인젝션 표면 축소가 이유다.

### 계약 테스트

`api`에 스냅샷 테스트를 하나 둔다.

```python
def test_openapi_snapshot():
    assert app.openapi() == json.load(open("tests/openapi.snapshot.json"))
```

스키마를 의도적으로 바꿨다면 스냅샷을 갱신하고, 커밋 메시지에
`schema:` 접두사를 붙인다. 다른 레포가 따라와야 한다는 신호다.

### 결정론적 매칭

`api/src/matching/`(B). LLM을 쓰지 않는다.

| 축 | 기준 |
|---|---|
| 금액 | `parsed_amount_minor` 완전 일치 |
| 날짜 | `transaction_date` ± `MATCHING_DATE_WINDOW_DAYS` |
| 가맹점명 | `merchant_name` 정규화 후 비교 |

세 축이 모두 맞으면 자동 매칭, 하나라도 어긋나면 집행자 에이전트가 서술한다.
에이전트는 서술만 하고 매칭을 확정하지 않는다.

---

## 7. 승인 토큰

### 흐름

```
POST /settlements/runs
  └ claims CONFIRMED → IN_RUN (CAS 트랜잭션)
  └ run 생성, status = DRAFT, 총액은 잠정치

POST /agents/safety/report        (Cloud Tasks, 승인 직전)
  └ agent_drafts에 risk_report 기록

POST /settlements/runs/{run_id}/approve
  └ 환율 조회 → fx_rates, fx_locked_at 고정
  └ total_amount_minor 재계산
  └ 한도 캡 3종 검사 → 실패 시 403
  └ approval_amount_hash 계산
  └ 토큰 발급 (원문은 응답 본문으로만, 저장은 해시)
  └ DRAFT → APPROVED (CAS)

POST /payouts        Header: X-Approval-Token
  └ 토큰 해시 대조 / 만료 확인 / used_at null 확인  → 실패 시 403
  └ approval_amount_hash 재계산 후 대조             → 불일치 시 403
  └ 한도 캡 3종 재검사                              → 실패 시 403
  └ approval_token_used_at 기록 (소각)
  └ APPROVED → EXECUTING (CAS)
  └ monthly_paid_minor 예약 가산
  └ Cloud Tasks enqueue 후 즉시 202 반환 — 동기 호출 금지
```

**승인 응답에서 PayPal을 동기로 부르지 않는다.** `EXECUTING`으로 마킹하고 큐에 넣은 뒤
바로 응답한다.

### `approval_amount_hash`

발급 측과 검증 측이 **같은 함수**를 부른다. `api/src/guards/`에 둔다.

```python
def approval_amount_hash(run: SettlementRun) -> str:
    payload = {
        "settlement_run_id": run.settlement_run_id,
        "base_currency": run.base_currency,
        "fx_rates": dict(sorted(run.fx_rates.items())),
        "items": [
            {"recipient_id": i.recipient_id,
             "amount_minor": i.amount_minor,
             "currency": i.currency}
            for i in sorted(run.items, key=lambda x: x.recipient_id)
        ],
    }
    canonical = json.dumps(payload, sort_keys=True,
                           separators=(",", ":"), ensure_ascii=False)
    return hashlib.sha256(canonical.encode("utf-8")).hexdigest()
```

- **총액이 아니라 항목별 전체를 해싱한다.** 총액만 넣으면 총액이 같고 분배만 바뀐 조작을
  못 잡는다.
- `fx_rates`를 포함하므로 승인 후 환율이 바뀌면 토큰이 자동으로 깨진다.
- `canonical`은 키 정렬, 구분자 `(",", ":")`, non-ASCII 이스케이프 없음, 개행 없음.

### 토큰 수명

- 발급 시 `approval_token_expires_at = now + APPROVAL_TOKEN_TTL_SECONDS` (600초).
- 저장은 해시만. 원문은 approve 응답 본문에 한 번 실려 나가고 서버에 남지 않는다.
- 사용 시 `approval_token_used_at`을 기록한다. non-null이면 이후 요청은 전부 403.

---

## 8. PayPal 연동

**Payouts API를 직접 호출한다.** MCP Server를 끼면 멱등성·게이트·캡의 통제점이 흐려진다.

### 상태 매핑

| PayPal `transaction_status` | 내부 `status` |
|---|---|
| `SUCCESS` | `SUCCESS` |
| `FAILED` | `FAILED` |
| `UNCLAIMED` | `UNCLAIMED` |
| `PENDING` | `PENDING` |
| 그 외 전부 | `OTHER` |

원문은 항상 `paypal_transaction_status`에 남긴다.

### 결과 대조

**주 경로는 Cloud Tasks 지연 폴링이다.** `/payouts` enqueue 시 `RECONCILE_DELAY_SECONDS`
뒤에 `/tasks/reconcile`을 함께 예약한다. 미종결 항목이 남아 있으면 자신을 다시 예약하되
`PAYOUT_MAX_RECONCILE_ATTEMPTS`까지만 한다.

`POST /webhooks/paypal`은 **보조 경로**다. 웹훅이 오면 대조가 빨라지지만, 오지 않아도
폴링으로 결말이 난다. 샌드박스 웹훅 불안정에 데모를 걸지 않는다.

종결 판정:

- 전 항목이 `SUCCESS` → run `SETTLED`, 해당 claims `IN_RUN → SETTLED`
- `FAILED` / `UNCLAIMED` / `OTHER`가 있음 → run `FAILED`,
  성공분 claims만 `SETTLED`, 나머지는 `IN_RUN → CONFIRMED`로 되돌리고
  `settlement_run_id`를 비운다. 예약했던 `monthly_paid_minor`도 그만큼 뺀다.

### 재발송

`POST /payouts/{run_id}/retry`. 미성공 항목만 모아 **새 배치**로 보낸다.
`retry_seq`를 1 올리고 §3의 재발송 ID 형식을 쓴다. 승인 토큰을 새로 발급받아야 한다 —
재발송도 돈이 나가는 행위다.

---

## 9. 에이전트

### 진입점

`agent` 서비스는 비공개다. Cloud Tasks의 OIDC 토큰만 통과시키고 audience는
`OIDC_AUDIENCE`로 맞춘다.

| 라우트 | 트랙 | 디렉터리 |
|---|---|---|
| `POST /agents/claimant/review` | A | `agent/claimant/` |
| `POST /agents/executor/analyze` | B | `agent/executor/` |
| `POST /agents/safety/report` | C | `agent/safety/` |

**응답 본문은 의미가 없다.** 결과를 `agent_drafts`에 쓰고 `200`만 돌려준다.
`api`가 draft를 읽어간다.

### 입출력

| 에이전트 | 입력 | `agent_drafts.payload` |
|---|---|---|
| 청구자 | `receipt_id`, 파싱 JSON, `raw_text_gcs_uri` | `needs_requery: bool`, `requery_message: str`, `is_business: bool`, `reason: str` |
| 집행자 | 자연어 문자열, 후보 `claims` 목록 | `filter: SettlementFilter`, `anomalies: list[str]`, `recategorized: list[{claim_id, code}]`, `summary_text: str` |
| 안전 확인 | `settlement_run` 스냅샷 | `risk_report: str` |

세부 필드는 각 담당이 자기 에이전트 것만 채운다. 서로 부르지 않으므로 에이전트 간 계약은
없다. `payload` 최상위 키만 위 표대로 맞춘다.

안전 확인 에이전트의 `risk_report`는 `audit_logs.reason`에 그대로 저장된다.
**게이트가 아니다.** 이 리포트가 비어 있어도 승인과 송금은 코드 게이트만으로 진행된다.

### 비신뢰 입력

영수증 원문은 GCS에서 읽어 `<untrusted_receipt_text>` 블록으로 감싼다.
블록 안의 내용은 데이터이지 지시가 아니다. Firestore에 마스킹된 값만 있는 것과 별개 조치다.

### 툴 콜백

`api/src/guards/`의 `before_tool_callback`이 모든 에이전트 툴 호출 전에 한도 검사,
중복 실행 검사, 감사 로그 기록을 한다.

---

## 10. API 라우트

라우터 객체는 각 디렉터리에서 정의하고 등록만 진입점에서 한다. **URL 경로와 디렉터리
소유권은 다를 수 있다** — `/settlements/runs/{run_id}/approve`가 그 예다.

### 공개

| 라우트 | 트랙 | 핸들러 위치 |
|---|---|---|
| `POST /slack/events` | A | `api/src/ingest/` |
| `POST /slack/interactions` | A | `api/src/ingest/` |
| `POST /claims/{claim_id}/confirm` | A | `api/src/ingest/` |
| `GET  /settlements` | B | `api/src/settlements/` |
| `POST /settlements/runs` | B | `api/src/settlements/` |
| `GET  /settlements/runs/{run_id}` | B | `api/src/settlements/` |
| `GET  /settlements/runs/{run_id}/export` | B | `api/src/settlements/` |
| `POST /settlements/runs/{run_id}/approve` | C | **`api/src/guards/`** |
| `POST /payouts` | C | `api/src/payouts/` |
| `POST /payouts/{run_id}/retry` | C | `api/src/payouts/` |
| `POST /webhooks/paypal` | C | `api/src/payouts/` |

Slack은 Event Subscriptions URL과 Interactivity Request URL을 앱 설정에서 **따로** 받는다.
버튼 응답은 `/slack/interactions`로 온다.

`POST /slack/events`는 서명 검증 후 **3초 이내에 ack**하고 처리는 큐로 넘긴다.

### Cloud Tasks 전용 (OIDC 필수, 공개 금지)

| 라우트 | 트랙 | 핸들러 위치 |
|---|---|---|
| `POST /tasks/parse-receipt` | A | `api/src/parsing/` |
| `POST /tasks/remind` | A | `api/src/ingest/` |
| `POST /tasks/execute-payout` | C | `api/src/payouts/` |
| `POST /tasks/reconcile` | C | `api/src/payouts/` |

---

## 11. 환경변수

```bash
# --- 실행 환경 ---
GCP_PROJECT=
FIRESTORE_DATABASE=dev          # dev | deploy — 로컬/테스트는 dev, 실 배포는 deploy
PAYPAL_ENV=sandbox              # sandbox | live
BASE_CURRENCY=KRW

# --- 모델 ---
GEMINI_MODEL_ID=                # A가 Vertex 콘솔에서 실사용 가능한 ID를 확인해 채운다
VERTEX_LOCATION=

# --- 큐 · 서비스 간 호출 ---
CLOUD_TASKS_QUEUE=
CLOUD_TASKS_LOCATION=
AGENT_SERVICE_URL=
OIDC_AUDIENCE=

# --- 파싱 · 매칭 ---
PARSING_CONFIDENCE_THRESHOLD=0.7
MATCHING_DATE_WINDOW_DAYS=3

# --- 재촉 루프 ---
REMINDER_DELAY_SECONDS=20       # 데모 20, 실제 86400
CLAIM_REQUEST_TTL_SECONDS=

# --- 대조 ---
RECONCILE_DELAY_SECONDS=
PAYOUT_MAX_RECONCILE_ATTEMPTS=

# --- 돈 게이트 (전부 BASE_CURRENCY의 minor 단위) ---
MAX_AMOUNT_PER_ITEM_MINOR=
MAX_AMOUNT_PER_BATCH_MINOR=
MAX_AMOUNT_MONTHLY_MINOR=
APPROVAL_TOKEN_TTL_SECONDS=600

# --- 시크릿: Secret Manager 경유. .env에 값을 넣지 않는다 ---
# PAYPAL_CLIENT_ID / PAYPAL_CLIENT_SECRET
# SLACK_SIGNING_SECRET
# SLACK_BOT_TOKEN
```

`PAYPAL_ENV`를 명시적으로 둔 것은 live 오발사 방지 목적이다. 기본값에 기대지 않는다.

**`agent` 서비스 계정에 PayPal 시크릿 접근 권한이 없어야 한다.** Terraform에서 IAM으로
분리하고 그 사실을 주석으로 남긴다.

`web`에는 시크릿이 없다. `NEXT_PUBLIC_` 접두사에 민감 정보를 넣지 않는다.

---

## 12. 데모 데이터셋 8종

`api/tests/fixtures/`에 둔다. **스텁 엔드포인트도 이걸 반환하고 최종 데모도 이걸 쓴다.**
따로 만들면 두 번 만든다. 추가만 하고 기존 fixture를 수정하지 않는다.

| # | 시나리오 | 검증 대상 | 시연 |
|---|---|---|---|
| 1 | 정상 영수증, 매칭 성공. **항목 하나는 USD** | 골든 패스 + `fx_rates` 환산 경로 | B |
| 2 | 파싱 실패 (흐릿한 사진) | 재요청 문안, 1단계 결정론적 폴백 | A |
| 3 | 중복 청구 의심 | 안전 확인 에이전트 이상 서술 | B |
| 4 | 신호는 깨끗한데 `llm_confidence` 낮음 | 2단계 임계값 → `UNCLASSIFIED` → 집행자 재판단 | B |
| 5 | 미청구 방치 → 재촉 → 무응답 만료 | 추적 루프 전체 상태 전이 | A |
| 6 | 프롬프트 인젝션 시도 영수증 텍스트 | `injection_suspected`, 비신뢰 입력 격리 | A |
| 7 | 한도 캡 초과 배치 + 토큰 없는 `/payouts` 호출 | **403 거부** | C |
| 8 | PayPal `FAILED` + `UNCLAIMED` 혼재 결과 | 대조 → 되돌리기 → 재발송 | C |

2번은 1단계(결정론적 신호), 4번은 2단계(confidence)를 각각 덮는다. 두 경로는 다르므로
둘 다 필요하다.

---

## 13. 통합 확인

각 트랙이 흩어지기 전에 넷 다 통과해야 한다. 하나라도 안 되면 그 사람만 막히는 게 아니라
전원이 막힌다.

| # | 확인 방법 | 통과 조건 |
|---|---|---|
| 1 | B가 `npx openapi-typescript` 실행 | 타입 파일 생성 |
| 2 | A·C가 `agent` 레포에서 `api` 스키마 import | 에러 없이 import |
| 3 | 세 명이 각자 스텁 엔드포인트 호출 | fixture JSON 반환 |
| 4 | Cloud Tasks에서 비공개 Cloud Run 호출 | 200 응답 |

### 변경 절차

1. 이 문서를 먼저 고친다.
2. `api/src/schemas/` 수정 → `schema:` 커밋. 본문에 영향 레포를 명시한다.
3. 태그를 끊고 전원에게 통보한다.
4. `agent`가 의존성 핀을 올린다.
5. `web`이 타입을 재생성하고 생성 파일을 커밋한다.

**순서는 `api → agent → web`이고 역순은 금지다.**

