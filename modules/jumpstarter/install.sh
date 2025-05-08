#!/bin/bash
set -e

mkdir -p /tmp/uv
ARCH=$(uname -m)
if [ "${ARCH}" = "aarch64" ]; then
    UV_ARCH="aarch64"
else
    UV_ARCH="x86_64"
fi

curl -L -o /tmp/uv.tar.gz "https://github.com/astral-sh/uv/releases/latest/download/uv-${UV_ARCH}-unknown-linux-gnu.tar.gz"

tar -xzf /tmp/uv.tar.gz -C /tmp/uv

UV_EXEC=$(find /tmp/uv -type f -name "uv" | head -n 1)
if [ -z "$UV_EXEC" ]; then
  find /tmp/uv -type f
  exit 1
fi

mv "$UV_EXEC" /bin/uv
chmod +x /bin/uv

rm -rf /tmp/uv /tmp/uv.tar.gz

dnf install -y make git
dnf clean all
rm -rf /var/cache/dnf

git clone https://github.com/jumpstarter-dev/jumpstarter.git /src
make -C /src build

/bin/uv python install 3.12.3
uv venv /jumpstarter
VIRTUAL_ENV=/jumpstarter uv pip install /src/dist/*.whl

mkdir -p /home/user/.jumpstarter
chmod -R g=u /home/user/.jumpstarter/

rm -rf /src
