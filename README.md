# Snowflake Examples

A collection of example code and reference implementations for Snowflake, maintained by the **Qlik Partner Engineering** team.

## Overview

This repository contains working examples that demonstrate Snowflake features and capabilities. Each example is self-contained and includes the necessary setup instructions to run independently.

## Repository Structure

```
snowflake-examples/
├── sql/              # SQL scripts and queries
├── python/           # Python and Snowpark examples
├── streamlit/        # Streamlit in Snowflake apps
├── notebooks/        # Snowflake Notebooks
├── pipelines/        # Data pipeline examples
└── native-apps/      # Native App Framework examples
```

## Topics Covered

- **Data Engineering** - Streams, tasks, dynamic tables, Snowpipe, and data ingestion patterns
- **Cortex AI** - AI functions, LLM integration, vector search, and ML pipelines
- **Snowpark** - Python UDFs, stored procedures, and DataFrames
- **Data Sharing** - Secure data sharing, listings, and clean rooms
- **Native Apps** - Snowflake Native App Framework development
- **Streamlit** - Building interactive apps within Snowflake
- **Security & Governance** - RBAC, masking policies, and access controls

## Prerequisites

- A Snowflake account
- Appropriate roles and permissions for the features being demonstrated
- Python 3.8+ (for Python-based examples)
- [Snowflake CLI](https://docs.snowflake.com/en/developer-guide/snowflake-cli/index) (recommended)

## Getting Started

1. Clone this repository:
   ```bash
   git clone <repository-url>
   cd snowflake-examples
   ```

2. Navigate to the example you want to run and follow its local README or inline comments for setup instructions.

3. Configure your Snowflake connection using one of:
   - Snowflake CLI (`snow connection add`)
   - Environment variables (`SNOWFLAKE_ACCOUNT`, `SNOWFLAKE_USER`, etc.)
   - A `connections.toml` file

## Contributing

Contributions from the Qlik Partner Engineering team are welcome. When adding a new example:

1. Place it in the appropriate directory (or create a new one if needed).
2. Include a brief description at the top of the file or in a local README.
3. Ensure the example is self-contained and lists any prerequisites.
4. Test against a clean Snowflake environment before submitting.

## License

See [LICENSE](LICENSE) for details.

## Contact

Maintained by the Qlik Partner Engineering team. For questions or issues, please open an issue in this repository.
