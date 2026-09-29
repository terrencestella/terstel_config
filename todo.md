# TODO

## zsh opruimen
- [ ] nvm wordt dubbel geladen: staat in `~/.zprofile` én in `zshrc`. Weghalen uit `.zprofile`.
- [ ] `~/.zprofile`: oude PATH-regel voor Python 3.13 (`/Library/Frameworks/Python.framework/Versions/3.13/bin`) weghalen als die Python niet meer gebruikt wordt (nu uv).
- [ ] `~/.zprofile` staat niet in dotfiles: toevoegen (symlinken zoals `zshrc`) of leegmaken.
- [ ] Server: fzf-tab clonen als je het daar ook wilt: `git clone https://github.com/Aloxaf/fzf-tab ~/.oh-my-zsh/custom/plugins/fzf-tab`
