"""
Legacy Artifact Translator
===========================
Translates QlikView load scripts, Talend job XML, or QlikSense script
fragments into idiomatic Snowflake SQL (CREATE TABLE, COPY INTO, dynamic
tables, tasks). Returns a structured migration report with the generated
DDL/DML and a list of constructs that need manual review.

Uses the SDK's file-reading capability so the agent can parse the source
artifact directly from disk.

Usage:
    python legacy_translator_agent.py --file ./qlikview_load_script.qvs
    python legacy_translator_agent.py --file ./talend_job.xml --dialect talend
"""

import argparse
import asyncio
import json
import sys
from pathlib import Path

from pydantic import BaseModel
from cortex_code_agent_sdk import (
    query,
    AssistantMessage,
    ResultMessage,
    CortexCodeAgentOptions,
)

# ---------------------------------------------------------------------------
# Structured output schema
# ---------------------------------------------------------------------------

class TranslatedStatement(BaseModel):
    source_line: str
    snowflake_sql: str
    confidence: str  # "high", "medium", "low"
    notes: str

class ManualReviewItem(BaseModel):
    source_fragment: str
    reason: str
    suggestion: str

class MigrationReport(BaseModel):
    summary: str
    source_dialect: str
    total_statements: int
    auto_translated: int
    needs_review: int
    translated_statements: list[TranslatedStatement]
    manual_review_items: list[ManualReviewItem]
    full_snowflake_script: str

# ---------------------------------------------------------------------------
# Prompts
# ---------------------------------------------------------------------------

SYSTEM_PROMPT = """\
You are a data migration specialist embedded inside a Qlik-to-Snowflake
integration. Your job is to translate legacy ETL artifacts (QlikView load
scripts, QlikSense scripts, Talend job definitions) into idiomatic Snowflake
SQL — preferring modern constructs like dynamic tables, COPY INTO, and tasks
over manual procedural code.

Rules:
- Map QlikView LOAD/SQL statements to CREATE TABLE ... AS SELECT or dynamic tables.
- Map STORE to COPY INTO (Snowflake stage).
- Map QlikView variables to Snowflake session variables or task parameters.
- Flag any QlikView expressions (Aggr, IntervalMatch, ApplyMap) that have no
  direct Snowflake equivalent and need manual rewrite.
- For Talend, map tMap to SELECT/JOIN, tFileInputDelimited to COPY INTO.
- Always produce runnable Snowflake SQL — not pseudocode.
"""

def build_prompt(file_path: str, dialect: str, content: str) -> str:
    return f"""\
Translate the following {dialect} artifact into Snowflake SQL.

Source file: {file_path}

```
{content}
```

Steps:
1. Parse the artifact and identify each data-loading or transformation step.
2. For each step, produce the equivalent Snowflake SQL statement.
3. Rate your confidence (high/medium/low) for each translation.
4. Flag anything that cannot be auto-translated and explain why.
5. Assemble all translated statements into a single runnable Snowflake script
   in the `full_snowflake_script` field.
"""

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

async def run(file_path: str, dialect: str) -> None:
    path = Path(file_path)
    if not path.exists():
        print(f"Error: file not found: {file_path}", file=sys.stderr)
        sys.exit(1)

    content = path.read_text(encoding="utf-8", errors="replace")
    if len(content) > 50_000:
        print(f"Warning: file truncated to 50k chars (was {len(content)})", file=sys.stderr)
        content = content[:50_000]

    prompt = build_prompt(file_path, dialect, content)
    output_schema = MigrationReport.model_json_schema()

    print("Launching CoCo legacy translator agent...")
    print(f"  file={file_path}  dialect={dialect}  size={len(content)} chars\n")

    async for message in query(
        prompt=prompt,
        options=CortexCodeAgentOptions(
            cwd=".",
            allowed_tools=["SQL"],
            system_prompt=SYSTEM_PROMPT,
            output_format={"type": "json_schema", "schema": output_schema},
            max_turns=20,
        ),
    ):
        if isinstance(message, AssistantMessage):
            for block in message.content:
                if hasattr(block, "text"):
                    print(block.text, end="")

        elif isinstance(message, ResultMessage):
            print(f"\n\n--- Agent finished (turns={message.num_turns}, "
                  f"duration={message.duration_ms}ms) ---")
            if message.is_error:
                print(f"Agent error: {message.subtype}")
                return

            if message.structured_output:
                report = MigrationReport.model_validate(message.structured_output)
                print("\n========== MIGRATION REPORT ==========")
                print(json.dumps(report.model_dump(), indent=2))

                out_path = path.with_suffix(".snowflake.sql")
                out_path.write_text(report.full_snowflake_script, encoding="utf-8")
                print(f"\nGenerated Snowflake script written to: {out_path}")
            else:
                print("\nNo structured output returned.")


def main():
    parser = argparse.ArgumentParser(description="Legacy artifact → Snowflake SQL translator")
    parser.add_argument("--file", required=True,
                        help="Path to the legacy artifact (QlikView .qvs, Talend .xml, etc.)")
    parser.add_argument("--dialect", default="qlikview",
                        choices=["qlikview", "qliksense", "talend"],
                        help="Source dialect (default: qlikview)")
    args = parser.parse_args()

    asyncio.run(run(args.file, args.dialect))


if __name__ == "__main__":
    main()
