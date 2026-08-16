# 스키마 계약

폴리레포에서 가장 잘 터지는 지점이다. 규칙이 없으면 해커톤 마지막 날
"프론트에서 금액이 undefined로 뜬다"로 두 시간을 쓴다.

## 단일 소스

**`api` 레포의 Pydantic 모델이 유일한 진실이다.**

```
api/src/schemas/*.py          ← 여기서만 정의
   │
   ├─► OpenAPI JSON  ─────► web (TS 타입 생성)
   └─► Python 패키지 ─────► agent (직접 import)
```

`web`이나 `agent`에서 정산 모델을 따로 정의하지 않는다. 필드 하나 추가하고
싶으면 `api`부터 고친다.

## `web` — 타입 생성

수기로 인터페이스를 쓰지 않는다. `api`가 뱉은 OpenAPI로 생성한다.

```bash
# api 로컬 실행 후
npx openapi-typescript http://localhost:8080/openapi.json -o src/types/api.d.ts
```

생성 파일은 커밋한다. 손으로 편집 금지. 상단에 생성 명령을 주석으로 남긴다.

## `agent` — Python 패키지 공유

`agent`는 `api`의 스키마를 git dependency로 당긴다.

```
# agent/pyproject.toml
dependencies = ["settlement-schemas @ git+ssh://...api.git@<tag>#subdirectory=src/schemas"]
```

**커밋 해시나 태그로 핀한다. `main` 브랜치를 가리키지 않는다.** 해커톤 중
`api` 쪽에서 필드 바꿨는데 `agent` 배포가 조용히 깨지는 게 이 규칙이 막는 사고다.

## 계약 테스트

`api`에 스냅샷 테스트를 하나 둔다.

```python
def test_openapi_snapshot():
    assert app.openapi() == json.load(open("tests/openapi.snapshot.json"))
```

스키마를 의도적으로 바꿨다면 스냅샷을 갱신하고, 커밋 메시지에
`schema:` 접두사를 붙인다. 다른 레포가 따라와야 한다는 신호다.

## 변경 순서

스키마를 건드리는 변경은 반드시 이 순서다.

```
1. api    스키마 수정 + 스냅샷 갱신 + 태그
2. agent  의존성 핀 올림 → 테스트 통과 확인
3. web    타입 재생성 → 빌드 통과 확인
```

역순으로 하면 `web`이 존재하지 않는 필드를 참조하는 상태로 커밋된다.

## 나가는 필드 최소화

`api → web` 응답에 Firestore 문서를 통째로 실어보내지 않는다. 응답 모델을
따로 정의한다. 내부 필드(승인 토큰, 원본 PII, 내부 상태 플래그)가 브라우저까지
가는 걸 막는 게 목적이다.

`api → agent` 툴 응답도 마찬가지다. 에이전트가 알 필요 없는 필드는 빼고 준다.
컨텍스트 절약이 아니라 인젝션 표면 축소가 이유다.
