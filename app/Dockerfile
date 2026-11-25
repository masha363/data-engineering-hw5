FROM python:3.12-slim
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY skills.py .
COPY hw3 ./hw3
CMD ["python", "skills.py", "local", "/data/hh_analysts_2024.csv"]
