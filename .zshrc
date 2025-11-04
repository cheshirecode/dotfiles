#!/usr/bin/env zsh

test -e "${HOME}/.iterm2_shell_integration.zsh" && source "${HOME}/.iterm2_shell_integration.zsh"

#   Change Prompt (zsh version)
#   ------------------------------------------------------------
# Enable parameter expansion, command substitution and arithmetic expansion in prompts
setopt PROMPT_SUBST

# Custom prompt with file count and directory size
PROMPT=$'\n%B%f(%F{cyan}%n@%m:%~%f) %f(%F{green}$(ls -1 | wc -l | sed "s: ::g") files, $(ls -lah | grep -m 1 total | sed "s/total //")b%f)%b\n%f--> %f'

#   Set Paths
#   ------------------------------------------------------------
export PATH="$HOME/.local/bin:$PATH"
export PATH="/usr/local/git/bin:/sw/bin/:/usr/local/bin:/usr/local/:/usr/local/sbin:/usr/local/mysql/bin:$PATH"
export PATH="$PATH:/usr/local/bin/"
export PATH="/opt/homebrew/opt/ruby/bin:$PATH"
export PATH="$PATH:/Users/`whoami`/.local/bin"
export PATH="/opt/homebrew/opt/python@3/libexec/bin:$PATH"
export PATH="$PATH:/Applications/Visual Studio Code.app/Contents/Resources/app/bin"

#   Environment Variables
#   ------------------------------------------------------------
export EDITOR=/usr/bin/vi
export BLOCKSIZE=1k
export REACT_EDITOR=code
export JAVA_HOME=/Library/Java/JavaVirtualMachines/zulu-17.jdk/Contents/Home
export NODE_TLS_REJECT_UNAUTHORIZED=0

#   Android SDK
#   ------------------------------------------------------------
export ANDROID_HOME=$HOME/Library/Android/sdk
export PATH=$PATH:$ANDROID_HOME/emulator
export PATH=$PATH:$ANDROID_HOME/build-tools
export PATH=$PATH:$ANDROID_HOME/platform-tools

#   NVM (Node Version Manager) - Homebrew installation
#   ------------------------------------------------------------
export NVM_DIR="$HOME/.nvm"
# Load NVM from Homebrew
[ -s "/opt/homebrew/opt/nvm/nvm.sh" ] && \. "/opt/homebrew/opt/nvm/nvm.sh"
# Load NVM bash completion
[ -s "/opt/homebrew/opt/nvm/etc/bash_completion.d/nvm" ] && \. "/opt/homebrew/opt/nvm/etc/bash_completion.d/nvm"

#   SSH Agent
#   ------------------------------------------------------------
[ -f "$HOME/.ssh-agent.sh" ] && source "$HOME/.ssh-agent.sh"

# # pnpm
# export PNPM_HOME="/Users/`whoami`/Library/pnpm"
# case ":$PATH:" in
#   *":$PNPM_HOME:"*) ;;
#   *) export PATH="$PNPM_HOME:$PATH" ;;
# esac
# # pnpm end

#   -----------------------------
#   MAKE TERMINAL BETTER
#   -----------------------------

alias reload="source ~/.zshrc"
alias cp='cp -iv'
alias mv='mv -iv'
alias mkdir='mkdir -pv'
alias ll='ls -FGlAhp'
alias less='less -FSRXc'
alias cd..='cd ../'
alias ..='cd ../'
alias ...='cd ../../'
alias .3='cd ../../../'
alias .4='cd ../../../../'
alias .5='cd ../../../../../'
alias .6='cd ../../../../../../'
alias edit='code'  # Updated to use VS Code
alias f='open -a Finder ./'
alias ~="cd ~"
alias c='clear'
alias which='type -a'
alias path='echo -e ${PATH//:/\\n}'
alias show_options='setopt'  # zsh equivalent
alias fix_stty='stty sane'
alias cic='setopt NO_CASE_GLOB'  # zsh equivalent for case-insensitive completion

# cd: Always list directory contents upon 'cd'
cd() {
  builtin cd "$@"
  ll
}

# mcd: Makes new Dir and jumps inside
mcd() { mkdir -p "$1" && cd "$1"; }

# trash: Moves a file to the MacOS trash
trash() { command mv "$@" ~/.Trash; }

# ql: Opens any file in MacOS Quicklook Preview
ql() { qlmanage -p "$*" >&/dev/null; }

alias DT='tee ~/Desktop/terminalOut.txt'

#   Full Recursive Directory Listing
#   ------------------------------------------
alias lr='ls -R | grep ":$" | sed -e '\''s/:$//'\'' -e '\''s/[^-][^\/]*\//--/g'\'' -e '\''s/^/   /'\'' -e '\''s/-/|/'\'' | less'

#   mans: Search manpage given in argument '1' for term given in argument '2'
#   ------------------------------------------------------------
mans() {
  man $1 | grep -iC2 --color=always $2 | less
}

#   showa: to remind yourself of an alias
#   ------------------------------------------------------------
showa() { grep --color=always -i -a1 $@ ~/.zshrc | grep -v '^\s*$' | less -FSRXc; }

#   -------------------------------
#   FILE AND FOLDER MANAGEMENT
#   -------------------------------

zipf() { zip -r "$1".zip "$1"; }
alias numFiles='echo $(ls -1 | wc -l)'
alias make1mb='mkfile 1m ./1MB.dat'
alias make5mb='mkfile 5m ./5MB.dat'
alias make10mb='mkfile 10m ./10MB.dat'

#   cdf: 'Cd's to frontmost window of MacOS Finder
#   ------------------------------------------------------
cdf() {
  currFolderPath=$(
    /usr/bin/osascript <<EOT
            tell application "Finder"
                try
            set currFolder to (folder of the front window as alias)
                on error
            set currFolder to (path to desktop folder as alias)
                end try
                POSIX path of currFolder
            end tell
EOT
  )
  echo "cd to \"$currFolderPath\""
  cd "$currFolderPath"
}

#   extract: Extract most know archives with one command
#   ---------------------------------------------------------
extract() {
  if [ -f $1 ]; then
    case $1 in
    *.tar.bz2) tar xjf $1 ;;
    *.tar.gz) tar xzf $1 ;;
    *.bz2) bunzip2 $1 ;;
    *.rar) unrar e $1 ;;
    *.gz) gunzip $1 ;;
    *.tar) tar xf $1 ;;
    *.tbz2) tar xjf $1 ;;
    *.tgz) tar xzf $1 ;;
    *.zip) unzip $1 ;;
    *.Z) uncompress $1 ;;
    *.7z) 7z x $1 ;;
    *) echo "'$1' cannot be extracted via extract()" ;;
    esac
  else
    echo "'$1' is not a valid file"
  fi
}

#   ---------------------------
#   SEARCHING
#   ---------------------------

alias qfind="find . -name "
ff() { /usr/bin/find . -name "$@"; }
ffs() { /usr/bin/find . -name "$@"'*'; }
ffe() { /usr/bin/find . -name '*'"$@"; }

#   spotlight: Search for a file using MacOS Spotlight's metadata
#   -----------------------------------------------------------
spotlight() { mdfind "kMDItemDisplayName == '$@'wc"; }

#   ---------------------------
#   PROCESS MANAGEMENT
#   ---------------------------

findPid() { lsof -t -c "$@"; }

alias memHogsTop='top -l 1 -o rsize | head -20'
alias memHogsPs='ps wwaxm -o pid,stat,vsize,rss,time,command | head -10'
alias cpu_hogs='ps wwaxr -o pid,stat,%cpu,time,command | head -10'
alias topForever='top -l 9999999 -s 10 -o cpu'
alias ttop="top -R -F -s 10 -o rsize"

my_ps() { ps $@ -u $USER -o pid,%cpu,%mem,start,time,bsdtime,command; }

#   ---------------------------
#   NETWORKING
#   ---------------------------

alias myip='curl ip.appspot.com'
alias netCons='lsof -i'
alias flushDNS='dscacheutil -flushcache'
alias lsock='sudo /usr/sbin/lsof -i -P'
alias lsockU='sudo /usr/sbin/lsof -nP | grep UDP'
alias lsockT='sudo /usr/sbin/lsof -nP | grep TCP'
alias ipInfo0='ipconfig getpacket en0'
alias ipInfo1='ipconfig getpacket en1'
alias openPorts='sudo lsof -i | grep LISTEN'
alias showBlocked='sudo ipfw list'

#   ii: display useful host related information
#   -------------------------------------------------------------------
ii() {
  echo -e "\nYou are logged on $HOST"
  echo -e "\nAdditional information: "
  uname -a
  echo -e "\nUsers logged on: "
  w -h
  echo -e "\nCurrent date: "
  date
  echo -e "\nMachine stats: "
  uptime
  echo -e "\nCurrent network location: "
  scselect
  echo -e "\nPublic facing IP Address: "
  myip
  echo
}

#   ---------------------------------------
#   SYSTEMS OPERATIONS & INFORMATION
#   ---------------------------------------

alias mountReadWrite='/sbin/mount -uw /'
alias cleanupDS="find . -type f -name '*.DS_Store' -ls -delete"
alias finderShowHidden='defaults write com.apple.finder ShowAllFiles TRUE'
alias finderHideHidden='defaults write com.apple.finder ShowAllFiles FALSE'
alias cleanupLS="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -kill -r -domain local -domain system -domain user && killall Finder"
alias screensaverDesktop='/System/Library/Frameworks/ScreenSaver.framework/Resources/ScreenSaverEngine.app/Contents/MacOS/ScreenSaverEngine -background'

#   ---------------------------------------
#   WEB DEVELOPMENT
#   ---------------------------------------

alias apacheEdit='sudo edit /etc/httpd/httpd.conf'
alias apacheRestart='sudo apachectl graceful'
alias editHosts='sudo edit /etc/hosts'
alias herr='tail /var/log/httpd/error_log'
alias apacheLogs="less +F /var/log/apache2/error_log"
httpHeaders() { /usr/bin/curl -I -L $@; }
httpDebug() { /usr/bin/curl $@ -o /dev/null -w "dns: %{time_namelookup} connect: %{time_connect} pretransfer: %{time_pretransfer} starttransfer: %{time_starttransfer} total: %{time_total}\n"; }
