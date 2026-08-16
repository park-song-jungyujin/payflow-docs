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
