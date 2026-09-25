# Qlik Connector App (Template)

A minimal Snowflake Native App template for Qlik + Snowflake integrations built around a Cortex Agent. Copy it as the starting point for any app that needs:

- a Cortex Agent wired to a Snowflake **Semantic View** (Cortex Analyst) and a **Qlik MCP server**,
- the application role, reference callback, grants and caller privileges set up correctly,
- a Snowflake Intelligence profile, so the agent shows up for users.

For a complete worked example built on this pattern, see the [Embedded Analytics Starter Kit](../embedded-analytics-kit/).

## Files

| File | Purpose |
|---|---|
| `manifest.yml` | App metadata; declares a consumer warehouse reference |
| `setup_script.sql` | Runs on install/upgrade: app role, schema, reference callback, placeholder table, (commented) Semantic View, agent, grants, profile |
| `scripts/consumer_setup.sql` | Run by the consumer after install: caller grants, role grant, Snowflake Intelligence registration, Qlik OAuth |

## Quick Start

1. **Copy this directory** and rename it.
2. **Replace the data model** in `setup_script.sql` (section 3) with your own tables and seed data.
3. **Uncomment and adapt the Semantic View** (section 4). The agent's `tool_resources` points at `core.my_semantic_view`, so the agent can't answer data questions until that view exists.
4. **Update the agent** (section 5): instructions, sample questions and tool description.
5. **Replace the placeholders** in the agent spec: `REPLACE_WITH_YOUR_WAREHOUSE` and `REPLACE_DB.REPLACE_SCHEMA.YOUR_QLIK_MCP_SERVER`.
6. **Package and install:**
   ```sql
   CREATE APPLICATION PACKAGE my_app_pkg;
   CREATE SCHEMA my_app_pkg.v1;
   CREATE STAGE  my_app_pkg.v1.app_stage;

   -- manifest.yml and setup_script.sql must be at the stage root
   PUT file://manifest.yml     @my_app_pkg.v1.app_stage AUTO_COMPRESS=FALSE OVERWRITE=TRUE;
   PUT file://setup_script.sql @my_app_pkg.v1.app_stage AUTO_COMPRESS=FALSE OVERWRITE=TRUE;

   ALTER APPLICATION PACKAGE my_app_pkg REGISTER VERSION V1
     USING '@my_app_pkg.v1.app_stage';
   CREATE APPLICATION my_app FROM APPLICATION PACKAGE my_app_pkg USING VERSION V1;
   ```
7. **Run `scripts/consumer_setup.sql`** after filling in its `SET` block. It grants the app caller access to your warehouse and MCP server, grants `APP_USER` to your role, registers the agent with Snowflake Intelligence, and starts the Qlik OAuth flow.

## Lessons Learned

- Create the **application role before** any `GRANT ... TO APPLICATION ROLE` that references it.
- Semantic View DDL details: write `comment=` in lowercase, use `with synonyms=(...)`, give every fact and dimension an `as` alias, and put attributes and dates in `DIMENSIONS` (not `FACTS`) so Cortex Analyst can group by them.
- An agent needs a **profile** (`ALTER AGENT ... SET PROFILE`) to display properly in Snowflake Intelligence. It must also be added to the Snowflake Intelligence object (`ALTER SNOWFLAKE INTELLIGENCE ... ADD AGENT`).
- The consumer must grant the app **caller** privileges on the warehouse and the MCP server (`GRANT CALLER USAGE ... TO APPLICATION`). Plain `USAGE` on the MCP server is not enough.
- When release channels are enabled, use `REGISTER VERSION`, not `ADD VERSION`.
- For updates, use `ADD PATCH FOR VERSION`, then `ALTER APPLICATION ... UPGRADE` to apply the patch.

## Try Qlik Cloud

Need a Qlik Cloud tenant to build your connector? [Start a free Qlik Cloud trial](https://www.qlik.com/us/trial/qlik-cloud-analytics) and connect it to Snowflake.
