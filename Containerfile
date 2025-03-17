FROM quay.io/devfile/universal-developer-image:latest

USER 0

# Install a recent version of ruby
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
    libusb && \
    libusb1 && \
    dnf clean all


# Jumpstarter
FROM --platform=${BUILDPLATFORM:-linux/arm64} ghcr.io/astral-sh/uv:latest AS uv

FROM fedora:40 AS builder
RUN dnf install -y make git && \
    dnf clean all && \
    rm -rf /var/cache/dnf
COPY --from=uv /uv /uvx /bin/
RUN git clone https://github.com/jumpstarter-dev/jumpstarter.git /src
RUN make -C /src build
COPY --from=uv /uv /bin/uv
RUN /bin/uv python install 3.12.3
RUN uv venv /jumpstarter
COPY --from=builder /src/dist/*.whl /tmp/
RUN VIRTUAL_ENV=/jumpstarter uv pip install /tmp/*.whl
ENV PATH="/jumpstarter/bin:${PATH}"

RUN mkdir -p /home/user/.config/jumpstarter/clients /home/user/.local/bin /home/user/.config/containers/
RUN chown -R 10001:0 /home/user && chmod g+rwx -R /home/user


# Switch back to default user
USER 10001

ENV HOME=/home/user
WORKDIR /projects
ENTRYPOINT [ "/entrypoint.sh" ]
CMD ["tail", "-f", "/dev/null"]
