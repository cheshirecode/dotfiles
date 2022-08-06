#!/usr/bin/env bash
# https://www.howtogeek.com/307701/how-to-customize-and-colorize-your-bash-prompt/
# https://www.quora.com/What-are-some-useful-bash_profile-and-bashrc-tips/answer/Shubham-Chaudhary-3
# https://natelandau.com/my-mac-osx-bash_profile/
#
# Source global definitions
if [ -f /etc/bashrc ]; then
    . /etc/bashrc
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

# nicer prompt
PS1="\n\[\e[30;1m\](\[\e[34;1m\]\u@\h:\w\[\e[30;1m\]) (\[\e[32;1m\]\$(/bin/ls -1 | /usr/bin/wc -l | /bin/sed 's: ::g') files, \$(/bin/ls -lah | /bin/grep -m 1 total | /bin/sed 's/total //')b\[\e[30;1m\])\n--> \[\e[0m\]"

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
alias alert='notify-send --urgency=low -i "$([ $? = 0 ] && echo terminal || echo error)" "$(history|tail -n1|sed -e '\''s/^\s*[0-9]\+\s*//;s/[;&|]\s*alert$//'\'')"'
# Alias definitions.
# You may want to put all your additions into a separate file like
# ~/.bash_aliases, instead of adding them here directly.
if [ -f ~/.bash_aliases ]; then
    . ~/.bash_aliases
fi
# enable programmable completion features (you don't need to enable
# this, if it's already enabled in /etc/bash.bashrc and /etc/profile
# sources /etc/bash.bashrc).
if [ -f /etc/bash_completion ] && ! shopt -oq posix; then
    . /etc/bash_completion
fi
export http_proxy= #"Page on 168"
if [ -f ~/.kde-bashrc ]; then
    . ~/.kde-bashrc
fi
#------------------------------------------////
# Colors:
#------------------------------------------////
black='\e[0;30m'
blue='\e[0;34m'
green='\e[0;32m'
cyan='\e[0;36m'
red='\e[0;31m'
purple='\e[0;35m'
brown='\e[0;33m'
lightgray='\e[0;37m'
darkgray='\e[1;30m'
lightblue='\e[1;34m'
lightgreen='\e[1;32m'
lightcyan='\e[1;36m'
lightred='\e[1;31m'
lightpurple='\e[1;35m'
yellow='\e[1;33m'
white='\e[1;37m'
nc='\e[0m'
IP_DEVICE='eth0'
#------------------------------------------////
## FUNCTIONS
welcome() {
    #------------------------------------------
    #------WELCOME MESSAGE---------------------
    # customize this first message with a message of your choice.
    # this will display the username, date, time, a calendar, the amount of users, and the up time.
    #clear
    # Gotta love ASCII art with figlet
    figlet "Welcome, " "$USER"
    #toilet "Welcome, " $USER;
    echo -e ""
    cal
    echo -ne "Today is "
    date #date +"Today is %A %D, and it is now %R"
    echo -e ""
    echo -ne "Up time:"
    uptime | awk /'up/'
    echo -en "Local IP Address :"
    /sbin/ifconfig ${IP_DEVICE} | awk /'inet / {print $2}' | sed -e s/addr:/' '/
    echo ""
}
welcome
# get IP adresses
#function my_ip() # get IP adresses
my_ip() {
    MY_IP=$(/sbin/ifconfig ${IP_DEVICE} | awk /'inet addr/ {print $2}')
    MY_ISP=$(/sbin/ifconfig ${IP_DEVICE} | awk "/P-t-P/ { print $3 } " | sed -e s/P-t-P://)
}
# get current host related info
ii() {
    echo -e "\nYou are logged on ${red}$HOST"
    echo -e "\nAdditionnal information:$NC "
    uname -a
    echo -e "\n${red}Users logged on:$NC "
    w -h
    echo -e "\n${red}Current date :$NC "
    date
    echo -e "\n${red}Machine stats :$NC "
    uptime
    echo -e "\n${red}Memory stats :$NC "
    free
    echo -en "\n${red}Local IP Address :$NC"
    /sbin/ifconfig ${IP_DEVICE} | awk /'inet / {print $2}' | sed -e s/addr:/' '/
    echo
}
# Easy extract
extract() {
    if [ -f "$1" ]; then
        case $1 in
        *.tar.bz2) tar xvjf "$1" ;;
        *.tar.gz) tar xvzf "$1" ;;
        *.bz2) bunzip2 "$1" ;;
        *.rar) rar x "$1" ;;
        *.gz) gunzip "$1" ;;
        *.tar) tar xvf "$1" ;;
        *.tbz2) tar xvjf "$1" ;;
        *.tgz) tar xvzf "$1" ;;
        *.zip) unzip "$1" ;;
        *.Z) uncompress "$1" ;;
        *.7z) 7z x "$1" ;;
        *) echo "don't know how to extract '$1'..." ;;
        esac
    else
        echo "'$1' is not a valid file!"
    fi
}
upinfo() {
    echo -ne "${green}$HOSTNAME ${red}uptime is ${cyan} \t "
    uptime | awk /'up/ {print $3,$4,$5,$6,$7,$8,$9,$10}'
}
# Makes directory then moves into it
#function mkcdr {
mkcdr() {
    mkdir -p -v "$1"
    cd "$1" || exit
}
alias reload='source ~/.bashrc'
alias biggest='BLOCKSIZE=1048576; du -x | sort -nr | head -10'
## App-specific
alias wget='wget -c'
alias trash='mv -t ~/.local/share/Trash/files'
#show most popular commands
alias top-commands='history | awk "{print $2}" | awk "{print $1}" |sort|uniq -c | sort -rn | head -10'
alias ps-aux='ps axo user:20,pid,pcpu,pmem,vsz,rss,tty,stat,start,time,comm'

# kill all by name https://stackoverflow.com/a/30515012
killAllByName() {
    ps -ef | grep "$1" | grep -v grep | awk '{print $2}' | xargs -r kill -9
}

# SSH
. "$HOME"/.ssh-agent.sh

# Docker helper methods\
alias docker-cleanup='docker container prune -f; docker image prune -f; docker rmi $(docker images --quiet --filter "dangling=true"); docker volume prune -f ; docker system prune -f;'
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"                   # This loads nvm
[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion" # This loads nvm bash_completion
# de-dupe PATH
PATH="$(perl -e 'print join(":", grep { not $seen{$_}++ } split(/:/, $ENV{PATH}))')"
