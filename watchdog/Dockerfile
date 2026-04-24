FROM python:3.12-alpine
RUN pip install --no-cache-dir requests
COPY watchdog.py /watchdog.py
CMD ["python", "-u", "/watchdog.py"]
