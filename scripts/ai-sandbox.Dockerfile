FROM node:22-slim

RUN apt-get update -qq && apt-get install -y -qq --no-install-recommends \
  ca-certificates \
  git \
  openssh-client \
  less \
  && rm -rf /var/lib/apt/lists/*

RUN npm install -g @anthropic-ai/claude-code @google/gemini-cli @openai/codex \
  && npm cache clean --force
