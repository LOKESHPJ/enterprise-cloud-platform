"""Mangum adapter: exposes the FastAPI ASGI app as an AWS Lambda handler."""

from mangum import Mangum

from app.main import app

handler = Mangum(app, lifespan="off")
