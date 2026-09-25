# Authoring Qlik Expressions

Write, review, and optimize Qlik Sense / Qlik Cloud chart expressions so they are correct under the associative model, fast on large data, and maintainable by the next developer.

**Trigger:** "write a Qlik expression", "review my Qlik measure", "why is this Qlik chart slow", "convert this IF to set analysis", "Qlik set analysis help", "qlik expression best practices"

## Core Principle

**The cheapest expression is the one you never write.** Qlik's expression layer runs on every selection change, for every object on the sheet, including expressions the user never sees (colour, conditional show, reference lines). Anything that does not depend on the current selection belongs in the load script, not the chart.

Decide placement before writing anything:

| Logic | Where it belongs |
|---|---|
| Static filter used everywhere (`Year = current year`, `Status = 'Active'`) | **Script flag** — `If(Year(OrderDate) = Year(Today()), 1, 0) AS IsCurrentYear` |
| Row-level arithmetic (`Price * Qty * (1 - Discount)`) | **Script column** — precompute `LineRevenue` |
| Calendar attributes, buckets, groupings | **Script** — master calendar, mapping load |
| Selection-dependent comparison (% of total, YoY, rank) | **Expression** |
| Dynamic filter driven by user selection | **Expression** (set analysis) |

If an expression starts to look like `If()` inside `Aggr()` inside `Sum()`, that is a signal to push logic upstream — not to keep nesting.

## Workflow

### Step 1 — Establish the Grain and the Selection Contract

Before writing, answer three questions explicitly:

1. **What grain does the number live at?** A line-item sum must not be written on the order header — it will fan out across the join and inflate.
2. **Should this respect the user's selections?** Default is yes (`{$}`). Only ignore selections deliberately.
3. **Which selections must it ignore, and why?** "% of total" ignores the dimension being measured; "target" ignores everything; "prior year" overrides only the date field.

Getting this wrong produces a number that looks plausible and is wrong — the most expensive kind of defect.

### Step 2 — Use Set Analysis, Not IF, Inside Aggregations

This is the single highest-impact change to an existing app.

`If()` inside an aggregation forces the engine to evaluate the condition **row by row across the whole table** before aggregating. Set analysis tells the engine which records to include **before** it starts, and it respects the associative selection model correctly.

```qlik
// Slow — row-by-row evaluation
Sum(If(Region = 'EMEA', Sales, 0))

// Fast — record set resolved up front
Sum({<Region = {'EMEA'}>} Sales)
```

Same for counting:

```qlik
Count(If(Status = 'Open', OrderID))          // avoid
Count({<Status = {'Open'}>} DISTINCT OrderID) // prefer
```

The exception: `If()` is fine **outside** the aggregation, where it runs once per dimension value rather than once per row.

```qlik
If(Sum(Sales) > 0, Sum(Cost) / Sum(Sales))   // fine — guards divide-by-zero, evaluated per row of the chart
```

### Step 3 — Write the Set Expression Correctly

Anatomy — the set expression goes in curly braces between the function name and the field:

```
Sum(  {  $  <  Year = {2026}, Region -= {'EMEA'}  >  }  Sales  )
        │  │     │            │
        │  │     │            └── modifier: exclude EMEA from current selection
        │  │     └── modifier: override Year
        │  └── identifier: current selection
        └── set expression
```

**Identifiers** — pick deliberately:

| Identifier | Meaning | Use for |
|---|---|---|
| `$` | Current selection (default if omitted) | Normal measures |
| `1` | Full data set, **all selections ignored** | Targets, budgets, grand totals |
| `$1` | Previous selection | Back-navigation comparisons |
| `Bookmark01` / `BM_Name` | A bookmark's selection | Governed baselines |
| `[State]` | An alternate state | Side-by-side comparative analysis |

**Modifier operators** — these are set operators on the *element list*, and they are the part people get wrong:

| Operator | Effect |
|---|---|
| `Field = {...}` | **Replace** the selection on that field |
| `Field += {...}` | Union — add values to the selection |
| `Field -= {...}` | Exclude values from the selection |
| `Field *= {...}` | Intersection — keep only values in both |
| `Field = ` (empty) | Clear the selection on that field |

Clearing is the idiom for "% of total ignoring this dimension":

```qlik
Sum(Sales) / Sum({<Product = >} Total Sales)
```

**Implicit element lists** with `P()` and `E()` — retrieve values rather than hardcoding them. Use these instead of a self-join or a hardcoded list:

```qlik
// Customers who bought Product A — evaluated as a set, no data duplication
Sum({<Customer = P({<Product = {'A'}>} Customer)>} Sales)

// Customers who never bought Product A
Sum({<Customer = E({<Product = {'A'}>} Customer)>} Sales)
```

### Step 4 — Handle Dates and Dollar-Sign Expansion Safely

**The most common Qlik expression bug:** comparing a date field to a text string. Qlik stores dates as numbers with a display format; a literal like `{'2026-01-01'}` matches only if the string representation matches exactly.

Always build date literals with an expansion that produces the field's own format:

```qlik
// Fragile — depends on string format matching
Sum({<OrderDate = {'>=2026-01-01'}>} Sales)

// Robust — evaluates to the numeric/formatted value before the set is parsed
Sum({<OrderDate = {">=$(=Date(YearStart(Today()), 'YYYY-MM-DD'))"}>} Sales)
```

Note the **double** quotes around a search/comparison element (`{">=..."}`) versus **single** quotes around a literal value (`{'EMEA'}`). Mixing these up is a silent-wrong-answer bug, not a syntax error.

Dollar-sign expansion rules worth internalising:

- `$(=expr)` evaluates `expr` **first**, then substitutes the result into the expression text, which is then parsed. It happens before set analysis is evaluated.
- `$(vVar)` is **text substitution** — the variable's text is pasted in, then evaluated. A variable defined *with* a leading `=` is evaluated in the variable itself; without `=` it is pasted verbatim. This distinction causes most "my variable works in a chart but not in a variable" confusion.
- `$(=...)` returns a **single value**. If the inner expression can yield multiple values it returns null. Wrap in an aggregation (`Only()`, `Max()`, `Concat()`) to be explicit.
- To inject a list, use `Concat()` inside the expansion:
  ```qlik
  Sum({<Region = {"$(=Concat(DISTINCT Region, '|'))"}>} Sales)   // search-match a pipe-delimited list
  ```
- Prefer a **set modifier over an expansion** when the goal is selection-independence — an expansion evaluated in the current selection will silently drift. Put set analysis *inside* the expansion if it must be stable: `$(=Max({1} Year))`.

Prior-year comparison, written the durable way:

```qlik
Sum({<Year = {$(=Max(Year) - 1)}, Month = >} Sales)
```

### Step 5 — Use Aggr() Only When You Must

`Aggr()` builds a temporary in-memory result set at a grain you specify, then aggregates over it. It is powerful and it is expensive — it is the usual culprit behind a chart that hangs.

Legitimate uses:

```qlik
// Average of a per-customer total — cannot be expressed as a plain aggregation
Avg(Aggr(Sum(Sales), Customer))

// Count customers above a threshold
Count({<Customer = {"=Sum(Sales) > 100000"}>} DISTINCT Customer)   // prefer this over Aggr + If
```

Rules for `Aggr()`:

- **Specify the grain fully.** Every dimension that scopes the inner aggregation must be listed, including chart dimensions, or the result changes when the user drills.
- Use `NODISTINCT` / `DISTINCT` deliberately; the default is `DISTINCT`.
- **Do not nest `Aggr()` inside `Aggr()`.** If you need this, the grain belongs in the script.
- In charts with cyclic or drill-down groups, the dimension inside `Aggr()` must be resolved with `$(=GetCurrentField(GroupName))` — a hardcoded field breaks on drill.
- A set-modifier search condition (`{"=Sum(Sales) > X"}`) is very often a cheaper equivalent. Try it first.

### Step 6 — Inter-Record Functions for Running Totals and Trends

Accumulation and period-over-period inside a chart use `RangeSum()` with `Above()` rather than an `Aggr()` construct:

```qlik
// Full running total across the chart's rows
RangeSum(Above(Sum(Sales), 0, RowNo()))

// Trailing 3-period moving total
RangeSum(Above(Sum(Sales), 0, 3))

// Period-over-period delta
Sum(Sales) - Above(Sum(Sales))
```

Caveats:

- These are **chart-position-dependent** — they depend on sort order and on the dimension being present and continuous. Turn off continuous-axis mode; set null handling to connect.
- They break in pivot tables with expanded/collapsed states in non-obvious ways. Prefer `Before()`/`After()` in pivots, or precompute in the script.
- If the calendar has gaps, the "previous row" is not the previous period. Use a dense master calendar in the script.

### Step 7 — Make It Maintainable

**Promote to a master measure.** Any expression used more than once becomes a master measure — single version of the truth, governed, reusable in self-service, and referenceable from other expressions. Do not copy-paste an expression into a second chart.

**Naming.** Give the master measure the business name (`Net Revenue`) and keep the underlying field name distinct (`RevenueAmount`). If a master measure and a field share a name, Qlik resolves to the master measure with no way to disambiguate — rename in the script to avoid this trap.

**Master measures vs. variables:**

| | Master measure | Variable |
|---|---|---|
| Renameable, colourable, label-linked | Yes | No |
| Reusable across apps | No (app-scoped) | Via script include |
| Composable as a fragment of a larger expression | Yes | Yes |
| Good for a reusable *set fragment* or constant | No | **Yes** |

Use variables for reusable *pieces* (a set modifier, a threshold, a date boundary) and master measures for complete, presentable metrics.

**Format for review.** Multi-line with indentation and comments — Qlik accepts whitespace freely in expressions:

```qlik
Sum(
    {<
        Year   = {$(=Max(Year))},   // latest year in data, not in selection
        Status -= {'Cancelled'}     // never count cancellations
    >}
    LineRevenue                     // precomputed in script: Price * Qty * (1 - Discount)
)
```

> **Warning:** Do not put `//`, `#`, or `REM` whole-line comments in expressions used in *property* fields (colour, title, conditional show). Property expressions do not consistently support comment syntax and will fail to evaluate. Block comments `/* */` are safer there; better still, keep property expressions trivial.

### Step 8 — Verify

Never ship an expression on the basis that it parsed.

1. **Reconcile against a known total.** Put the measure in a KPI with no selections and compare to a straight `Sum` on the source, or to the source system. A join fan-out shows up here and nowhere else.
2. **Test the selection contract.** Make a selection on each field the expression modifies. Confirm it responds — or correctly does not — as designed.
3. **Test the empty and single-value cases.** Zero rows, one row, a dimension value with no matching records. Guard division explicitly; do not rely on Qlik returning null politely.
4. **Test at the boundary.** First and last period for inter-record functions; year boundary for date logic.
5. **Drill and cycle.** If the chart has a drill-down group, confirm `Aggr()` and inter-record expressions still hold.
6. **Time it.** Open the sheet cold with no selections, then with a heavy selection. If the calculating indicator lingers, return to Step 1 — something belongs in the script.

## Performance Checklist

Work down this list when a sheet is slow; the top items pay off most.

- [ ] `If()` inside aggregations replaced with set analysis
- [ ] Row-level arithmetic precomputed as a script column
- [ ] Frequently used static filters replaced with script flags (`Sum({<IsCurrentYear = {1}>} …)`)
- [ ] `Aggr()` removed where a set-modifier search condition works instead
- [ ] No nested `Aggr()`
- [ ] Count of "invisible" expressions reduced — conditional colour per cell, conditional show, dynamic titles
- [ ] Object count per sheet kept modest; heavy objects behind a container or a later sheet
- [ ] First-load cost limited via a default bookmark or a landing sheet with simple objects
- [ ] `Count(DISTINCT …)` justified — distinct counts on high-cardinality fields are expensive
- [ ] Data model clean: no synthetic keys, no unnecessary fields, star-shaped where possible

## Common Mistakes

| Symptom | Cause | Fix |
|---|---|---|
| Date filter returns nothing, no syntax error | String literal vs. numeric date | `{">=$(=Date(…, 'YYYY-MM-DD'))"}` |
| Number too low / too high but plausible | Wrong quote type: `{'…'}` vs `{"…"}` | Single = literal value, double = search/comparison |
| Measure inflated | Expression at the wrong grain, join fan-out | Move measure to the table owning the grain |
| `$(=…)` returns null | Expansion yielded multiple values | Wrap in `Only()`, `Max()`, or `Concat()` |
| Works in chart, breaks as a variable | `=` prefix on variable definition changes evaluation timing | Build and test in a chart, then move; set the variable in the variable editor, not the script |
| Breaks on drill-down | Hardcoded field inside `Aggr()` | `$(=GetCurrentField(GroupName))` |
| Running total wrong after a selection | Gaps in the dimension, or sort order changed | Dense master calendar; verify sort |
| Comparison measure ignores a filter it should respect | `{1}` used where `{$}` with modifiers was needed | Use `{$<…>}` and override only the intended field |

## Deliverable Checklist

- [ ] Placement decision recorded — why this is an expression and not a script column
- [ ] Selection contract stated: what it respects, what it ignores, why
- [ ] Set analysis used in place of `If()` inside aggregations
- [ ] Date literals built with `$(=Date(…))`, correct quote type throughout
- [ ] `Aggr()` justified, grain fully specified, not nested
- [ ] Promoted to a master measure if used more than once; business-friendly name distinct from field names
- [ ] Formatted multi-line with comments (and no `//` comments in property expressions)
- [ ] Reconciled against a known total
- [ ] Empty, single-row, and boundary cases tested
- [ ] Cold-load and heavy-selection timing acceptable
