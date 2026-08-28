# Coding-agent setup contract

Use this workflow when installing the plugin or adding a model. Keep the runtime
architecture to three layers:

1. A GGUF model and any matching draft model.
2. One tested systemd **user** service containing the llama-server command.
3. One `name`/`service` entry in `~/.config/omarchy/local-ai.toml`.

## Add or change a profile

1. Inspect the machine, llama.cpp build, accelerator, available memory, model
   files, and existing profile services.
2. Choose launch arguments appropriate for that machine and model. Do not copy
   another model's context, cache, GPU, or speculative-decoding settings without
   verifying compatibility.
3. Create one user service per useful launch profile. Services sharing an
   endpoint or accelerator should conflict with each other.
4. Run `systemctl --user daemon-reload`, start the new service directly, wait
   for the API to become ready, make a small inference request, then stop it.
5. Add only its friendly name and unit name to `local-ai.toml`.
6. Run `local-ai-control doctor` and `test.sh`.
7. Leave the service disabled. The panel must start it only on demand.

## Minimal service shape

Use this only as a structural example. Replace every model path and choose
context, accelerator, cache, and offload settings from measurements on the target
machine:

```ini
[Unit]
Description=Local llama.cpp profile
Conflicts=local-ai-other.service

[Service]
Type=simple
ExecStart=/usr/bin/llama-server \
  --model %h/.local/share/models/example.gguf \
  --host 127.0.0.1 \
  --port 8080 \
  --ctx-size 8192
Restart=on-failure
RestartSec=3

[Install]
WantedBy=default.target
```

Do not add secrets to the plugin TOML. If the service uses `--api-key`, keep the
credential in the service or a protected environment file and configure clients
separately. The panel intentionally copies only the endpoint.

The service is the source of truth. The plugin reads `--model`,
`--spec-draft-model`, `--ctx-size`, `--device`, `--host`, and `--port` from its
`ExecStart`; it does not generate, rewrite, or own services.

Harnesses such as Pi or Codex are separate clients. Configure them against the
endpoint shown by the panel after the runtime has been verified.

## Optional Copilot contract

Copilot is a fourth, optional consumer of the endpoint, not another runtime
profile and not another Omarchy plugin. Configure it from the **Always-on
Copilot** section in the Local AI dropdown.

1. Install Pi and verify the desired light model endpoint.
2. Open **Copilot settings** and set `runtime.endpoint` plus either an exact
   served model ID or `model = "auto"`.
3. If the endpoint should be started automatically, configure a fixed
   `runtime.start_command` argv that invokes `local-ai-control start PROFILE`.
4. Keep screenshots disabled. Adjust privacy deny rules before widening shared
   window metadata.
5. Configure delegation only as a fixed argv. It is launched in a visible
   terminal after an explicit click; it is never a tool granted to the light
   model.
6. Run `local-ai-copilot doctor --online`, test a synthetic suggestion, then
   enable the observer.

The Copilot systemd service owns only its observer, state, isolated Pi catalog,
and suggestion UI. Disabling it must not stop or rewrite the shared model
runtime.
