# review-web

The page a customer opens from the "customer time review" e-mail that Business Central sends.
It shows the tasks and hours logged on their project, lets them enter approved hours per task,
and submits the answer back to Business Central, which then marks the time entries billable or
not billable.

Single file, no npm dependencies, Node 18+.

## How it works

```
customer ──GET /review/<token>──▶ review-web ──S2S OAuth──▶ BC API integrated/jira/v1.0
                                              GET  customerReviews?$filter=accessToken eq '<token>'
                                              GET  customerReviewLines?$filter=reviewNo eq N
customer ──POST /review/<token>─▶ review-web  PATCH customerReviewLines(<id>)  { approvedHours, customerComment }
                                              POST  customerReviews(<id>)/Microsoft.NAV.submit
```

The access token in the URL is the only thing that identifies the customer. Links are unguessable
(32 hex chars), single-use (BC refuses a second submit) and can be cancelled from BC.

## Configuration

Copy `.env.example` to `.env` and fill it in. Environment variables:

| Variable | Meaning |
|---|---|
| `BC_TENANT_ID` | Entra tenant of the BC environment |
| `BC_ENVIRONMENT` | BC environment name (`sandbox`, `Production`) |
| `BC_COMPANY_ID` | Company system id (`GET .../api/v2.0/companies`) |
| `AAD_CLIENT_ID` / `AAD_CLIENT_SECRET` | Entra app registration with BC API permission `API.ReadWrite.All` (application), registered in BC on page 9860 with permission set `BCJ JiraIntegration` |
| `BRAND_NAME` | Page title |
| `PORT` | Listen port (default 3000) |

The base URL where this app is reachable goes into BC: Jira Integration Setup → Customer Review Base URL,
e.g. `https://review.integrated.ee`. BC builds links as `<base>/review/<token>`.

## Run locally

```bash
cd review-web
set -a; source .env; set +a      # or export the variables another way
node server.js
# open http://localhost:3000/review/<token from a BC Customer Time Review>
```

## Deploy

Any host that runs a container or Node works. `Dockerfile` is included. Set the environment
variables in the host, expose port 3000, point a domain at it, and put that domain into
Customer Review Base URL in BC.
