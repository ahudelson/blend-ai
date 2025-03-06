# Build stage
FROM python:3.12-slim AS builder
WORKDIR /app
COPY requirements.txt .
RUN pip install --user -r requirements.txt
RUN python -m nltk.downloader -d /var/task/nltk_data punkt stopwords

# Final stage
FROM public.ecr.aws/lambda/python:3.12
WORKDIR ${LAMBDA_TASK_ROOT}
COPY --from=builder /root/.local/lib/python3.12/site-packages/ .
COPY --from=builder /var/task/nltk_data /var/task/nltk_data
COPY main.py .
CMD ["main.handler"]