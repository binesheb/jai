# JAI API

Initial FastAPI service for the reusable JAI platform.

The API is deliberately small in the first foundation commit. Business modules and AI tools will be added behind explicit application boundaries rather than exposing the database directly.

## Local run

```bash
python -m pip install -r requirements.txt
uvicorn main:app --reload
```

Endpoints:

- `GET /health/live`
- `GET /health/ready`
- `GET /api/v1/platform`

No customer data is required to run this service.
