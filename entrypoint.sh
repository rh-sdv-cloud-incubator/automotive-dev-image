#!/usr/bin/env bash

set -e
if [ ! -d "${HOME}" ]
then
  mkdir -p "${HOME}"
fi

mkdir -p "${HOME}/.ssh"
if [ ! -f "${HOME}/.ssh/config" ]; then
  cat > "${HOME}/.ssh/config" <<EOF
Host *
    StrictHostKeyChecking no
    UserKnownHostsFile /dev/null
    LogLevel QUIET
EOF
fi
chmod 700 "${HOME}/.ssh"
chmod 600 "${HOME}/.ssh/config"

if [ ! -d "${HOME}/.config/containers" ]; then
  mkdir -p ${HOME}/.config/containers
  (echo 'unqualified-search-registries = [';echo '  "registry.access.redhat.com",';echo '  "registry.redhat.io",';echo '  "docker.io"'; echo ']'; echo 'short-name-mode = "permissive"') > ${HOME}/.config/containers/registries.conf
  if [ -c "/dev/fuse" ] && [ -f "/usr/bin/fuse-overlayfs" ]; then
    (echo '[storage]';echo 'driver = "overlay"';echo '[storage.options.overlay]';echo 'mount_program = "/usr/bin/fuse-overlayfs"') > ${HOME}/.config/containers/storage.conf
  else
    (echo '[storage]';echo 'driver = "vfs"') > "${HOME}"/.config/containers/storage.conf
  fi
fi

if ! whoami &> /dev/null
then
  if [ -w /etc/passwd ]
  then
    echo "${USER_NAME:-user}:x:$(id -u):0:${USER_NAME:-user} user:${HOME}:/bin/bash" >> /etc/passwd
    echo "${USER_NAME:-user}:x:$(id -u):" >> /etc/group
  fi
fi

USER=$(whoami)
START_ID=$(( $(id -u)+1 ))
echo "${USER}:${START_ID}:2147483646" > /etc/subuid
echo "${USER}:${START_ID}:2147483646" > /etc/subgid

if [ ! -f ${HOME}/.bashrc ]
then
  (echo "if [ -f ${PROJECT_SOURCE}/workspace.rc ]"; echo "then"; echo "  . ${PROJECT_SOURCE}/workspace.rc"; echo "fi") > ${HOME}/.bashrc
fi

oc whoami &> /dev/null && podman login -u $(oc whoami) -p $(oc whoami -t) image-registry.openshift-image-registry.svc:5000 || true

if [ -n "${SSHFS_REMOTE}" ] && [ -n "${SSHFS_MOUNTPOINT}" ] && [ -n "${SSHFS_PASSWORD}" ]; then
  echo "Setting up SSHFS mount from ${SSHFS_REMOTE} to ${SSHFS_MOUNTPOINT}"
  mkdir -p "${SSHFS_MOUNTPOINT}"

  set +e
  sshfs "${SSHFS_REMOTE}" "${SSHFS_MOUNTPOINT}" \
    -o ssh_command="sshpass -p ${SSHFS_PASSWORD} ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null" \
    -o reconnect \
    -o ServerAliveInterval=15 \
    -o ServerAliveCountMax=3

  MOUNT_RESULT=$?
  set -e

  if [ $MOUNT_RESULT -eq 0 ]; then
    echo "SSHFS mount successful, continuing with startup"
  else
    echo "SSHFS mount failed with exit code $MOUNT_RESULT, but continuing with startup anyway"
  fi
fi

exec "$@"
