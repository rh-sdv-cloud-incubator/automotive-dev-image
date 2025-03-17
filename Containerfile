FROM --platform=${BUILDPLATFORM:-linux/arm64} ghcr.io/astral-sh/uv:latest AS uv

FROM quay.io/fedora/fedora:40 AS builder
RUN dnf install -y make git && \
    dnf clean all && \
    rm -rf /var/cache/dnf
COPY --from=uv /uv /uvx /bin/
RUN git clone https://github.com/jumpstarter-dev/jumpstarter.git /src
RUN make -C /src build

FROM quay.io/devfile/universal-developer-image:latest

USER 0

# Install required packages
RUN dnf install -y --allowerasing \
    gcc \
    gcc-c++ \
    make \
    automake \
    autoconf \
    libtool \
    pkgconfig \
    rpm-build \
    bc \
    clang \
    llvm \
    python3-docutils && \
    dnf clean all

# Jumpstarter
RUN dnf install -y libusb || dnf install -y libusb1 || true && \
    dnf clean all


COPY --from=uv /uv /bin/uv
RUN /bin/uv python install 3.12.3
RUN uv venv /jumpstarter

COPY --from=builder /src/dist/*.whl /tmp/
RUN VIRTUAL_ENV=/jumpstarter uv pip install /tmp/*.whl
ENV PATH="/jumpstarter/bin:${PATH}"

# caib
RUN curl -L -o /usr/local/bin/caib https://github.com/rh-sdv-cloud-incubator/automotive-dev-operator/releases/download/v0.0.1/caib-c02b0c200980f1e99d8e9d55ce902ed76781714c-arm64 && \
    chmod +x /usr/local/bin/caib

RUN mkdir -p /home/user/.config
RUN chmod -R g+rwx /home/user/{.config,.local,.cache} && \
    chgrp -R 0 /home/user/{.config,.local,.cache}

# Switch back to default user
USER 10001

ENV HOME=/home/user
WORKDIR /projects
ENTRYPOINT [ "/entrypoint.sh" ]
CMD ["tail", "-f", "/dev/null"]
