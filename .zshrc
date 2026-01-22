#!/usr/bin/env zsh
# https://www.howtogeek.com/307701/how-to-customize-and-colorize-your-bash-prompt/
# https://www.quora.com/What-are-some-useful-bash_profile-and-bashrc-tips/answer/Shubham-Chaudhary-3
# https://natelandau.com/my-mac-osx-bash_profile/
#
# Source global definitions
if [ -f /etc/zshrc ]; then
    . /etc/zshrc
fi

# ~/.zshrc: executed by zsh for interactive shells.
# History settings
HISTFILE=~/.zsh_history
HISTSIZE=100000
SAVEHIST=200000
setopt HIST_IGNORE_DUPS        # Don't record duplicate entries
setopt HIST_IGNORE_SPACE       # Don't record entries starting with space
setopt APPEND_HISTORY          # Append to history file
setopt SHARE_HISTORY           # Share history between sessions
setopt EXTENDED_HISTORY        # Save timestamp and duration

# Shell options
setopt AUTO_CD                 # cd by just typing directory name
setopt INTERACTIVE_COMMENTS    # Allow comments in interactive shells

# Enable command completion
autoload -Uz compinit
compinit

# Make less more friendly for non-text input files
[ -x /usr/bin/lesspipe ] && eval "$(SHELL=/bin/sh lesspipe)"

# Set variable identifying the chroot you work in (used in the prompt below)
if [ -z "$debian_chroot" ] && [ -r /etc/debian_chroot ]; then
    debian_chroot=$(cat /etc/debian_chroot)
fi

parse_git_branch() {
    if which git &>/dev/null && git rev-parse --is-inside-work-tree &>/dev/null; then
        local BR=$(git rev-parse --symbolic-full-name --abbrev-ref HEAD 2>/dev/null)
        if [ "$BR" = "HEAD" ]; then
            local NM=$(git name-rev --name-only HEAD 2>/dev/null)
            if [ "$NM" != "undefined" ]; then
                echo -n "@$NM"
            else
                git rev-parse --short HEAD 2>/dev/null
            fi
        else
            echo -n "$BR"
        fi
    else
        echo "∅"
    fi
}

# Enable prompt substitution for command substitution in PS1
setopt PROMPT_SUBST

# Nicer prompt - adapted for zsh
PS1=$'\n%{\e[30;1m%}(%{\e[34;1m%}%n@%m:%~%{\e[30;1m%}) (%{\e[32;1m%}$(/bin/ls -1 | /usr/bin/wc -l | /bin/sed "s: ::g") files, $(/bin/ls -lah | /bin/grep -m 1 total | /bin/sed "s/total //")b%{\e[30;1m%}) (%{\e[36m%}$(parse_git_branch)%{\e[0m%}%{\e[30;1m%})\n--> %{\e[0m%}'

# Enable color support of ls and also add handy aliases
if [ -x /usr/bin/dircolors ]; then
    test -r ~/.dircolors && eval "$(dircolors -b ~/.dircolors)" || eval "$(dircolors -b)"
    alias ls='ls --color=auto'
    alias grep='grep --color=auto'
    alias fgrep='fgrep --color=auto'
    alias egrep='egrep --color=auto'
fi

# Some more ls aliases
alias ll='ls -alF'
alias la='ls -a'

# Alert alias - only enable if notify-send is available
if command -v notify-send &>/dev/null; then
    alias alert='notify-send --urgency=low -i "$([ $? = 0 ] && echo terminal || echo error)" "$(history | tail -n1 | sed -e '\''s/^\s*[0-9]\+\s*//;s/[;&|]\s*alert$//'\'')"'
fi

# Alias definitions.
# You may want to put all your additions into a separate file like
# ~/.zsh_aliases, instead of adding them here directly.
if [ -f "$HOME/.zsh_aliases" ]; then
    . "$HOME/.zsh_aliases"
fi

# Also source bash aliases if they exist
if [ -f "$HOME/.bash_aliases" ]; then
    . "$HOME/.bash_aliases"
fi

# Enable completion features
if [ -f /usr/share/zsh/functions/Completion/Unix/_zsh_completion ]; then
    . /usr/share/zsh/functions/Completion/Unix/_zsh_completion
fi

if [ -f ~/.kde-zshrc ]; then
    . ~/.kde-zshrc
fi

#------------------------------------------////
# Source common shell configuration
#------------------------------------------////
if [ -f "$HOME/.shell_common" ]; then
    . "$HOME/.shell_common"
fi

#------------------------------------------////
# Zsh-specific configuration
#------------------------------------------////

# Reload alias (zsh-specific)
alias reload='source ~/.zshrc'

# Show most popular commands (zsh-specific syntax)
alias top-commands='history 1 | awk "{print \$2}" | awk "{print \$1}" | sort | uniq -c | sort -rn | head -10'
