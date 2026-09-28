"""
Shared helpers for the Cortex Code Agent SDK prototypes.

Every agent in this folder follows the same shape: stream the agent's text to
stdout, validate the final structured output with a Pydantic model, and print
it as JSON. This module holds that plumbing so each script only defines its
schema, prompts and CLI.

Exit codes (see ``run_main``), so the scripts can gate cron jobs or CI:
    0  report produced, nothing needing attention
    1  agent or SDK error
    2  agent finished but returned no valid structured output
    3  report produced and it flags findings (script-specific, e.g. SLA breach)
  130  interrupted (Ctrl+C)
"""

import asyncio
import json
import sys
from datetime import datetime, timezone
from typing import Awaitable, Callable, TypeVar

from pydantic import BaseModel, ValidationError
from cortex_code_agent_sdk import (
    query,
    AssistantMessage,
    ResultMessage,
    CortexCodeAgentOptions,
    CortexCodeSDKClient,
    CortexCodeSDKError,
    CLINotFoundError,
    HookMatcher,
)

EXIT_OK = 0
EXIT_ERROR = 1
EXIT_NO_OUTPUT = 2
EXIT_FINDINGS = 3

T = TypeVar("T", bound=BaseModel)


class AgentRunError(Exception):
    """The agent session ended in an error or without usable output."""

    def __init__(self, message: str, exit_code: int = EXIT_ERROR):
        super().__init__(message)
        self.exit_code = exit_code


# ---------------------------------------------------------------------------
# Options and hooks
# ---------------------------------------------------------------------------

def make_options(system_prompt: str, **overrides) -> CortexCodeAgentOptions:
    """Options shared by every prototype: SQL tool only, current directory."""
    kwargs = {"cwd": ".", "allowed_tools": ["SQL"], "system_prompt": system_prompt}
    kwargs.update(overrides)
    return CortexCodeAgentOptions(**kwargs)


def sql_audit_hooks(audit_log: list[dict]) -> dict:
    """PreToolUse hook config that appends every SQL tool call to ``audit_log``."""

    async def audit_sql_hook(input_data, tool_use_id, context):
        # The bundled SDK docs name this tool "SQL" (as in allowed_tools) while
        # some versions report "sql_execute"; accept both so the log is not empty.
        if input_data.get("tool_name") in ("SQL", "sql_execute"):
            sql = input_data.get("tool_input", {}).get("sql", "")
            audit_log.append({
                "timestamp": datetime.now(timezone.utc).isoformat(),
                "tool_use_id": tool_use_id,
                "sql": sql[:500],
            })
            print(f"  [AUDIT] {sql[:80]}...", file=sys.stderr)
        return {"continue_": True}

    return {"PreToolUse": [HookMatcher(matcher=None, hooks=[audit_sql_hook], timeout=10.0)]}


# ---------------------------------------------------------------------------
# Message handling
# ---------------------------------------------------------------------------

def _print_text(message: AssistantMessage) -> None:
    for block in message.content:
        if hasattr(block, "text"):
            print(block.text, end="", flush=True)


def _finish(result: ResultMessage | None, model: type[T]) -> T:
    if result is None:
        raise AgentRunError("agent stream ended without a result message")
    print(f"\n\n--- Agent finished (turns={result.num_turns}, "
          f"duration={result.duration_ms}ms) ---")
    if result.is_error:
        detail = "; ".join(result.errors or []) or result.subtype
        raise AgentRunError(f"agent error: {detail}")
    if not result.structured_output:
        raise AgentRunError("no structured output returned", EXIT_NO_OUTPUT)
    try:
        return model.model_validate(result.structured_output)
    except ValidationError as exc:
        raise AgentRunError(f"structured output failed validation: {exc}", EXIT_NO_OUTPUT)


# ---------------------------------------------------------------------------
# Session patterns
# ---------------------------------------------------------------------------

async def run_structured(prompt: str, model: type[T], options: CortexCodeAgentOptions) -> T:
    """Single-shot session that returns a validated ``model`` instance."""
    options.output_format = {"type": "json_schema", "schema": model.model_json_schema()}
    result = None
    async for message in query(prompt=prompt, options=options):
        if isinstance(message, AssistantMessage):
            _print_text(message)
        elif isinstance(message, ResultMessage):
            result = message
    return _finish(result, model)


async def run_multi_turn(
    turns: list[tuple[str, str]],
    final: tuple[str, str],
    model: type[T],
    options: CortexCodeAgentOptions,
) -> T:
    """Free-form investigation turns, then one structured final turn.

    ``turns`` and ``final`` are ``(label, prompt)`` pairs. The investigation
    turns run in one ``CortexCodeSDKClient`` session without an output format.
    Options cannot be changed on a live client, so the final turn resumes that
    same session through ``query(resume=session_id)`` with the JSON schema set.
    It keeps the full conversation, including earlier tool results.
    """
    session_id = None
    async with CortexCodeSDKClient(options) as client:
        for i, (label, prompt) in enumerate(turns, start=1):
            print(f"=== Turn {i}: {label} ===\n")
            await client.query(prompt)
            async for message in client.receive_response():
                if isinstance(message, AssistantMessage):
                    _print_text(message)
                elif isinstance(message, ResultMessage):
                    if message.is_error:
                        raise AgentRunError(f"turn {i} failed: {message.subtype}")
                    session_id = message.session_id
                    print(f"\n  (turn {i} done, {message.num_turns} agent turns)\n")
    if not session_id:
        raise AgentRunError("investigation turns returned no session id")

    label, prompt = final
    print(f"=== Turn {len(turns) + 1}: {label} ===\n")
    options.resume = session_id
    return await run_structured(prompt, model, options)


# ---------------------------------------------------------------------------
# Output and entry point
# ---------------------------------------------------------------------------

def print_report(title: str, report: BaseModel) -> None:
    print(f"\n========== {title} ==========")
    print(json.dumps(report.model_dump(), indent=2))


def run_main(coro_factory: Callable[[], Awaitable[int | None]]) -> None:
    """Run an agent coroutine and exit with a meaningful status code.

    The coroutine may return ``EXIT_FINDINGS`` to signal that the report
    flags something (SLA breach, anomalies, no-go); ``None`` means success.
    """
    try:
        code = asyncio.run(coro_factory())
    except KeyboardInterrupt:
        print("\nInterrupted.", file=sys.stderr)
        sys.exit(130)
    except AgentRunError as exc:
        print(f"\nError: {exc}", file=sys.stderr)
        sys.exit(exc.exit_code)
    except CLINotFoundError:
        print("Error: Cortex Code CLI not found. Install it or set CORTEX_CODE_CLI_PATH.",
              file=sys.stderr)
        sys.exit(EXIT_ERROR)
    except CortexCodeSDKError as exc:
        print(f"Error: Cortex Code SDK failure: {exc}", file=sys.stderr)
        sys.exit(EXIT_ERROR)
    sys.exit(code or EXIT_OK)
