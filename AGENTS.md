# Project Overview

A set of Go microservices that send telemetry to the Grafana LGTM stack (Loki, Grafana, Tempo, Mimir). Logs are also saved to a GCP bucket.

# Documentation

Most code changes do not need an internal documentation change. Agents can read the code.

- Focus on the *why* behind decisions, not the *how* (unless the how is relevant).
- When documenting the *how*, document flows, e.g. how data moves from a request to Loki. Basic API endpoints don't need docs; only complex ones do.

# Pull Requests

- Never open a PR unless the developer explicitly asks for one.
- Title: conventional commit, plain language, e.g. `fix: user create endpoint is now idempotent`.
- Body: the problem in a sentence or two, then how you fixed it. End with the model and harness that did the work.
- One request is one PR. Split it only when the maintainer asks.
