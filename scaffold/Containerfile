FROM registry.access.redhat.com/ubi9/python-312:latest
WORKDIR /opt/app-root/src
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY server.py .
ENV MCP_TRANSPORT=streamable-http
EXPOSE 8080
CMD ["python", "server.py"]
