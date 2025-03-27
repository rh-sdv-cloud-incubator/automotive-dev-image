FROM --platform=${BUILDPLATFORM:-linux/arm64} ghcr.io/astral-sh/uv:latest AS uv

FROM quay.io/fedora/fedora:40 AS builder
RUN dnf install -y make git && \
    dnf clean all && \
    rm -rf /var/cache/dnf
COPY --from=uv /uv /uvx /bin/
RUN git clone https://github.com/jumpstarter-dev/jumpstarter.git /src
RUN make -C /src build

FROM quay.io/centos/centos:stream9-development AS dependencies

ARG TARGETARCH

RUN dnf update -y
RUN mkdir -p /etc/yum.repos.d
RUN echo -e "[alexl-cs9-sample-images]\n\
name=Copr repo for cs9-sample-images owned by alexl\n\
baseurl=https://download.copr.fedorainfracloud.org/results/alexl/cs9-sample-images/centos-stream-9-${TARGETARCH}/\n\
type=rpm-md\n\
skip_if_unavailable=True\n\
gpgcheck=0\n\
repo_gpgcheck=0\n\
enabled=1\n\
enabled_metadata=1" > /etc/yum.repos.d/alexl-cs9-sample-images.repo

RUN dnf install --releasever 9 --installroot /installroot -y --nogpgcheck vsomeip3 bash \
    boost-system boost-thread boost-log boost-chrono boost-date-time boost-atomic \
    boost-log boost-filesystem boost-regex auto-apps boost-devel vsomeip3-devel

FROM quay.io/devfile/universal-developer-image:latest

USER 0

RUN dnf install -y --allowerasing \
    gcc \
    gcc-c++ \
    make \
    cmake \
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

COPY --from=dependencies /installroot /

COPY --from=uv /uv /bin/uv
RUN /bin/uv python install 3.12.3
RUN uv venv /jumpstarter

COPY --from=builder /src/dist/*.whl /tmp/
RUN VIRTUAL_ENV=/jumpstarter uv pip install /tmp/*.whl
ENV PATH="/jumpstarter/bin:${PATH}"

# caib
RUN curl -L -o /usr/local/bin/caib https://github.com/rh-sdv-cloud-incubator/automotive-dev-operator/releases/download/v0.0.2/caib-v0.0.2-${TARGETARCH} && \
    chmod +x /usr/local/bin/caib

RUN mkdir -p /home/user/.config/jumpstarter
RUN chmod -R g+rwx /home/user/{.config,.local,.cache}

RUN echo "user:10000:65536" >> /etc/subuid && \
    echo "user:10000:65536" >> /etc/subgid

# Switch back to default user
USER 10001
ENV HOME=/home/user
ENV XDG_CONFIG_HOME=/tmp/.config
WORKDIR /projects
ENTRYPOINT [ "/entrypoint.sh" ]
CMD ["tail", "-f", "/dev/null"]
