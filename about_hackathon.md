## 0. 가장 먼저 결론

이 해커톤에서 제일 중요한 조건은 딱 4개야.

> **① Gemini 3.5+ 사용
② Google Agent Framework 사용
③ Google Cloud 인프라 사용
④ 단순 챗봇이 아니라 실제로 자율적으로 행동하는 Agent**
> 

그리고 **제출물의 완성도보다 더 중요한 게 "실제로 Agent가 행동하는 모습을 증명하는 것"**이야.

심사 비중도

- **Innovation & Operational Utility 40%**
- **Architectural Discipline & Tech Stack 30%**
- **Demo & Production Readiness 30%**

이라서, 예쁜 UI보다 **"이 문제가 진짜 귀찮고 → Agent가 알아서 처리하고 → 그 과정이 기술적으로 잘 설계되어 있고 → 영상에서 실제 실행이 보이는가"**가 핵심이야.

---

# 1. 참가 자격 — 한국에서 참가 가능?

### 한국은 참가 가능

현재 규정에서 참가 제한 국가는

> 이탈리아, 퀘벡, 크림반도, 쿠바, 이란, 시리아, 북한, 수단, 벨라루스, 러시아 및 미국의 제재 대상 국가/지역
> 

등으로 되어 있어 **대한민국은 제한 국가가 아니야.**

기본적으로:

- 거주 국가의 성년 연령 이상
- 인터넷 접속 가능
- 미국 수출통제/제재 대상자가 아닐 것

등의 조건을 만족하면 돼.

### 팀 구성

**개인 / 팀 / 조직 모두 가능**하고, 팀이라면 모든 팀원이 참가 자격을 갖춰야 하며 **Devpost 프로젝트에 팀원으로 등록되어 있어야 해.** 대표자 1명도 지정해야 해.

---

# 2. 기간 — 한국 시간으로

공식 규정의 시간은 Pacific Time 기준이야.

| 일정 | 미국 PT | 🇰🇷 한국 |
| --- | --- | --- |
| 시작 | 8/3 09:00 | **8/4 01:00** |
| 제출 시작 | 8/3 09:00 | **8/4 01:00** |
| 🔥 제출 마감 | 8/31 17:00 | **9/1 09:00** |
| 심사 | 9/1 ~ 10/1 | **9/2 ~ 10/2** |
| 결과 발표 | 10/8 10:00 PT | **10/9 02:00 KST** |

즉 **한국 기준 최종 마감은 9월 1일 오전 9시**야. 공식 규정도 참가자가 자신의 지역 시간대를 직접 확인할 책임이 있다고 명시하고 있어.

---

# 3. 🚨 가장 중요한 기술 필수조건

이건 **보너스가 아니라 필수**야.

모든 카테고리에서 반드시:

### ① Gemini 3.5 이상

**Gemini API 또는 Vertex AI를 통해 Gemini 3.5 이상**을 사용해야 해.

### ② Google Agent Framework 최소 1개

다음 중 **최소 하나**:

- Google ADK
- GenAI SDK
- Antigravity SDK
- GenKit 3

### ③ Google Cloud 인프라 최소 1개

예:

- Cloud Run
- Cloud SQL
- Firestore
- GKE
- Pub/Sub

등.

즉 최소한 구조가

```
User
 ↓
Frontend
 ↓
Backend ─────→ Gemini 3.5+
 ↓
Google Agent Framework
 ↓
Google Cloud Service
```

형태가 되어야 한다고 보면 돼.

---

# 4. 단순 Chatbot이면 안 됨

공식 설명에서 굉장히 강하게 강조하는 부분이야.

단순히

> User → 질문 → Gemini → 답변
> 

이런 구조는 **이 해커톤이 원하는 핵심과 거리가 멀어.**

요구하는 것은 **autonomous AI Agent**이고,

- 백그라운드에서 비동기적으로 실행
- 복잡한 workflow 수행
- 데이터 pipeline 조작
- 여러 단계를 스스로 처리

같은 행동이 필요해.

특히 심사에서도 **simple chat queries보다 autonomous execution을 높게 평가**한다고 명시돼 있어.

# 5. 세 카테고리 중 반드시 하나 선택

### 🥇 Taskmaster

**"AI가 일을 대신 끝내주는 것"**

예:

```
사용자:
"이번 주에 해야 할 업무들 정리해서 처리해줘."

Agent:
→ 이메일 확인
→ 필요한 정보 추출
→ 문서 작성
→ 캘린더 확인
→ 관련 사람에게 메시지
→ 결과 보고
```

핵심은 **multi-step workflow + 실제 action**.

단순히 답변을 생성하면 안 되고 실제로 행동해야 해.

---

### 🤝 Collaborative Partner

AI가 사용자를 계속 도와주면서 **사용자의 작업 방식을 학습/적응**하는 형태.

필수적인 느낌은:

```
질문
 ↓
사용자 답변
 ↓
Agent가 다음 단계 안내
 ↓
Feedback 저장
 ↓
다음 작업에서 반영
```

즉 **clarifying questions + step-by-step guidance + feedback + personalization**이 중요해.

---

### 🏢 Fortified Enterprise Fleet

가장 기술적으로 무거운 카테고리.

기업 내부 여러 Agent를 관리하는 **Agent Platform / Agent Infrastructure**에 가까워.

공식적으로 요구하는 개념이:

**Agent Registry**

- Agent 등록
- 버전 관리
- 검색/발견

**Agent Runtime**

- 장시간 실행
- 비동기 background execution

**Memory Bank**

- 장기간 context 유지
- cross-session memory

**Agent Identity**

- Zero-trust access control

**Agent Gateway**

- routing
- policy enforcement

**Model Armor**

- prompt injection
- tool poisoning
- PII leak 방어

**Agent Observability**

- OpenTelemetry audit log
- end-to-end trace

까지 들어가 있어.

그래서 **짧은 해커톤에서 Enterprise Fleet를 제대로 구현하는 난이도는 상당히 높아.**

---

# 6. ⭐ 프로젝트는 "Submission Period 동안 새로 만들어야 함"

이거 중요해.

공식적으로:

> **Projects must be newly created during the Submission Period.**
> 

즉 **8월 3일 이후부터 제출 기간 안에 만든 프로젝트**여야 해.

다만 기존 개발 도구는 사용할 수 있어.

허용되는 것:

- framework
- library
- starter template
- AI coding assistant

등.

그리고 기존 코드나 작업물을 프로젝트에 포함했다면 **그 사실을 공개해야 한다**고 되어 있어.

따라서 예전에 만들어 놓은 프로젝트를 그대로 제출하는 건 위험하고,

> 기존 프로젝트의 아이디어/기술을 기반으로 하되 **이번 Submission Period에 새로운 프로젝트로 개발**
> 

하는 식이 안전해.

---

# 7. 오픈소스 / 외부 API 사용 가능?

가능해.

다만:

- 라이선스 준수
- 사용할 권리가 있어야 함
- 제3자의 IP/개인정보/저작권 침해 금지

조건이 있어.

즉

```
Gemini
+ Open-source library
+ GitHub library
+ 외부 API
+ Google Cloud
```

같은 구성 자체는 문제없어.

# 8. 제출할 때 반드시 필요한 것

## 필수 제출물

### ① Category

세 카테고리 중 하나 선택.

---

### ② Hosted Project URL

웹사이트 / Chrome Extension / Mobile App 등.

**강력 권장**이지만 "if available"이라서 모든 형태에서 절대적 필수는 아니야.

다만 실제 심사에 상당히 유리하니까 **가능하면 반드시 배포하는 걸 추천.**

---

### ③ Text Description

반드시 다음 내용을 포함:

- 문제
- 기능
- 사용 기술
- 외부 데이터 소스
- 프로젝트를 만들며 얻은 findings / learnings

---

### ④ GitHub / GitLab / Bitbucket

Public 또는 Private 모두 가능.

Private이면:

- testing@devpost.com
- cloudhackathons@google.com

에 접근 권한을 줘야 해.

---

### ⑤ README

**Spin-up Instructions 필수**

즉 다른 사람이

```
git clone
npm install
.env 설정
DB 설정
npm run dev
```

등으로 재현할 수 있도록 설명해야 해.

---

### ⑥ Architecture Diagram

필수.

예:

```
                  ┌──────────────┐
                  │    User      │
                  └──────┬───────┘
                         ↓
                  ┌──────────────┐
                  │  Frontend    │
                  └──────┬───────┘
                         ↓
                  ┌──────────────┐
                  │ Cloud Run    │
                  │   Backend    │
                  └──────┬───────┘
                         ↓
                  ┌──────────────┐
                  │ Google ADK   │
                  └──────┬───────┘
                         ↓
                  ┌──────────────┐
                  │ Gemini 3.5+  │
                  └──────────────┘
```

이런 식으로 **전체 시스템 구조가 한눈에 보여야 함.**

---

# 9. 🎥 4분 Demo Video — 진짜 중요

영상은 **최대 4분**.

4분을 넘으면 **첫 4분까지만 평가**해.

그리고 반드시:

### ① Problem

"우리가 어떤 문제를 해결하는가?"

### ② Value Proposition

"그래서 사용자에게 뭐가 좋은가?"

### ③ 실제 Demo

**Agent가 실제로 행동하는 장면**

### ④ Google Cloud 사용 증명

이게 중요해.

예:

- Google Cloud Console
- Cloud Run Dashboard
- Vertex AI logs
- `.run` URL

등을 영상에 보여줘야 해.

---

# 10. Demo에서 특히 점수 잘 받으려면

공식 심사 기준에 **Proof of Action**이 따로 명시돼 있어.

즉,

> "우리 Agent가 이런 일을 할 수 있습니다."
> 

보다

> **"지금 실제로 Agent를 실행했고 → 실제로 DB가 바뀌었고 → 실제로 이메일/문서/작업이 처리됐습니다."**
> 

를 보여주는 게 훨씬 좋아.

예를 들어 화면에

```
Agent started
      ↓
Task 1 completed
      ↓
Task 2 completed
      ↓
Database updated
      ↓
Email sent
      ↓
Workflow completed
```

같은 실제 execution log가 보이면 굉장히 좋음.

# 11. 영어 조건

**Application 자체는 최소 영어를 지원해야 하고**, 제출 자료도 영어가 원칙이야.

한국어로 만들더라도:

- Demo video
- Text description
- Testing instructions
- 기타 제출 자료

에 **영어 번역을 제공해야 해.**

따라서 한국어 UI 자체가 문제라는 뜻은 아니지만, **심사위원이 영어로 이해할 수 있어야 한다**고 보면 돼.

---

# 12. 🚨 실격/탈락 위험이 있는 부분

공식 규정상 특히 조심해야 할 것들.

### ❌ 마감 이후 제출/수정

Submission Period가 끝난 후에는 제출물을 변경할 수 없어.

---

### ❌ 기존 프로젝트 그대로 제출

Submission Period 이전에 만들어 놓은 프로젝트를 그대로 제출하는 것은 안 됨.

새 프로젝트여야 함.

---

### ❌ IP 침해

타인의:

- 코드
- 이미지
- 데이터
- 상표
- 특허
- 개인정보

등을 권리 없이 사용하면 안 됨.

---

### ❌ Google/Devpost의 사전 지원으로 만들어진 프로젝트

Google 또는 Devpost로부터 이전에:

- 투자
- funding
- 계약
- commercial license

등의 지원을 받아 개발된 프로젝트는 문제가 될 수 있어.

---

### ❌ 영상이 4분 초과

초과하면 **4분 이후는 심사하지 않음.**

---

### ❌ 영상이 Public이 아님

YouTube/Vimeo에 **Public**으로 올려야 하고, 링크를 제출해야 해.

Unlisted는 안 돼.

---

### ❌ 영어 자료가 없음

영어 또는 영어 자막/번역이 필요함.

---

### ❌ 부적절한 콘텐츠

혐오, 차별, 불법, 명예훼손, 성적 콘텐츠 등은 금지.

제3자 광고나 제3자 sponsorship/endorsement를 암시하는 콘텐츠도 제한돼 있어.

---

# 13. 🏆 심사 기준 — 이게 제일 중요

## ① Innovation & Operational Utility — **40%**

**가장 높은 비중.**

심사위원이 보는 건:

> "이거 실제로 사람의 귀찮음을 얼마나 없애주나?"
> 

그리고

> **"그냥 ChatGPT에 질문하는 것보다 Agent여야 할 이유가 있나?"**
> 

야.

### Taskmaster라면

- multi-step workflow인가?
- 사람이 계속 개입하지 않아도 되는가?
- 실제로 작업을 완료하는가?
- 독특한 문제인가?

### Evolving Knowledge Engine이라면

- 단순히 데이터를 읽기만 하는 게 아닌가?
- 데이터를 synthesis / mutation 하는가?
- 복잡하고 messy한 데이터를 다루는가?

### Multi-Agent Nexus라면

- 정말 multi-agent가 필요한 문제인가?
- specialized agent로 task delegation을 하는가?
- 각 agent 역할이 명확한가?

이런 걸 봐.

---

# 14. 🏗️ Architectural Discipline & Tech Stack — **30%**

여기서는

> "Gemini API 한 번 호출했어요."
> 

같은 건 거의 의미가 없어.

보는 건 **engineering quality**야.

### 중요 요소

- 시스템 분리
- state management
- modular architecture
- failure tolerance
- security
- tool isolation
- 데이터 구조
- context management

등.

예를 들어 Agent가

```
Agent
 ↓
Tool A
Tool B
Tool C
```

를 사용할 때 각각 권한을 적절히 제한했는지,

Agent가 중간에 실패하면 어떻게 복구하는지,

context를 어떻게 저장하는지,

등이 중요해.

# 15. 🎥 Demo & Production Readiness — **30%**

여기서는 **"실제로 돌아간다는 증거"**를 본다.

특히 공식적으로:

> **Proof of Action**
> 

을 강조하고 있어.

즉 영상에서 **편집된 fake demo보다 실제 실행**을 보여주는 게 중요해.

또:

- README가 잘 되어 있는가?
- Architecture Diagram이 있는가?
- 재현 가능한가?
- Google Cloud에서 실제 실행되는가?
- 영상에서 실제 Agent 실행을 볼 수 있는가?

를 평가해.

---

# 16. ⭐ Bonus Points

보너스는 **필수 아님.**

### Blog / Podcast / Video

프로젝트를 어떻게 만들었는지 공개 콘텐츠 작성.

Public이어야 하고,

> "This content was created for the purposes of entering this hackathon."
> 

같은 취지의 문구가 필요해.

**최대 +0.2점**.

---

### SNS

X / LinkedIn / Instagram / Facebook 등에 프로젝트 홍보.

X/LinkedIn 등에서는

**#AllThingsAgenticHackathon**

사용.

**최대 +0.2점**.

---

### 추가 Google AI 모델

기본 Gemini 외에

- Gemma
- Veo
- Lyria

등 추가 Google AI 모델을 성공적으로 통합하면:

**모델 하나당 +0.2점**

최대 **+0.6점**.

---

# 17. 그래서 점수 구조를 실제로 보면

기본 점수:

| 평가 | 비중 |
| --- | --- |
| 💡 Innovation & Operational Utility | **40%** |
| 🏗️ Architecture & Tech Stack | **30%** |
| 🎥 Demo & Production Readiness | **30%** |
| **기본 총점** | **100%** |

그리고 Bonus:

| Bonus | 최대 |
| --- | --- |
| Blog/Podcast/Video | +0.2 |
| Social Media | +0.2 |
| 추가 Google AI 모델 | +0.6 |
| **최대** | **+1.0** |

공식 규정상 최종 점수는 **1~6점 체계**로 계산되며 최고 점수는 6점이야.

---

# 18. 🏆 상금 구조도 꽤 중요함

현재 공식 규정상:

- **Grand Prize:** $50,000 + $5,000 Google Cloud Credits
- **Taskmaster:** $20,000 + $2,000 Cloud Credits
- **Collaborative Partner:** $20,000 + $2,000 Cloud Credits
- **Fortified Enterprise Fleet:** $20,000 + $2,000 Cloud Credits
- **Startup Excellence:** $20,000 + $5,000 Cloud Credits
- **Individual/Hobbyist:** $10,000 + $1,000 Cloud Credits
- **Best Architectural Design:** $5,000 + $1,000 Cloud Credits
- **Best Multimodal UX:** $5,000 + $1,000 Cloud Credits
- **Honorable Mention:** $2,000 + $500 Cloud Credits

등이 있어. 프로젝트 하나는 **최대 한 개의 Prize만 받을 수 있어.**

# 19. 너희가 실제로 프로젝트 만들 때의 "필수 체크리스트"

내가 이 해커톤에 참가한다면 아래처럼 체크할 것 같아.

### 🔴 개발 중 반드시

- [ ]  Gemini 3.5+
- [ ]  Google ADK / GenAI SDK / Antigravity SDK / GenKit 3 중 하나
- [ ]  Google Cloud 서비스 하나 이상
- [ ]  실제 Agent 행동
- [ ]  단순 chatbot이 아님
- [ ]  multi-step workflow
- [ ]  가능한 한 human intervention 최소화
- [ ]  프로젝트는 Submission Period에 새로 개발
- [ ]  외부 코드/데이터 라이선스 확인

### 🟠 제출 전에

- [ ]  Category 하나 선택
- [ ]  Hosted URL
- [ ]  GitHub/GitLab/Bitbucket
- [ ]  README
- [ ]  Spin-up instructions
- [ ]  Architecture Diagram
- [ ]  Text description
- [ ]  Demo video ≤ 4분
- [ ]  YouTube/Vimeo **Public**
- [ ]  영어 또는 영어 자막
- [ ]  Google Cloud 실행 증거
- [ ]  실제 Agent execution 증거

### 🟢 보너스

- [ ]  개발 과정 Blog/YouTube
- [ ]  SNS + `#AllThingsAgenticHackathon`
- [ ]  Gemma / Veo / Lyria 추가

---

## 그리고 **너희가 아이디어를 고를 때 제일 중요한 포인트**

이 규정을 보면 나는 **카테고리 이름보다 심사 기준을 먼저 보고 아이디어를 정하는 게 좋다**고 봐.

특히 **40%가 Innovation & Operational Utility**라서,

> ❌ "Gemini를 이용한 ~~ 관리 서비스"
> 

보다

> ✅ **"기존에는 사람이 30분~2시간씩 반복하던 일을 Agent가 백그라운드에서 알아서 끝낸다"**
> 

가 훨씬 강해.

그리고 30%가 Architecture라서 **Agent가 실제로 어떤 tool을 호출하고, state를 어떻게 유지하고, 실패하면 어떻게 복구하는지**까지 보여주면 좋고, 나머지 30%는 **그게 실제로 돌아가는 모습을 4분 안에 증명**하면 돼.
