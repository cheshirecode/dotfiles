a#!/usr/bin/env bash
#ssh-agent handling
if [ ! -S ~/.ssh/ssh_auth_sock ]; then
  eval $(ssh-agent)
  ln -sf "$SSH_AUTH_SOCK" ~/.ssh/ssh_auth_sock
fi
export SSH_AUTH_SOCK=~/.ssh/ssh_auth_sock
ssh-add -l >/dev/null || ssh-add ~/.ssh/*rsa >/dev/null || ssh-add ~/.ssh/id_* >/dev/null
