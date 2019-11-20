FROM kindest/node:v1.15.3

RUN echo "Installing gVisor binaries ..." \
    && export RUNSC_URL="https://storage.googleapis.com/gvisor/releases/nightly/latest/runsc" \
    && curl -sSL --retry 5 --output /usr/bin/runsc "${RUNSC_URL}" \
    && export RUNSC_SHIM_URL="https://github.com/google/gvisor-containerd-shim/releases/download/v0.0.3/containerd-shim-runsc-v1.linux-amd64"\
    && curl -sSL --retry 5 --output /usr/bin/containerd-shim-runsc-v1 "${RUNSC_SHIM_URL}"\
    && chmod 0755 /usr/bin/containerd-shim-runsc-v1 /usr/bin/runsc

# copy updated containerd config 
# uncomment/needed if kind version is < 0.6.0 
# COPY config.toml /etc/containerd/config.toml