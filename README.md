# hn_aggregator

Hacker News Aggregator written in **Erlang/OTP**.

Application periodically fetches top stories from the [Hacker News API](https://github.com/HackerNews/API) and makes them available via **HTTP** and **WebSockets**.

---

## Features

- Fetches the **top 50 stories** from Hacker News every **5 minutes**.
- Stores all data **in-memory** (no external databases).
- Provides two public APIs:
  - **HTTP API** (JSON)
    - List stories with pagination (10 per page).
    - Fetch a single story by ID.
  - **WebSockets API** (JSON)
    - Sends the 50 top stories immediately on connection.
    - Pushes refreshed stories automatically when updates are fetched.
- Proper supervision tree using OTP principles.
- Non-blocking operation: fetching new stories does not block serving data from memory.
- Includes tests with strategy for mocking Hacker News API responses.
- Function specifications and typespecs included.

---

## Architecture

The application is structured as a standard **OTP application**:

- **hn_aggregator_app** – Application entry point, starts supervision tree.
- **hn_aggregator_sup** – Supervisor for application components.
- **hn_poller** – Periodically fetches top stories from Hacker News API, supervised by `hn_aggregator_sup`.
- **hn_storage_handler** – In-memory store of the latest 50 stories, supervised by `hn_aggregator_sup`.
- **hn_rate_limiter** – ETS-based rate limiter for HTTP/WebSocket connections, supervised by `hn_aggregator_sup`.
- **hn_http_handler** – Cowboy-based HTTP handler exposing REST endpoints.
- **hn_ws_handler** – Cowboy-based WebSocket handler pushing updates to clients.

### Data Flow
1. `hn_poller` polls the Hacker News API every 5 minutes. First poll is immediate.
2. Results are stored in `hn_storage_handler`'s ETS tables.
3. HTTP API serves stories directly from ETS.
4. WebSocket connections get initial stories from ETS, and updates (from ETS) when new data is fetched.

---

## Installation & Running

### Prerequisites
- Erlang/OTP 26+
- `rebar3`

### Build (environment: local|prod)
```bash
rebar3 as <environment> release
```

### Run in shell
```bash
./_build/<environment>/rel/hn_aggregator/bin/hn_aggregator console
```
This starts the OTP application with supervision tree.

---

## API Usage

### HTTP API
- **List stories (paginated):**
  ```
  GET /stories?page=1
  ```
  Response (JSON): 10 stories per page.

- **Fetch a single story:**
  ```
  GET /stories/:id
  ```

### WebSocket API
- Connect to:
  ```
  ws://localhost:8080/ws
  ```
- On connection, the client receives the 50 top stories.
- When the fetcher updates, clients receive the new stories.
- Client should take care of supporting connection open with ping/heartbeat messages.

---

## Testing

Tests are implemented using **Common Test**. To run:
```bash
rebar3 as test ct --suite=test/hn_aggregator_SUITE --config ./config/test/ct.args
```

Tests include:
- Tests for story fetching and storage.
- Mocked API tests for retry logic (when HN API fails).
- Basic WebSocket tests.

---

## Suggested Improvements

While the current implementation satisfies the challenge requirements, the following improvements are suggested:

- **Retry Backoff:** Implement exponential backoff instead of fixed retries with linear backoff when HN API is unavailable.
- **WebSocket Subscriptions:** Allow clients to request partial updates (e.g., only new story IDs) instead of full list.
- **Security Hardening:**
  - Improve rate limiting to HTTP and WS endpoints with more sophisticated algorithms.
  - Sanitize query parameters for pagination.
- **Observability:** Add metrics for monitoring fetch durations, API errors, and active connections.
- **Test Coverage:**
  - Introduce unit tests for individual modules.
  - Improve integration tests.
  - Extend WebSocket test cases.
---

## License

This project is licensed under the Apache License 2.0 - see the LICENSE.md file for details.

---


## Dependencies

- **Erlang/OTP 26+**: Required runtime
- **cowboy**: HTTP/WebSocket server
- **jsone**: JSON encoding/decoding

## Dependencies (tests only)

- **gun**: HTTP/WebSocket client
