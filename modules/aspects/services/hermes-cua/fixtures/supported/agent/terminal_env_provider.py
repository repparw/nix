class TerminalEnvironmentProvider:
    supports_streams = False

    @property
    def default_cwd(self):
        return None
