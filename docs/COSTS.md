# Costs

All figures are `us-east-1`, on-demand, list price, running 24/7 for a month.
Verify against the AWS pricing calculator before trusting them for a budget.

## Serverless track

| Service | Free allowance | Demo usage | Cost |
|---|---|---|---|
| Lambda | 1M requests, 400,000 GB-s | a few thousand requests | $0.00 |
| API Gateway HTTP API | 1M requests (12 months) | a few thousand | $0.00 |
| DynamoDB (on-demand) | 25 GB storage + 25 WCU/RCU equivalent | < 10 MB | $0.00 |
| S3 | 5 GB, 20k GET (12 months) | < 5 MB | $0.00 |
| CloudFront | 1 TB transfer, 10M requests | negligible | $0.00 |
| CloudWatch Logs | 5 GB ingest | < 100 MB | $0.00 |
| CloudWatch alarms | 10 alarms | 2 | $0.00 |
| IAM / OIDC / STS | free | — | $0.00 |
| **Total** | | | **$0.00** |

Caveats:

- DynamoDB is on-demand. Past the free allowance, writes are $1.25 per million.
- The free tier for HTTP API and S3 is a 12 month allowance on legacy accounts. On the
  new account model, free-plan credits cover the same usage.
- CloudWatch Logs is the easiest line item to grow accidentally: a runaway log loop can
  exceed 5 GB. Retention is set to 7 days for this reason.

## Enterprise track

### Cost mode (default: `enable_nat_gateway = false`)

| Resource | Configuration | Monthly |
|---|---|---|
| Application Load Balancer | 1 ALB, minimal LCU | $16.00 - $20.00 |
| ECS Fargate | 0.25 vCPU / 0.5 GB, 3 tasks running | $13.50 - $16.00 |
| RDS PostgreSQL | `db.t4g.micro`, gp3 20 GB, single-AZ | $12.00 - $15.00 |
| Secrets Manager | 1 secret | $0.40 |
| ECR | ~1 GB images | $0.10 |
| CloudWatch | 6 alarms, 3 log groups, 1 dashboard | $0.50 - $1.00 |
| **Total** | | **≈ $43 - $52** |

### Production mode (`enable_nat_gateway = true`, Multi-AZ, more tasks)

| Change | Adds |
|---|---|
| 2 NAT gateways | +$32.00 |
| RDS Multi-AZ | +$12.00 - $15.00 |
| API 4 tasks | +$6.00 |
| **Total** | **≈ $93 - $105** |

### Per-hour intuition

- ALB: ~$0.0225/hour base + LCU charges
- Fargate 0.25 vCPU + 0.5 GB: ~$0.0123/hour per task
- RDS `db.t4g.micro`: ~$0.018/hour
- Everything idle: roughly **$0.06/hour**, about **$1.50/day**

A two-hour demo costs about **$0.12**. The expensive mistakes are leaving it running
for a week ($10) or forgetting NAT and Multi-AZ are on.

## Cost controls built into this repo

1. `confirm_spend` variable — Terraform refuses to plan the enterprise track unless it is
   `true`. The workflow additionally requires typing `DEPLOY-BILLABLE`.
2. `enable_services` — the first apply creates no running compute.
3. NAT gateway default off — saves $32/month and is called out in the README.
4. CloudWatch retention 7 days, Container Insights disabled, Performance Insights off,
   PITR off on DynamoDB, no DynamoDB Provisioned capacity.
5. ECR lifecycle policy — 10 tagged images max, untagged expire in 7 days.
6. `skip_final_snapshot = true` and no deletion protection in cost mode, so teardown does
   not fail or leave paid snapshots behind.
7. Destroy workflows for both tracks.

## Recommended extra guard (not provisioned here)

Create an AWS Budget with a $1 threshold and email alerts:

```bash
aws budgets create-budget \
  --account-id "$(aws sts get-caller-identity --query Account --output text)" \
  --budget '{"BudgetName":"ecp-zero-spend","BudgetLimit":{"Amount":"1","Unit":"USD"},"TimeUnit":"MONTHLY","BudgetType":"COST"}' \
  --notifications-with-subscribers '[{"Notification":{"NotificationType":"ACTUAL","ComparisonOperator":"GREATER_THAN","Threshold":80},"Subscribers":[{"SubscriptionType":"EMAIL","Address":"you@example.com"}]}]'
```

Budgets themselves are free for the first two budgets.
