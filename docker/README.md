# Containers

No local Docker is used in this project. Both images are built inside GitHub
Actions and pushed to Amazon ECR:

| Image | Dockerfile | Registry path |
|---|---|---|
| Backend (FastAPI + uvicorn) | `application/backend/Dockerfile` | `<account>.dkr.ecr.<region>.amazonaws.com/cloudforge-<env>-api:<sha>` |
| Frontend (React → nginx) | `application/frontend/Dockerfile` | `<account>.dkr.ecr.<region>.amazonaws.com/cloudforge-<env>-web:<sha>` |

Every image is tagged with the full commit SHA (immutable) plus `latest`.
ECS task definitions reference the SHA tag, which is what makes rollback a
matter of redeploying the previous revision.

`nginx.conf` in this folder is baked into the frontend image.
