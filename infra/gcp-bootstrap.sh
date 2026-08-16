#!/usr/bin/env bash
# Payflow GCP 프로젝트 부트스트랩 (Track C)
#
# 새 프로젝트로 옮기거나 다른 팀원 머신에서 재현할 때, PROJECT_ID만 바꿔서 실행.
#   PROJECT_ID=payflow-hackathon-2026 ./gcp-bootstrap.sh
#
# 전제: gcloud, terraform, uv가 로컬에 설치되어 있어야 한다.
#   - gcloud   : brew install --cask google-cloud-sdk
#   - terraform: brew tap hashicorp/tap && brew install hashicorp/tap/terraform
#                (brew core에서 라이선스 문제로 빠졌음. tap 필수)
#   - uv       : brew install uv

set -euo pipefail

PROJECT_ID="${PROJECT_ID:?PROJECT_ID 환경변수 필요. 예: PROJECT_ID=payflow-hackathon-2026 ./gcp-bootstrap.sh}"
REGION="asia-northeast3"  # 서울. Firestore는 한 번 정하면 변경 불가

echo "== 로컬 도구 확인 =="
command -v gcloud >/dev/null || { echo "gcloud 미설치"; exit 1; }
command -v terraform >/dev/null || { echo "terraform 미설치"; exit 1; }
command -v uv >/dev/null || { echo "uv 미설치"; exit 1; }

echo "== Python 3.12 준비 (uv) =="
uv python install 3.12

echo "== gcloud 활성 프로젝트 설정 =="
gcloud config set project "$PROJECT_ID"

echo "== ADC 로그인 (브라우저 인증 필요, Vertex AI 로컬 호출용) =="
gcloud auth application-default login

echo "== 필요 API 4종 활성화 =="
gcloud services enable \
  aiplatform.googleapis.com \
  firestore.googleapis.com \
  cloudtasks.googleapis.com \
  run.googleapis.com \
  --project="$PROJECT_ID"

echo "== Firestore Native DB 2개 생성 (dev/deploy, 최초 1회만, 이미 있으면 에러 나고 무시해도 됨) =="
for DB in development deploy; do
  gcloud firestore databases create \
    --database="$DB" \
    --location="$REGION" \
    --type=firestore-native \
    --project="$PROJECT_ID" || echo "$DB: 이미 존재하거나 실패 — 위 에러 확인"
done

echo "== dev/deploy DB에 데모 fixture 시딩 (기존 (default) DB는 더 이상 쓰지 않음) =="
BACKEND_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../backend" && pwd)"
for DB in development deploy; do
  (cd "$BACKEND_DIR" && GCP_PROJECT="$PROJECT_ID" FIRESTORE_DATABASE="$DB" PYTHONPATH=. uv run python scripts/seed_firestore.py)
done

echo "== 완료: $PROJECT_ID =="
