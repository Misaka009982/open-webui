ARG BUILD_HASH=dev-build
ARG UID=0
ARG GID=0

FROM --platform=$BUILDPLATFORM node:22-alpine3.20 AS build
ARG BUILD_HASH

WORKDIR /app

RUN apk add --no-cache git

COPY package.json package-lock.json ./
RUN npm ci --force

COPY . .
ENV APP_BUILD_HASH=${BUILD_HASH}
RUN npm run build

FROM python:3.11-slim-bookworm AS base

ARG UID
ARG GID
ARG BUILD_HASH

ENV ENV=prod \
    PORT=8080

ENV ENABLE_OLLAMA_API=false \
    ENABLE_IMAGE_GENERATION=false \
    ENABLE_SPEECH_TO_TEXT=false \
    ENABLE_TEXT_TO_SPEECH=false \
    ENABLE_ADMIN_EXPORT=false \
    ENABLE_MODEL_FILTER=false \
    ENABLE_FUNCTION_CALLING=false \
    ENABLE_AGENT_CHAT=false \
    ENABLE_MESSAGE_RATING=false \
    ENABLE_MCP_SERVERS=false

ENV ENABLE_RAG_WEB_SEARCH=true \
    ENABLE_WEB_BROWSING=true \
    SEARCH_PROVIDER=duckduckgo

ENV RAG_EMBEDDING_ENGINE="openai" \
    OPENAI_API_KEY="" \
    WEBUI_SECRET_KEY="" \
    SCARF_NO_ANALYTICS=true \
    DO_NOT_TRACK=true \
    ANONYMIZED_TELEMETRY=false

WORKDIR /app/backend

ENV HOME=/root

RUN if [ $UID -ne 0 ]; then \
    if [ $GID -ne 0 ]; then \
    addgroup --gid $GID app; \
    fi; \
    adduser --uid $UID --gid $GID --home $HOME --disabled-password --no-create-home app; \
    fi

RUN mkdir -p $HOME/.cache/chroma && \
    echo -n 00000000-0000-0000-0000-000000000000 > $HOME/.cache/chroma/telemetry_user_id

RUN chown -R $UID:$GID /app $HOME

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    curl jq \
    && rm -rf /var/lib/apt/lists/*

COPY --chown=$UID:$GID ./backend/requirements.txt ./requirements.txt

RUN pip3 install --no-cache-dir uv && \
    pip3 install torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cpu --no-cache-dir && \
    uv pip install --system -r requirements.txt --no-cache-dir && \
    mkdir -p /app/backend/data && chown -R $UID:$GID /app/backend/data/

COPY --chown=$UID:$GID --from=build /app/build /app/build
COPY --chown=$UID:$GID --from=build /app/CHANGELOG.md /app/CHANGELOG.md
COPY --chown=$UID:$GID --from=build /app/package.json /app/package.json

COPY --chown=$UID:$GID ./backend .

EXPOSE 8080

HEALTHCHECK CMD curl --silent --fail http://localhost:${PORT:-8080}/health | jq -ne 'input.status == true' || exit 1

USER $UID:$GID

ENV WEBUI_BUILD_VERSION=${BUILD_HASH}
ENV DOCKER=true

CMD [ "bash", "start.sh"]
