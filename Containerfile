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

RUN dnf update -y && \
    mkdir -p /etc/yum.repos.d && \
    COPR_ARCH=$(case "$TARGETARCH" in \
        "amd64") echo "x86_64" ;; \
        "arm64") echo "aarch64" ;; \
        *) echo "$TARGETARCH" ;; \
    esac) && \
    echo "Using architecture for COPR repo: $COPR_ARCH for Docker TARGETARCH: $TARGETARCH" && \
    echo -e "[alexl-cs9-sample-images]\n\
name=Copr repo for cs9-sample-images owned by alexl\n\
baseurl=https://download.copr.fedorainfracloud.org/results/alexl/cs9-sample-images/centos-stream-9-$COPR_ARCH/\n\
type=rpm-md\n\
skip_if_unavailable=True\n\
gpgcheck=0\n\
repo_gpgcheck=0\n\
enabled=1\n\
enabled_metadata=1" > /etc/yum.repos.d/alexl-cs9-sample-images.repo

RUN dnf install --releasever 9 --installroot /installroot -y --nogpgcheck vsomeip3 bash \
    boost-system boost-thread boost-log boost-chrono boost-date-time boost-atomic \
    boost-log boost-filesystem boost-regex auto-apps boost-devel vsomeip3-devel

FROM quay.io/centos/centos:stream9-development

ARG TARGETARCH
ARG USER_HOME_DIR="/home/user"
ARG WORK_DIR="/projects"
ARG INSTALL_PACKAGES="\
    procps-ng openssl tar gzip zip xz unzip which shadow-utils bash vi wget jq \
    podman buildah skopeo podman-docker fuse-overlayfs \
    gcc gcc-c++ make cmake \
    glibc-devel glibc-langpack-en \
    zlib-devel \
    libffi-devel \
    libstdc++-devel \
    python3-pip python3-devel \
    util-linux \
    vim-minimal vim-enhanced \
    git \
    ca-certificates \
    # sample apps dependencies
    vsomeip3 vsomeip3-devel \
    boost-devel"

ENV HOME=${USER_HOME_DIR}
ENV BUILDAH_ISOLATION=chroot

COPY --from=dependencies /installroot /
COPY --chown=0:0 entrypoint.sh /


COPY --from=uv /uv /bin/uv
# breaks stuff
RUN /bin/uv python install 3.12.3
RUN uv venv /jumpstarter
COPY --from=builder /src/dist/*.whl /tmp/
RUN VIRTUAL_ENV=/jumpstarter uv pip install /tmp/*.whl
ENV PATH="/jumpstarter/bin:${PATH}"

RUN dnf --disableplugin=subscription-manager install -y ${INSTALL_PACKAGES}; \
  dnf update -y ; \
  dnf clean all ; \
  ln -s /usr/bin/pip3.12 /usr/bin/pip3 ; \
  ln -s /usr/bin/pip3.12 /usr/bin/pip ; \
  ln -s /usr/bin/python3.12 /usr/bin/python3 ; \
  ln -s /usr/bin/python3.12 /usr/bin/python ; \
  mkdir -p /usr/local/bin ; \
  mkdir -p ${WORK_DIR} ; \
  pip3 install -U podman-compose ; \
  pip3 install -U cekit ; \
  chgrp -R 0 /home ; \
  chmod -R g=u /home ${WORK_DIR} ; \
  chmod +x /entrypoint.sh ; \
  chown 0:0 /etc/passwd ; \
  chown 0:0 /etc/group ; \
  chmod g=u /etc/passwd /etc/group ; \
  # Setup for rootless podman
  setcap cap_setuid+ep /usr/bin/newuidmap ; \
  setcap cap_setgid+ep /usr/bin/newgidmap ; \
  touch /etc/subgid /etc/subuid ; \
  chown 0:0 /etc/subgid ; \
  chown 0:0 /etc/subuid ; \
  chmod -R g=u /etc/subuid /etc/subgid

# oc client
ENV OC_VERSION=4.18
RUN echo "TARGETARCH=${TARGETARCH}, OC_VERSION=${OC_VERSION}" && \
    if [ "${TARGETARCH}" = "arm64" ]; then \
        curl -L -o /tmp/oc.tar.gz "https://mirror.openshift.com/pub/openshift-v4/clients/ocp/stable-${OC_VERSION}/openshift-client-linux-arm64.tar.gz"; \
    else \
        curl -L -o /tmp/oc.tar.gz "https://mirror.openshift.com/pub/openshift-v4/clients/ocp/stable-${OC_VERSION}/openshift-client-linux-amd64-rhel9.tar.gz"; \
    fi && \
    tar -C /usr/local/bin -xzvf /tmp/oc.tar.gz --no-same-owner && \
    chmod +x /usr/local/bin/oc && \
    rm -f /tmp/oc.tar.gz

# OS Pipelines CLI (tkn)
ENV TKN_VERSION=1.18.0
RUN if [ "${TARGETARCH}" = "arm64" ]; then \
        curl -L "https://mirror.openshift.com/pub/openshift-v4/clients/pipelines/${TKN_VERSION}/tkn-linux-arm64.tar.gz"; \
    else \
        curl -L "https://mirror.openshift.com/pub/openshift-v4/clients/pipelines/${TKN_VERSION}/tkn-linux-amd64.tar.gz"; \
    fi | tar -C /usr/local/bin -xz --no-same-owner && \
    chmod +x /usr/local/bin/tkn /usr/local/bin/opc /usr/local/bin/tkn-pac

USER 1000
WORKDIR ${WORK_DIR}
ENTRYPOINT ["/usr/libexec/podman/catatonit","--","/entrypoint.sh"]
CMD [ "tail", "-f", "/dev/null" ]
