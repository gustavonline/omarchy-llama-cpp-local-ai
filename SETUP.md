# Coding-agent setup contract

Use this workflow when installing the plugin or adding a model. Keep the
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

The service is the source of truth. The plugin reads `--model`,
`--spec-draft-model`, `--ctx-size`, `--device`, `--host`, and `--port` from its
`ExecStart`; it does not generate, rewrite, or own services.

Harnesses such as Pi or Codex are separate clients. Configure them against the
endpoint shown by the panel after the runtime has been verified.
