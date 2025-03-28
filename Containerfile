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
    # Build essentials
    make \
    cmake \
    procps-ng \
    # Security & Certificates
    openssl \
    ca-certificates \
    # Compression tools
    libbrotli \
    tar \
    gzip \
    zip \
    xz \
    unzip \
    # Version Control
    git \
    # System utilities
    which \
    shadow-utils \
    util-linux \
    # Shells and editors
    bash \
    zsh \
    vi \
    vim-minimal \
    vim-enhanced \
    # Network tools
    openssh-clients \
    wget \
    jq \
    # Container tools
    podman \
    buildah \
    skopeo \
    podman-docker \
    fuse-overlayfs \
    # Python
    python3.12 \
    python3.12-pip \
    python3.12-devel"

ENV HOME=${USER_HOME_DIR}
ENV BUILDAH_ISOLATION=chroot

COPY --chown=0:0 entrypoint.sh /

RUN dnf install --disableplugin=subscription-manager -y https://dl.fedoraproject.org/pub/epel/epel-release-latest-9.noarch.rpm ; \
  dnf --disableplugin=subscription-manager install -y ${INSTALL_PACKAGES} ; \
  dnf update -y ; \
  dnf clean all ; \
  ln -s /usr/bin/pip3.12 /usr/bin/pip3 ; \
  ln -s /usr/bin/pip3.12 /usr/bin/pip ; \
  ln -s /usr/bin/python3.12 /usr/bin/python3 ; \
  ln -s /usr/bin/python3.12 /usr/bin/python ; \
  useradd -u 10001 -G wheel,root -d /home/user --shell /bin/bash -m user && \
  mkdir -p /usr/local/bin ; \
  mkdir -p ${WORK_DIR} ; \
  pip install -U podman-compose ; \
  pip install -U cekit ; \
  mkdir -p ${USER_HOME_DIR}/.config/containers/ ; \
  chown -R 10001:0 ${USER_HOME_DIR}/.config ; \
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
  chmod -R g=u /etc/subuid /etc/subgid ;

# caib
RUN curl -L -o /usr/local/bin/caib https://github.com/rh-sdv-cloud-incubator/automotive-dev-operator/releases/download/v0.0.4/caib-v0.0.4-${TARGETARCH} && \
    chmod +x /usr/local/bin/caib

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


USER 10001
WORKDIR ${WORK_DIR}
ENV KUBECONFIG=/home/user/.kube/config
ENTRYPOINT ["/usr/libexec/podman/catatonit","--","/entrypoint.sh"]
CMD [ "tail", "-f", "/dev/null" ]
