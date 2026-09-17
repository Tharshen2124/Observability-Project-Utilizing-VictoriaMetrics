# VictoriaMetrics + VictoriaLogs Dummy Project
<img width="2804" height="1622" alt="ArchitectureDiagram" src="https://github.com/user-attachments/assets/0dc62c5d-b494-44e5-b26c-315df8b99058" />


This is a **learning project** to practice setting up and using:

- VictoriaMetrics
- VictoriaLogs
- VictoriaTraces
- OpenTelemetry
- Grafana
- AWS S3 (log archival)
- Terraform (AWS infrastructure provisioning)
- Golang (for instrumented demo app)

The goal is to understand how metrics, logs, and traces flow through a modern observability stack, how to visualize/query them in Grafana, and how to archive logs long-term to S3.

## What this project is for

- Learn how to run a local observability stack with Docker Compose.
- Learn how OpenTelemetry can collect/forward telemetry (metrics, logs, and traces).
- Learn how VictoriaMetrics stores and serves time-series metrics.
- Learn how VictoriaLogs stores and serves logs.
- Learn how VictoriaTraces stores and serves distributed traces.
- Learn how Grafana connects to all three backends for dashboards and exploration.
- Learn how to archive logs long-term to AWS S3 with time-based partitioning.
- Learn how to provision cloud infrastructure (S3 bucket, IAM) with Terraform.

## Tech Stack

- **VictoriaMetrics** (`victoriametrics/victoria-metrics`)
- **VictoriaLogs** (`victoriametrics/victoria-logs`)
- **VictoriaTraces** (`victoriametrics/victoria-traces`)
- **OpenTelemetry Collector** (`otel/opentelemetry-collector-contrib`)
- **Grafana** (`grafana/grafana`)
- **AWS S3** (long-term log archival via OTel Collector `awss3` exporter)
- **Golang** (to produce sample app telemetry)

## Architecture (high level)

1. A Golang app emits metrics/logs/traces via the OpenTelemetry SDK.
2. OpenTelemetry Collector receives telemetry on OTLP HTTP (`4318`).
3. Metrics are exported to VictoriaMetrics; traces to VictoriaTraces.
4. Logs are exported to **both** VictoriaLogs (hot/queryable) and **AWS S3** (cold archival, partitioned by `YYYY/MM/DD/HH/MM`).
5. Grafana reads from VictoriaMetrics, VictoriaLogs, and VictoriaTraces for dashboards and queries.

## Services and Ports

From `compose.yml`:

- **VictoriaMetrics**: `http://localhost:8428`
- **VictoriaLogs**: `http://localhost:9428`
- **VictoriaTraces**: `http://localhost:9429`
- **Grafana**: `http://localhost:3000`
- **OpenTelemetry Collector (OTLP HTTP)**: `http://localhost:4318`
- **Cloudflare Tunnel connector** (`cloudflared`): host-networked; carries the `*.tharshen.xyz` hostnames

> Current retention in this setup is `2d` for VictoriaMetrics and VictoriaLogs.

## Prerequisites

- Docker + Docker Compose
- AWS account with credentials that have permissions to provision S3 and IAM resources
- Terraform installed (to provision the S3 bucket and IAM resources in `terraform/`)
- A `.env` file in the project root with your AWS credentials and Cloudflare tunnel token (see Getting Started)
- (Optional) Go installed locally if you want to run a sample app outside containers

## Getting Started

1. Provision AWS infrastructure with Terraform:

	```bash
	cd terraform
	terraform init
	terraform apply
	```

2. Create a `.env` file in the project root with your AWS credentials:

	```bash
	AWS_ACCESS_KEY_ID=your_access_key_id
	AWS_SECRET_ACCESS_KEY=your_secret_access_key
	TUNNEL_TOKEN=your_cloudflare_tunnel_token
	```

	> The OTel Collector uses these to authenticate the `awss3` log exporter. The
	> `TUNNEL_TOKEN` (from the Cloudflare Zero Trust dashboard) lets the
	> `cloudflared` service run the `homelab` tunnel.

3. Start the stack:

	```bash
	docker compose up -d
	```

4. Check running services:

	```bash
	docker compose ps
	```

5. Open Grafana:

	- URL: `http://localhost:3000`
	- Default credentials (unless changed): `admin` / `admin`

6. Stop the stack when done:

	```bash
	docker compose down
	```

## Useful Commands

View all logs:

```bash
docker compose logs -f
```

View a single service logs:

```bash
docker compose logs -f victoria-metrics
docker compose logs -f victoria-logs
docker compose logs -f opentelemetry
docker compose logs -f grafana
```

Reset all persisted data (destructive):

```bash
docker compose down -v
```

## Recovery

The stack is built to come back on its own after a crash or a host reboot:

- Every service declares `restart: always`, so Docker restarts a container that
  exits, and brings the project back up when the host (and Docker daemon) restarts.
- The Cloudflare Tunnel connector (`cloudflared`) is part of this project and
  pinned to an image version, so `docker compose up -d` also restores public
  ingress instead of relying on a connector started by hand.

When a hostname served through the tunnel is unavailable, work through this order:

1. Check the connector is running and registered:

	```bash
	docker compose ps cloudflared
	docker compose logs --tail=50 cloudflared
	```

	A healthy connector logs `Registered tunnel connection`.

2. If it is not running, start (or restart) the project:

	```bash
	docker compose up -d
	```

3. Confirm the origin services are up:

	```bash
	docker compose ps
	docker compose logs --tail=50 api opentelemetry grafana
	```

4. Only if the connector still shows no active connection, inspect the tunnel in
   the Cloudflare Zero Trust dashboard (Networks -> Tunnels).

> The connector requires `TUNNEL_TOKEN` in `.env`. If it is missing, `cloudflared`
> exits immediately and Docker restarts it in a loop; `docker compose logs
> cloudflared` shows this.

## Suggested Learning Path

1. Provision AWS infrastructure with Terraform (`terraform/`).
2. Bring up the stack and verify all services are healthy.
3. Send sample telemetry from the Go app using OpenTelemetry.
4. Confirm data ingestion in VictoriaMetrics, VictoriaLogs, and VictoriaTraces.
5. Explore data in Grafana (dashboards + query editors).
6. Verify logs are being archived in the S3 bucket under `logs/YYYY/MM/DD/HH/MM`.
7. Tune retention and collector pipelines to understand trade-offs.

## Project Structure

```text
.
├── compose.yml
├── .env                          # AWS credentials (not committed)
├── README.md
├── ARCHITECTURE.md
├── config/
│   └── otel-collector-config.yml
├── grafana-datasources.yaml
└── terraform/                    # AWS infrastructure (S3 bucket, IAM)
```

## Notes

- This is intentionally a **dummy/non-production** setup.
- Defaults are kept simple for learning and quick iteration.
- For production, add auth, TLS, backup strategy, and hardened configs.
