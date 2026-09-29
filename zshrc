# --- moet bovenaan: voorkomt alias/functie-conflict bij re-sourcen ---
unalias finder 2>/dev/null
unalias fm 2>/dev/null

# Path to your Oh My Zsh installation.
export ZSH="$HOME/.oh-my-zsh"

# ZSH_THEME="robbyrussell"
zstyle ':omz:update' mode auto      # update automatically without asking

# Which plugins would you like to load?
# Standard plugins can be found in $ZSH/plugins/
# Custom plugins may be added to $ZSH_CUSTOM/plugins/
plugins=(git docker history-substring-search)
# fzf-tab: tab-completion via fzf (git clone https://github.com/Aloxaf/fzf-tab $ZSH/custom/plugins/fzf-tab)
[[ -d "$ZSH/custom/plugins/fzf-tab" ]] && plugins+=(fzf-tab)

source $ZSH/oh-my-zsh.sh

# history: elk commando maar één keer bewaren en tonen
setopt HIST_IGNORE_ALL_DUPS HIST_FIND_NO_DUPS HIST_SAVE_NO_DUPS

# User configuration

if [[ "$(uname)" == "Darwin" ]]; then
  source $(brew --prefix)/share/zsh-autosuggestions/zsh-autosuggestions.zsh
  source $(brew --prefix)/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh
else
  source /usr/share/zsh-autosuggestions/zsh-autosuggestions.zsh
  source /usr/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh
fi
export PATH="$HOME/.local/bin:$HOME/bin:$PATH"

# bun completions
[ -s "$HOME/.bun/_bun" ] && source "$HOME/.bun/_bun"

# bun
export BUN_INSTALL="$HOME/.bun"
export PATH="$BUN_INSTALL/bin:$PATH"

# --- terminal tooling (alleen Mac) ---
if [[ "$(uname)" == "Darwin" ]]; then

  # zoxide als cd
  eval "$(zoxide init zsh --cmd cd)"

  # fzf
  source <(fzf --zsh)
  export FZF_DEFAULT_OPTS="--height 40% --layout=reverse --border"
  export FZF_DEFAULT_COMMAND='fd --type f --hidden --strip-cwd-prefix --exclude .git'
  export FZF_CTRL_T_COMMAND="$FZF_DEFAULT_COMMAND"
  export FZF_CTRL_T_OPTS="--preview 'bat --color=always --style=numbers --line-range=:300 {}'"
  export FZF_ALT_C_COMMAND='fd --type d --hidden --strip-cwd-prefix --exclude .git'
  export FZF_ALT_C_OPTS="--preview 'eza --tree --level=2 --icons --color=always {}'"

  # fzf-tab: menu via fzf, met preview van mappen bij cd/zoxide
  zstyle ':completion:*' menu no
  zstyle ':fzf-tab:complete:cd:*' fzf-preview 'eza -1 --color=always --icons $realpath'
  zstyle ':fzf-tab:complete:__zoxide_z:*' fzf-preview 'eza -1 --color=always --icons $realpath'

  # eza als ls
  alias ls='eza --group-directories-first --icons'
  alias ll='eza -l --git --group-directories-first --icons'
  alias la='eza -la --git --group-directories-first --icons'
  alias lt='eza --tree --level=2 --icons' #***HANDY***

  # bat als cat
  # glow-stijl volgt macOS light/dark modus
  glow_style() { defaults read -g AppleInterfaceStyle >/dev/null 2>&1 && echo dark || echo light; }
  cat() {
    if [ "$#" -eq 1 ] && [[ "$1" == *.md ]]; then
      glow -s "$(glow_style)" "$1"
    else
      bat --paging=never "$@"
    fi
  }
  alias less='bat'
  export BAT_THEME="Catppuccin Mocha"

  # overig
  alias lg='lazygit'

  # yazi
  finder() {
    local tmp="$(mktemp -t yazi-cwd.XXXXXX)"
    yazi "$@" --cwd-file="$tmp"
    if cwd="$(command cat -- "$tmp")" && [ -n "$cwd" ] && [ "$cwd" != "$PWD" ]; then
      builtin cd -- "$cwd"
    fi
    rm -f -- "$tmp"
  }
  alias fm='finder'

  # starship
  eval "$(starship init zsh)"

fi
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"  # This loads nvm
[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"  # This loads nvm bash_completion

# herdr-automatic-rename: live tab naming hook
# (N) = nullglob: geen match (plugin niet geinstalleerd, bv. op de server) geeft geen fout
for _f in $HOME/.config/herdr/plugins/github/herdr-automatic-rename-*/shell/hook.zsh(N); do
  source $_f; break
done
