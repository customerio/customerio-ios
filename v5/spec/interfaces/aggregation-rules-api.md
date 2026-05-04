# Aggregation Rules — SDK API

> **Status:** Proposal — not yet implemented. No network code exists for this
> endpoint. The rule evaluation engine, accumulator storage, and flush mechanics
> are fully implemented; only the server-side config fetch is missing.
>
> Endpoint paths and response schema are provisional pending backend
> confirmation.
>
> For the full aggregation engine — rule types, operations, accumulator
> lifecycle, flush scheduling, and engine internals — see
> [`spec/features/aggregation.md`](../features/aggregation.md).

---

## Overview

The `AggregationEngine` loads its ruleset from a CIO-hosted static endpoint
relative to the region base URL. The fetch happens on SDK startup and on each
app foreground, rate-limited to once per 24 hours. The SDK stores the last-seen
ruleset version and discards stale responses.

---

## Conventions

| Convention | Detail |
|---|---|
| Endpoint URL | CIO-hosted. Path relative to region base URL. Will be derived from `SdkConfig.region` once backend paths are finalised. |
| Method | `GET` |
| Response body | `application/json` |
| Refresh cadence | At most once per 24 hours. Last fetch timestamp persisted to `sdk_meta`. Triggered on SDK startup and app foreground. |

---

## Authentication

All SDK requests to this endpoint carry:

| Header | Value |
|---|---|
| `Authorization` | `Basic <base64("cdpApiKey:")>` |
| `User-Agent` | The SDK's standard `User-Agent` string. |

---

## Request

```
GET <regionBaseURL>/v1/aggregation_rules
```

No request body or query parameters. The SDK uses the stored `version` from the
last successful response to decide whether to apply a new ruleset (see Version
Skipping below).

---

## Response

**200 OK**

```json
{
  "version": 4,
  "rules": [
    {
      "id": "session_lifecycle_summary",
      "uploadInterval": 86400,
      "eventRules": [
        {
          "eventType": "app_backgrounded",
          "operations": [
            { "op": "count", "outputKey": "background_count" }
          ]
        },
        {
          "eventType": "app_foregrounded",
          "operations": [
            { "op": "count", "outputKey": "foreground_count" }
          ]
        },
        {
          "eventType": "session_ended",
          "operations": [
            { "op": "count", "outputKey": "session_count" },
            { "op": "sum",   "field": "event.properties.durationSeconds", "outputKey": "total_session_seconds" },
            { "op": "max",   "field": "event.properties.durationSeconds", "outputKey": "longest_session_seconds" }
          ]
        }
      ]
    },
    {
      "id": "screen_view_counts",
      "uploadInterval": 86400,
      "eventRules": [
        {
          "eventType": "screen_viewed",
          "operations": [
            { "op": "count",       "outputKey": "screen_view_count" },
            { "op": "countUnique", "field": "event.properties.name", "outputKey": "unique_screens_viewed" }
          ]
        }
      ]
    }
  ]
}
```

**Top-level fields**

| Field | Type | Description |
|---|---|---|
| `version` | integer | Monotonically increasing. The SDK stores the last-seen version and discards any response whose version is ≤ the stored value (stale CDN delivery). |
| `rules` | array | Ordered list of aggregation rules. See [Rule Schema](../features/aggregation.md#rule-schema) in the feature doc for full field definitions. |

---

## Version Skipping

The SDK stores the last successfully applied ruleset version in `sdk_meta`
(`aggregation_rules_version`). On receipt of a new response:

- If `response.version > stored version` — apply the new ruleset atomically and update the stored version.
- If `response.version ≤ stored version` — discard the response. The cached ruleset remains active.

This protects against CDN serving a stale cached response after a ruleset rollback.

---

## Rate Limiting (Client-Side)

The SDK enforces a 24-hour minimum interval between fetches, regardless of how
often `configure()` runs or how many foreground events occur. The last fetch
timestamp is stored in `sdk_meta` (`aggregation_rules_last_fetched_at`).

The rate limit is checked before making the request. If fewer than 24 hours
have elapsed since the last fetch, the request is skipped and the cached
ruleset remains active.

---

## Retry Behaviour

| Response class | Action |
|---|---|
| `2xx` | Apply ruleset (subject to version check). Update `last_fetched_at`. |
| `4xx` | Log error — no retry. Cached ruleset remains active. |
| `5xx` or network error | No retry in the current fetch window. Cached ruleset remains active until the next scheduled fetch. |
