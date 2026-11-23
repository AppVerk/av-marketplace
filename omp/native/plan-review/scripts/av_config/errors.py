"""Safe consumer-facing configuration errors."""


class ConfigError(ValueError):
    """A safe, consumer-facing configuration or transaction error."""


class InvalidConfig(ConfigError):
    """Invalid configuration or transaction input (CLI usage exit 2)."""


