# `agent_sessions__{org_id}` 벡터 인덱스 생성 런북

`find_similar_sessions`(`agent/shared/memory.py`)가 Firestore 네이티브 벡터 검색
(`find_nearest`, COSINE)로 같은 org 내 닫힌 세션 중 유사 사건을 찾는다.

이 쿼리는 **복합 벡터 인덱스**가 있어야 동작한다. 인덱스가 없는 org에서는
Firestore가 `FAILED_PRECONDITION: no matching vector index`를 던지고, 코드는
이를 삼키고 `[]`로 폴백한다 — 에러는 안 나지만 기능이 inert다.

## 전제

- `agent_sessions` → `agent_sessions__{org_id}` 마이그레이션이 끝난 상태.
  `scripts/migrate_agent_sessions_v2.py`로 org별 컬렉션이 이미 만들어져 있어야
  한다(인덱스는 빈 컬렉션에도 만들 수 있지만, 후보 풀이 있어야 의미가 있다).
- `gcloud auth application-default login` 완료.
- 프로젝트: `payflow-hackathon-2026`, DB: `development`.

## 1. 인덱스 생성 대상 org 목록 확인

마이그레이션 결과로 생긴 컬렉션 이름을 보면 된다.

```bash
gcloud firestore collections list \
  --project=payflow-hackathon-2026 \
  --database=development \
  --filter="agent_sessions__"
```

또는 콘솔: Firestore > 데이터 > `development` DB > 컬렉션 그룹.

`agent_sessions__org_1`, `agent_sessions__unknown` 등이 나온다. 데이터가 있는
컬렉션마다 아래 인덱스를 하나씩 만든다. **org마다 따로 만들어야 한다** —
컬렉션명이 다르므로 컬렉션별 인덱스가 된다.

## 2. 복합 벡터 인덱스 생성 (org 하나당 1회)

`find_similar_sessions` 쿼리 구조(`shared/memory.py`):

```
.collection("agent_sessions__{org_id}")
  .where("agent_type", "==", ...)
  .where("status", "==", "CLOSED")
  .find_nearest(vector_field="summary_embedding", distance_measure=COSINE)
```

필요 인덱스 — 동등 필터 2개 + 벡터 필드 1개. 벡터 필드엔 차원을 명시해야
한다(`text-embedding-005` = 768차원).

```bash
ORG=org_1   # 대상 org_id로 교체. unknown 파티션은 ORG=unknown
gcloud firestore indexes composite create \
  --project=payflow-hackathon-2026 \
  --database=development \
  --collection-group="agent_sessions__${ORG}" \
  --field-config='[{"field-path":"agent_type","order":"ascending"},
                   {"field-path":"status","order":"ascending"},
                   {"field-path":"summary_embedding","vector-config":{"dimension":768,"flat":{}}}]' \
  --async
```

주의:
- gcloud의 `vector-config`는 `dimension`과 `flat` 키만 받는다(단순 `=vector`가 아님).
  JSON 배열 형태로 주면 확실하다. 차원을 모르면 콘솔에서 문서 하나를 열어
  `summary_embedding` 배열 길이를 세면 된다(현재 `text-embedding-005` = 768).
- 컬렉션명 그대로 쓴다. Firestore는 컬렉션 ID로 그룹화하므로
  `agent_sessions__org_1` 컬렉션 안의 모든 문서에 적용된다.

## 3. 생성 상태 확인 (비동기)

인덱스는 즉시 `READY`가 아니다. 수 분 소요.

```bash
gcloud firestore indexes composite list \
  --project=payflow-hackathon-2026 \
  --database=development
```

`agent_sessions__{org_id}` 행의 `state`가 `READY`가 될 때까지 대기. `CREATING`인
동안 `find_similar_sessions`를 호출하면 여전히 `FAILED_PRECONDITION` → `[]` 폴백.

## 4. 동작 확인

인덱스가 `READY`가 된 뒤, 닫힌 세션(`close_session`이 저장한
`summary_embedding` 포함)이 1건 이상 있는 org에서 의미 있는 쿼리를 던져본다.

```bash
# 닫힌 세션이 있는지 먼저 확인
gcloud firestore documents list \
  --project=payflow-hackathon-2026 \
  --database=development \
  --collection="agent_sessions__org_1" \
  --filter="status:CLOSED" \
  --limit=5
```

실제 동작 검증은 `claimant_review` / `executor_analyze` 엔드포인트를 한 번 이상
호출해 닫힌 세션을 쌓은 뒤, 같은 org의 새 요청에서 "관련 과거 사례" 블록에
과거 사건 요약이 주입되는지를 `agent` 로그로 확인한다.

## 5. `find_prior_session_summary` 복합 색인(벡터 아님)

`find_prior_session_summary`(`shared/memory.py`)는 같은 org·`actor_ref`의
닫힌 세션 중 최근 요약을 찾는다 — `claimant_review`(`main.py`)가 첫 호출일 때
`try`/`except` 없이 직접 부른다. 벡터 색인과 달리 `FAILED_PRECONDITION`를
삼키지 않으므로 색인이 없으면 엔드포인트가 500으로 떨어진다.

쿼리 구조:

```
.collection("agent_sessions__{org_id}")
  .where("agent_type", "==", ...)
  .where("org_id", "==", ...)
  .where("actor_ref", "==", ...)
  .where("status", "==", "CLOSED")
  .order_by("updated_at", DESCENDING)
  .limit(5)
```

필요 색인 — 동등 필터 4개 + 정렬 1개. **주의: org마다 따로 만든다** (컬렉션이
`agent_sessions__{org_id}`로 파티셔닝돼 있어 컬렉션별 색인이 된다).

```bash
ORG=unknown   # 대상 org_id로 교체
gcloud firestore indexes composite create \
  --project=payflow-hackathon-2026 \
  --database=development \
  --collection-group="agent_sessions__${ORG}" \
  --field-config='[{"field-path":"agent_type","order":"ascending"},
                   {"field-path":"org_id","order":"ascending"},
                   {"field-path":"actor_ref","order":"ascending"},
                   {"field-path":"status","order":"ascending"},
                   {"field-path":"updated_at","order":"descending"}]' \
  --async
```

`development` DB 현재 상태(2026-08-25):
- `agent_sessions__unknown` — 생성 완료, `READY`(`CICAgJim14AK`).
- `agent_sessions`(구 단일 컬렉션)에도 동일 색인이 있으나(`CICAgOjXh4EK`),
  v2 마이그레이션으로 데이터가 `agent_sessions__unknown`로 옮겨갔으므로
  구 컬렉션 색인은 닿지 않는다 — 신규 파티션마다 별도 생성이 필수다.

## 언제 다시 만드나

새 org가 생길 때마다(신규 조직 온보딩). 코드는 org 수를 모르므로 자동으로
만들지 않는다 — 온보딩 절차에 이 런북 1회 실행을 포함시킨다. **위 §2 벡터
색인과 §5 `find_prior_session_summary` 색인 둘 다** 만들어야 한다.

`find_similar_sessions`의 필터(`agent_type`, `status`)나 벡터 필드
(`summary_embedding`)가 바뀌면 §2 인덱스 정의도 같이 바꿔야 한다.
`find_prior_session_summary`의 필터·정렬이 바뀌면 §5 정의도 같이.
