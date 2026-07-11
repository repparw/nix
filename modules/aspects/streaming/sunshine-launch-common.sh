# shellcheck shell=bash

sunshine_prepare_launch() {
    log_name="$1"
    exec >> "/tmp/${log_name}-sunshine.log" 2>&1

    while IFS='=' read -r key value; do
        case "$key" in
            NIRI_SOCKET|WAYLAND_DISPLAY|DISPLAY|XDG_RUNTIME_DIR)
                export "$key=$value"
                ;;
        esac
    done < <(systemctl --user show-environment)

    if [ -z "${NIRI_SOCKET:-}" ]; then
        echo "WARNING: NIRI_SOCKET not found in systemd user environment"
    fi
    if [ -z "${WAYLAND_DISPLAY:-}" ]; then
        echo "WARNING: WAYLAND_DISPLAY not set, gamescope may fail"
    fi

    state_dir="${XDG_RUNTIME_DIR:-/tmp}/sunshine-stream"
    mkdir -p "$state_dir"
    date +%s > "$state_dir/managed-app-started"

    graphical_session="$(loginctl --json=short 2>/dev/null | jq -r '[.[] | select(.seat != null and .seat != "-")] | first | .session' || true)"
    if [ -n "$graphical_session" ] && [ "$graphical_session" != "null" ]; then
        loginctl unlock-session "$graphical_session"
    fi
}
