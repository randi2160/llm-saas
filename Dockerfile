FROM python:3.12-slim
WORKDIR /app
COPY app.py .
RUN pip install --no-cache-dir fastapi uvicorn
EXPOSE 8080
CMD ["uvicorn", "app:app", "--host", "0.0.0.0", "--port", "8080"]
