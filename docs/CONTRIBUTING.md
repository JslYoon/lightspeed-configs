# Contributing

- [Prerequisites](#prerequisites)
- [Running Locally](#running-locally)
- [Configuring RAG Content](#configuring-rag-content)
- [Configuring Validation](#configuring-validation)
- [Syncing Configs](#syncing-configs)
  - [Syncing Images](#syncing-images)
- [Formatting and Validating YAML](#formatting-and-validating-yaml)
- [Makefile Commands](#makefile-commands)
- [Troubleshooting](#troubleshooting)

## Prerequisites

- [Podman](https://podman.io/docs/installation) v5.4.1+ (recommended) or [Docker](https://docs.docker.com/engine/) v28.1.0+ with Compose support
- [yq](https://github.com/mikefarah/yq) v4.52.4+ for image and config sync/validation
- `python3.12+` for the prompt-template sync/validation scripts

## Running Locally

1. Copy `./env/default-values.env` to `./env/values.env` and fill in any provider-specific values (see [docs/PROVIDERS.md](./PROVIDERS.md)).

2. Pull the RAG content:

```sh
make get-rag
```

3. Start the local API stack:

```sh
make local-up
```

This starts Lightspeed Core using the mounted config/content below.

Lightspeed Core uses mounted config/content in local compose:

- `lightspeed-core-configs/lightspeed-stack.yaml` -> `/app-root/lightspeed-stack.yaml`
- `lightspeed-core-configs/rhdh-profile.py` -> `/app-root/rhdh-profile.py`
- `llama-stack-configs/config.yaml` -> `/app-root/config.yaml`
- `rag-content/` -> `/rag-content`

Question validation is not enabled automatically. If you want it, set `ENABLE_VALIDATION`, `VALIDATION_PROVIDER`, and `VALIDATION_MODEL_NAME` in `env/values.env`, along with any env vars required by the selected inference provider.

See [Configuring Validation](#configuring-validation) for example configurations.

4. Stop services:

```sh
make local-down
```

## Configuring RAG Content

`make get-rag` pulls the embeddings model and vector database from the RAG content image into `./rag-content`. It fully replaces the directory on each run.

To use a different RAG image:

```sh
make get-rag RAG_CONTENT_IMAGE=quay.io/redhat-ai-dev/rag-content:<tag>
```

> [!IMPORTANT]
> The vector_store ID value changes whenever the RAG content is updated in the image. This means that you only need to do the below update once per image.

With Llama Stack `0.4.3` the way Vector Stores are created has changed. This means that the RAG content you download locally by running `make get-rag` contains a generated Vector Store ID. In order for RAG to work properly you need to navigate to `rag-content/vector_db/rhdh_product_docs/<docs number>/llama-stack.yaml` and find the `vector_stores` section, it should look like:

```
vector_stores:
  - embedding_dimension: 768
    embedding_model: sentence-transformers//rag-content/embeddings_model
    provider_id: rhdh-product-docs-1_8
    vector_store_id: vs_3d47e06c-ac95-49b6-9833-d5e6dd7252dd
```

You will need the `vector_store_id` value. After copying that value you will need to update `config.yaml`. The `vector_store_id` you copied will replace the `vector_store_id` in that file.



## Configuring Validation

Question validation is controlled by the `ENABLE_VALIDATION` environment variable in `llama-stack-configs/config.yaml`. When set, it activates the `lightspeed_question_validity` shield. The shield uses `VALIDATION_PROVIDER` and `VALIDATION_MODEL_NAME` to select an enabled inference provider and model.

`make local-up` does not start a validation service or inject validation defaults. If you enable validation, you must provide both `VALIDATION_PROVIDER` and `VALIDATION_MODEL_NAME` yourself in `env/values.env`.

If `ENABLE_VALIDATION` is empty, validation is disabled and no additional configuration is required.

To enable validation, set the following in `env/values.env`:

| Variable | Required | Description |
| ---- | ---- | ---- |
| `ENABLE_VALIDATION` | Yes, set to `true` | Activates the validation shield in `config.yaml` |
| `VALIDATION_PROVIDER` | Yes | Inference provider used by the validation shield, for example `vllm` or `openai` |
| `VALIDATION_MODEL_NAME` | Yes | Model name served by the selected inference provider |

You must also enable and configure the referenced inference provider. Examples:

### Example: vLLM-backed validation

```env
ENABLE_VALIDATION=true
VALIDATION_PROVIDER=vllm
VALIDATION_MODEL_NAME=<your-model-name>
ENABLE_VLLM=true
VLLM_URL=<your-vllm-endpoint>
VLLM_API_KEY=<api-key>
```


## Syncing Configs

This repository has sync scripts that keep generated values consistent with their sources. CI validates these on every PR -- if they drift, the PR will fail.

### Syncing Images

[images.yaml](./images.yaml) is the source of truth for sprint images. It is also consumed by an external service for a different environment. The image values in `env/default-values.env` must stay in sync with it.

After updating `images.yaml`:

```sh
make sync-images
```

This reads the `image` field for each service in `images.yaml` and updates the corresponding env vars (`LIGHTSPEED_CORE_IMAGE`, `RAG_CONTENT_IMAGE`) in `env/default-values.env`.

`lightspeed-core-configs/rhdh-profile.py` is maintained directly in this repository (not synced from upstream). Keep `customization.profile_path` in `lightspeed-core-configs/lightspeed-stack.yaml` aligned with the mount path configured in `compose/compose.yaml` (`/app-root/rhdh-profile.py`).

### Syncing Prompt Templates

The question-validation `model_prompt` and `invalid_question_response` in `llama-stack-configs/config.yaml` are sourced from `lightspeed-core-configs/rhdh-profile.py`.

`make update-prompt-templates` and `make validate-prompt-templates` call `scripts/sync-prompt-templates.py` directly with `python3`. The helper requires Python 3.12+ and will exit with a clear error if invoked with an older interpreter.

The Python helper is used because the source of truth lives in a Python file and the sync step needs to parse Python triple-quoted strings, translate placeholders for the Llama Stack YAML (`{SUBJECT_ALLOWED}` -> `${allowed}`, `{SUBJECT_REJECTED}` -> `${rejected}`, `{{query}}` -> `${message}`), and rewrite YAML block scalars in a stable format. The helper uses only the Python standard library.

After updating `QUESTION_VALIDATOR_PROMPT_TEMPLATE` or `INVALID_QUERY_RESP` in `lightspeed-core-configs/rhdh-profile.py`:

```sh
make update-prompt-templates
make validate-prompt-templates
```

## Formatting and Validating YAML

Format and validate YAML files (also used by CI):

```sh
make format-yaml
make validate-yaml
```

## Makefile Commands

| Command | Description |
| ---- | ---- |
| `get-rag` | Pull and unpack RAG content into `./rag-content` (replaces existing contents). Optional: `RAG_CONTENT_IMAGE=<image>`. |
| `local-up` | Start local compose services. Validation is controlled entirely through env vars in `env/values.env`. |
| `local-down` | Stop local compose services. |
| `sync-images` | Sync image values from `images.yaml` into `env/default-values.env`. Requires `yq`. |
| `validate-images` | Validate that `images.yaml` and `env/default-values.env` are in sync. Requires `yq`. |
| `validate-yaml` | Validate YAML formatting/syntax. |
| `format-yaml` | Format YAML files. |
| `validate-prompt-templates` | Validate that the question-validation prompt values in `llama-stack-configs/config.yaml` match `lightspeed-core-configs/rhdh-profile.py`. |
| `update-prompt-templates` | Sync the question-validation prompt values in `llama-stack-configs/config.yaml` from `lightspeed-core-configs/rhdh-profile.py`. |

## Troubleshooting

Enable debug logs:

```sh
LLAMA_STACK_LOGGING=all=DEBUG
```

If you hit a permission error for `vector_db`, such as:

```sh
sqlite3.OperationalError: attempt to write a readonly database
```

fix permissions with:

```sh
chmod -R 777 rag-content/vector_db
```

If `podman compose` delegates to `docker-compose` and you get a registry auth error like:

```sh
unable to retrieve auth token: invalid username/password: unauthorized
```

it means `docker-compose` cannot find your credentials. Even if you are logged in via `podman login`, `docker-compose` looks for credentials at `~/.docker/config.json`. Write your credentials there with:

```sh
mkdir -p ~/.docker
podman login --authfile ~/.docker/config.json registry.redhat.io
```
