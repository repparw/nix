import importlib.util
import os
from pathlib import Path
from types import SimpleNamespace
import unittest
from unittest.mock import patch

from hermes_cua_spaces.client import ExecResult
from hermes_cua_spaces.environment import CuaSpaceEnvironment

spec = importlib.util.spec_from_file_location("fleet_cua", Path(os.environ["CUA_PLUGIN"]) / "__init__.py")
policy = importlib.util.module_from_spec(spec)
spec.loader.exec_module(policy)


class PolicyTests(unittest.TestCase):
    def setUp(self):
        self.space = SimpleNamespace(
            id="relay:remote-machine", os="linux", name="hermes-gui",
            run=lambda *args, **kwargs: ExecResult("", 0), home=lambda: "/home/cua",
        )
        self.client = SimpleNamespace(attach=lambda name: self.space)
        self.settings = {"space": "hermes-gui", "desktop": False}
        self.provider = policy.RemoteLinuxProvider(
            get_config=lambda key, default=None: self.settings.get(key, default)
        )
        self.patch_client = patch.object(policy, "_shared_client", return_value=self.client)
        self.patch_client.start()
        self.addCleanup(self.patch_client.stop)
        self.env_patch = patch.dict(os.environ, {}, clear=True)
        self.env_patch.start()
        self.addCleanup(self.env_patch.stop)

    def create(self):
        with patch.object(CuaSpaceEnvironment, "init_session"):
            return self.provider.create_environment(cwd="/home/cua", timeout=30)

    def test_named_space_preserves_approvals_and_streams(self):
        self.assertFalse(self.provider.skip_container_guards)
        with patch("hermes_cua_spaces.streams.stream_argv", return_value=["cua", "sandbox", "exec", "-i", self.space.id, "--"]):
            env = self.create()
            self.assertEqual(env.exec_prefix()[-2:], [self.space.id, "--"])
            self.assertFalse(env._delete_on_cleanup)
            env.cleanup()

    def test_create_and_desktop_install_overrides_are_refused(self):
        for settings in ({"space": "create"}, {"desktop": True}):
            with self.subTest(settings=settings):
                self.settings.update(settings)
                with self.assertRaises(RuntimeError):
                    self.create()
                self.settings = {"space": "hermes-gui", "desktop": False}

    def test_environment_cannot_bypass_approvals_or_enable_create(self):
        with patch.dict(os.environ, {"HERMES_CUA_SPACE": "create"}):
            self.assertFalse(self.provider.skip_container_guards)
            with self.assertRaises(RuntimeError):
                self.create()

    def test_local_or_non_linux_space_is_refused_before_setup(self):
        for ref, system in [("local:hermes-gui", "linux"), ("direct:127.0.0.1:3211", "linux"), ("direct:[::1]:3211", "linux"), ("relay:remote", "windows"), ("relay:remote", "")]:
            with self.subTest(ref=ref, system=system):
                self.space.id, self.space.os = ref, system
                with self.assertRaises(RuntimeError):
                    self.create()

    def test_missing_desktop_is_refused(self):
        self.space.run = lambda *args, **kwargs: ExecResult("missing", 1)
        with self.assertRaisesRegex(RuntimeError, "desktop stack"):
            self.create()

    def test_missing_cli_or_stream_never_falls_back(self):
        with patch("hermes_cua_spaces.streams.stream_argv", return_value=None):
            with self.assertRaisesRegex(RuntimeError, "refusing local fallback"):
                self.create()

    def test_missing_named_space_propagates_without_create(self):
        def missing(name):
            raise RuntimeError("Space not enrolled")
        self.client.attach = missing
        with self.assertRaisesRegex(RuntimeError, "not enrolled"):
            self.create()


if __name__ == "__main__":
    unittest.main()
