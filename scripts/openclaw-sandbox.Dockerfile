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
  sudo \
  tree \
  unzip \
  wget \
  && rm -rf /var/lib/apt/lists/*

# Node.js 24 via NodeSource
RUN curl -fsSL https://deb.nodesource.com/setup_24.x | bash - \
  && apt-get install -y -qq --no-install-recommends nodejs \
  && rm -rf /var/lib/apt/lists/*

# Non-root user with passwordless sudo (long-lived; agent needs to install packages)
# ubuntu:24.04 ships with a 'ubuntu' user at uid 1000; reuse it or create fresh.
RUN if getent passwd 1000 >/dev/null; then \
      usermod -l claw -d /home/claw -m -s /bin/bash \
        $(getent passwd 1000 | cut -d: -f1) 2>/dev/null || true; \
      groupmod -n claw $(getent group 1000 | cut -d: -f1) 2>/dev/null || true; \
    else \
      groupadd -g 1000 claw && useradd -m -u 1000 -g claw -s /bin/bash claw; \
    fi \
  && echo 'claw ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/claw \
  && chmod 0440 /etc/sudoers.d/claw

USER claw
WORKDIR /home/claw
CMD ["bash"]
