# IAM 격리 403 데모 절차

절대 규칙 1 (`payflow-agent`는 PayPal 자격증명에 접근하지 않는다)를 심사 앞에서
실제로 보여주는 절차. 관련 Terraform: `backend/infra/iam.tf`, `secrets.tf`.

## 방법 A — 정적 증명 (항상 안전, 부작용 없음)

IAM 정책을 그대로 조회해서 `payflow-agent` SA가 어느 시크릿에도 바인딩이
없음을 보여준다. 상태를 바꾸지 않으므로 리허설·본 시연 모두에 반복 사용.

```bash
for s in PAYPAL_CLIENT_ID PAYPAL_CLIENT_SECRET SLACK_SIGNING_SECRET SLACK_BOT_TOKEN; do
  echo "=== $s ==="
  gcloud secrets get-iam-policy "$s" --project payflow-hackathon-2026 \
    --format="table(bindings.role,bindings.members)"
done
```

기대 결과: 4개 시크릿 모두 `roles/secretmanager.secretAccessor` 멤버가
`payflow-api@...`뿐이고 `payflow-agent@...`는 어디에도 등장하지 않는다.

콘솔로 보여주려면: IAM & Admin → Service Accounts →
`payflow-agent@payflow-hackathon-2026.iam.gserviceaccount.com` → Permissions.
바인딩 자체가 비어 있다 (아래 명령으로도 확인 가능):

```bash
gcloud iam service-accounts get-iam-policy \
  payflow-agent@payflow-hackathon-2026.iam.gserviceaccount.com \
  --project payflow-hackathon-2026
# → {"etag": "ACAB"}  (바인딩 없음)
```

## 방법 B — 실제 403 캡처 (일시적 IAM 변경 필요)

`payflow-agent` SA를 impersonate할 권한이 기본적으로 아무에게도 없다
(방법 A의 마지막 명령이 그 증거). 그래서 실제 `PERMISSION_DENIED`를 화면에
띄우려면 시연자 본인 계정에 **그 SA를 impersonate할 권한만** 잠깐 부여해야
한다. 시크릿 접근 권한은 여전히 없으므로 최종 호출은 여전히 거부된다.

**시연 직전에 부여 → 캡처 → 시연 직후 반드시 회수.** 부여된 채로 두면
절대 규칙 1이 문서상으로만 참이고 실제로는 깨진 상태가 된다.

```bash
ME="$(gcloud config get-value account)"

# 1) 임시 부여 (impersonate 권한만 — secretAccessor 아님)
gcloud iam service-accounts add-iam-policy-binding \
  payflow-agent@payflow-hackathon-2026.iam.gserviceaccount.com \
  --project payflow-hackathon-2026 \
  --member="user:${ME}" \
  --role="roles/iam.serviceAccountTokenCreator"

# 2) agent SA로 시크릿 접근 시도 → 403 (secretAccessor 없음)
gcloud secrets versions access latest --secret=PAYPAL_CLIENT_SECRET \
  --project=payflow-hackathon-2026 \
  --impersonate-service-account=payflow-agent@payflow-hackathon-2026.iam.gserviceaccount.com

# 3) 회수 (필수 — 시연 끝나면 바로)
gcloud iam service-accounts remove-iam-policy-binding \
  payflow-agent@payflow-hackathon-2026.iam.gserviceaccount.com \
  --project payflow-hackathon-2026 \
  --member="user:${ME}" \
  --role="roles/iam.serviceAccountTokenCreator"
```

1단계를 건너뛰고 2단계만 실행하면 (2026-08-17 실제 확인) impersonate 권한 자체가
없어 이 단계에서 막힌다:

```
ERROR: (gcloud.secrets.versions.access) PERMISSION_DENIED: Failed to impersonate
[payflow-agent@...]. ... permission: iam.serviceAccounts.getAccessToken
```

1단계로 impersonate 권한을 부여한 뒤 2단계를 실행하면 그다음 관문인
secretAccessor에서 막힌다 — 2026-08-17 실제로 3단계 전체(부여 → 캡처 → 회수)를
실행해 확인했다:

```
ERROR: (gcloud.secrets.versions.access) PERMISSION_DENIED: Permission
'secretmanager.versions.access' denied on resource (or it may not exist).
...
  permission: secretmanager.versions.access
  reason: IAM_PERMISSION_DENIED
```

부여 직후 바로 시도하면 IAM 바인딩 전파 지연(수십 초)으로 1단계 에러
(`iam.serviceAccounts.getAccessToken`)가 그대로 재현될 수 있다 — 45초 정도
기다렸다 재시도하면 된다. 회수는 `remove-iam-policy-binding` 직후
`get-iam-policy`로 바인딩이 비었는지 재확인했다.

## 리허설 체크리스트

- [ ] 방법 A 먼저 실행 — 무해하므로 카메라 앞에서 여러 번 연습 가능
- [ ] 방법 B는 본 시연 시작 직전 1회 부여, 촬영 직후 즉시 회수까지 한 세트로 연습
- [ ] `terraform plan`으로 드리프트 없는지 확인 (`cd backend/infra && terraform plan`) —
      Cloud Run `scaling` 블록 표현 차이만 나오면 정상, IAM/시크릿 관련 diff가 있으면 안 됨
- [ ] 방법 B 회수를 잊었는지 `gcloud iam service-accounts get-iam-policy payflow-agent@...`로 재확인
