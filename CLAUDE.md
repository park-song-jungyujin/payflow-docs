# Payflow — 공통 규칙

3인 스타트업용 지출 정산 에이전트. 영수증/PayPal 원장을 대조해 정산안을 만들고,
사람이 승인하면 PayPal Payouts로 일괄 송금한다.

## 레포 구성

| 레포 | 런타임 | 배포 | 시크릿 |
|---|---|---|---|
| `payflow-frontend` | Next.js / TS | Cloud Run | 없음 |
| `payflow-backend` | FastAPI / Python | Cloud Run | PayPal, Slack |
| `payflow-agent` | ADK / Python | Cloud Run | 없음 (Vertex는 ADC) |
| `docs` | — | — | — |

이 레포는 각 레포에 submodule로 붙는다. 각 레포 루트 `CLAUDE.md`는 얇게 두고
여기 `rules/`를 참조한다.

## 해커톤 제약

공식 페이지: https://allthingsagentichackathon.devpost.com/ · 상세: [docs/about_hackathon.md](docs/about_hackathon.md)

필수 조건 4개 — 하나라도 빠지면 심사 대상이 아니다: **Gemini 3.5 이상**, **Google Agent
Framework 최소 1개**(ADK 등), **Google Cloud 서비스 최소 1개**, **자율 Agent**(단순
chatbot 구조는 탈락 사유). 제출물(README, description, demo video)은 **영어**여야 한다.
**최종 마감: 2026-09-01 09:00 KST**.

심사 비중: Innovation & Operational Utility 40% / Architecture & Tech Stack 30% /
Demo & Production Readiness 30%. → 기능을 늘리기보다 **"Agent가 실제로 행동한 증거"**
확보에 시간을 쓴다.

## 절대 규칙 3개

나머지를 다 잊어도 이건 지킨다.

1. **`payflow-agent`는 PayPal 자격증명에 접근하지 않는다.** 코드가 아니라 IAM으로 막혀 있다.
   에이전트가 하는 일은 "정산안 문서를 쓰는 것"이지 "돈을 보내는 것"이 아니다.
2. **승인 토큰 없이 송금 엔드포인트는 실행되지 않는다.** 토큰은 LLM 컨텍스트에
   절대 들어가지 않는다.
3. **금액 계산은 LLM이 하지 않는다.** LLM은 판단 근거를 서술하고, 숫자는 코드가 만든다.

## 규칙 인덱스

- [`docs/rules/architecture.md`](docs/rules/architecture.md) — 서비스 책임, 호출 방향, 신뢰 경계
- [`docs/rules/money-safety.md`](docs/rules/money-safety.md) — 멱등성, 승인 게이트, 금액 표현
- [`docs/rules/schema-contract.md`](docs/rules/schema-contract.md) — 폴리레포 스키마 동기화
- [`docs/rules/agent-tools.md`](docs/rules/agent-tools.md) — ADK 툴 작성 규칙
- [`docs/rules/workflow.md`](docs/rules/workflow.md) — 커밋, 크로스레포 변경 순서

## 문서 작업 규칙

무엇을 하든 기록을 남긴다.

- **작업 일지**: `docs/journal/YYYY-mm-dd.md` — 그날 진행한 작업 정리. 파일이 있으면 이어서 추가.
- **요약 테이블**: `docs/SUMMARY.md` — 작업을 큰 범주로 묶어 한 줄 추가 (`YYYY-mm-dd | 요약`).
- **사용자 보고서**: `docs/reports/`에 단일 `.html` 파일로. 스타일은 전역
  `~/.claude/rules/report-rule.md`를 따른다.
- 모든 마크다운 문서는 **200줄을 넘기지 않는다.** 넘으면 `원본-1.md`, `원본-2.md`로
  분리하고, 원본에는 분리된 파일 참조만 남긴다.

## 코딩 태도

- 요청된 것만 구현한다. 투기적 추상화 금지.
- 기존 코드 스타일에 맞춘다. 인접 코드를 "개선"하지 않는다.
- 불확실하면 멈추고 묻는다. 조용히 하나 골라서 진행하지 않는다.
- 해커톤이다. 동작하는 200줄이 아름다운 500줄을 이긴다.
