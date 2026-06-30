#!/usr/bin/env bash
# https://www.howtogeek.com/307701/how-to-customize-and-colorize-your-bash-prompt/
# https://www.quora.com/What-are-some-useful-bash_profile-and-bashrc-tips/answer/Shubham-Chaudhary-3
# https://natelandau.com/my-mac-osx-bash_profile/
#
# Source global definitions
if [ -f /etc/bashrc ]; then
    # shellcheck source=/dev/null
    . /etc/bashrc
fi

# Per-machine env overrides that must load even for non-interactive shells
# (e.g. `bash -c` from tools/hooks): worklog WORKLOG_REPO/WORKLOG_BIN, etc.
# Keep this above the interactive guard. Interactive extras still go in
# ~/.shell_common.local, sourced later via .shell_common.
if [ -f "$HOME/.shell_common.local" ]; then
    # shellcheck source=/dev/null
    . "$HOME/.shell_common.local"
fi

# ~/.bashrc: executed by bash(1) for non-login shells.
# If not running interactively, don't do anything
[ -z "$PS1" ] && return
# don't put duplicate lines in the history or force ignoredups and ignorespace
HISTCONTROL=ignoredups:ignorespace
# append to the history file, don't overwrite i
shopt -s histappend
# for setting history length see HISTSIZE and HISTFILESIZE in bash(1)
HISTSIZE=100000
HISTFILESIZE=200000
# check the window size after each command and, if necessary,
# update the values of LINES and COLUMNS.
shopt -s checkwinsize
# make less more friendly for non-text input files, see lesspipe(1)
[ -x /usr/bin/lesspipe ] && eval "$(SHELL=/bin/sh lesspipe)"
# set variable identifying the chroot you work in (used in the prompt below)
if [ -z "$debian_chroot" ] && [ -r /etc/debian_chroot ]; then
    debian_chroot=$(cat /etc/debian_chroot)
fi
# set a fancy prompt (non-color, unless we know we "want" color)
case "$TERM" in
xterm-color) color_prompt=yes ;;
esac
# uncomment for a colored prompt, if the terminal has the capability; turned
# off by default to not distract the user: the focus in a terminal window
# should be on the output of commands, not on the prompt
#force_color_prompt=yes
if [ -n "$force_color_prompt" ]; then
    if [ -x /usr/bin/tput ] && tput setaf 1 >&/dev/null; then
        # We have color support; assume it's compliant with Ecma-48
        # (ISO/IEC-6429). (Lack of such support is extremely rare, and such
        # a case would tend to support setf rather than setaf.)
        color_prompt=yes
    else
        color_prompt=
    fi
fi
if [ "$color_prompt" = yes ]; then
    PS1='${debian_chroot:+($debian_chroot)}\[\033[01;32m\]\u@\h\[\033[00m\]:\[\033[01;34m\]\w\[\033[00m\]\$ '
else
    PS1='${debian_chroot:+($debian_chroot)}\u@\h:\w\$ '
fi
unset color_prompt force_color_prompt
# If this is an xterm set the title to user@host:dir
case "$TERM" in
xterm* | rxvt*)
    PS1="\[\e]0;${debian_chroot:+($debian_chroot)}\u@\h: \w\a\]$PS1"
    ;;
*) ;;

esac

parse_git_branch() {
    if which git &>/dev/null && git rev-parse --is-inside-work-tree &>/dev/null; then
        local BR=$(git rev-parse --symbolic-full-name --abbrev-ref HEAD 2>/dev/null)
        if [ "$BR" == HEAD ]; then
            local NM=$(git name-rev --name-only HEAD 2>/dev/null)
            if [ "$NM" != undefined ]; then
                echo -n "@$NM"
            else
                git rev-parse --short HEAD 2>/dev/null
            fi
        else
            echo -n "$BR"
        fi
    else
        echo ∅
    fi
}
# nicer prompt
PS1="\n\[\e[30;1m\](\[\e[34;1m\]\u@\h:\w\[\e[30;1m\]) (\[\e[32;1m\]$(/bin/ls -1 | /usr/bin/wc -l | /bin/sed 's: ::g') files, $(/bin/ls -lah | /bin/grep -m 1 total | /bin/sed 's/total //')b\[\e[30;1m\]) (\e[36m$(parse_git_branch))\] \n--> \[\e[0m\]"

# enable color support of ls and also add handy aliases
if [ -x /usr/bin/dircolors ]; then
    test -r ~/.dircolors && eval "$(dircolors -b ~/.dircolors)" || eval "$(dircolors -b)"
    alias ls='ls --color=auto'
    #alias dir='dir --color=auto'
    #alias vdir='vdir --color=auto'
    alias grep='grep --color=auto'
    alias fgrep='fgrep --color=auto'
    alias egrep='egrep --color=auto'
fi
# some more ls aliases
alias ll='ls -alF'
alias la='ls -a'
#alias l='ls -CF'
# Add an "alert" alias for long running commands.  Use like so:
#   sleep 10; alert
# Alert alias - only enable if notify-send is available
if command -v notify-send &>/dev/null; then
    alias alert='notify-send --urgency=low -i "$([ $? = 0 ] && echo terminal || echo error)" "$(history|tail -n1|sed -e '\''s/^\s*[0-9]\+\s*//;s/[;&|]\s*alert$//'\'')"'
fi
# Alias definitions.
# You may want to put all your additions into a separate file like
# ~/.bash_aliases, instead of adding them here directly.
if [ -f "$HOME"/.bash_aliases ]; then
    # shellcheck source=/dev/null
    . "$HOME"/.bash_aliases
fi
# enable programmable completion features (you don't need to enable
# this, if it's already enabled in /etc/bash.bashrc and /etc/profile
# sources /etc/bash.bashrc).
if [ -f /etc/bash_completion ] && ! shopt -oq posix; then
    # shellcheck source=/dev/null
    . /etc/bash_completion
fi
export http_proxy= #"Page on 168"
if [ -f ~/.kde-bashrc ]; then
    # shellcheck source=/dev/null
    . ~/.kde-bashrc
fi

#------------------------------------------////
# Source common shell configuration
#------------------------------------------////
if [ -f "$HOME/.shell_common" ]; then
    # shellcheck source=/dev/null
    . "$HOME/.shell_common"
fi

#------------------------------------------////
# Bash-specific configuration
#------------------------------------------////

# Reload alias (bash-specific)
alias reload='source ~/.bashrc'

# Show most popular commands (bash-specific syntax)
alias top-commands='history | awk "{print $2}" | awk "{print $1}" |sort|uniq -c | sort -rn | head -10'
. ~/.super-autocomplete.bash
unset KUBERNETES_SERVICE_PORT
unset KUBERNETES_SERVICE_HOST
# --- datadog-vscode-autoinstall (super) ---
DATADOG_ID="datadog.datadog-vscode"

# pick an editor CLI we can talk to
if command -v code >/dev/null 2>&1; then
  EDITOR_CLI=code
elif command -v cursor >/dev/null 2>&1; then
  EDITOR_CLI=cursor
fi

# only proceed if editor CLI exists and extension not installed
if [ -n "$EDITOR_CLI" ] && ! "$EDITOR_CLI" --list-extensions 2>/dev/null | grep -qx "$DATADOG_ID"; then
  # install via our own CLI
  if command -v super >/dev/null 2>&1; then
    super extensions enable datadog >/dev/null 2>&1 || true
  fi
  # verify again; if still not installed, log message
  if ! "$EDITOR_CLI" --list-extensions 2>/dev/null | grep -qx "$DATADOG_ID"; then
    echo "[datadog] CLI ran but extension not present yet; will retry on next shell" >&2
  fi
fi
# --- end datadog-vscode-autoinstall (super) ---
# --- claude-code-autoinstall (super) ---
CLAUDE_CODE_ID="anthropic.claude-code"

# pick an editor CLI we can talk to
if command -v code >/dev/null 2>&1; then
  EDITOR_CLI=code
elif command -v cursor >/dev/null 2>&1; then
  EDITOR_CLI=cursor
fi

# only proceed if editor CLI exists and extension not installed
if [ -n "$EDITOR_CLI" ] && ! "$EDITOR_CLI" --list-extensions 2>/dev/null | grep -qx "$CLAUDE_CODE_ID"; then
  # install via our own CLI
  if command -v super >/dev/null 2>&1; then
    super extensions enable claude-code >/dev/null 2>&1 || true
  fi
  # verify again; if still not installed, log message
  if ! "$EDITOR_CLI" --list-extensions 2>/dev/null | grep -qx "$CLAUDE_CODE_ID"; then
    echo "[claude-code] CLI ran but extension not present yet; will retry on next shell" >&2
  fi
fi
# --- end claude-code-autoinstall (super) ---
