# Architecture

## 1. Folder Structure

```
.
├── main.go                        Entry point — loads config, inits store, starts HTTP server
├── compose.yml                    Docker Compose stack (API, OTel Collector, Victoria*, Grafana)
├── .env                           AWS credentials injected into OTel Collector (not committed)
├── grafana-datasources.yaml       Grafana datasource provisioning
├── config/
│   ├── config.go                  Reads PORT and DATABASE_URL from .env via spf13/viper
│   └── otel-collector-config.yml  OTel Collector pipeline: receivers, exporters (Victoria* + S3)
├── terraform/
│   ├── main.tf                    Root Terraform config — wires modules, sets AWS provider
│   └── modules/
│       └── s3/
│           └── main.tf            S3 bucket + IAM policy for log archival
├── db/
│   └── db.go                      Thread-safe in-memory store (sync.RWMutex maps); seeds sample products
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
db.InMemoryStore             ← acquires mutex, reads/writes maps, logs [DB] events
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
- When an order is created, stock is deducted from each referenced **Product** atomically (all-or-nothing via a single lock acquisition in `db.DeductStock`).

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
| Stock not being deducted | `db/db.go` — `DeductStock`; check the `[DB]` log lines for each product |
| Product not found | `db/db.go` — `Products` map; run a `GET /api/products` to see what IDs exist |
| User not found | `db/db.go` — `Users` map; confirm the UUID used in the request matches a `POST /api/users` response |
| Duplicate email error | `db/db.go` — `EmailExists` linear scan; email comparison is case-sensitive |
| Request not reaching handler | `routes/routes.go` — verify the method and path prefix `/api` are registered correctly |
| Status code not appearing in logs | `middlewares/logging.go` — the `responseWriter` wrapper; check `WriteHeader` is called by the handler |
| Server does not start | `main.go` + `config/config.go` — ensure `.env` contains `PORT=<number>` |
| Middleware not executing | `routes/routes.go` — `r.Use(middlewares.Logging)` must be called before handler registration |
| Logs not appearing in S3 | `config/otel-collector-config.yml` — verify `awss3` exporter is listed under `logs.exporters`; check `.env` has valid `AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY` |
| OTel Collector fails to start | Run `docker compose logs opentelemetry` — missing `.env` or malformed `otel-collector-config.yml` are the most common causes |
| S3 bucket does not exist | Run `terraform apply` in `terraform/` — the bucket is not created manually, it is provisioned by the S3 module |
