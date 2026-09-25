---
name: qlik-expression-authoring
description: Write, review, and optimize Qlik Sense / Qlik Cloud chart expressions (set analysis, outer set expressions, dollar-sign expansion, Aggr, inter-record functions, master measures). Use for "write a Qlik expression", "review my Qlik measure", "why is this Qlik chart slow", "convert this IF to set analysis", "Qlik set analysis help", "qlik expression best practices".
---

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

`If()` inside an aggregation forces the engine to evaluate the condition **row by row across the whole table** before aggregating. Set analysis defines the record set **once**, before aggregation starts, and it respects the associative selection model.

```qlik
// Slow — row-by-row evaluation
Sum(If(Region = 'EMEA', Sales, 0))

// Fast — record set resolved up front
Sum({<Region = {'EMEA'}>} Sales)
```

Same for counting — keep the rewrite semantically identical:

```qlik
Count(If(Status = 'Open', OrderID))          // avoid
Count({<Status = {'Open'}>} OrderID)         // same result, set analysis
Count({<Status = {'Open'}>} DISTINCT OrderID) // only if you actually want distinct orders
```

The exception: `If()` is fine **outside** the aggregation, where it runs once per chart row rather than once per data row.

```qlik
If(Sum(Sales) > 0, Sum(Cost) / Sum(Sales))   // fine — guards divide-by-zero, evaluated per chart row
```

> **Limit:** A set expression is evaluated **once per chart**, not per dimension value. It cannot say "the year of *this* row minus one". When the filter must depend on the row's dimension value, use a condition outside the aggregation, `Above()`/`Before()` (Step 7), `Aggr()` (Step 6), or — best — an as-of/comparison table built in the script.

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
| `$1`, `$2`, … | Previous selection, previous-but-one, … | Back-navigation comparisons |
| `$_1`, `$_2`, … | Next (forward) selection | Forward-navigation comparisons |
| `BM01` / bookmark name | A bookmark's selection (ID or name) | Governed baselines |
| `[StateName]` | An alternate state | Side-by-side comparative analysis |

Identifiers can be combined with **set operators**: `+` union, `-` exclusion, `*` intersection, `/` symmetric difference. For example `{1-$}` is everything *not* in the current selection, and `{$*BM01}` is the overlap with a bookmark.

**Modifier operators** — these are set operators on the *element list*, and they are the part people get wrong:

| Operator | Effect |
|---|---|
| `Field = {...}` | **Replace** the selection on that field |
| `Field += {...}` | Union — add values to the selection |
| `Field -= {...}` | Exclude values from the selection |
| `Field *= {...}` | Intersection — keep only values in both |
| `Field /= {...}` | Symmetric difference — values in one but not both |
| `Field = ` (empty) | Clear the selection on that field |

Clearing is the idiom for "% of total ignoring this dimension":

```qlik
Sum(Sales) / Sum({<Product = >} Total Sales)
```

**Element values — quoting decides matching:**

| Syntax | Meaning |
|---|---|
| `{'EMEA'}` | Literal value, **case-sensitive** exact match |
| `{"emea"}`, `{"C*"}`, `{"*garlic*"}` | Search, **case-insensitive**; `*` and `?` wildcards |
| `{">2019"}`, `{">=100<=200"}` | Numeric search (comparison or range) |
| `{"=Sum(Sales) > 100000"}` | Expression search — keeps values for which the condition is true |
| `{2026}` | Unquoted number |
| `{'Nut', "*Bolt", Washer}` | Lists may mix literals and searches |

Field names with spaces or special characters go in square brackets: `{<[Order Year] = {2026}>}`.

**Implicit element lists** with `P()` and `E()` — retrieve values rather than hardcoding them. Use these instead of a self-join or a hardcoded list:

```qlik
// Customers who bought Product A — evaluated as a set, no data duplication
Sum({<Customer = P({<Product = {'A'}>} Customer)>} Sales)

// Customers who never bought Product A
Sum({<Customer = E({<Product = {'A'}>} Customer)>} Sales)
```

`P()` and `E()` accept only *natural* sets (an identifier with or without modifiers), not sets built with set operators.

### Step 4 — Consider an Outer Set Expression

A set expression can also sit **outside** the aggregation, at the start of the lexical scope (Qlik Sense August 2022+, QlikView May 2023+). Two things make this worth reaching for.

**It removes repetition** across multi-aggregation expressions:

```qlik
// Inner — the same scope restated in every aggregation
Sum({$<Year = {2021}>} Sales) / Count({$<Year = {2021}>} DISTINCT Customer)

// Outer — written once, applies to both
{<Year = {2021}>} Sum(Sales) / Count(DISTINCT Customer)
```

**It can scope a master measure** — which inner set analysis cannot do:

```qlik
{<Year = {$(=Max(Year) - 1)}>} [Net Revenue]
```

This is the idiom for prior-year, single-region, or budget-basis variants of a governed metric **without cloning it**. Prefer it over duplicating a master measure.

**Scope is lexical.** An outer set expression affects the whole expression unless round brackets confine it:

```qlik
( {<Year = {2021}>} Sum(Amount) / Count(DISTINCT Customer) ) - Avg(CustomerSales)
// Avg(CustomerSales) is NOT scoped
```

**Inheritance depends on whether the inner set has an identifier.** This is the rule to internalise:

```qlik
// Inner HAS an identifier ({1}) → the outer set is NOT applied to it
{<Year = {2023}>} Sum(Sales) / Count({1} DISTINCT OrderNumber)

// Inner has NO identifier → outer and both inners all apply
{<Year = {2023}>}
    Sum({<Status = {'Confirmed'}>} Sales_Stream1)
  + Sum({<UpdatedStatus = {'Confirmed'}>} Sales_Stream2)
```

Where outer and inner touch the same field, the assignment operator decides the merge: `=` replaces the outer selection, `+=` unions with it, `*=` intersects.

**Chains** evaluate left to right, rightmost wins on conflict:

```qlik
{<Year = {2021}>} {<Region = {"Europe"}>} Sum({$<Product = {"XI345"}>} Sales)
```

> **Warning:** Only **one** inner set expression is honoured.
> Outer set expressions may be chained without limit, but two adjacent *inner* set expressions raise **no error** — only the rightmost is evaluated. The other is silently ignored, producing a wrong number that parses cleanly.

With `Aggr()`, the inner aggregation never inherits context from the outer aggregation — it inherits from `Aggr()`'s own set expression. An outer set expression, however, is inherited by both.

> **Warning:** An outer set expression does **not** reach inside a dollar-sign expansion.
> `$(=…)` is evaluated in isolation first and its result pasted in. `{<Year = {2024}>} $(=Sum(Sales))` returns the unfiltered total: the expansion becomes a plain number, and a set expression in front of a number does nothing. Put the set *inside* the expansion, or build the expression text so it is aggregated after expansion.

> **Danger:** Implicit selection set clearing.
> If a set expression yields an **empty set** for a dimension and another outer set expression follows it, that dimension's selection is silently **cleared back to the full set** — the opposite of the intended filter.

```qlik
{<Year = {}>} {<Region = {"Europe"}>} Sum(Sales)
// Year={} is discarded; every year is included
```

Empty sets are not only typos (`{'0025'}` for `{'2025'}`). They arise legitimately whenever a user's selection leaves no matching data — `Region = 'Europe'` combined with `{<ProductCategory = {'Shirts'}>}` when no shirts sell in Europe. Only the affected dimension is cleared; other sets pass through intact.

Two fixes. Move the component into the **last** outer expression in the chain:

```qlik
{<Product = {"XI345"}>} {<Year = {}, Region = {"Europe"}>} Sum(Sales)
```

Or use the **empty set preserve flag** `&` — a single `&` at the very start of an outer set expression, before any modifiers, identifiers, or operators. Valid in any outer set expression **except the last** in a chain:

```qlik
{& <Year = {}, Product = {XI345}>} {<Region = {Europe}>} Sum(Sales)
```

When a chained expression returns more rows than expected, suspect implicit clearing before suspecting the data.

### Step 5 — Handle Dates and Dollar-Sign Expansion Safely

**The most common Qlik expression bug:** a date search string that does not match the field's format. Qlik stores dates as duals (a number plus a display text), and a search like `{">=2026-01-01"}` is interpreted in the **field's own display format**. It works on a field shown as `YYYY-MM-DD`, and silently matches nothing on a field shown as `DD/MM/YYYY`.

Build the boundary with an expansion that produces **the field's format**:

```qlik
// Fragile — hardcoded text in one particular format
Sum({<OrderDate = {">=2026-01-01"}>} Sales)

// Robust — Date() without a format string uses the app's DateFormat,
// which is the field's format if it was loaded with the default
Sum({<OrderDate = {">=$(=Date(YearStart(Today())))"}>} Sales)

// If the field has its own format, repeat that exact format string
Sum({<OrderDate = {">=$(=Date(YearStart(Today()), 'YYYY-MM-DD'))"}>} Sales)
```

The most robust option avoids formats altogether: add an integer key in the script (`Num(Floor(OrderDate)) AS OrderDateNum`, or `Year`/`YearMonth` fields) and filter on that — `{<OrderDateNum = {">=$(=Num(YearStart(Today())))"}>}`.

Note the **double** quotes around a search/comparison element (`{">=..."}`) versus **single** quotes around a literal value (`{'EMEA'}`). Mixing these up is a silent-wrong-answer bug, not a syntax error.

Dollar-sign expansion rules worth internalising:

- `$(=expr)` evaluates `expr` **first**, in the current selection, then substitutes the result into the expression text, which is then parsed. It happens before set analysis is evaluated, and **once per chart**, not per row.
- `$(vVar)` is **text substitution** — the variable's text is pasted in, then evaluated. A variable defined *with* a leading `=` is evaluated in the variable itself; without `=` it is pasted verbatim. This distinction causes most "my variable works in a chart but not in a variable" confusion.
- `$(=...)` returns a **single value**. A bare field reference (`$(=Region)`) behaves like `Only()`, so it returns null when there are multiple values. Wrap in an explicit aggregation (`Only()`, `Max()`, `Concat()`) so the intent is visible.
- To inject a list, use `Concat()` inside the expansion:
  ```qlik
  Sum({<Region = {"$(=Concat(DISTINCT Region, '","'))"}>} Sales)   // produces {"EMEA","APAC",...}
  ```
- Prefer a **set modifier over an expansion** when the goal is selection-independence — an expansion evaluated in the current selection will silently drift. Put set analysis *inside* the expansion if it must be stable: `$(=Max({1} Year))`.
- The expression editor shows a **preview** of what each `$(…)` expands to. Check it before trusting the result.

Prior-year comparison, written the durable way:

```qlik
Sum({<Year = {$(=Max(Year) - 1)}, Month = >} Sales)
```

### Step 6 — Use Aggr() Only When You Must

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
- Use `NODISTINCT` / `DISTINCT` deliberately; the default is `DISTINCT` (one value per combination, shown on one chart row).
- **Do not nest `Aggr()` inside `Aggr()`.** If you need this, the grain belongs in the script.
- In charts with cyclic or drill-down groups, the dimension inside `Aggr()` must be resolved with `$(=GetCurrentField(GroupName))` — a hardcoded field breaks on drill.
- A set-modifier search condition (`{"=Sum(Sales) > X"}`) is very often a cheaper equivalent. Try it first.

### Step 7 — Inter-Record Functions for Running Totals and Trends

Accumulation and period-over-period inside a chart use `RangeSum()` with `Above()` rather than an `Aggr()` construct:

```qlik
// Full running total across the chart's rows
RangeSum(Above(Sum(Sales), 0, RowNo()))

// Trailing 3-period moving total
RangeSum(Above(Sum(Sales), 0, 3))

// Period-over-period delta
Sum(Sales) - Above(Sum(Sales))
```

`RangeSum()` treats nulls as zero, so the first rows (where `Above()` has nothing to return) still produce a number.

Caveats:

- These are **chart-position-dependent** — the result depends on the chart's sort order and on the dimension being present. Sort by the time dimension, ascending.
- `Above()` works **within a column segment**. With two dimensions in a table it restarts for each value of the outer dimension. Use `Above(TOTAL Sum(Sales))` and `RowNo(TOTAL)` to run across segments.
- In pivot tables, `Above()`/`Below()` move along rows and `Before()`/`After()` along columns. Expanding or collapsing changes which rows exist, so check the result in every layout the user can reach.
- If the calendar has gaps, the "previous row" is not the previous period. Use a dense master calendar in the script, or compute prior-period values there.

### Step 8 — Make It Maintainable

**Promote to a master measure.** Any expression used more than once becomes a master measure — single version of the truth, governed, reusable in self-service, and referenceable from other expressions. Do not copy-paste an expression into a second chart.

**Naming.** Give the master measure the business name (`Net Revenue`) and keep the underlying field name distinct (`RevenueAmount`). When a measure label, a field and a variable share a name, Qlik resolves it by position: **inside an aggregation** the name is read as a field; **outside an aggregation** a measure label wins over a variable, which wins over a field. You can't override this, so `Sum([Net Revenue])` and `[Net Revenue]` can silently mean different things — rename in the script to avoid the clash.

**Do not clone a master measure to change its scope.** A prior-year or single-region variant is an outer set expression applied to the existing measure — `{<Year = {$(=Max(Year) - 1)}>} [Net Revenue]` — not a second master measure that will drift from the first. See Step 4.

**Master measures vs. variables:**

| | Master measure | Variable |
|---|---|---|
| Renameable, colourable, label-linked | Yes | No |
| Reusable across apps | No (app-scoped) | Via script include |
| Composable as a fragment of a larger expression | Yes | Yes |
| Good for a reusable *set fragment* or constant | No | **Yes** |

Use variables for reusable *pieces* (a set modifier, a threshold, a date boundary) and master measures for complete, presentable metrics.

**Format for review.** Multi-line with indentation and comments — chart expressions accept whitespace freely, plus `//` line comments and `/* */` block comments:

```qlik
Sum(
    {<
        Year   = {$(=Max(Year))},   // latest year in the current selection
        Status -= {'Cancelled'}     // never count cancellations
    >}
    LineRevenue                     // precomputed in script: Price * Qty * (1 - Discount)
)
```

> **Warning:** Do not put `//` comments inside a **variable** that is used with dollar-sign expansion.
> `$(vX)` pastes the variable's text in verbatim, so a trailing `// note` comments out everything that follows it on the line. `$(vMargin) / 2` becomes `0.3 // margin / 2` — the division is silently lost. Use `/* */` in variables, or no comments at all. `REM` and `#` are script syntax and are not comments in chart expressions.

### Step 9 — Verify

Never ship an expression on the basis that it parsed.

1. **Reconcile against a known total.** Put the measure in a KPI with no selections and compare to a straight `Sum` on the source, or to the source system. A join fan-out shows up here and nowhere else.
2. **Test the selection contract.** Make a selection on each field the expression modifies. Confirm it responds — or correctly does not — as designed.
3. **Test the empty and single-value cases.** Zero rows, one row, a dimension value with no matching records, and a selection that empties a set used in an outer chain (Step 4). Guard division explicitly; do not rely on Qlik returning null politely.
4. **Test at the boundary.** First and last period for inter-record functions; year boundary for date logic.
5. **Drill and cycle.** If the chart has a drill-down group, confirm `Aggr()` and inter-record expressions still hold.
6. **Check the expansion preview.** Confirm every `$(…)` expands to what you expect under a few different selections.
7. **Time it.** Open the sheet cold with no selections, then with a heavy selection. If the calculating indicator lingers, return to Step 1 — something belongs in the script.

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
- [ ] `Count(DISTINCT …)` justified — distinct counts on high-cardinality fields are expensive; a script counter field (`1 AS OrderCounter`) summed is often cheaper
- [ ] Data model clean: no synthetic keys, no unnecessary fields, star-shaped where possible

## Common Mistakes

| Symptom | Cause | Fix |
|---|---|---|
| Date filter returns nothing, no syntax error | Search string not in the field's display format | Build the boundary with `Date(…)` in the field's format, or filter on a numeric date key |
| Number too low / too high but plausible | Wrong quote type: `{'…'}` vs `{"…"}` | Single = case-sensitive literal, double = case-insensitive search/comparison |
| Measure inflated | Expression at the wrong grain, join fan-out | Move measure to the table owning the grain |
| Rewrite of `Count(If(…))` gives a smaller number | `DISTINCT` added during the rewrite | Keep `DISTINCT` only if the original meant it |
| `$(=…)` returns null | Expansion yielded multiple values | Wrap in `Only()`, `Max()`, or `Concat()` |
| Works in chart, breaks as a variable | `=` prefix on variable definition changes evaluation timing | Build and test in a chart, then move; set the variable in the variable editor, not the script |
| Variable-based expression silently loses part of its math | `//` comment inside the variable swallowed the rest of the line after expansion | Use `/* */` in variables, or none |
| Set analysis can't reference "this row's" value | Set expressions are evaluated once per chart | Condition outside the aggregation, `Above()`, `Aggr()`, or a script-side as-of table |
| Outer set has no effect on a `$(=…)` result | Dollar-sign expansions are evaluated in isolation, before the outer set | Put the set inside the expansion |
| `Sum([X])` and `[X]` disagree | A field and a master measure share the name `X` | Rename the field in the script |
| Breaks on drill-down | Hardcoded field inside `Aggr()` | `$(=GetCurrentField(GroupName))` |
| Running total restarts mid-table | `Above()` works per column segment | `Above(TOTAL …)` / `RowNo(TOTAL)` |
| Running total wrong after a selection | Gaps in the dimension, or sort order changed | Dense master calendar; verify sort |
| Comparison measure ignores a filter it should respect | `{1}` used where `{$}` with modifiers was needed | Use `{$<…>}` and override only the intended field |
| Chained set expression returns far too many rows | Implicit selection set clearing — an empty set was silently restored to the full set | Move the component to the last outer expression, or add the `&` empty set preserve flag |
| Outer set expression appears to be ignored | Inner set expression contains a set identifier, so it overrides the outer context | Remove the inner identifier, or move the scope inward |
| One of two adjacent inner set expressions has no effect | Only the rightmost inner set expression is evaluated; no error is raised | Merge them into a single inner set expression |

## Deliverable Checklist

- [ ] Placement decision recorded — why this is an expression and not a script column
- [ ] Selection contract stated: what it respects, what it ignores, why
- [ ] Set analysis used in place of `If()` inside aggregations, with identical semantics
- [ ] Repeated inner scopes collapsed into an outer set expression where it aids readability
- [ ] Chained set expressions checked for implicit clearing; `&` flag applied where an empty set must survive
- [ ] Date boundaries match the field's format (or use a numeric date key); correct quote type throughout
- [ ] `Aggr()` justified, grain fully specified, not nested
- [ ] Promoted to a master measure if used more than once; business-friendly name distinct from field names
- [ ] Formatted multi-line with comments (and no `//` comments inside variables used in expansions)
- [ ] Reconciled against a known total
- [ ] Empty, single-row, and boundary cases tested
- [ ] Cold-load and heavy-selection timing acceptable
