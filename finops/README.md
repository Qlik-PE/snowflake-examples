# FinOps: Snowflake FOCUS Cost & Usage (temporary)

> Temporary. This folder holds an export of a Qlik Cloud app, taken after an app-wide clean-up on 2026-10-09. Delete it, or replace it with a proper example, once the app has been verified.

## What is here

| File | What it is |
|---|---|
| `snowflake-focus-cost-usage.qvf` | Export of the "Snowflake FOCUS Cost & Usage (v1.3)" app **without data**: load script, sheets, charts, master items and variables. |

The data is billing data and reloads from Snowflake.

- Source app: `51bf05e6-2663-45f4-a846-e9660dd53ff9` on `partner-engineering-saas.us.qlikcloud.com`, space "Snowflake".
- Data source: `SNOWFLAKE.BILLING.FOCUS_COST_USAGE_V1_3`, through the connection `Snowflake:SNOWFLAKE_MONITORING_DATA`. History from 2026-01-01.

## Restoring

1. In Qlik Cloud, go to **Create → Upload app**, choose the `.qvf`, and pick a space that can use the `Snowflake:SNOWFLAKE_MONITORING_DATA` connection.
2. Reload the app. The load script reads the FOCUS view again and rebuilds the relative-period fields (`DayRelNo`, `WeeksAgo`, `MonthsAgo`, `YearsAgo`) from the reload date.
3. Check the sheet thumbnails. They live in the app's media library under `thumbnails/`; if they are missing after the upload, they need to be uploaded again.

## The app after the clean-up

| Sheet | What it answers | Time window |
|---|---|---|
| About | Purpose, data source, how to use the app | — |
| Billing Overview | Billed cost by account, service and provider | The Period selector (only sheet that follows it) |
| 1. Daily Anomalies | Which days and services spent unusually | Latest settled day (3 days before reload) vs the 28 days before it |
| 2. Month-over-Month Services | How service costs changed month over month | M-1 vs M-2, plus month to date and forecast |
| 3. Month-End Forecast | Where the current month will land | Settled month to date plus the 7-day run rate |
| 4. Price vs Volume | Whether a change came from usage or from rates | M-1 vs M-2, split into volume, price and mix |
| 5. AI & ML Spend | What Cortex, CoCo and other AI services cost | Current selections |

M-1 and M-2 are the 2nd and 3rd most recent months in the current selection (variables `vSAM-1`/`vSAM-2`). With nothing selected, they are the last complete month and the month before.

## Changes made in the clean-up

1. **Removed unused objects:** 8 hidden leftovers on sheets 1 and 3, and 131 objects that were on no sheet. A filter-pane master visualization was kept.
2. **Formatting:** removed `Num()` from every expression; number formats are set on the objects and master measures. KPI measure titles are hidden.
3. **Master measures:** added 11 (Billed Cost M-1 and M-2, Month to Date, Settled Month to Date, Daily Run Rate, Month-End Forecast, 28-Day Baseline, Latest Settled Day, Volume Effect, Price Effect, AI & ML Billed Cost), each with a description. 32 chart measures use them instead of copied expressions. The 3 master dimensions now have descriptions.
4. **Period handling:** only Billing Overview follows the Period selector. Measures tied to the reload date ignore date selections. Each sheet description states its windows.
5. **Naming:** "Billing Cost" became "Billing Overview"; sheets renumbered 1 to 5 after an older sheet 4 was removed; period labels aligned.
6. **Fields:** 15 technical fields are hidden in the load script (33 visible). The About sheet text was updated.
7. **Thumbnails:** every sheet has an 800×500 thumbnail.
8. **Sheet layouts:** sheets 4 and 5 were rebuilt (duplicate stacked objects removed, blank charts fixed). Sheet 4 has a top-10 change-drivers chart.
