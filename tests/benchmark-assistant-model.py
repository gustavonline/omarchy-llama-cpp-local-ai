#!/usr/bin/env python3
"""Compare local OpenAI-compatible models against Assistant decision cases."""

from __future__ import annotations

import argparse
import json
import time
import urllib.request
from pathlib import Path


CASES = (
    {
        "name": "passive-video",
        "context": {"appId": "zen", "title": "YouTube — Zen Browser", "workspace": "1"},
        "hints": [],
        "expectedShow": False,
    },
    {
        "name": "actionable-failure",
        "context": {
            "appId": "codex",
            "title": "Fix failing Local AI voice-start regression test — Codex",
            "workspace": "1",
        },
        "hints": ["When a test is failing, offer one concrete diagnosis or harness handoff."],
        "expectedShow": True,
    },
    {
        "name": "generic-browser",
        "context": {"appId": "zen", "title": "New Tab — Zen Browser", "workspace": "2"},
        "hints": [],
        "expectedShow": False,
    },
)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--endpoint", required=True)
    parser.add_argument("--model", required=True)
    parser.add_argument("--api-key", default="")
    parser.add_argument("--repeat", type=int, default=1)
    parser.add_argument("--max-tokens", type=int, default=256)
    return parser.parse_args()


def extract_json(text: str) -> dict:
    value = text.strip()
    if value.startswith("```"):
        value = value.split("\n", 1)[1].rsplit("```", 1)[0].strip()
    parsed = json.loads(value)
    if not isinstance(parsed, dict):
        raise ValueError("response was not a JSON object")
    return parsed


def request_case(
    args: argparse.Namespace, system_prompt: str, context: dict, hints: list[str]
) -> dict:
    payload = {
        "model": args.model,
        "messages": [
            {"role": "system", "content": system_prompt},
            {
                "role": "user",
                "content": json.dumps(
                    {
                        "interaction_mode": "proactive",
                        "active_window": context,
                        "playbook_hints": hints,
                        "suggestion_mode": "proactive",
                        "dismissed_suggestion_examples": [],
                    },
                    separators=(",", ":"),
                ),
            },
        ],
        "temperature": 0.1,
        "reasoning_effort": "none",
        "max_tokens": args.max_tokens,
        "stream": True,
    }
    headers = {"Content-Type": "application/json"}
    if args.api_key:
        headers["Authorization"] = f"Bearer {args.api_key}"
    request = urllib.request.Request(
        args.endpoint.rstrip("/") + "/chat/completions",
        data=json.dumps(payload).encode(),
        headers=headers,
        method="POST",
    )
    started = time.perf_counter()
    first_token = None
    first_any_token = None
    chunks: list[str] = []
    reasoning_chunks: list[str] = []
    finish_reason = None
    with urllib.request.urlopen(request, timeout=90) as response:
        for raw_line in response:
            line = raw_line.decode(errors="replace").strip()
            if not line.startswith("data: ") or line == "data: [DONE]":
                continue
            event = json.loads(line[6:])
            choice = event.get("choices", [{}])[0]
            delta = choice.get("delta", {})
            text = str(delta.get("content") or "")
            reasoning = str(delta.get("reasoning_content") or "")
            if (text or reasoning) and first_any_token is None:
                first_any_token = time.perf_counter()
            if text:
                if first_token is None:
                    first_token = time.perf_counter()
                chunks.append(text)
            if reasoning:
                reasoning_chunks.append(reasoning)
            if choice.get("finish_reason") is not None:
                finish_reason = choice.get("finish_reason")
    finished = time.perf_counter()
    output = "".join(chunks)
    try:
        parsed = extract_json(output)
        json_valid = True
    except (json.JSONDecodeError, ValueError, IndexError):
        parsed = {}
        json_valid = False
    return {
        "ttfbAnySec": round((first_any_token or finished) - started, 3),
        "ttfbSec": round((first_token or finished) - started, 3),
        "totalSec": round(finished - started, 3),
        "finishReason": finish_reason,
        "jsonValid": json_valid,
        "show": parsed.get("show"),
        "title": parsed.get("title", ""),
        "reason": parsed.get("reason", ""),
        "reasoningPreview": "".join(reasoning_chunks)[:240],
        "output": output if not json_valid else "",
    }


def main() -> None:
    args = parse_args()
    plugin_dir = Path(__file__).resolve().parent.parent
    system_prompt = (plugin_dir / "prompts/assistant-system.md").read_text(encoding="utf-8")
    for run in range(1, args.repeat + 1):
        for case in CASES:
            result = request_case(args, system_prompt, case["context"], case["hints"])
            print(
                json.dumps(
                    {
                        "run": run,
                        "case": case["name"],
                        "expectedShow": case["expectedShow"],
                        "decisionCorrect": result["show"] == case["expectedShow"],
                        **result,
                    },
                    ensure_ascii=False,
                ),
                flush=True,
            )


if __name__ == "__main__":
    main()
