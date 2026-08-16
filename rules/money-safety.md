# 돈 관련 불변식

이 파일의 규칙은 협상 대상이 아니다. 어기면 이중 지급이 난다.

## 금액 표현

- 내부 전역에서 **정수 minor unit**을 쓴다. `1200.50 USD` → `{amount_minor: 120050, currency: "USD"}`.
- `float`로 금액을 다루지 않는다. JSON 직렬화 포함.
- PayPal 경계에서만 문자열 소수로 변환한다. 변환 함수는 한 곳에만 존재한다.
- 통화 없는 금액 필드를 만들지 않는다. 항상 붙어 다닌다.

## 멱등성

PayPal Payouts의 `sender_batch_id`에 **`settlement_run_id`를 그대로 넣는다.**

```python
sender_batch_header = {"sender_batch_id": run_id}
```

매번 새 UUID를 만들면 네트워크 타임아웃 한 번에 두 번 나간다. Cloud Run은
요청 재시도가 있으므로 이건 가정이 아니라 실제로 일어난다.

`sender_item_id`도 마찬가지로 결정론적으로 만든다. `f"{run_id}:{recipient_id}"`.

## 승인 게이트

```
draft → approved → executing → settled | failed
```

- `draft → approved` 전이는 **Firestore 트랜잭션 안에서 CAS로** 처리한다.
  이미 `approved` 이상이면 거부한다. 승인 버튼 두 번 눌러서 두 번 나가는 걸 막는 유일한 방어다.
- 승인 토큰은 `run_id` + 금액 해시에 바인딩한다. 다른 run에 재사용 불가.
- 토큰은 단기 만료(10분). 승인 후 즉시 소각.
- **승인 토큰이 LLM 프롬프트나 툴 인자에 들어가면 안 된다.** 리뷰에서 이것만은 본다.

## 송금 실행

- 승인 응답에서 PayPal을 **동기 호출하지 않는다.** `executing` 마킹 후 Cloud Tasks로 위임.
- 상태 갱신은 webhook 또는 폴링. 배치 상태와 건별 상태를 모두 기록한다.
- 실패/`UNCLAIMED` 건은 취소 후 재발송 제안까지가 한 사이클이다.

취소 가능 범위를 오해하지 말 것: **PayPal Payouts는 `UNCLAIMED` 상태에서만 취소된다.**
수취인이 이미 수령한 건은 API로 회수할 수 없다.

## 한도

`api`에서 하드 캡을 건다. 환경변수, 코드 상수 아님.

- 1회 배치 총액 캡
- 건별 캡
- 월간 누적 캡

캡 초과 시 에이전트에게 되묻지 않는다. 거부하고 사람에게 올린다.

## 감사 로그

모든 툴 호출과 상태 전이를 `audit_logs`에 남긴다. 최소 필드:

```
{ts, actor: "agent"|"user"|"system", action, run_id, before, after, reason}
```

`reason`에는 LLM이 쓴 판단 근거 원문을 그대로 넣는다. 요약하지 않는다.
"왜 이 금액이 나왔는가"를 나중에 재구성할 수 있어야 한다.

## PII 마스킹

영수증 파싱 결과를 Firestore에 쓰기 **전에** 마스킹한다. 원본은 GCS에만.
카드번호, CVC, 주민등록번호, 여권번호. 마스킹 함수는 파싱 파이프라인 안에 둔다.
