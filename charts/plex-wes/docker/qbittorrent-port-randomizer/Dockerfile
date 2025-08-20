FROM python:3-slim

COPY requirements.txt .
COPY qbt_randomize_port.py .

RUN pip install -r requirements.txt

ENTRYPOINT ["python3", "qbt_randomize_port.py"]