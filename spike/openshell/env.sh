# Source me: user-local OpenShell spike environment (no sudo, no systemd, no Docker driver).
# Everything OpenShell writes lives under $OS_ROOT; binaries under $OS_OPT.
export OS_OPT="$HOME/.local/opt/openshell-0.1.8"
export OS_ROOT="$HOME/.local/share/openshell-spike"
export PATH="$OS_OPT/bin:$PATH"
export XDG_CONFIG_HOME="$OS_ROOT/config"
export XDG_STATE_HOME="$OS_ROOT/state"
export OPENSHELL_LOCAL_TLS_DIR="$OS_ROOT/state/openshell/tls"
export OPENSHELL_GATEWAY_CONFIG="$OS_ROOT/gateway.toml"
