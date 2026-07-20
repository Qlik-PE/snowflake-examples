"""
Cortex Agent Chat Interface (Qlik MCP)

A Streamlit in Snowflake app that provides a chat UI for interacting with
a Cortex Agent wired to the Qlik MCP server. Uses the Snowpark session
and the MCP server connection — no raw REST calls needed.

Prerequisites:
  - Qlik MCP server created via mcp/create-mcp-agent.sql
  - Cortex Agent created and wired to the MCP server
  - User has completed OAuth flow: SELECT SYSTEM$START_USER_OAUTH_FLOW('<integration>')
  - Streamlit in Snowflake enabled
  - Appropriate grants on the agent and MCP server objects

Deploy:
  See README.md for deployment instructions.
"""

import streamlit as st
import json
from snowflake.snowpark.context import get_active_session

# =============================================================================
# Configuration
# =============================================================================

st.set_page_config(page_title="Qlik MCP Chat", page_icon="🤖", layout="wide")

DEFAULTS = {
    "database": "QLIK_MCP",
    "schema": "PUBLIC",
    "agent_name": "qlik_mcp",
    "mcp_server_name": "qlik_mcp_server",
}

# =============================================================================
# Snowpark Session
# =============================================================================

session = get_active_session()

# =============================================================================
# Sidebar - Agent Configuration
# =============================================================================

with st.sidebar:
    st.header("Qlik MCP Configuration")

    agent_database = st.text_input("Database", value=DEFAULTS["database"])
    agent_schema = st.text_input("Schema", value=DEFAULTS["schema"])
    agent_name = st.text_input("Agent Name", value=DEFAULTS["agent_name"])
    mcp_server_name = st.text_input("MCP Server", value=DEFAULTS["mcp_server_name"])

    st.divider()

    if st.button("Clear Conversation"):
        st.session_state.messages = []
        st.rerun()

    st.caption(
        f"Agent: `{agent_database}.{agent_schema}.{agent_name}`\n\n"
        f"MCP Server: `{agent_database}.{agent_schema}.{mcp_server_name}`"
    )

    st.divider()
    st.subheader("Available Qlik Tools")
    st.caption(
        "The agent has access to 70+ Qlik MCP tools including: "
        "app discovery, data analysis, chart creation, bookmarks, "
        "glossary management, datasets, lineage, and more."
    )

# =============================================================================
# Session State
# =============================================================================

if "messages" not in st.session_state:
    st.session_state.messages = []

# =============================================================================
# Agent Call via Snowpark + MCP Connection
# =============================================================================


def call_cortex_agent(user_message: str, history: list[dict]) -> str:
    """
    Call the Cortex Agent through the Snowpark session.

    The agent is wired to the Qlik MCP server, so it automatically has access
    to all Qlik Cloud tools (search, describe apps, create charts, etc.)
    via the MCP connection created in create-mcp-agent.sql.
    """
    agent_fqn = f"{agent_database}.{agent_schema}.{agent_name}"

    # Build conversation messages
    messages = []
    for msg in history:
        messages.append({"role": msg["role"], "content": msg["content"]})
    messages.append({"role": "user", "content": user_message})

    messages_json = json.dumps(messages).replace("'", "''")

    # Call the agent via SQL using the CORTEX.AGENT function
    # The agent routes requests through the MCP server connection
    query = f"""
        SELECT SNOWFLAKE.CORTEX.AGENT(
            '{agent_fqn}',
            PARSE_JSON('{messages_json}')
        ) AS response
    """

    try:
        result = session.sql(query).collect()
        if not result:
            return "No response received from the agent."

        response_raw = result[0]["RESPONSE"]

        # Parse the response JSON
        if isinstance(response_raw, str):
            try:
                response_data = json.loads(response_raw)
            except json.JSONDecodeError:
                return response_raw
        else:
            response_data = response_raw

        # Extract the message content from the agent response
        if isinstance(response_data, dict):
            # Standard agent response format
            choices = response_data.get("choices", [])
            if choices:
                message = choices[0].get("message", {})
                return message.get("content", str(response_data))
            # Direct content field
            if "content" in response_data:
                return response_data["content"]
            # Message wrapper
            if "message" in response_data:
                msg = response_data["message"]
                if isinstance(msg, dict):
                    return msg.get("content", str(msg))
                return str(msg)

        return str(response_data)

    except Exception as e:
        error_msg = str(e)
        if "OAuth" in error_msg or "authentication" in error_msg.lower():
            return (
                "OAuth authentication required. Please run the following in a "
                "Snowflake worksheet:\n\n"
                "```sql\n"
                "SELECT SYSTEM$START_USER_OAUTH_FLOW('<your_integration_name>');\n"
                "```\n\n"
                "Then complete the Qlik Cloud authorization flow."
            )
        return f"Error calling agent: {error_msg}"


# =============================================================================
# Chat UI
# =============================================================================

st.title("Qlik MCP Chat")
st.caption("Chat with Qlik Cloud through the Snowflake Cortex Agent + MCP connection")

# Display conversation history
for message in st.session_state.messages:
    with st.chat_message(message["role"]):
        st.markdown(message["content"])

# Chat input
if prompt := st.chat_input("Ask about your Qlik apps, data, or dashboards..."):
    # Display user message
    with st.chat_message("user"):
        st.markdown(prompt)

    # Call the agent via MCP connection
    with st.chat_message("assistant"):
        with st.spinner("Querying Qlik via MCP..."):
            response = call_cortex_agent(prompt, st.session_state.messages)
        st.markdown(response)

    # Save to history
    st.session_state.messages.append({"role": "user", "content": prompt})
    st.session_state.messages.append({"role": "assistant", "content": response})
