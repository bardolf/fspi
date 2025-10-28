#!/usr/bin/env bash
# utils.sh — pomocné funkce pro idempotentní instalaci
set -euo pipefail

# Ujisti se, že logging.sh je načtený
if ! declare -F log_info >/dev/null 2>&1; then
    echo "ERROR: logging.sh must be sourced before utils.sh" >&2
    exit 1
fi

ensure_sudo_nopasswd() {
    local user="${1:-$USER}"
    local file="/etc/sudoers.d/${user}"
    local entry="${user} ALL=(ALL) NOPASSWD: ALL"

    # Zkontroluj, jestli už soubor existuje a obsahuje správný záznam
    if [[ -f "$file" ]] && sudo grep -Fxq "$entry" "$file"; then
        log_debug "Sudoers entry for $user already exists."
        return
    fi

    log_info "Adding NOPASSWD sudoers entry for user: $user"
    echo "$entry" | sudo tee "$file" >/dev/null
    sudo chmod 440 "$file"
}



# --- Obecné pomocné funkce ---

check_command() {
    command -v "$1" >/dev/null 2>&1
}

ensure_command() {
    if ! check_command "$1"; then
        log_error "Missing required command: $1"
        exit 1
    fi
}

run_sudo() {
    if [[ $EUID -ne 0 ]]; then
        sudo "$@"
    else
        "$@"
    fi
}

# --- Instalace balíčků ---

ensure_package() {
    local pkg="$1"
    if ! rpm -q "$pkg" &>/dev/null; then
        log_info "Installing package: $pkg"
        run_sudo dnf install -y "$pkg"
    else
        log_debug "Package already installed: $pkg"
    fi
}

ensure_repo() {
    local name="$1"
    local url="$2"
    if ! dnf repolist --enabled | grep -q "$name"; then
        log_info "Adding repository: $name"
        run_sudo dnf config-manager --add-repo "$url"
    else
        log_debug "Repository already present: $name"
    fi
}

# --- Souborové operace ---

ensure_symlink() {
    local target="$1" dest="$2"
    if [[ -L "$dest" && "$(readlink "$dest")" == "$target" ]]; then
        log_debug "Symlink already correct: $dest -> $target"
    else
        log_info "Creating symlink: $dest -> $target"
        mkdir -p "$(dirname "$dest")"
        ln -sf "$target" "$dest"
    fi
}

ensure_file_copy() {
    local src="$1" dest="$2"
    if cmp -s "$src" "$dest" 2>/dev/null; then
        log_debug "File already up-to-date: $dest"
    else
        log_info "Copying file: $src -> $dest"
        mkdir -p "$(dirname "$dest")"
        cp -f "$src" "$dest"
    fi
}

# --- Uživatel / sudoers ---

ensure_user_in_group() {
    local user="$1" group="$2"
    if id -nG "$user" | grep -qw "$group"; then
        log_debug "User $user already in group $group"
    else
        log_info "Adding $user to group $group"
        run_sudo usermod -aG "$group" "$user"
    fi
}

ensure_sudoers_entry() {
    local user="$1" entry="$2"
    local file="/etc/sudoers.d/$user"
    if [[ ! -f "$file" ]] || ! grep -Fxq "$entry" "$file"; then
        log_info "Adding sudoers entry for $user"
        echo "$entry" | run_sudo tee -a "$file" >/dev/null
        run_sudo chmod 440 "$file"
    else
        log_debug "Sudoers entry already present for $user"
    fi
}

# --- Utility ---
pause_if_needed() {
    if [[ -n "${INTERACTIVE:-}" ]]; then
        read -rp "Press Enter to continue..."
    fi
}
