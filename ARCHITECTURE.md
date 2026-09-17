# Architecture

## 1. Folder Structure

```
.
├── main.go                        Entry point — loads config, inits store, starts HTTP server
├── compose.yml                    Docker Compose stack (API, Postgres, OTel Collector, Victoria*, Grafana)
├── .env                           PORT, DATABASE_URL, POSTGRES_* and AWS credentials (not committed)
├── grafana-datasources.yaml       Grafana datasource provisioning
├── config/
│   ├── config.go                  Reads PORT and DATABASE_URL from .env via spf13/viper
│   └── otel-collector-config.yml  OTel Collector pipeline: receivers, exporters (Victoria* + S3)
├── scripts/
│   └── postgres-backup.sh         Scheduled pg_dump of the Postgres volume; entrypoint of the postgres-backup service
├── terraform/
│   ├── main.tf                    Root Terraform config — wires modules, sets AWS provider
│   └── modules/
│       └── s3/
│           └── main.tf            S3 bucket + IAM policy for log archival
├── db/
│   └── db.go                      Postgres-backed store (GORM); InitDB opens the connection used by all handlers
├── models/
│   ├── user.go                    User domain type
│   ├── product.go                 Product domain type
│   └── order.go                   Order + OrderItem domain types; OrderStatus constants
├── handlers/
│   ├── user_handler.go            HTTP handlers for /api/users endpoints
│   ├── product_handler.go         HTTP handlers for /api/products endpoints
│   └── order_handler.go           HTTP handlers for /api/orders endpoints
├── routes/
│   └── routes.go                  Registers all routes on a gorilla/mux router; attaches middleware
├── middlewares/
│   └── logging.go                 Per-request logging: method, path, status code, duration
└── utils/
    └── response.go                JSON() and Error() response helpers; NewID() random hex ID generator
```

## 2. Request Lifecycle

```
HTTP Request
    │
    ▼
gorilla/mux Router
    │  (matches path + method)
    ▼
middlewares.Logging          ← wraps ResponseWriter to capture status code
    │  records start time
    ▼
Handler function             ← decodes body, validates input, calls db.Store methods
    │  e.g. handlers.CreateOrder
    ▼
db.PostgresStore             ← gorm.DB; runs SQL against the Postgres service over the compose network
    │
    ▼
utils.JSON / utils.Error     ← sets Content-Type, writes status + JSON body
    │
    ▼
middlewares.Logging          ← prints [HTTP] line with method/path/status/duration
    │
    ▼
HTTP Response
```

## 3. Entities and Relationships

```
User  1 ──────────── * Order
                          │
                          │  contains 1..*
                          ▼
                      OrderItem  * ──── 1  Product
```

- A **User** can place many **Orders**.
- Each **Order** contains one or more **OrderItems**.
- Each **OrderItem** references exactly one **Product** and captures the `unit_price` at the moment the order was placed (so future price changes do not retroactively alter historical orders).
- When an order is created, stock is deducted from each referenced **Product** atomically (all-or-nothing) inside a single Postgres transaction in `db.PostgresStore.CreateOrder`.

## 4. API Endpoint Table

| Method | Path                        | Purpose                                      |
|--------|-----------------------------|----------------------------------------------|
| POST   | /api/users                  | Register a new user                          |
| GET    | /api/users/{id}             | Get a user by ID                             |
| GET    | /api/users/{id}/orders      | List all orders belonging to a user          |
| GET    | /api/products               | List all products                            |
| POST   | /api/products               | Create a new product                         |
| GET    | /api/products/{id}          | Get a product by ID                          |
| PUT    | /api/products/{id}          | Partially update a product (price, stock, …) |
| DELETE | /api/products/{id}          | Delete a product                             |
| POST   | /api/orders                 | Create an order (validates stock, deducts)   |
| GET    | /api/orders/{id}            | Get an order by ID                           |
| PUT    | /api/orders/{id}/status     | Update order status (pending/completed/cancelled) |

### Request / Response shapes

**POST /api/users**
```json
// Request
{ "name": "Alice", "email": "alice@example.com" }

// 201 Created
{ "id": "...", "name": "Alice", "email": "alice@example.com", "created_at": "..." }
```

**POST /api/products**
```json
// Request
{ "name": "Widget", "description": "...", "price": 9.99, "stock": 100 }

// 201 Created — full Product object
```

**PUT /api/products/{id}**
```json
// Request — all fields optional, only provided fields are changed
{ "price": 12.99, "stock": 80 }

// 200 OK — updated Product object
```

**POST /api/orders**
```json
// Request
{
  "user_id": "<user-id>",
  "items": [
    { "product_id": "<product-id>", "quantity": 2 }
  ]
}

// 201 Created
{
  "id": "...",
  "user_id": "...",
  "items": [{ "product_id": "...", "quantity": 2, "unit_price": 9.99 }],
  "total_amount": 19.98,
  "status": "pending",
  "created_at": "..."
}
```

**PUT /api/orders/{id}/status**
```json
// Request
{ "status": "completed" }

// 200 OK — updated Order object
```

All error responses have the shape:
```json
{ "error": "human-readable message" }
```

## 5. Observability & Telemetry Pipeline

The Go API is instrumented with the OpenTelemetry SDK and exports telemetry to a local OTel Collector, which fans it out to the appropriate backends.

```
Go API (OTLP HTTP → :4318)
    │
    ▼
OpenTelemetry Collector
    ├── metrics  ──► VictoriaMetrics  (:8428)
    ├── traces   ──► VictoriaTraces   (:10428)
    └── logs     ──► VictoriaLogs     (:9428)   ← hot, queryable via Grafana
                 └──► AWS S3                    ← cold archive
                          bucket : tharshen-terraform-primary-bucket
                          prefix : logs/YYYY/MM/DD/HH/MM
```

**AWS S3 log export** is handled by the `awss3` exporter in `config/otel-collector-config.yml`. AWS credentials are injected into the collector container via a `.env` file (`AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`). The bucket and IAM resources are provisioned in `terraform/`.

## 6. Debugging Guide

| Symptom | Where to look |
|---------|---------------|
| Order total is wrong | `handlers/order_handler.go` — `CreateOrder`, the `total +=` accumulation loop |
| Stock not being deducted | `handlers/order_handler.go` — `CreateOrder`; the deduction happens in the `db.PostgresStore.CreateOrder` transaction |
| Product not found | Postgres `products` table; run a `GET /api/products` to see what IDs exist |
| User not found | Postgres `users` table; confirm the ID used in the request matches a `POST /api/users` response |
| Duplicate email error | `db/db.go` — `EmailExists` runs a `COUNT` over the `users` table; the match is case-sensitive |
| Request not reaching handler | `routes/routes.go` — verify the method and path prefix `/api` are registered correctly |
| Status code not appearing in logs | `middlewares/logging.go` — the `responseWriter` wrapper; check `WriteHeader` is called by the handler |
| Server does not start | `main.go` + `config/config.go` — ensure `.env` (or the compose environment) provides `PORT` and a reachable `DATABASE_URL`; the process exits if the Postgres connection fails |
| Middleware not executing | `routes/routes.go` — `r.Use(middlewares.Logging)` must be called before handler registration |
| Logs not appearing in S3 | `config/otel-collector-config.yml` — verify `awss3` exporter is listed under `logs.exporters`; check `.env` has valid `AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY` |
| OTel Collector fails to start | Run `docker compose logs opentelemetry` — missing `.env` or malformed `otel-collector-config.yml` are the most common causes |
| API cannot reach the database | Run `docker compose logs api postgres`; the `postgres` service must be healthy and `DATABASE_URL` must point at it |
| Restoring from backup | Run `docker compose logs postgres-backup` for the dump path, then `pg_restore` the file from the `pgbackups` volume |
| S3 bucket does not exist | Run `terraform apply` in `terraform/` — the bucket is not created manually, it is provisioned by the S3 module |
