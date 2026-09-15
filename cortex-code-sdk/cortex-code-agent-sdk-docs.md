# Cortex Code Agent SDK - Complete Documentation

All pages fetched from https://docs.snowflake.com/en/user-guide/cortex-code-agent-sdk/

---

## Page 1: Cortex Code Agent SDK (Main Page)
**URL:** https://docs.snowflake.com/en/user-guide/cortex-code-agent-sdk/cortex-code-agent-sdk

### Overview

The Cortex Code Agent SDK lets you build agentic AI applications using Python and TypeScript. Your agents can read files, run commands, search codebases, execute SQL, and edit code, using the same tools and agent loop that power Cortex Code.

The SDK includes built-in tools for file operations, shell commands, and code editing, so your agent can start working immediately without you implementing tool execution.

**TypeScript:**

```typescript
for await (const message of query({
  prompt: "Explore the SALES.PUBLIC schema and give me a one-paragraph summary of the tables it contains.",
  options: { cwd: process.cwd() },
})) {
  if (message.type === "assistant") {
    for (const block of message.content) {
      if (block.type === "text") process.stdout.write(block.text);
    }
  }
}
```

**Python:**

```python
from cortex_code_agent_sdk import query, AssistantMessage, CortexCodeAgentOptions

async def main():
    async for message in query(
        prompt="Explore the SALES.PUBLIC schema and give me a one-paragraph summary of the tables it contains.",
        options=CortexCodeAgentOptions(cwd="."),
    ):
        if isinstance(message, AssistantMessage):
            for block in message.content:
                if hasattr(block, "text"):
                    print(block.text, end="")

asyncio.run(main())
```

### Get started

#### Prerequisites

| Requirement | Details |
|---|---|
| Cortex Code CLI | Install with `curl -LsS https://ai.snowflake.com/static/cc-scripts/install.sh \| sh` |
| Snowflake connection | Configured through Snowflake CLI connection settings, typically in `~/.snowflake/connections.toml`. Existing setups in `~/.snowflake/config.toml` are also supported. Pass the `connection` option or set `default_connection_name` in the TOML file. |
| Node.js (TypeScript) | Version 22.0.0 or later |
| Python (Python SDK) | Version 3.10 or later |

#### 1. Install the Cortex Code CLI

```shell
curl -LsS https://ai.snowflake.com/static/cc-scripts/install.sh | sh
```

#### 2. Install the SDK

**TypeScript:**
```shell
npm install cortex-code-agent-sdk
```

**Python:**
```shell
pip install cortex-code-agent-sdk
```

#### 3. Configure your Snowflake connection

```toml
[my-connection]
account = "myorg-myaccount"
user = "myuser"
authenticator = "externalbrowser"
```

The SDK uses the CLI's default connection unless you specify one explicitly through the `connection` option.

If the Cortex Code CLI is not on your `PATH`, point the SDK at it by setting `CORTEX_CODE_CLI_PATH=/path/to/cortex` or by passing `cliPath` (TypeScript) or `cli_path` (Python) in the SDK options.

#### 4. Run your first agent

**TypeScript:**

```typescript
for await (const message of query({
  prompt:
    "Explore the SALES.PUBLIC schema and summarize its tables, then profile the ORDERS table: " +
    "report its row count, its columns and types, and the NULL rate of each column.",
  options: {
    cwd: process.cwd(),
    allowedTools: ["SQL"],
  },
})) {
  if (message.type === "assistant") {
    for (const block of message.content) {
      if (block.type === "text") process.stdout.write(block.text);
    }
  }
  if (message.type === "result") {
    console.log("\nDone:", message.subtype);
  }
}
```

**Python:**

```python
from cortex_code_agent_sdk import query, AssistantMessage, ResultMessage, CortexCodeAgentOptions

async def main():
    async for message in query(
        prompt=(
            "Explore the SALES.PUBLIC schema and summarize its tables, then profile the ORDERS table: "
            "report its row count, its columns and types, and the NULL rate of each column."
        ),
        options=CortexCodeAgentOptions(
            cwd=".",
            allowed_tools=["SQL"],
        ),
    ):
        if isinstance(message, AssistantMessage):
            for block in message.content:
                if hasattr(block, "text"):
                    print(block.text, end="")
        elif isinstance(message, ResultMessage):
            print(f"\nDone: {message.subtype}")

asyncio.run(main())
```

### Capabilities

#### Built-in tools

| Tool | Description |
|---|---|
| **Read** | Read any file in the working directory |
| **Write** | Create new files |
| **Edit** | Make precise edits to existing files |
| **Bash** | Run terminal commands, scripts, and git operations |
| **Glob** | Find files by pattern (`**/*.ts`, `src/**/*.py`) |
| **Grep** | Search file contents with regex |
| **SQL** | Execute SQL queries against Snowflake |

#### Multi-turn sessions

```typescript
const session = await createCortexCodeSession({
  cwd: process.cwd(),
  allowedTools: ["SQL"],
});

await session.send("List the tables in the SALES.PUBLIC schema with their row counts.");
for await (const event of session.stream()) {
  if (event.type === "result") break;
}

await session.send("Now write a query that joins the two largest tables.");
for await (const event of session.stream()) {
  if (event.type === "result") break;
}

await session.close();
```

**Python:**

```python
from cortex_code_agent_sdk import CortexCodeSDKClient, CortexCodeAgentOptions

async with CortexCodeSDKClient(CortexCodeAgentOptions(allowed_tools=["SQL"])) as client:
    await client.query("List the tables in the SALES.PUBLIC schema with their row counts.")
    async for msg in client.receive_response():
        pass

    await client.query("Now write a query that joins the two largest tables.")
    async for msg in client.receive_response():
        pass
```

Continue/fork sessions:

```typescript
// Continue the most recent conversation
const session = await createCortexCodeSession({
  cwd: process.cwd(),
  continue: true,
});

// Or fork a resumed session into a new session ID
const forked = await createCortexCodeSession({
  cwd: process.cwd(),
  resume: "previous-session-id",
  forkSession: true,
});
```

```python
# Continue the most recent conversation
async with CortexCodeSDKClient(
    CortexCodeAgentOptions(continue_conversation=True)
) as client:
    await client.query("What were we working on?")

# Or fork a resumed session into a new session ID
async with CortexCodeSDKClient(
    CortexCodeAgentOptions(resume="previous-session-id", fork_session=True)
) as client:
    await client.query("Let's try a different approach")
```

#### MCP servers

```python
from cortex_code_agent_sdk import CortexCodeAgentOptions

options = CortexCodeAgentOptions(
    mcp_servers={
        "my-tools": {
            "command": "node",
            "args": ["my-mcp-server.js"],
        },
    },
)
```

#### Hooks

Available hook events include `PreToolUse`, `PostToolUse`, `Stop`, `UserPromptSubmit`, and more.

#### Structured output

```typescript
const result = query({
  prompt: "Profile the ORDERS table in the SALES.PUBLIC schema",
  options: {
    cwd: ".",
    allowedTools: ["SQL"],
    outputFormat: {
      type: "json_schema",
      schema: {
        type: "object",
        properties: {
          table: { type: "string" },
          row_count: { type: "number" },
          columns: {
            type: "array",
            items: {
              type: "object",
              properties: {
                name: { type: "string" },
                type: { type: "string" },
                null_rate: { type: "number" },
              },
              required: ["name", "type", "null_rate"],
            },
          },
        },
        required: ["table", "row_count", "columns"],
      },
    },
  },
});
```

#### Session control

| Option | Description |
|---|---|
| `maxTurns` / `max_turns` | Limit the number of agentic turns before the agent stops |
| `effort` | Set model thinking effort (`"minimal"`, `"low"`, `"medium"`, `"high"`, `"max"`) |
| `abortController` / `abort_event` | Interrupt the running agent mid-turn. The session stays alive for further prompts. |
| `env` | Pass environment variables to the agent process |
| `additionalDirectories` / `add_dirs` | Add extra directories the agent can access beyond `cwd` |
| `plugins` | Load plugin directories for custom extensions |
| `systemPrompt` / `system_prompt` | Replace or append to the default system prompt |
| `settingSources` / `setting_sources` | Control which setting files are loaded (`"user"`, `"project"`, `"local"`) |

### Supported models

| Model | Identifier |
|---|---|
| Auto (recommended) | `auto` |
| Claude Opus 5 | `claude-opus-5` |
| Claude Opus 4.8 | `claude-opus-4-8` |
| Claude Opus 4.7 | `claude-opus-4-7` |
| Claude Opus 4.6 | `claude-opus-4-6` |
| Claude Opus 4.5 | `claude-opus-4-5` |
| Claude Sonnet 5 | `claude-sonnet-5` |
| Claude Sonnet 4.6 | `claude-sonnet-4-6` |
| Claude Sonnet 4.5 | `claude-sonnet-4-5` |
| Claude Sonnet 4.0 | `claude-4-sonnet` |
| OpenAI GPT 5.5 (Preview) | `openai-gpt-5.5` |
| OpenAI GPT 5.4 | `openai-gpt-5.4` |
| OpenAI GPT 5.2 | `openai-gpt-5.2` |

#### Cross-region inference

```sql
ALTER ACCOUNT SET CORTEX_ENABLED_CROSS_REGION = 'AWS_US';
```

---

## Page 2: Quickstart
**URL:** https://docs.snowflake.com/en/user-guide/cortex-code-agent-sdk/quickstart

This walks through building an AI agent that reads a data pipeline script, finds bugs, and fixes them automatically.

### Setup

```shell
mkdir my-agent && cd my-agent
npm init -y
npm install cortex-code-agent-sdk
```

Or Python:
```shell
python3 -m venv .venv && source .venv/bin/activate
pip install cortex-code-agent-sdk
```

### Build an agent that finds and fixes bugs

**TypeScript:**

```typescript
// agent.mjs
for await (const message of query({
  prompt: "Review report.ts for bugs in the data pipeline. Fix any issues you find.",
  options: {
    cwd: process.cwd(),
    connection: "my-connection",
    allowedTools: ["Read", "Edit", "Bash"],
  },
})) {
  if (message.type === "assistant") {
    for (const block of message.content) {
      if (block.type === "text") {
        process.stdout.write(block.text);
      } else if (block.type === "tool_use") {
        console.log(`Tool: ${block.name}`);
      }
    }
  } else if (message.type === "result") {
    console.log(`\nDone: ${message.subtype}`);
  }
}
```

**Python:**

```python
# agent.py
from cortex_code_agent_sdk import query, AssistantMessage, ResultMessage, CortexCodeAgentOptions

async def main():
    async for message in query(
        prompt="Review report.py for bugs in the data pipeline. Fix any issues you find.",
        options=CortexCodeAgentOptions(
            cwd=".",
            connection="my-connection",
            allowed_tools=["Read", "Edit", "Bash"],
        ),
    ):
        if isinstance(message, AssistantMessage):
            for block in message.content:
                if hasattr(block, "text"):
                    print(block.text, end="")
                elif hasattr(block, "name"):
                    print(f"Tool: {block.name}")
        elif isinstance(message, ResultMessage):
            print(f"\nDone: {message.subtype}")

asyncio.run(main())
```

### Permission modes

| Mode | Behavior | Use case |
|---|---|---|
| `"bypassPermissions"` (with safety flag) | Runs every tool without prompts. Requires `allowDangerouslySkipPermissions: true` | Sandboxed CI, fully trusted environments |
| `"default"` | Uses standard permission checks. Configure `allowedTools`, `disallowedTools`, or `canUseTool` | Controlled workflows with explicit permission policy |
| `"autoAcceptPlans"` | Auto-approves plan requests and plan-exit confirmations | Specialized workflows that want plan approvals to proceed automatically |
| `"plan"` | Starts in planning; approving `ExitPlanMode` lets execution continue | Code review, analysis |

---

## Page 3: Build a Data Copilot
**URL:** https://docs.snowflake.com/en/user-guide/cortex-code-agent-sdk/build-a-data-copilot

Builds a data engineering copilot web app (Next.js) with three tools backed by the SDK:

- **Pipeline health audit**: discovers tables, counts rows, checks load freshness, returns typed health report (structured output)
- **Schema drift detector**: compares two schemas, returns typed list of changes with breaking changes flagged
- **AI query optimizer**: multi-turn agent session diagnoses bottleneck then produces optimized rewrite

### Shared options helper

```typescript
// lib/sdk.ts
import {
  CortexCodeSessionOptions,
  ContentBlock,
  TextBlock,
  ToolUseBlock,
} from "cortex-code-agent-sdk";

export function sdkOptions(
  override?: Partial<CortexCodeSessionOptions>,
): CortexCodeSessionOptions {
  const connection =
    process.env.SNOWFLAKE_DEFAULT_CONNECTION_NAME ||
    process.env.SNOWFLAKE_CONNECTION_NAME;

  return {
    permissionMode: "bypassPermissions",
    allowDangerouslySkipPermissions: true,
    noMcp: true,
    ...(connection ? { connection } : {}),
    ...override,
  };
}

export function textBlocks(content: ContentBlock[]): TextBlock[] {
  return content.filter((b): b is TextBlock => b.type === "text");
}

export function sqlToolUses(content: ContentBlock[]): string[] {
  return content
    .filter((b): b is ToolUseBlock => b.type === "tool_use" && b.name === "SQL")
    .map((b) => {
      const input = b.input as Record<string, unknown>;
      return (input.command ?? input.query ?? JSON.stringify(input)) as string;
    });
}
```

### Tool 1: Pipeline health audit (Structured output)

```typescript
const AUDIT_OUTPUT_SCHEMA = {
  type: "object",
  properties: {
    tables: {
      type: "array",
      items: {
        type: "object",
        properties: {
          name: { type: "string" },
          rowCount: { type: "number" },
          lastLoaded: { type: ["string", "null"] },
          hoursSinceLoad: { type: ["number", "null"] },
          status: { type: "string", enum: ["healthy", "stale", "empty", "high_nulls"] },
          recommendation: { type: "string" },
        },
        required: ["name", "rowCount", "lastLoaded", "hoursSinceLoad", "status", "recommendation"],
      },
    },
    total: { type: "number" },
    healthy: { type: "number" },
    issues: { type: "number" },
  },
  required: ["tables", "total", "healthy", "issues"],
};

for await (const event of query({
  prompt,
  options: sdkOptions({
    allowedTools: ["SQL"],
    outputFormat: { type: "json_schema", schema: AUDIT_OUTPUT_SCHEMA as Record<string, unknown> },
  }),
})) {
  if (event.type === "system" && event.subtype === "init") {
    console.log(`Agent started, model: ${event.model}`);
  }
  if (event.type === "assistant") {
    for (const block of textBlocks(event.content)) { /* stream text */ }
    for (const sql of sqlToolUses(event.content)) { /* stream SQL */ }
  }
  if (event.type === "result" && event.subtype === "success") {
    const report = event.structured_output as {
      tables: unknown[];
      total: number;
      healthy: number;
      issues: number;
    };
    console.log(`${report.issues} issue(s) across ${report.total} tables`);
  }
}
```

**Python:**

```python
from pydantic import BaseModel
from cortex_code_agent_sdk import query, AssistantMessage, ResultMessage, CortexCodeAgentOptions

class TableHealth(BaseModel):
    name: str
    row_count: int
    last_loaded: str | None
    hours_since_load: float | None
    status: str  # "healthy" | "stale" | "empty" | "high_nulls"
    recommendation: str

class PipelineReport(BaseModel):
    tables: list[TableHealth]
    total: int
    healthy: int
    issues: int

async for msg in query(
    prompt=f"Audit schema {database}.{schema}: flag stale (>24h), empty, and high-null tables",
    options=CortexCodeAgentOptions(
        connection="my-connection",
        allowed_tools=["SQL"],
        output_format={"type": "json_schema", "schema": PipelineReport.model_json_schema()},
    ),
):
    if isinstance(msg, ResultMessage) and msg.structured_output:
        report = PipelineReport(**msg.structured_output)
        print(f"{report.issues} issue(s) across {report.total} tables")
```

### Tool 2: Schema drift detector

```typescript
const SCHEMA_DIFF_OUTPUT = {
  type: "object",
  properties: {
    sourceSchema: { type: "string" },
    targetSchema: { type: "string" },
    tablesCompared: { type: "number" },
    addedTables: { type: "array", items: { type: "string" } },
    removedTables: { type: "array", items: { type: "string" } },
    changes: {
      type: "array",
      items: {
        type: "object",
        properties: {
          tableName: { type: "string" },
          columnName: { type: "string" },
          changeType: { type: "string", enum: ["added", "removed", "type_changed"] },
          sourceType: { type: ["string", "null"] },
          targetType: { type: ["string", "null"] },
          isBreaking: { type: "boolean" },
        },
        required: ["tableName", "columnName", "changeType", "sourceType", "targetType", "isBreaking"],
      },
    },
    breakingChanges: { type: "number" },
  },
  required: ["sourceSchema", "targetSchema", "tablesCompared", "addedTables", "removedTables", "changes", "breakingChanges"],
};

// Use as deploy gate:
if (diff.breakingChanges > 0) {
  process.exit(1); // In CI, block the deploy
}
```

### Tool 3: AI query optimizer (Multi-turn)

```typescript
const session = await createCortexCodeSession(
  sdkOptions({
    allowedTools: ["SQL"],
    appendSystemPrompt:
      "You are a Snowflake SQL expert. When diagnosing queries, be specific about " +
      "micro-partition pruning, clustering keys, partition pruning ratios, and warehouse " +
      "sizing. Reference Snowflake-native features by name.",
  }),
);

const init = await session.initializationResult();

// Turn 1: diagnose the bottleneck
await session.send(
  `Diagnose this Snowflake SQL query. Identify the main performance bottleneck:\n\n\`\`\`sql\n${sql}\n\`\`\``,
);
await streamTurn();

// Turn 2: rewrite with full diagnosis context
await session.send(
  "Now produce the full optimized rewrite of that query with inline comments explaining each key change.",
);
await streamTurn();

await session.close();
```

---

## Page 4: MCP Servers
**URL:** https://docs.snowflake.com/en/user-guide/cortex-code-agent-sdk/mcp-custom-tools

Supports transports: `stdio`, `http`, `sse`.

### Stdio servers

```typescript
for await (const message of query({
  prompt: "Search our docs for authentication best practices",
  options: {
    cwd: process.cwd(),
    permissionMode: "bypassPermissions",
    allowDangerouslySkipPermissions: true,
    mcpServers: {
      "my-tools": {
        command: "node",
        args: ["my-mcp-server.js"],
      },
    },
  },
})) {
  // Handle messages...
}
```

### HTTP and SSE servers

```typescript
for await (const message of query({
  prompt: "Look up customer data",
  options: {
    cwd: process.cwd(),
    permissionMode: "bypassPermissions",
    allowDangerouslySkipPermissions: true,
    mcpServers: {
      "remote-api": {
        type: "http",
        url: "https://my-mcp-server.example.com/mcp",
        headers: { "Authorization": "Bearer ${MCP_TOKEN}" },
      },
    },
  },
})) {
  // Handle messages...
}
```

### Controlling which MCP tools are allowed

MCP tools namespaced: `mcp__<server-name>__<tool-name>`.

```typescript
allowedTools: [
  "mcp__my-tools__search_docs",
  "mcp__my-tools__*",
],
```

### Disabling MCP

```typescript
const session = await createCortexCodeSession({
  cwd: process.cwd(),
  noMcp: true,
});
```

---

## Page 5: Multi-turn Sessions and Streaming Input
**URL:** https://docs.snowflake.com/en/user-guide/cortex-code-agent-sdk/streaming-input

### Input patterns

| Mode | When to use | API |
|---|---|---|
| **Single prompt input** | Send one prompt with `query()` | `query()` |
| **Streamed input** | Send user messages incrementally from an async iterable | `query()` + `Query.streamInput()` |
| **Multi-turn session** | Interactive conversations with context | `createCortexCodeSession()` / `CortexCodeSDKClient` |

### Session lifecycle (TypeScript)

1. Call `createCortexCodeSession(options)` to start a session
2. Call `session.send(prompt)` to send a user message
3. Iterate `session.stream()` to receive responses. Stop on `result` event.
4. Repeat steps 2-3
5. Call `session.close()` to end

### Session lifecycle (Python)

1. Create `CortexCodeSDKClient` and call `connect()` (or use `async with`)
2. Call `client.query(prompt)`
3. Iterate `client.receive_response()` to get messages up to `ResultMessage`
4. Repeat steps 2-3
5. Call `client.disconnect()` (or let `async with` exit)

### Continue a previous session

```typescript
const session = await createCortexCodeSession({
  cwd: process.cwd(),
  continue: true,
});
```

### Fork a session

```typescript
const forked = await createCortexCodeSession({
  cwd: process.cwd(),
  resume: "previous-session-id",
  forkSession: true,
});
```

### Interrupt a turn

```typescript
const session = await createCortexCodeSession({ cwd: process.cwd() });
await session.send("Analyze every file in this large codebase");
setTimeout(() => session.interrupt(), 10_000);
```

Or with abort controller:

```typescript
const controller = new AbortController();
const session = await createCortexCodeSession({
  cwd: process.cwd(),
  abortController: controller,
});
setTimeout(() => controller.abort(), 10_000);
```

**Python:**

```python
abort_event = asyncio.Event()
async with CortexCodeSDKClient(
    CortexCodeAgentOptions(cwd=".", abort_event=abort_event)
) as client:
    # abort_event.set() triggers interrupt
```

---

## Page 6: System Prompts
**URL:** https://docs.snowflake.com/en/user-guide/cortex-code-agent-sdk/system-prompts

### Replace the default prompt

```typescript
const session = await createCortexCodeSession({
  cwd: process.cwd(),
  systemPrompt: `You are a code review assistant.
Prioritize finding bugs, security issues, and maintainability risks.
Explain the issue and suggest concrete fixes.`,
});
```

**Warning:** Replacing the default prompt removes all built-in instructions, including tool usage guidance and safety guardrails.

### Append to the default prompt

```typescript
const session = await createCortexCodeSession({
  cwd: process.cwd(),
  systemPrompt: {
    type: "preset",
    append: "Focus on Python files. Always run pytest after making changes.",
  },
});
```

Shorthand:

```typescript
const session = await createCortexCodeSession({
  cwd: process.cwd(),
  appendSystemPrompt: "Focus on Python files. Always run pytest after making changes.",
});
```

```python
options = CortexCodeAgentOptions(
    append_system_prompt="Focus on Python files. Always run pytest after making changes.",
)
```

### Common patterns

**Review-focused code reviewer:**
```
You are a code reviewer. Follow these rules:
- Prioritize reading code and analyzing behavior before proposing changes.
- Do not modify files unless the user explicitly asks for an implementation.
- Identify bugs, security issues, and style problems.
- Provide specific line numbers and suggested fixes in your response.
```

**Domain-specific expert:**
```
You are a SQL and database specialist working with Snowflake.
- Write efficient SQL queries optimized for Snowflake's columnar storage.
- Use Snowflake-specific features like VARIANT columns and FLATTEN.
- Always include LIMIT clauses in exploratory queries.
- Validate SQL syntax before suggesting changes.
```

**Style enforcer:**
```
Enforce these coding standards in all changes:
- Use TypeScript strict mode conventions.
- Prefer const over let; never use var.
- All functions must have explicit return types.
- Use async/await instead of raw Promises.
- Run "npm run lint" after every file change.
```

### When to append vs. replace

| Append to the default prompt | Replace the default prompt |
|---|---|
| You want to add domain context or constraints | You need full control over agent behavior |
| You want to keep built-in tool usage guidance | You are building a highly specialized agent |
| You want to maintain safety guardrails | The default instructions conflict with your use case |

---

## Page 7: Handle Approvals and User Input
**URL:** https://docs.snowflake.com/en/user-guide/cortex-code-agent-sdk/user-input

### Permission levels

| Level | Behavior |
|---|---|
| `allowedTools` / `allowed_tools` | Auto-approve listed tools |
| `disallowedTools` / `disallowed_tools` | Block listed tools entirely |
| `canUseTool` | Custom callback for per-call decisions |
| `permissionMode: "bypassPermissions"` | Skip all permission checks (requires safety flag) |

### Using allowedTools

```typescript
for await (const message of query({
  prompt: "List the tables in the SALES schema",
  options: {
    cwd: process.cwd(),
    allowedTools: ["SQL", "Read"],
  },
})) {
  // Handle messages
}
```

### Using canUseTool callback

**TypeScript:**

```typescript
const session = await createCortexCodeSession({
  cwd: process.cwd(),
  canUseTool: async (toolUse) => {
    if (toolUse.name === "SQL") {
      const sql = (toolUse.input as Record<string, unknown>).sql as string;
      if (sql.trim().toUpperCase().startsWith("DROP")) {
        return { behavior: "deny", message: "DROP statements are not allowed" };
      }
      return { behavior: "allow" };
    }
    if (toolUse.name === "Bash") {
      return { behavior: "deny", message: "Bash is not allowed in this session" };
    }
    return { behavior: "allow" };
  },
});
```

**Python:**

```python
from cortex_code_agent_sdk import CortexCodeSDKClient, CortexCodeAgentOptions

async def can_use_tool(tool_use):
    if tool_use.name == "SQL":
        sql = tool_use.input.get("sql", "")
        if sql.strip().upper().startswith("DROP"):
            return {"behavior": "deny", "message": "DROP statements are not allowed"}
        return {"behavior": "allow"}
    if tool_use.name == "Bash":
        return {"behavior": "deny", "message": "Bash is not allowed in this session"}
    return {"behavior": "allow"}

async with CortexCodeSDKClient(
    CortexCodeAgentOptions(can_use_tool=can_use_tool)
) as client:
    ...
```

### canUseTool return values

| Behavior | Effect |
|---|---|
| `{ behavior: "allow" }` | Approve the tool call |
| `{ behavior: "deny", message: "..." }` | Block the tool call with explanation |
| `{ behavior: "ask" }` | Escalate to user (only in interactive contexts) |

### Handling user input prompts

When the agent needs user input (e.g., `AskUserQuestion`), the SDK emits an `InputRequest` event:

**TypeScript:**

```typescript
for await (const event of session.stream()) {
  if (event.type === "input_request") {
    // Present the question to the user
    const answer = await getUserAnswer(event.question);
    await session.sendInputResponse(event.id, answer);
  }
}
```

---

## Page 8: Structured Output
**URL:** https://docs.snowflake.com/en/user-guide/cortex-code-agent-sdk/structured-output

### Overview

Force the agent to return a response matching a JSON Schema by passing `outputFormat` in query options.

### Basic usage

**TypeScript:**

```typescript
for await (const message of query({
  prompt: "Profile the ORDERS table in the SALES.PUBLIC schema",
  options: {
    cwd: process.cwd(),
    allowedTools: ["SQL"],
    outputFormat: {
      type: "json_schema",
      schema: {
        type: "object",
        properties: {
          table: { type: "string" },
          row_count: { type: "number" },
          columns: {
            type: "array",
            items: {
              type: "object",
              properties: {
                name: { type: "string" },
                type: { type: "string" },
                null_rate: { type: "number" },
              },
              required: ["name", "type", "null_rate"],
            },
          },
        },
        required: ["table", "row_count", "columns"],
      },
    },
  },
})) {
  if (message.type === "result" && message.subtype === "success") {
    const profile = message.structured_output;
    // profile is validated against the schema
  }
}
```

**Python:**

```python
from pydantic import BaseModel
from cortex_code_agent_sdk import query, ResultMessage, CortexCodeAgentOptions

class ColumnProfile(BaseModel):
    name: str
    type: str
    null_rate: float

class TableProfile(BaseModel):
    table: str
    row_count: int
    columns: list[ColumnProfile]

async for msg in query(
    prompt="Profile the ORDERS table in the SALES.PUBLIC schema",
    options=CortexCodeAgentOptions(
        cwd=".",
        allowed_tools=["SQL"],
        output_format={"type": "json_schema", "schema": TableProfile.model_json_schema()},
    ),
):
    if isinstance(msg, ResultMessage) and msg.structured_output:
        profile = TableProfile(**msg.structured_output)
```

### Tips

- The structured output appears in `ResultMessage.structured_output`, not as streaming deltas
- Use Pydantic's `model_json_schema()` in Python to generate schemas from Python classes
- JSON Schema supports `type: ["string", "null"]` for nullable fields

---

## Page 9: Streaming Output
**URL:** https://docs.snowflake.com/en/user-guide/cortex-code-agent-sdk/streaming-output

### Enable streaming output

Set `includePartialMessages` (TypeScript) or `include_partial_messages` (Python) to `true`.

```typescript
for await (const message of query({
  prompt: "List the files in my project",
  options: {
    cwd: process.cwd(),
    includePartialMessages: true,
    allowedTools: ["Bash", "Read"],
  },
})) {
  if (message.type === "stream_event") {
    const event = message.event;
    if (event.type === "content_block_delta") {
      if (event.delta.type === "text_delta") {
        process.stdout.write(event.delta.text);
      }
    }
  }
}
```

### StreamEvent reference

**TypeScript:**
```typescript
interface SDKPartialAssistantMessage {
  type: "stream_event";
  event: Record<string, unknown>;
  parent_tool_use_id: string | null;
  uuid: string;
  session_id: string;
}
```

**Python:**
```python
@dataclass
class StreamEvent:
    uuid: str
    session_id: str
    event: dict[str, Any]
    parent_tool_use_id: str | None
```

### Event types

| Event Type | Description |
|---|---|
| `content_block_start` | Start of a new text or thinking block |
| `content_block_delta` | Incremental text or thinking update |
| `content_block_stop` | End of the current text or thinking block |

### Message flow

```text
SystemMessage -- session initialization
StreamEvent (content_block_start)
StreamEvent (content_block_delta) -- text_delta or thinking_delta chunks...
StreamEvent (content_block_stop)
AssistantMessage -- complete text/thinking block, or complete tool_use block
UserMessage -- complete tool_result block
... more assistant/user turns ...
ResultMessage -- final result
```

---

## Page 10: Hooks
**URL:** https://docs.snowflake.com/en/user-guide/cortex-code-agent-sdk/hooks

### Overview

Hooks let you run custom code at key points in the agent lifecycle.

### Available hook events

| Event | When it fires |
|---|---|
| `PreToolUse` | Before a tool is called |
| `PostToolUse` | After a tool completes |
| `Stop` | When the agent finishes |
| `UserPromptSubmit` | When a user prompt is submitted |
| `Notification` | When the agent emits a notification |

### TypeScript hooks

```typescript
const session = await createCortexCodeSession({
  cwd: process.cwd(),
  hooks: {
    PreToolUse: async (event) => {
      console.log(`About to call: ${event.toolName}`);
      // Return undefined to proceed, or return { action: "deny" } to block
      return undefined;
    },
    PostToolUse: async (event) => {
      console.log(`Tool ${event.toolName} completed`);
      if (event.toolName === "SQL") {
        // Log every SQL statement for audit
        const sql = (event.input as Record<string, unknown>).sql;
        await appendToAuditLog(sql as string);
      }
      return undefined;
    },
    Stop: async (event) => {
      console.log("Agent finished:", event.reason);
      return undefined;
    },
  },
});
```

### Python hooks

```python
from cortex_code_agent_sdk import CortexCodeSDKClient, CortexCodeAgentOptions

async def pre_tool_use(event):
    print(f"About to call: {event.tool_name}")
    return None  # proceed

async def post_tool_use(event):
    print(f"Tool {event.tool_name} completed")
    if event.tool_name == "SQL":
        await append_to_audit_log(event.input.get("sql", ""))
    return None

async with CortexCodeSDKClient(
    CortexCodeAgentOptions(
        hooks={
            "PreToolUse": pre_tool_use,
            "PostToolUse": post_tool_use,
        },
    )
) as client:
    ...
```

### Hook return values

- Return `None` / `undefined` to proceed normally
- Return `{ action: "deny", message: "..." }` from `PreToolUse` to block the tool call
- Hooks run synchronously in the agent loop (the agent waits for them)

---

## Page 11: TypeScript SDK Reference
**URL:** https://docs.snowflake.com/en/user-guide/cortex-code-agent-sdk/typescript-reference

### query() function

```typescript
import { query } from "cortex-code-agent-sdk";

function query(options: {
  prompt: string | AsyncIterable<SDKUserMessage>;
  options?: CortexCodeSessionOptions;
}): AsyncIterable<CortexCodeEvent>;
```

### createCortexCodeSession()

```typescript
import { createCortexCodeSession } from "cortex-code-agent-sdk";

async function createCortexCodeSession(
  options?: CortexCodeSessionOptions,
): Promise<CortexCodeSession>;
```

### CortexCodeSession

```typescript
interface CortexCodeSession {
  send(prompt: string): Promise<void>;
  stream(): AsyncIterable<CortexCodeEvent>;
  interrupt(): void;
  close(): Promise<void>;
  initializationResult(): Promise<Record<string, unknown>>;
  sendInputResponse(id: string, answer: string): Promise<void>;
}
```

### CortexCodeSessionOptions

```typescript
interface CortexCodeSessionOptions {
  cwd?: string;
  connection?: string;
  model?: string;
  maxTurns?: number;
  effort?: "minimal" | "low" | "medium" | "high" | "max";
  allowedTools?: string[];
  disallowedTools?: string[];
  canUseTool?: (toolUse: ToolUseBlock) => Promise<ToolPermission>;
  permissionMode?: "default" | "bypassPermissions" | "plan" | "autoAcceptPlans";
  allowDangerouslySkipPermissions?: boolean;
  systemPrompt?: string | { type: "preset"; append: string };
  appendSystemPrompt?: string;
  outputFormat?: { type: "json_schema"; schema: Record<string, unknown> };
  mcpServers?: Record<string, McpServerConfig>;
  noMcp?: boolean;
  env?: Record<string, string>;
  additionalDirectories?: string[];
  plugins?: string[];
  settingSources?: ("user" | "project" | "local")[];
  abortController?: AbortController;
  includePartialMessages?: boolean;
  hooks?: {
    PreToolUse?: (event: PreToolUseEvent) => Promise<HookResult | undefined>;
    PostToolUse?: (event: PostToolUseEvent) => Promise<HookResult | undefined>;
    Stop?: (event: StopEvent) => Promise<HookResult | undefined>;
    UserPromptSubmit?: (event: UserPromptSubmitEvent) => Promise<HookResult | undefined>;
  };
  continue?: boolean;
  resume?: string;
  forkSession?: boolean;
  cliPath?: string;
}
```

### CortexCodeEvent types

```typescript
type CortexCodeEvent =
  | SystemMessage      // type: "system", subtype: "init" | "status" | ...
  | AssistantMessage   // type: "assistant", content: ContentBlock[]
  | UserMessage        // type: "user" (tool results)
  | ResultMessage      // type: "result", subtype: "success" | "error_max_turns" | ...
  | StreamEvent        // type: "stream_event" (when includePartialMessages: true)
  | InputRequest;      // type: "input_request"
```

### ContentBlock types

```typescript
type ContentBlock =
  | TextBlock          // { type: "text", text: string }
  | ToolUseBlock       // { type: "tool_use", name: string, input: unknown, id: string }
  | ThinkingBlock;     // { type: "thinking", thinking: string }
```

### ResultMessage

```typescript
interface ResultMessage {
  type: "result";
  subtype: "success" | "error_max_turns" | "error_tool_denied" | "interrupted" | string;
  structured_output?: unknown;  // Present when outputFormat is set
  session_id: string;
  uuid: string;
}
```

---

## Page 12: Python SDK Reference
**URL:** https://docs.snowflake.com/en/user-guide/cortex-code-agent-sdk/python-reference

### query() function

```python
from cortex_code_agent_sdk import query

async def query(
    prompt: str | AsyncIterable,
    options: CortexCodeAgentOptions | None = None,
) -> AsyncIterator[Message]:
    ...
```

### CortexCodeSDKClient

```python
from cortex_code_agent_sdk import CortexCodeSDKClient

class CortexCodeSDKClient:
    def __init__(self, options: CortexCodeAgentOptions | None = None): ...
    async def connect(self) -> None: ...
    async def disconnect(self) -> None: ...
    async def query(self, prompt: str) -> None: ...
    async def receive_response(self) -> AsyncIterator[Message]: ...
    async def interrupt(self) -> None: ...
    async def send_input_response(self, id: str, answer: str) -> None: ...
    async def __aenter__(self) -> "CortexCodeSDKClient": ...
    async def __aexit__(self, *args) -> None: ...
```

### CortexCodeAgentOptions

```python
from cortex_code_agent_sdk import CortexCodeAgentOptions

@dataclass
class CortexCodeAgentOptions:
    cwd: str | None = None
    connection: str | None = None
    model: str | None = None
    max_turns: int | None = None
    effort: str | None = None  # "minimal" | "low" | "medium" | "high" | "max"
    allowed_tools: list[str] | None = None
    disallowed_tools: list[str] | None = None
    can_use_tool: Callable | None = None
    permission_mode: str | None = None
    allow_dangerously_skip_permissions: bool = False
    system_prompt: str | dict | None = None
    append_system_prompt: str | None = None
    output_format: dict | None = None
    mcp_servers: dict | None = None
    no_mcp: bool = False
    env: dict[str, str] | None = None
    add_dirs: list[str] | None = None
    plugins: list[str] | None = None
    setting_sources: list[str] | None = None
    abort_event: asyncio.Event | None = None
    include_partial_messages: bool = False
    hooks: dict | None = None
    continue_conversation: bool = False
    resume: str | None = None
    fork_session: bool = False
    cli_path: str | None = None
```

### Message types

```python
from cortex_code_agent_sdk import (
    AssistantMessage,
    UserMessage,
    ResultMessage,
    SystemMessage,
)
from cortex_code_agent_sdk.types import StreamEvent, InputRequest

@dataclass
class AssistantMessage:
    type: str = "assistant"
    content: list  # TextBlock, ToolUseBlock, ThinkingBlock
    uuid: str
    session_id: str
    parent_tool_use_id: str | None

@dataclass
class ResultMessage:
    type: str = "result"
    subtype: str  # "success", "error_max_turns", "interrupted", etc.
    structured_output: dict | None
    uuid: str
    session_id: str

@dataclass
class StreamEvent:
    type: str = "stream_event"
    event: dict[str, Any]
    uuid: str
    session_id: str
    parent_tool_use_id: str | None
```

---

## Important Notes

### This is the Cortex Code Agent SDK, NOT the Cortex Agent (SQL) specification

The Cortex Code Agent SDK is a **Python/TypeScript library** for building agents programmatically. It is distinct from:

- **Cortex Agent** (CREATE CORTEX AGENT SQL command) - which uses YAML spec files with `tools`, `instructions`, `sample_questions` etc.
- **code_toolset_all** - which is a tool type in the Cortex Agent SQL specification, not this SDK

The SDK docs do NOT cover:
- YAML agent specification format
- `code_toolset_all` tool definitions
- `instructions` format with `system`, `response`, `sample_questions` sections
- Document intelligence or AI function agent use cases via CREATE CORTEX AGENT

Those topics are covered in the **Cortex Agent** documentation (separate from the Agent SDK), typically at:
- https://docs.snowflake.com/en/user-guide/snowflake-cortex/cortex-agent

### SDK Key Patterns Summary

1. **`query()` for single prompts** - manages session lifecycle automatically
2. **`createCortexCodeSession()` / `CortexCodeSDKClient` for multi-turn** - maintains context
3. **`outputFormat` for structured output** - JSON Schema validated results
4. **`systemPrompt` / `appendSystemPrompt` for behavior customization**
5. **`allowedTools` / `disallowedTools` / `canUseTool` for permission control**
6. **`mcpServers` for external tool integration** - stdio, http, sse transports
7. **Hooks** - `PreToolUse`, `PostToolUse`, `Stop`, `UserPromptSubmit` for lifecycle events
8. **`includePartialMessages` for streaming** - real-time text deltas
