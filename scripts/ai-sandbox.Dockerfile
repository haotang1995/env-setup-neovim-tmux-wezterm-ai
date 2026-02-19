FROM ubuntu:24.04

# Build tools, common utilities, and agent dependencies
RUN apt-get update -qq && apt-get install -y -qq --no-install-recommends \
  build-essential \
  ca-certificates \
  curl \
  git \
  jq \
  less \
  openssh-client \
  python3 \
  python3-pip \
  python3-venv \
  ripgrep \
  tree \
  wget \
  && rm -rf /var/lib/apt/lists/*

# Node.js 22 via NodeSource
RUN curl -fsSL https://deb.nodesource.com/setup_22.x | bash - \
  && apt-get install -y -qq --no-install-recommends nodejs \
  && rm -rf /var/lib/apt/lists/*

# Non-root user (uid 1000) for Claude's --dangerously-skip-permissions
RUN groupadd -g 1000 sandbox && useradd -m -u 1000 -g sandbox sandbox

RUN npm install -g @anthropic-ai/claude-code @google/gemini-cli @openai/codex \
  && npm cache clean --force
