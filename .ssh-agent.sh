#!/usr/bin/env bash
#ssh-agent handling
if [ ! -S ~/.ssh/ssh_auth_sock ]; then
  eval $(ssh-agent)
  ln -sf "$SSH_AUTH_SOCK" ~/.ssh/ssh_auth_sock
fi
export SSH_AUTH_SOCK=~/.ssh/ssh_auth_sock

# Add SSH keys if they exist
if ! ssh-add -l >/dev/null 2>&1; then
  # Try to add common SSH key patterns
  for key in ~/.ssh/*rsa ~/.ssh/id_*; do
    if [ -f "$key" ] && [[ "$key" != *.pub ]]; then
      ssh-add "$key" >/dev/null 2>&1
    fi
  done
fi
