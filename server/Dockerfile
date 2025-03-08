FROM eclipse-temurin:21-jre

# Install dependencies
RUN apt-get update && apt-get install -y \
    tmux \
    curl \
    unzip \
    git \
    python3 \
    python3-pip \
    python3-venv \
    python3-redis \
    netcat-openbsd \
    iputils-ping \
    dnsutils \
    procps

# Create a virtual environment and install Python packages
RUN python3 -m venv /opt/venv
ENV PATH="/opt/venv/bin:$PATH"
RUN pip3 install redis mcstatus

# Install tailscale
RUN curl -fsSL https://tailscale.com/install.sh | sh

WORKDIR /minecraft

# Copy server script and controller
COPY ./server.sh /usr/local/bin/server.sh
RUN chmod +x /usr/local/bin/server.sh
# Fix Windows line endings
RUN sed -i 's/\r$//' /usr/local/bin/server.sh

# Create Redis controller
COPY ./redis_controller.py /usr/local/bin/redis_controller.py
RUN chmod +x /usr/local/bin/redis_controller.py

# Copy entrypoint script
COPY ./entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh
RUN sed -i 's/\r$//' /usr/local/bin/entrypoint.sh

ENV ALLOW_CRACK_CLIENT=true
ENV TS_STATE_DIR=/minecraft/ts-authkey-test/state
ENV TS_HOSTNAME=minecraft-server

CMD ["/usr/local/bin/entrypoint.sh"]
