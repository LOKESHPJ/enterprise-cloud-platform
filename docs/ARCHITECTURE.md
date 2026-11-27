# Architecture

## Design constraints

1. No component runs on a developer machine. Builds, plans and deploys happen on GitHub runners.
2. No long-lived AWS credentials. GitHub assumes IAM roles through OIDC.
3. The default deployment must cost nothing. A billable architecture is available but gated.
4. One application codebase, two very different runtimes.

## Tracks

### Serverless track (`infrastructure/serverless`)

| Layer | Service | Notes |
|---|---|---|
| Edge / SPA hosting | API Gateway, `$default` route | One HTTPS origin for UI and API, so no CORS |
| Optional CDN | CloudFront + private S3 (OAC) | `enable_cloudfront=true`; blocked on unverified accounts |
| API | API Gateway HTTP API | `GET /`, `ANY /api/{proxy+}`, `$default`, 100 rps throttle |
| Compute | Lambda (python3.12, 512 MB) | FastAPI through Mangum, 25 s timeout, serves the SPA bundle from `static/` |
| Data | DynamoDB single table | `pk`/`sk` + `gsi1`, PAY_PER_REQUEST, encryption at rest |
| Logs | CloudWatch Logs | 7 day retention on both log groups |
| Alerts | 2 metric alarms + dashboard | Lambda errors, API 5xx |

Request path (default mode):

```
Browser -> API Gateway -> Lambda
                            |- /api/*  -> FastAPI routers -> DynamoDB
                            '- /*      -> static/index.html + /assets
```

Two hosting modes exist because CloudFront is unavailable until AWS verifies a new
account:

| `enable_cloudfront` | SPA served from | URL scheme |
|---|---|---|
| `false` (default here) | the Lambda bundle, same origin as the API | HTTPS on `*.execute-api.*` |
| `true` | private S3 + CloudFront + OAC | HTTPS on `*.cloudfront.net` |


### Enterprise track (`infrastructure/terraform`)

| Layer | Resource | Notes |
|---|---|---|
| Network | VPC `10.20.0.0/16` | 2 AZs, 2 public + 2 private subnets, IGW |
| Egress | NAT gateway (optional) | Off in cost mode; tasks run public with restricted SGs |
| Edge | ALB | HTTP :80, optional HTTPS :443 with ACM |
| Routing | Listener rules | `/api/*` goes to the API target group, everything else to the web target group |
| Compute | ECS Fargate | API 0.25 vCPU and 512 MB, two tasks. Web one task. Circuit breaker rollback |
| Registry | ECR | Immutable tags, scan on push, lifecycle policy |
| Data | RDS PostgreSQL 16.4 | `db.t4g.micro`, gp3 20 GB, single-AZ, TLS enforced |
| Secrets | Secrets Manager | Generated 32 char password, read only by the execution role |
| Observability | CloudWatch | 6 alarms, 1 dashboard, 7 day log retention |

Request path:

```
Browser -> ALB :80
             |- /api/*  -> ECS API task (FastAPI + SQLAlchemy -> RDS)
             '- /*      -> ECS web task (nginx -> React bundle)
```

## Security controls

- **No static AWS credentials.** The OIDC trust policy is limited to
  `repo:LOKESHPJ/enterprise-cloud-platform:ref:refs/heads/main` and
  `...:environment:*`. A pull request from a fork cannot assume the role.
- **Identity escalation blocked.** The enterprise deploy role has an explicit deny on
  `iam:CreateUser`, `iam:CreateAccessKey`, `iam:CreateLoginProfile`, `organizations:*`
  and `account:*`, even though it holds PowerUserAccess.
- **Least privilege at runtime.** The ECS task role has no policies attached. The
  execution role can read exactly one secret ARN.
- **Network segmentation.** ALB SG accepts 80/443 from the internet. App SG accepts
  8000/8080 only from the ALB SG. DB SG accepts 5432 only from the app SG.
- **Database not public.** `publicly_accessible = false`, private subnets, `rds.force_ssl=1`.
- **Bucket not public.** Block Public Access on, CloudFront reads via OAC with a
  `AWS:SourceArn` condition.
- **Immutable images.** ECR tag immutability prevents silently replacing a deployed tag.

## Failure modes and behaviour

| Failure | Behaviour |
|---|---|
| API task crashes on boot | Target group never marks it healthy; ECS circuit breaker rolls back to the previous task definition |
| API returns 5xx | `api-5xx` alarm fires, dashboard shows the target group error rate |
| Database unreachable | `/api/health` returns 503, ALB marks targets unhealthy after 3 failed checks |
| Database slow | p95 latency alarm at 2 s for 10 minutes; RDS CPU alarm at 80% |
| Traffic spike | Target tracking at 60% CPU scales the API from 2 to 6 tasks, with a 60 s scale-out cooldown |
| Image tag missing | Task fails to pull; circuit breaker stops the deployment instead of taking down the service |
| Log volume grows | Retention is enforced at 7 days by Terraform, so log groups cannot grow unbounded |

## Why two phases for the ECS deploy

ECS services reference an image that Terraform cannot build. Applying services before
the image exists produces a deployment loop of failing tasks. Instead:

1. `enable_services=false`: creates VPC, ALB, RDS, ECR, secret and alarms. The ALB has empty
   target groups.
2. `build-push.yml`: images tagged `sha-<commit>` land in ECR.
3. `enable_services=true` with `image_tag`: services start and health checks pass.

The same flag makes teardown safe: `destroy` runs with `enable_services=false` so
services are removed before the images and cluster disappear.

## Release model

Every deploy publishes an immutable Lambda version and moves the `live` alias.

```
terraform apply  -> new version N+1 published, alias untouched
release job      -> alias live: N -> N+1
ship job         -> builds the SPA, seeds data, runs API and site smoke tests
                 -> on any failure: alias moves back to N automatically
```

Terraform owns the function and its versions; the pipeline owns the alias
position (`lifecycle { ignore_changes = [function_version] }`). That split is
what makes a rollback a single atomic alias update rather than a redeploy.

AWS CodeDeploy would provide a 10%/5-minute canary with alarm-driven rollback,
but it is unavailable on this account until AWS completes verification
(`SubscriptionRequiredException`). The pipeline implements the same guarantee
with a verify-then-revert step, and `release.tf` documents where CodeDeploy
would slot in.

## Data model

Single table design (DynamoDB) and relational equivalent (PostgreSQL):

| Entity | DynamoDB | PostgreSQL |
|---|---|---|
| Product | `pk=PRODUCT#<id>`, `sk=METADATA`, `gsi1pk=TYPE#PRODUCT` | `products` |
| Order | `pk=ORDER#<id>`, `sk=METADATA`, `gsi1pk=TYPE#ORDER` | `orders` (line items in JSONB) |

Money is stored as integer cents in both. Orders are priced server side from the
catalogue, so a tampered request cannot change the total.
