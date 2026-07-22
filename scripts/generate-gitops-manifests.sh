#!/usr/bin/env bash
#
#
# Copyright Red Hat
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUTPUT_DIR="${REPO_ROOT}/generated"
GITOPS_REPO="${GITOPS_REPO:-${REPO_ROOT}/../ai-rolling-demo-gitops}"

mkdir -p "${OUTPUT_DIR}"

indent() {
  sed 's/^/    /'
}

strip_license() {
  sed -n '/^[^#]/,$p' "$1"
}

get_image() {
  local key="$1"
  awk -v key="${key}" '
    /^[^[:space:]]/ { in_section = ($0 == key":") }
    in_section && /^[[:space:]]+image:/ { print $2; exit }
  ' "${REPO_ROOT}/images.yaml"
}

notebooks_faiss_to_pgvector() {
  awk '
    /^    - provider_id: notebooks$/ {
      skip = 1
      print "    - provider_id: notebooks"
      print "      provider_type: remote::pgvector"
      print "      config:"
      print "        host: ${env.PGVECTOR_HOST:=lightspeed-postgres-svc.lightspeed-postgres.svc.cluster.local}"
      print "        port: ${env.PGVECTOR_PORT:=5432}"
      print "        db: ${env.PGVECTOR_DB}"
      print "        user: ${env.PGVECTOR_USER}"
      print "        password: ${env.PGVECTOR_PASSWORD}"
      print "        distance_metric: COSINE"
      print "        vector_index:"
      print "          type: HNSW"
      print "          m: 16"
      print "          ef_construction: 64"
      print "          ef_search: 40"
      print "        persistence:"
      print "          namespace: vector_io::pgvector"
      print "          backend: kv_default"
      next
    }
    skip && /^    - provider_id:/ { skip = 0 }
    skip && /^  [a-zA-Z]/ { skip = 0 }
    skip { next }
    /^    kv_notebooks:$/ { skip_kv = 1; next }
    skip_kv && /^[^ ]|^  [a-zA-Z]|^    [a-zA-Z]/ { skip_kv = 0 }
    skip_kv { next }
    { print }
  '
}

echo "Generating llama-stack ConfigMap..."
{
  cat << 'HEADER'
kind: ConfigMap
apiVersion: v1
metadata:
  name: llama-stack-config
  namespace: {{ .Release.Namespace }}
data:
  config.yaml: |
HEADER
  strip_license "${REPO_ROOT}/llama-stack-configs/config.yaml" \
    | notebooks_faiss_to_pgvector \
    | indent
} > "${OUTPUT_DIR}/llama-stack-config.yaml"

echo "Generating lightspeed-stack ConfigMap..."
{
  cat << 'HEADER'
kind: ConfigMap
apiVersion: v1
metadata:
  name: lightspeed-stack-config
  namespace: {{ .Release.Namespace }}
data:
  lightspeed-stack.yaml: |
HEADER
  strip_license "${REPO_ROOT}/lightspeed-core-configs/lightspeed-stack.yaml" \
    | awk '/^    - type: sentence_transformers$/ {
        print "    - type: vllm"
        print "      id: vllm"
        print "      api_key_env: VLLM_API_KEY"
        print "      extra:"
        print "        base_url: ${env.VLLM_URL:=}"
        print "        max_tokens: ${env.VLLM_MAX_TOKENS:=4096}"
        print "        network:"
        print "          tls:"
        print "            verify: ${env.VLLM_TLS_VERIFY:=true}"
        print "    - type: openai"
        print "      id: openai"
        print "      api_key_env: OPENAI_API_KEY"
        print "      extra:"
        print "        allowed_models:"
        print "          - gpt-4o-mini"
        print "          - gpt-5.1"
        print "          - gpt-4.1-mini"
        print "          - gpt-4.1-nano"
        print
        next
      }
      { print }' \
    | indent
} > "${OUTPUT_DIR}/lightspeed-stack-config.yaml"

echo "Generating rhdh-profile.py..."
cp "${REPO_ROOT}/lightspeed-core-configs/rhdh-profile.py" "${OUTPUT_DIR}/rhdh-profile.py"

echo "Updating lightspeed-core sidecar image in values.yaml..."
LIGHTSPEED_CORE_IMAGE="$(get_image "lightspeed-core")"
VALUES_YAML="${GITOPS_REPO}/charts/rhdh/values.yaml"
if [[ ! -f "${VALUES_YAML}" ]]; then
  echo "Error: ${VALUES_YAML} not found." >&2
  exit 1
fi
sed -i "s|image: [^ ]*/lightspeed-stack[^ ]*|image: ${LIGHTSPEED_CORE_IMAGE}|g" "${VALUES_YAML}"

echo "Generated manifests:"
ls -1 "${OUTPUT_DIR}"
