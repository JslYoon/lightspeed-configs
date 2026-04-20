# Llama Stack Configuration Files

This directory stores the Llama Stack config for the single active release tracked on `main`.

- `config.yaml` is the unified config. The question-validation shield is conditionally enabled via `ENABLE_VALIDATION` and uses the `VALIDATION_PROVIDER` and `VALIDATION_MODEL_NAME` env vars you supply (see [CONTRIBUTING.md](../docs/CONTRIBUTING.md#configuring-validation)).

Historical release-specific configs are maintained in release branches and tags.