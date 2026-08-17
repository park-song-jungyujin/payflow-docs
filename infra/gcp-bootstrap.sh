#!/usr/bin/env bash
# Payflow 로컬 개발 환경 부트스트랩 (Track C)
#
# API 활성화 · Firestore DB 생성 · Cloud Run · Cloud Tasks · Secret Manager는
# backend/infra/의 terraform이 소유한다 (이 스크립트가 아니다). 이 스크립트는
# terraform이 대신할 수 없는 로컬 머신 셋업 + 데모 fixture 시딩만 한다.
#
#   PROJECT_ID=payflow-hackathon-2026 ./gcp-bootstrap.sh
#
# 순서: 이 스크립트로 로컬 도구 준비 → backend/infra에서 `terraform apply` →
#       그다음 이 스크립트를 다시 돌려 fixture 시딩 (또는 아래 시딩 부분만 재실행).
#
# 전제: gcloud, uv가 로컬에 설치되어 있어야 한다.
#   - gcloud: brew install --cask google-cloud-sdk
#   - uv    : brew install uv

set -euo pipefail

PROJECT_ID="${PROJECT_ID:?PROJECT_ID 환경변수 필요. 예: PROJECT_ID=payflow-hackathon-2026 ./gcp-bootstrap.sh}"

echo "== 로컬 도구 확인 =="
command -v gcloud >/dev/null || { echo "gcloud 미설치"; exit 1; }
command -v uv >/dev/null || { echo "uv 미설치"; exit 1; }

echo "== Python 3.12 준비 (uv) =="
uv python install 3.12

echo "== gcloud 활성 프로젝트 설정 =="
gcloud config set project "$PROJECT_ID"

echo "== ADC 로그인 (브라우저 인증 필요, Vertex AI 로컬 호출용) =="
gcloud auth application-default login

echo "== dev/deploy DB에 데모 fixture 시딩 (기존 (default) DB는 더 이상 쓰지 않음) =="
BACKEND_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../backend" && pwd)"
for DB in development deploy; do
  (cd "$BACKEND_DIR" && GCP_PROJECT="$PROJECT_ID" FIRESTORE_DATABASE="$DB" PYTHONPATH=. uv run python scripts/seed_firestore.py)
done

echo "== 완료: $PROJECT_ID =="
