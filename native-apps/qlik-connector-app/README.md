# Qlik Connector App (Boilerplate)

A minimal Native App template for building Qlik + Snowflake integrations with a Cortex Agent.

## What This Is

A starting point for any Native App that needs:
- A Cortex Agent wired to both a Snowflake Semantic View and a Qlik MCP server
- Proper RBAC, caller grants, and Snowflake Intelligence registration
- The correct file structure and manifest for deployment

## Quick Start

1. Copy this directory
2. Replace the placeholder data model in `setup_script.sql` with your own tables
3. Uncomment and configure the semantic view
4. Update the agent instructions and tool descriptions
5. Replace `REPLACE_*` values with your actual object names
6. Deploy:

```sql
CREATE APPLICATION PACKAGE my_app_pkg;
CREATE SCHEMA my_app_pkg.v1;
CREATE STAGE my_app_pkg.v1.app_stage;
-- Upload files to stage
ALTER APPLICATION PACKAGE my_app_pkg REGISTER VERSION V1
  USING '@my_app_pkg.v1.app_stage';
CREATE APPLICATION my_app FROM APPLICATION PACKAGE my_app_pkg USING VERSION V1;
```

7. Run `scripts/consumer_setup.sql` to wire everything up

## Files

| File | Purpose |
|------|---------|
| `manifest.yml` | App metadata and warehouse reference |
| `setup_script.sql` | Tables, semantic view, agent, grants |
| `scripts/consumer_setup.sql` | Post-install: caller grants, Intelligence registration, OAuth |

## Key Lessons

- Application role must be created BEFORE any grants referencing it
- Semantic view syntax: lowercase `comment=`, `with synonyms=()`, facts need `as` aliases
- Agent profile must be set for CoWork visibility
- Agent must be registered with `ALTER SNOWFLAKE INTELLIGENCE ... ADD AGENT`
- Consumer needs both USAGE on MCP server AND caller grants to the app
- Use `REGISTER VERSION` (not `ADD VERSION`) when release channels are enabled
- Use `ADD PATCH FOR VERSION` for updates, `ALTER APPLICATION ... UPGRADE` to apply
