source ~/.bash_profile
export REACT_EDITOR=code
export JAVA_HOME=/Library/Java/JavaVirtualMachines/zulu-17.jdk/Contents/Home

alias reload="source ~/.zshrc"

export ANDROID_HOME=$HOME/Library/Android/sdk
export PATH=$PATH:$ANDROID_HOME/emulator
export PATH=$PATH:$ANDROID_HOME/build-tools
export PATH=$PATH:$ANDROID_HOME/platform-tools
export PATH="/opt/homebrew/opt/ruby/bin:$PATH"

export PATH="$PATH:/Users/`whoami`/.local/bin"
export PATH="/opt/homebrew/opt/python@3/libexec/bin:$PATH"
# # pnpm
# export PNPM_HOME="/Users/`whoami`/Library/pnpm"
# case ":$PATH:" in
#   *":$PNPM_HOME:"*) ;;
#   *) export PATH="$PNPM_HOME:$PATH" ;;
# esac
# # pnpm end
