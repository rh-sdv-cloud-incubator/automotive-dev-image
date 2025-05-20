#!/bin/bash
set -e

dnf update -y

mkdir -p /etc/yum.repos.d

echo "ta $TARGETARCH"

case "${TARGETARCH:-x86_64}" in
  amd64)
    COPR_ARCH="x86_64"
    ;;
  arm64)
    COPR_ARCH="aarch64"
    ;;
  *)
    COPR_ARCH="${TARGETARCH:-x86_64}"
    ;;
esac

echo "copr arch: $COPR_ARCH"

cat > /etc/yum.repos.d/alexl-cs9-sample-images.repo << EOF
[alexl-cs9-sample-images]
name=Copr repo for cs9-sample-images owned by alexl
baseurl=https://download.copr.fedorainfracloud.org/results/alexl/cs9-sample-images/centos-stream-9-$COPR_ARCH/
type=rpm-md
skip_if_unavailable=True
gpgcheck=0
repo_gpgcheck=0
enabled=1
enabled_metadata=1
EOF

dnf install --releasever 9 -y --nogpgcheck \
    vsomeip3 \
    boost-system \
    boost-thread \
    boost-log \
    boost-chrono \
    boost-date-time \
    boost-atomic \
    boost-filesystem \
    boost-regex \
    auto-apps \
    boost-devel \
    vsomeip3-devel

dnf clean all
