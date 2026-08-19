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

컬렉션은 10개다.

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
| `image_gcs_uri` | str \| None | 원본 이미지 |
| `raw_text_gcs_uri` | str \| None | 파싱 원문. 에이전트의 비신뢰 입력이 여기서 온다 |
| `slack_file_id` | str \| None | `F0123ABC`. Slack 재전송 dedup 키 |
| `slack_channel_id` | str \| None | 영수증을 올린 원 메시지의 채널 |
| `slack_message_ts` | str \| None | 같은 메시지의 ts. 스레드 답글의 `thread_ts`로 넣는다 |
| `merchant_name` | str \| None | 마스킹 후 값. 결정론적 매칭이 쓴다 |
| `transaction_date` | date \| None | **결제일.** `created_at`(업로드 시각)과 다르다 |
| `parsed_amount_minor` | int \| None | |
| `currency` | str \| None | |
| `account_category_code` | enum \| None | §5 |
| `category_source` | enum \| None | `LLM_PARSE` / `DETERMINISTIC_FALLBACK` / `EXECUTOR_AGENT` / `HUMAN` |
| `parse_signals` | map \| None | §5 |
| `llm_confidence` | float \| None | 0.0~1.0 |
| `verified_at` | Timestamp \| None | 검증 통과 시각. 미검증이거나 검증 실패면 `None` |
| `verification_signals` | map \| None | 아래 "검증" 참조 |
| `status` | enum | `RECEIVED` / `PARSED` / `NEEDS_REQUERY` / `VERIFICATION_FAILED` / `FAILED` |
| `created_at`, `updated_at` | Timestamp | |

**PII 마스킹은 Firestore 쓰기 전에 한다.** Firestore에 들어가는 값은 전부 마스킹 후이고,
원문은 `image_gcs_uri`와 `raw_text_gcs_uri`로만 접근한다.

`slack_channel_id`·`slack_message_ts`는 **업로드된 원 메시지의 좌표**다. "파싱했습니다,
이게 맞나요?" 카드를 그 메시지 스레드에 답글로 붙이는 데 쓴다. `claim_requests.slack_dm_ts`는
DM으로 보낸 청구 확인 메시지의 ts라서 이 용도로 쓸 수 없다 — 두 값은 다른 대화를 가리킨다.
채널 ID 없이는 `chat.postMessage`를 부를 수 없으므로 둘을 함께 저장한다.

**둘 다 nullable이다.** Slack 인입이 아닌 경로(fixture 시딩, 수동 등록)로 만들어진
영수증에는 값이 없다. 비어 있으면 스레드 답글을 포기하고 DM으로 폴백한다.
한쪽만 있는 상태는 만들지 않는다 — 같이 쓰거나 같이 비운다.

**`slack_file_id` 중복 검사와 `receipts` 생성은 하나의 Firestore 트랜잭션 안에서 한다.**
검사와 쓰기가 갈라지면 Slack이 같은 파일 이벤트를 재전송할 때 영수증이 두 건 생긴다.

상태 의미:

| 값 | 뜻 |
|---|---|
| `RECEIVED` | Slack 인입 완료, 파싱 전 |
| `PARSED` | 파싱 성공. 청구 항목 생성 가능 |
| `NEEDS_REQUERY` | 파싱은 됐으나 청구자 에이전트가 영수증과 불일치 판단. 재요청 대상 |
| `VERIFICATION_FAILED` | 파싱은 됐으나 이미지-파싱 결과 검증(코드 판정) 실패. 재요청 대상 |
| `FAILED` | 파싱 자체 실패 |

`NEEDS_REQUERY`와 `VERIFICATION_FAILED`는 판정 주체와 판정 시점이 다르다.
`NEEDS_REQUERY`는 **청구자 에이전트**가 청구 확정 과정에서 내리는 판단이고,
`VERIFICATION_FAILED`는 그 이전에 **코드가** 아래 검증 단계에서 내리는 결정론적 판정이다.
하나로 합치면 "왜 재요청이 갔는지"를 감사 로그로 재구성할 때 판정 주체를 잃는다.

#### 검증 (verification)

영수증 이미지는 파싱 시점에 이미 GCS에 저장돼 있다(`image_gcs_uri`). **정산 실행
시점**, 정산 후보로 잡힌 claim들이 딸린 receipt마다 이미지와 파싱 결과가 실제로
일치하는지 Gemini structured output **단발 호출**로 재확인한다. 이미지 1장당 호출
1회이고 ADK 에이전트가 아니다 — 파싱 호출과 같은 이유로 세션·툴루프가 필요 없다.

**호출 시점은 `POST /settlements/runs` 처리 중, 후보 claim을 확정하는 단계다** —
새 Cloud Tasks 라우트가 아니라 그 요청 핸들러 안에서 receipt별로 순차/병렬 호출한다.
이건 `architecture.md` §비동기의 "3초 넘게 걸리는 일은 Cloud Tasks로" 원칙에 대한
**의도적 예외다** — 이 엔드포인트는 Slack webhook처럼 3초 ack 제약이 걸린 인입
경로가 아니라, 대시보드에서 사람이 버튼을 눌러 트리거하는 동기 액션이다.
`api` Cloud Run 타임아웃은 300초(`backend/infra/cloud_run.tf`)로, 데모 규모(후보
receipt 수십 건 이하, 건당 단발 Gemini 호출)에서 인라인으로 충분히 끝난다. 후보 건수가
늘어 300초에 근접하면 이 절을 갱신하고 `/tasks/verify-receipt` 같은 fan-out 태스크로
옮긴다 — 그전까지는 새 라우트를 만들지 않는다.

**청구자 에이전트의 검토와는 다른 게이트다.** 청구자 에이전트는 영수증 **인입
직후**(§9 에이전트 표) 파싱 결과를 검토해 청구 확정 여부를 판단한다 — 이건 청구
생성을 막는 게이트다. 이 검증은 그보다 한참 뒤, **정산 후보 편입**을 막는 별도
게이트다. 청구자 에이전트를 거쳐 이미 `PARSED`인 receipt도, 나중에 이 검증에서
불일치가 나오면 정산에서 빠진다. 하나가 다른 하나를 대체하지 않는다 — 청구자
에이전트의 책임 범위는 이 변경으로 줄지 않는다.

검증 결과는 `receipt_id`에 영구히 캐싱된다 — 이미지와 파싱 텍스트의 일치 여부는
어느 정산 배치에서 봐도 같은 값이므로, 이미 `verified_at`이 있는 receipt는 다음
배치에서 재검증하지 않는다.

**검증 호출은 판정만 반환하고 숫자를 고치지 않는다.** 절대 규칙 3("금액 계산은 LLM이
하지 않는다")이 여기도 적용된다. VLM은 `parsed_amount_minor` 등 코드가 이미 들고 있는
값과 이미지가 맞는지 bool로만 답하고, 대체 금액이나 대체 텍스트를 내놓지 않는다.

```python
class VerificationSignals(BaseModel):
    model_config = ConfigDict(extra="forbid")
    image_legible: bool
    amount_matches: bool
    merchant_matches: bool
    date_matches: bool
    injection_suspected: bool
```

판정은 코드가 결정론적으로 내린다. **코드가 들고 있지 않은 필드(`None`)는 비교
대상이 아니다** — `merchant_name`·`transaction_date`는 nullable이고(§2), 값이 없는
필드에 대해 VLM이 반환한 `_matches`를 강제로 보면 정상 `PARSED` 영수증이 널 필드
하나 때문에 검증 탈락한다:

```python
def verify_passed(r: Receipt, s: VerificationSignals) -> bool:
    if not s.image_legible or s.injection_suspected:
        return False
    if r.parsed_amount_minor is not None and not s.amount_matches:
        return False
    if r.merchant_name is not None and not s.merchant_matches:
        return False
    if r.transaction_date is not None and not s.date_matches:
        return False
    return True
```

통과하면 `verified_at = now`, `verification_signals`에 신호를 저장하고 `status`는
`PARSED`를 유지한다. 실패하면 `status = VERIFICATION_FAILED`,
`claim_requests.reason = VERIFICATION_FAILED`로 재요청을 만들고, 해당 claim은 이번
정산 후보에서 빠진다.

**`claim_requests` 문서는 B(`POST /settlements/runs`)가 쓰지만, 그 뒤 DM 발송은 A가
소유한 기존 재촉 루프를 그대로 탄다** — `PENDING` 상태로 써넣기만 하면 A의 알림
트리거가 `AMOUNT_MISMATCH`와 똑같은 방식으로 집어가 청구자 에이전트를 불러 문안을
짓는다. 정산 흐름 안에 별도 알림 진입점이나 청구자 에이전트 호출을 새로 만들지 않는다
— `receipt_id`가 있으니 스레드 답글도 §2 규칙대로 그대로 붙는다.

**검증은 `claims`의 `CONFIRMED → IN_RUN` CAS 전이(§7, `api/src/guards/` 소관) 이전에
끝나야 한다.** 순서를 뒤집어 먼저 점유부터 시키면, 검증에서 나중에 떨어진 claim이
어느 run에도 속하지 않으면서 `IN_RUN` + `settlement_run_id`를 들고 있는 상태가
생긴다 — 이건 `settled` 실패 시 되돌리기(§7)만 정의된 상태라 방치된다. 그래서
`POST /settlements/runs`는 후보를 **먼저 필터로 조회**하고, **검증해 탈락분을
제외**한 뒤, **그 살아남은 집합에 대해서만** CAS 트랜잭션을 연다.

**§5 계정과목 라우팅과는 독립된 축이다.** 검증은 `account_category_code`,
`category_source`를 건드리지 않는다. 파싱 시점의 2단계 게이트(§5)가 이미 끝난 뒤에
검증이 도니 순서를 다시 따질 필요는 없다 — 검증 통과 여부는 오직 "정산 후보에 넣을지"만
결정한다(§9).

**마이그레이션.** Firestore는 스키마리스이므로 DDL은 없다. `verified_at`·
`verification_signals`는 nullable/optional이라 기존 문서는 필드가 없는 채로도 유효하다.
`verified_at`이 없는 receipt는 "미검증"으로 취급되어 정산 후보 필터(§9)에서 자동
제외되고, `POST /settlements/runs`가 그 자리에서 검증을 돌려 채운다 — 별도 backfill
스크립트는 원칙적으로 불필요하다. 다만 데모용 fixture는 수정 금지(§0)라 검증
필드를 담고 있지 않으므로, C 시연 시나리오(fixture 07·08)가 이미 `settlement_runs`를
동반한 상태로 시딩되는 문제가 남는다 — `backend/scripts/seed_firestore.py`가 시딩
시점에 `status = PARSED`이면서 `parse_signals.injection_suspected`가 아닌 receipt에
통과 판정을 채워 넣어 우회한다. fixture 06(프롬프트 인젝션)은 이 보정에서 제외되어
계속 미검증 상태로 남는다 — claim·settlement_run이 없는 receipt라 다른 데모에
영향이 없고, 인젝션 탐지 시연 목적을 훼손하지 않는다.

**인프라 변경 없음.** `api` 서비스 계정은 이미 `roles/aiplatform.user`를 갖고 있다
(`backend/infra/iam.tf`, 파싱 호출과 동일 권한) — 검증 호출에 추가 IAM이 필요 없다.
새 Cloud Tasks 라우트가 없으므로 큐 설정도 그대로다. Terraform 변경 없음.

### `receipt_dedup_keys`

Slack 재전송으로 같은 영수증이 두 번 들어오는 걸 막는 유일한 장치다. 문서 ID가
`slack_file_id`이고, 그 자체가 유일성 제약이다.

| 필드 | 타입 | 비고 |
|---|---|---|
| `slack_file_id` | str | `F0123ABC`. **문서 ID로도 사용** |
| `receipt_id` | str | 이 파일로 만들어진 영수증 |
| `created_at` | Timestamp | |

**왜 `receipts`를 쿼리해서 막지 않는가.** Firestore 트랜잭션은 **읽어서 반환된
문서**에만 락을 건다. `slack_file_id == X` 쿼리가 0건을 돌려주면 잠글 대상이 없어서
동시 요청 두 개가 각각 "없음"을 보고 서로 다른 `rct_{ulid}`에 쓴다. 문서 ID가 다르니
충돌하지 않고 **둘 다 커밋된다.** 쿼리 기반 dedup은 동시 재전송에서 뚫린다.

반면 **결정론적 문서 경로에 대한 `transaction.get()`은 문서가 없어도 read set에
들어가 락이 걸린다.** 그래서 유일성은 반드시 문서 ID로 강제한다.

```python
def _txn(transaction):
    dedup_ref = client.collection("receipt_dedup_keys").document(slack_file_id)
    snapshot = dedup_ref.get(transaction=transaction)   # 없어도 잠긴다
    if snapshot.exists:
        return snapshot.get("receipt_id"), False        # 재전송
    receipt_id = f"rct_{ULID()}"
    transaction.set(dedup_ref, {...})                   # 읽기가 모든 쓰기보다 앞
    transaction.set(client.collection("receipts").document(receipt_id), {...})
    return receipt_id, True
```

**`receipts`의 문서 ID 규칙은 건드리지 않는다.** `receipts`는 계속 `receipt_id`를
문서 ID로 쓴다 — `backend/src/settlements/export.py`가 `.document(receipt_id).get()`으로
읽고 `backend/scripts/seed_firestore.py`·fixture 8종도 같은 규칙이라, `receipts` 문서
ID를 `slack_file_id`로 바꾸면 이미 배포된 XLSX 출력이 깨진다. 게다가 Slack이 아닌
경로(수동 등록·fixture)로 만든 영수증엔 `slack_file_id`가 없어 한 컬렉션에 ID 체계가
두 개 생긴다.

`receipt_id`를 dedup 문서에 함께 저장하는 이유는 재전송 경로가 **쿼리 없이 문서 직접
조회로** 끝나기 때문이다. `receipts.slack_file_id`에 인덱스가 필요 없어지고, 자동
인덱싱 설정에 dedup이 의존하지 않는다.

dedup 문서는 계속 쌓인다. 이 규모에서는 무시해도 되고, 정리가 필요해지면 TTL 정책을
건다 — 지우면 그 파일이 다시 인입될 수 있으므로 보존 기간은 Slack 재전송 창(수 분)이
아니라 넉넉히 잡는다.

### `claim_requests`

| 필드 | 타입 | 비고 |
|---|---|---|
| `claim_request_id` | str | `crq_{ulid}` |
| `recipient_id` | str | |
| `receipt_id` | str \| None | 영수증에 매이지 않는 사유가 있다. 아래 |
| `reason` | enum | **필수.** 왜 보내는지. 아래 |
| `slack_dm_ts` | str \| None | 버튼 응답을 원 메시지에 붙일 때 쓴다. 생성 시점엔 아직 DM 전이라 비어 있다 |
| `reminded_at` | Timestamp \| None | |
| `expires_at` | Timestamp | 생성 시각 + `CLAIM_REQUEST_TTL_SECONDS` |
| `status` | enum | `PENDING` / `REMINDED` / `RESPONDED` / `EXPIRED` |
| `created_at`, `updated_at` | Timestamp | |

전이: `PENDING → REMINDED → RESPONDED | EXPIRED`.
`PENDING → RESPONDED`도 가능하다(재촉 전에 응답).

#### `reason`

청구자에게 보내는 DM은 상황마다 문안이 다르다. **무엇을 보낼지 고르는 근거를 코드가
저장하고 에이전트가 읽는다.** 이 값이 없으면 에이전트가 상황을 추측해야 한다.

| 값 | 언제 | 문안 방향 |
|---|---|---|
| `PARSE_FAILED` | 영수증이 흐릿해 파싱 실패 (`receipts.status = FAILED`) | 다시 올려달라 |
| `AMOUNT_MISMATCH` | 영수증 금액과 청구 금액이 다름 (`receipts.status = NEEDS_REQUERY`) | 확인해달라 |
| `VERIFICATION_FAILED` | 이미지-파싱 결과 검증 실패 (`receipts.status = VERIFICATION_FAILED`) | 이미지와 내용이 안 맞으니 다시 확인해달라 |
| `MISSING_CLAIM` | 결제 기록은 있는데 청구가 없음 | 청구 안 했는지 묻는다 |
| `UNPAID_NOTICE` | 지급 결과 통지 — "10건 중 8건 지급, 2건 사유" | 재촉이 아니라 통지 |

`reason`은 **분기 근거이지 문안이 아니다.** 문안 자체는 청구자 에이전트가 만든다.
에이전트는 이 값을 읽기만 하고 쓰지 않는다 — 에이전트가 사유를 지어내는 경로는 없다.

`MISSING_CLAIM`과 `UNPAID_NOTICE`는 특정 영수증에서 출발하지 않는다. 전자는 결제 기록만
있고 영수증이 아직 없는 상태이고, 후자는 배치 결과 통지다. 그래서 **`receipt_id`가
nullable**이다. 나머지 두 사유는 반드시 `receipt_id`를 채운다.

`reason`은 필수다. 다만 §12 fixture 02·05의 `claim_requests`에는 이 필드가 없다 —
fixture는 수정하지 않는다(§0). 시딩 데이터가 계약보다 뒤처진 상태이고, **새로 만드는
문서에는 반드시 채운다.** 이 간극이 걸리면 fixture를 새로 추가해서 덮는다.

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

### `agent_sessions`

**절대 규칙 2의 예외가 아니다 — "에이전트끼리 직접 호출 금지"와는 별개 문제다.**
대신 architecture.md "하지 말 것"의 "Firestore SDK 직접 쓰기" 규칙에 대한 **범위가
좁혀진 예외**다: `agent` 서비스가 이 컬렉션 하나에 한해 `agent/shared/memory.py`를
통해 직접 읽고 쓴다. 다른 모든 Firestore 접근은 여전히 `api` 툴을 거친다.

**대상은 청구자·집행자 두 에이전트뿐이다.** 둘 다 같은 실행 단위(청구 요청 · 정산
실행)에 대해 반복 호출될 수 있어 이전 턴을 이어붙일 필요가 있다. 안전 확인 에이전트는
승인 직전 1회성 호출이라 이어갈 대화 자체가 없다 — 이 컬렉션을 쓰지 않는다.

| 필드 | 타입 | 비고 |
|---|---|---|
| `session_id` | str | `{agent_type}__{entity_id}`. 문서 ID로도 사용 |
| `agent_type` | enum | `CLAIMANT` / `EXECUTOR` |
| `entity_id` | str | `claimant`는 `claim_request_id`, `executor`는 `settlement_run_id` |
| `actor_ref` | str \| None | `recipient_id` 등 — 이전 세션 요약을 찾을 때 쓰는 연결 키 |
| `status` | enum | `ACTIVE` / `CLOSED` |
| `turns` | list[Turn] | 아래 |
| `summary` | str \| None | `CLOSED` 전환 시 코드가 생성 (LLM 아님, 아래 "요약" 참조) |
| `created_at`, `updated_at` | Timestamp | |

**`Turn`**

| 필드 | 타입 | 비고 |
|---|---|---|
| `turn_id` | str | ULID |
| `ts` | Timestamp | |
| `role` | enum | `INPUT` / `OUTPUT` |
| `content` | str | 원문 그대로 저장. `<untrusted_receipt_text>` 같은 래핑을 벗기지 않는다 |
| `untrusted` | bool | `content`가 영수증·Slack·파일명에서 왔으면 `true` |
| `doc_refs` | list[str] | 관련 Firestore 문서 ID (`claim_id`, `receipt_id` 등). 금액은 넣지 않는다 |

**요약은 코드가 만든다, LLM이 아니다.** 절대 규칙 3("금액 계산은 LLM이 하지 않는다")의
연장으로, 세션 요약도 자유 서술이 아니라 결정론적 템플릿으로 생성한다 —
`"{turn_count}턴, 관련 문서 {doc_refs}, 상태 {status}"` 형태. 이유: LLM이 요약을 쓰면
비신뢰 입력(인젝션된 영수증 문구)이 다음 세션에 "시스템이 이미 검토한 요약"이라는
더 신뢰받는 형태로 재유입될 수 있다 — 압축이 곧 검열 우회 경로가 된다.

**마이그레이션.** Firestore는 스키마리스이므로 DDL은 없다. 새 컬렉션이라 기존
문서 백필도 없다 — VLM 검증 필드 추가 때와 같은 패턴(§ `receipts` "마이그레이션" 참조).
배포 순서만 지키면 된다: Terraform IAM 적용(`agent` SA에 `datastore.user` 부여) →
`agent` 배포. 순서가 바뀌면 `agent`가 `PermissionDenied`로 즉시 실패한다 — 조용한
데이터 손실은 없다.

`find_prior_session_summary`(`agent_type` + `actor_ref` + `status` 동등 필터 3개 +
`updated_at` 정렬)는 복합 색인이 필요하다. Terraform엔 색인 리소스가 없으므로(이
프로젝트 관례) 첫 호출 시 Firestore가 콘솔 링크가 담긴 `FailedPrecondition`을
던진다 — 그 링크로 한 번 만들면 된다. 데모 전에 한 번 트리거해서 색인을 미리
만들어 둔다(콜드 색인 생성은 몇 분 걸릴 수 있다).

**IAM 한계.** Firestore Admin SDK(서버 SDK)는 Security Rules를 우회한다. 즉 프로젝트
IAM(`roles/datastore.user`)은 컬렉션 단위로 좁힐 수 없다 — `agent` SA는 이 권한을 얻는
순간 `agent_drafts`, `receipts` 등 다른 모든 컬렉션도 기술적으로 읽고 쓸 수 있게 된다.
"agent_sessions 컬렉션만 쓴다"는 코드 컨벤션(`agent/shared/memory.py`가 유일한 창구)과
코드 리뷰로 지키는 경계이지, IAM이 강제하는 경계가 아니다. 이 부분은 architecture.md
"신뢰 경계" 절의 예외로 명시해 둔다.

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
  └ 필터로 후보 claim 조회 (아직 점유 안 함)
  └ 후보 claim의 receipt마다 검증 (§2 "검증") — 미검증분만, 통과분은 캐시 재사용
  └ 검증 실패(VERIFICATION_FAILED) claim은 후보에서 제외
  └ claims CONFIRMED → IN_RUN (CAS 트랜잭션, 살아남은 후보만)
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

**집행자의 "후보 `claims` 목록"은 검증을 통과한 receipt에 물린 claim만 포함한다.**
연결된 `receipts.verified_at`이 `None`이거나 `status = VERIFICATION_FAILED`인 claim은
후보에서 코드가 미리 걸러내고 집행자 에이전트에게 넘기지 않는다 — "검증된 텍스트
데이터만 취합하는" 경계는 프롬프트가 아니라 후보 목록을 만드는 코드(`api/src/matching/`
또는 `api/src/settlements/`, B)가 지킨다.

안전 확인 에이전트의 `risk_report`는 `audit_logs.reason`에 그대로 저장된다.
**게이트가 아니다.** 이 리포트가 비어 있어도 승인과 송금은 코드 게이트만으로 진행된다.

### 세션 메모리 (청구자·집행자)

같은 `entity_id`(청구자는 `claim_request_id`, 집행자는 `settlement_run_id`)로 다시
호출되면 이전 턴이 이어진다 — 진입점(`agent/main.py`)이 호출 전 `agent_sessions`에서
현재 세션의 전체 턴 히스토리를 읽어 프롬프트에 포함시킨다. 같은 `actor_ref`(예:
동일 수취인)로 종료된 과거 세션이 있으면 그 요약도 함께 포함된다.

에이전트가 과거 세션의 **원문 전체**가 필요하면 `fetch_full_session` 툴을 호출한다.
평소엔 요약만으로 충분하므로 이 툴 호출은 선택이다 — `agent-tools.md`의 "툴 하나는
한 가지 일만" 원칙에 따라 이 컬렉션 관련 툴은 이 하나뿐이다. 턴 기록 자체는 툴이 아니라
진입점 코드가 호출 전후로 직접 `agent_sessions`에 쓴다(`agent/shared/memory.py`) —
LLM이 "기록을 남길지 말지"를 판단할 이유가 없는 순수 배관이라 툴로 노출하지 않는다.

세부는 §2 `agent_sessions` 참조.

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
FIRESTORE_DATABASE=development  # development | deploy — 로컬/테스트는 development, 실 배포는 deploy
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
| 9 | 파싱은 성공했지만 이미지-파싱 결과 불일치 (예: 사진엔 32,000원, 파싱은 35,000원) | 정산 실행 시 `VERIFICATION_FAILED` 전이, 집행자 후보 목록에서 제외 | B |

2번은 1단계(결정론적 신호), 4번은 2단계(confidence)를 각각 덮는다. 두 경로는 다르므로
둘 다 필요하다. 9번은 정산 시점 검증 전용이라 2·4번(파싱 시점)과 겹치지 않는다 —
fixture JSON과 `POST /settlements/runs`의 검증 호출 구현은 B가 채운다(§10 라우트
소유권과 동일).

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

