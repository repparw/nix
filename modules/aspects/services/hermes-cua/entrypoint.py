"""Fleet policy for the pinned CUA backend: remote Linux, no local GUI fallback."""
import ipaddress
import sys
from pathlib import Path
from urllib.parse import urlsplit

sys.path.insert(0, str(Path(__file__).resolve().parent))
from hermes_cua_spaces import CuaSpacesProvider, _shared_client
from hermes_cua_spaces.config import load_settings


def require_remote_linux(space):
    scheme, _, address = space.id.partition(":")
    if scheme == "direct":
        host = urlsplit("//" + address).hostname
        if not host or host == "localhost":
            raise RuntimeError("CUA requires a remote Space")
        try:
            local = ipaddress.ip_address(host).is_loopback
        except ValueError:
            local = False
        if local:
            raise RuntimeError("CUA requires a remote Space")
    elif scheme not in {"relay", "aws", "gcp", "modal"}:
        raise RuntimeError(f"CUA requires a remote Space, got {space.id!r}")
    if space.os != "linux":
        raise RuntimeError("CUA GUI integration requires a Linux Space")


class RemoteClient:
    def attach(self, name):
        space = _shared_client().attach(name)
        # Validate before the upstream environment can run OS-specific setup.
        require_remote_linux(space)
        result = space.run(
            "command -v Xvnc && command -v xfwm4 && command -v xdpyinfo "
            "&& command -v cua-driver && command -v agent-browser "
            "&& ls /opt/playwright/chromium-*/chrome-linux*/chrome >/dev/null",
            timeout_s=30,
        )
        if result.exit_code:
            raise RuntimeError("Remote CUA desktop stack is incomplete; complete enrollment")
        return space


class RemoteLinuxProvider(CuaSpacesProvider):
    @property
    def skip_container_guards(self):
        return False

    def __init__(self, get_config=None):
        super().__init__(get_config=get_config, client=RemoteClient())

    def create_environment(self, **kwargs):
        settings = load_settings(self._get_config)
        if settings.creates or settings.desktop:
            raise RuntimeError("CUA requires an enrolled named Space with a prepared desktop")
        env = super().create_environment(**kwargs)
        original_prefix = env.exec_prefix

        def required_prefix(**options):
            argv = original_prefix(**options)
            if not argv:
                raise RuntimeError("CUA GUI stream unavailable; refusing local fallback")
            return argv

        env.exec_prefix = required_prefix
        env.exec_prefix()
        return env


def register(ctx):
    ctx.register_terminal_environment_provider(
        RemoteLinuxProvider(get_config=getattr(ctx, "get_config", None))
    )
