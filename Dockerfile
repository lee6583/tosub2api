FROM node:22-bookworm-slim

RUN apt-get update \
    && apt-get install -y --no-install-recommends python3 python3-venv ca-certificates \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app
COPY package.json package-lock.json requirements.txt ./
RUN npm ci --include=dev \
    && python3 -m venv /opt/tosub2-venv \
    && /opt/tosub2-venv/bin/pip install --no-cache-dir -r requirements.txt

COPY --chown=node:node . .
ENV NODE_ENV=production \
    TOSUB2_PYTHON=/opt/tosub2-venv/bin/python \
    ONBOARDING_OUTPUT_ROOT=/data
USER node
EXPOSE 4399
CMD ["node", "src/console-server.mjs", "--host", "0.0.0.0", "--port", "4399"]
