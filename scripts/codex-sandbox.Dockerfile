FROM node:22-slim

RUN apt-get update -qq && apt-get install -y -qq --no-install-recommends \
  ca-certificates \
  git \
  openssh-client \
  less \
  && rm -rf /var/lib/apt/lists/*

