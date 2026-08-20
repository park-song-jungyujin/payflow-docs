# 작업 요약

작업 내역을 큰 범주로 묶은 요약 표. 상세 기록은 [`journal/`](journal/) 참조.

| 날짜 | 작업 |
|---|---|
| 2026-08-16 | 문서 기반 구축 — 기획 README, 개발 규칙 5종, 레포별 `CLAUDE.md` 및 `docs` submodule 연결. 마크다운 200줄 제한은 `CLAUDE.md`에만 적용하도록 축소. 3인 병렬 구현 계획(`plan.md`) 작성 — 에이전트 3분할 결정. D1 착수 준비 완료 — 결정 8건 확정, 규칙 4곳 갱신, 회의록 아카이빙, 진행 현황 표시 |
| 2026-08-16 | GCP 프로젝트(`payflow-hackathon-2026`) 부트스트랩 — Terraform·uv·ADC·API 4종·Firestore(서울) 세팅을 `docs/infra/gcp-bootstrap.sh`로 스크립트화. 스키마 계약 초안(`docs/schema-contract-draft.md`) 작성 — 전원 합의 대기 |
| 2026-08-16 | 스키마 계약 확정본을 `rules/schema-contract.md`에 반영, `rules/` 나머지 4종과 대조해 `agent-tools.md`·`money-safety.md` 불일치 2건 수정 |
| 2026-08-16 | `backend/.env` 생성. `payflow-api` FastAPI 스텁을 비공개 Cloud Run에 배포하고 Cloud Tasks OIDC 관통(403→200) 확인 |
| 2026-08-16 | PayPal 샌드박스 payout 멱등성 확인 — 동일 `sender_batch_id` 재전송은 400 에러로 거부되어 중복 송금 없음을 검증 |
| 2026-08-16 | Track A 스키마 초안을 확정본에 병합하고 폐기 — 문서 단일화. PayPal ID 길이 정정(`sender_item_id` 상한 63자, 확정본 형식은 70자로 초과) 및 Track A 델타 3건 제안 |
| 2026-08-16 | D1 착수 블로커 5개 해소 — 트랙 배정(A 정유진 · B 박수현 · C 송재훈), GCP 결제 연결, PayPal Sandbox·Slack 계정 발급 완료. `plan.md`·`README.md` 미결 표를 남은 항목만으로 정리 |
| 2026-08-16 | S0 통과 확인 — `payflow-backend`에 `src/schemas/` Pydantic 모델과 `v0.1.0` 태그. `sender_item_id` 길이 제약은 미구현이라 형식 변경 비용이 아직 0 |
| 2026-08-17 | `backend`·`agent` 디렉터리 소유권 스캐폴딩 커밋. `CLAUDE.md` 문서 작업 규칙에 "매 작업 종료 시 즉시 반영" 트리거 명시 |
| 2026-08-17 | 데모 fixture 8종 작성 (`backend/tests/fixtures/`) — 스텁 엔드포인트와 최종 데모가 공유할 골든 패스·오류·403·PayPal 혼재 시나리오 |
| 2026-08-17 | `guards`·`payouts` 스텁 라우트 + 승인 토큰 403 게이트 구현 (`feat/guards-payouts-stub` 브랜치) — DRAFT→APPROVED→EXECUTING CAS, 한도 캡 3종, 감사 로그, TestClient로 8개 경로 검증 |
| 2026-08-17 | `sender_item_id` 길이 초과(70자 > 상한 63자) 해소 — `settlement_run_id`를 축약형(`run_{yymmdd}_{ULID 앞 12자}`)으로 확정, `rules/schema-contract.md`·`plan.md`·`README.md`·fixture 5개 일괄 반영 |
| 2026-08-17 | `/tasks/execute-payout`에 PayPal Payouts 실제 호출 + 멱등성 구현 (`feat/paypal-payout-call` 브랜치) — 결정론적 `sender_batch_id`/`sender_item_id`, minor→PayPal 문자열 변환, `/payouts`는 Cloud Tasks 미구성 시 명시적 실패로 전환 |
| 2026-08-17 | `/tasks/reconcile`·`/webhooks/paypal` 지급 결과 대조 구현 (`feat/paypal-reconcile-webhook` 브랜치) — SUCCESS/FAILED 종결 판정, claim·monthly_paid_minor 롤백, max attempts 강제 종결. `/payouts`에 빠져 있던 monthly_paid_minor 예약 가산도 같이 메꿈 |
| 2026-08-17 | C 트랙(guards·payouts) Firestore 연동 — 인메모리 fixture를 실 Firestore로 교체, CAS 트랜잭션 2곳, `scripts/seed_firestore.py` 추가, execute-payout 이름 충돌 버그 수정 |
| 2026-08-17 | Firestore DB를 `(default)` 단일에서 `dev`/`deploy` 2개로 분리 — 부트스트랩 스크립트에 생성·재시딩 명령 추가, 코드·문서 기본값 갱신 |
| 2026-08-17 | (hotfix) `dev`→`development` 개명(Firestore ID 4자 제약) 후 `development`·`deploy` DB 실제 생성, fixture 재시딩. 부트스트랩 스크립트 `PYTHONPATH` 누락 버그 수정 |
| 2026-08-17 | `backend/infra/`에 Terraform 작성(Cloud Run 3·Firestore·Cloud Tasks·Secret Manager·IAM) — 이미 떠 있던 리소스를 import로 편입, `payflow-api`를 default compute SA(roles/editor)에서 전용 SA로 마이그레이션, GitHub Actions CI(WIF keyless) 추가, `gcp-bootstrap.sh`를 로컬 셋업·시딩 전용으로 축소 |
| 2026-08-17 | IAM 격리(절대 규칙 1) 라이브 재검증 — 드리프트 없음, 4개 시크릿 모두 `payflow-agent` 바인딩 없음 확인. 심사 시연용 403 데모 절차를 `docs/infra/iam-403-demo.md`로 문서화(정적 조회 + 임시 impersonate 캡처 2가지 방법) |
| 2026-08-17 | 방법 B 실제 실행 — `agent` SA에 임시 impersonate 권한 부여 → PayPal 시크릿 접근 시도해 실제 `PERMISSION_DENIED` 캡처 → 즉시 회수·재확인. `iam-403-demo.md`에 실제 에러 문구 반영 |
| 2026-08-17 | `DRAFT→APPROVED`·`APPROVED→EXECUTING` CAS 동시성 라이브 검증(각 5개 동시 요청, 1개만 통과 확인) 중 `/payouts` 500 버그 발견 — Cloud Tasks enqueue 미구현(`NotImplementedError`)이 큐 프로비저닝 후 노출된 것. 실제 enqueue 구현 + IAM 2건 추가로 수정, 재검증 완료(PR #5) |
| 2026-08-17 | PayPal/Slack 시크릿 4개를 Cloud Run `payflow-api` env로 실제 주입 — `secret_key_ref` Terraform 추가, 시크릿 실값 최초 등록, Cloud Run 서비스 에이전트 IAM 바인딩 누락 발견해 추가 |
| 2026-08-17 | SLACK_BOT_TOKEN 재발급 반영, execute-payout 실검증 중 PayPal이 KRW 통화를 지원 안 함을 발견 |
| 2026-08-17 | PayPal 지원 통화 검증 + 승인 시점 FX 환산(schema-contract.md §4) 구현, 캡 검사 미환산 버그도 수정 (PR #6) |
| 2026-08-17 | `plan.md` Track C 체크박스를 실제 상태로 정리 — api·인프라 12개 완료 처리, S1 동기화 지점 통과 표시. 미착수(`before_tool_callback`, 안전 확인 에이전트)는 agent 레포 담당으로 남겨둠 |
| 2026-08-17 | 안전 확인 에이전트 + before_tool_callback 신규 구현 — `agent` 레포 서비스 스캐폴드 최초 작성, backend에 agent_drafts 쓰기 엔드포인트 추가. 두 레포 PR로 올림(agent#1, backend#7) |
| 2026-08-17 | agent#1·backend#7 머지 확인, `plan.md` 진행 현황 재점검 — Track C 체크박스·코드 상태 표·다음 액션을 실제 상태로 갱신 |
| 2026-08-17 | XLSX 출력(세무사용, 계정과목 컬럼 포함) 구현 — `GET /settlements/runs/{run_id}/export`, `openpyxl` 의존성 추가 |
| 2026-08-18 | 스키마 계약 v0.2.0 — Track A 델타 1·2 반영. `claim_requests.reason`(필수 enum 4값) 추가 및 `receipt_id` nullable 완화, `receipts.slack_channel_id`·`slack_message_ts`(nullable) 추가. 문서 → `backend/src/schemas/` → 태그 순으로 반영, `agent` 핀·`web` 타입 재생성은 대기 |
| 2026-08-18 | 스키마 계약 v0.3.0(안) — 영수증 이미지 검증 단계 추가. 정산 실행 시(`POST /settlements/runs`) 파싱과 별개인 Gemini 단발 호출(이미지당 1회)로 이미지-파싱 일치를 판정, 통과분만 집행자 후보에 포함. 청구자 에이전트의 인입 시점 검토와는 다른 별도 게이트. `receipts.verified_at`·`verification_signals`·`VERIFICATION_FAILED` 상태 신설. `seed_firestore.py`에 fixture 검증 보정 추가. 인프라 변경 없음(기존 IAM·큐 재사용). 구현·fixture 9는 B 담당으로 남김, 아직 `schema:` 커밋·태그 전 |
| 2026-08-18 | 청구자·집행자 세션 메모리(`agent_sessions`) 신설 — 같은 실행 단위 반복 호출을 이어받는 구조. `agent`가 이 컬렉션 하나에 한해 Firestore를 직접 쓰는 명시적 예외 도입, 요약은 LLM이 아니라 코드가 생성(인젝션 재유입 방지). `agent/shared/memory.py`·`memory_tools.py` 구현, `backend/infra/iam.tf`에 `agent` SA `datastore.user` 추가, 3개 rule 문서 갱신 |
| 2026-08-18 | 스키마 계약 v0.4.0 — Slack 인입 시점 필드. `receipts.slack_file_id`(재전송 dedup 키) 신설, 파싱 결과 필드 5개와 `claim_requests.slack_dm_ts` nullable 완화 — `RECEIVED`(파싱 전) 상태의 유효한 문서를 만들 수 없던 문제. `receipts.currency`가 nullable이 되어 B의 결정론적 매칭에 영향 |
| 2026-08-18 | Slack 인입 경로 착수 — 계획서 작성 후 Task 2(v0 서명 검증, raw body 기준·5분 skew) 구현. 레포에 없던 pytest 하네스(`dev` 의존성 + `tests/conftest.py`)를 함께 세움. non-ASCII 서명 헤더가 401 대신 500이 되어 Slack 재전송을 유발하던 버그 수정. C의 Cloud Tasks enqueue 일반화(`guards/tasks.py`, PR #8) 수신 |
| 2026-08-19 | Slack 인입 경로 구현 완료 — Task 3(`receipts` 인입 창구, dedup 트랜잭션) · Task 5(`POST /slack/events`) · Task 4(enqueue를 `guards/tasks.py`에 연결). 쿼리 기반 dedup이 동시 재전송에서 뚫리는 것을 발견해 `receipt_dedup_keys/{slack_file_id}` 문서 ID 강제로 교체, `ReceiptStoreUnavailable`로 예외 범위 축소, `MAX_FILES_PER_EVENT=5` 상한(초과분은 버리지 않고 `RECEIPT_INGEST_DEFERRED`). Task 6(OpenAPI 스냅샷) 미착수 |
| 2026-08-19 | Slack 인입 경로 3초 예산 재측정 — enqueue를 `guards/tasks.py`에 연결하고 `MAX_FILES_PER_EVENT=5` 상한을 넣은 뒤 재측. 전체 37 passed/3.88s, 예산 테스트 0.77s(주입 0.75s → 라우트 자체 0.02s), 파일당 400ms 최악에서 2.02s로 예산의 67%. n≥5에서 평평해져 계획서 표의 3초 초과 칸이 사라짐. 다만 예산의 enqueue 항은 여전히 sleep 가정 — 실경로는 테스트에서 monkeypatch·`CLOUD_TASKS_QUEUE` 미설정으로 한 번도 안 돌아 배포 후 로그 확인 필요 |
| 2026-08-19 | 영수증 원본 GCS 버킷(`receipts`) 프로비저닝 — 이미 apply되어 있었지만 커밋이 빠져 있던 `infra/storage.tf`·`cloud_run.tf`·`outputs.tf`를 `main`에 반영, Track A의 raw 이미지 업로드 경로를 언블록. `GCS_RECEIPTS_BUCKET`을 `schema-contract.md` §11에 추가 |
| 2026-08-19 | Track B 부재 대응 — `GET /settlements`·`POST /settlements/runs`·`GET /settlements/runs/{run_id}` 하드코딩 스텁(매칭·검증 없이 스키마만), `payflow-frontend`에 최소 Next.js + 승인 게이트 버튼 1개(BFF 프록시로 approve 호출). 나머지는 `TODO(B)` 주석 |
| 2026-08-19 | `payflow-frontend` 배포 파이프라인 — backend에 frontend 전용 WIF provider·`payflow-web-deployer` SA 격리 추가, GitHub Actions는 build/typecheck/lint/test 통과해야 Cloud Run 배포. vitest 도입 및 승인 프록시 테스트 3종 작성 |
| 2026-08-19 | 정산 배치 스텁에 실제 claims 연결 — `matching/select_claims_for_run`(TEMP, 필터링만) 신설, `POST /settlements/runs`가 후보 claims를 배치에 링크하도록 교체 |
| 2026-08-19 | `payflow-frontend` 배포 실패 해소 — 커밋만 되고 미적용이던 `ci_web.tf` WIF/IAM 9종 apply. Cloud Run 3서비스의 `gcloud deploy` drift(client·build_config·top-level scaling)를 `ignore_changes`로 고정, `agent_datastore` IAM·`web` `API_BASE_URL` env 등 남은 변경 apply |
| 2026-08-19 | `payflow-agent` 배포 파이프라인 신설 — Dockerfile·CI 부재로 방치돼 있던 Cloud Run 서비스를 언블록. `uv sync --frozen` 기반 Dockerfile, `ci_web.tf`와 동일 패턴의 `ci_agent.tf`(WIF·`payflow-agent-deployer` SA 격리), `deploy.yml`. claimant/executor 도메인 로직(Track A/B)은 손대지 않음 |
| 2026-08-20 | `docs/reports/` 다이어그램 리포트 정리 — 기존 2개 파일 가로 배치 레이아웃 수정, `cicd-infra-diagrams.html` 신설(push→CI/CD→Cloud Run 3서비스→GCP 인프라→사용자 접점을 구현 상태 색상과 함께 정리) |
| 2026-08-20 | `payflow-backend` CI에 pytest 게이트 추가, money-safety 핵심(멱등성/승인 토큰/한도) 단위 테스트 21종 신규 |
| 2026-08-20 | `payflow-agent` 테스트 인프라 신설(pytest 부재였음) — CI 게이트, 툴/api_client/callbacks/memory 단위 테스트, 스키마 계약 테스트, LLM 미호출 파이프라인 테스트 총 40종 |
