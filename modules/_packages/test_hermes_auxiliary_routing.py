"""Exercise Hermes' real auxiliary router with offline provider transports."""

import asyncio
import socket
import tempfile
from types import SimpleNamespace
from unittest.mock import AsyncMock, Mock

import pytest


@pytest.fixture
def router(monkeypatch):
    with tempfile.TemporaryDirectory(prefix="hermes-auxiliary-test-") as state:
        monkeypatch.setenv("HERMES_HOME", state)
        monkeypatch.setattr(socket.socket, "connect", Mock(side_effect=AssertionError("network disabled")))
        monkeypatch.setattr(socket.socket, "connect_ex", Mock(side_effect=AssertionError("network disabled")))
        monkeypatch.setattr(socket, "getaddrinfo", Mock(side_effect=AssertionError("network disabled")))
        from agent import auxiliary_client as ac

        config = {
            "model": {"provider": "openai-codex", "default": "gpt-6.1-sol"},
            "auxiliary": {},
            "fallback_providers": [],
        }
        monkeypatch.setattr("hermes_cli.config.load_config_readonly", lambda: config)
        monkeypatch.setattr(ac, "_read_main_provider", lambda: config["model"]["provider"])
        monkeypatch.setattr(ac, "_read_main_model", lambda: config["model"]["default"])
        monkeypatch.setattr(ac, "_get_auxiliary_task_config", lambda task: config["auxiliary"].get(task, {}))
        monkeypatch.setattr(ac, "_is_provider_unhealthy", lambda *args: False)
        monkeypatch.setattr(ac, "_mark_provider_unhealthy", lambda *args, **kwargs: None)
        monkeypatch.setattr(ac, "_task_minimum_context_length", lambda task: None)
        monkeypatch.setattr(ac, "_resolve_provider_vision_default", lambda provider: None)
        monkeypatch.setattr(ac, "_main_model_supports_vision", lambda *args: True)
        monkeypatch.setattr(ac, "load_pool", lambda *args, **kwargs: None)
        monkeypatch.setattr(ac, "_refresh_provider_credentials", lambda *args: False)
        monkeypatch.setattr(ac, "_build_call_kwargs", lambda provider, model, messages, **kwargs: {
            "model": model, "messages": messages,
        })
        monkeypatch.setattr(ac, "_get_task_extra_body", lambda task: {})
        monkeypatch.setattr(ac, "_retry_same_provider_sync", lambda **kwargs: None)
        monkeypatch.setattr(ac, "_retry_same_provider_async", AsyncMock(return_value=None))
        monkeypatch.setattr(ac, "_stale_base_url_warned", True)
        ac._client_cache.clear()

        transport = Mock(return_value=(None, None))
        original_resolve = ac.resolve_provider_client

        def resolve(provider, *args, **kwargs):
            if provider in {"auto", "main", ""}:
                return original_resolve(provider, *args, **kwargs)
            return transport(provider, *args, **kwargs)

        def to_async(candidate, model, **kwargs):
            create = candidate.chat.completions.create
            if isinstance(create, AsyncMock):
                return candidate, model
            return SimpleNamespace(
                base_url=candidate.base_url,
                chat=SimpleNamespace(completions=SimpleNamespace(create=AsyncMock(side_effect=create))),
            ), model

        monkeypatch.setattr(ac, "resolve_provider_client", resolve)
        monkeypatch.setattr(ac, "_to_async_client", to_async)
        discovery = Mock(return_value=(client("unselected response"), "paid-default"))
        monkeypatch.setattr(ac, "_get_provider_chain", lambda: [("openrouter", discovery)])
        monkeypatch.setattr(ac, "_resolve_strict_vision_backend", discovery)
        yield ac, config, transport, discovery
        ac._client_cache.clear()


def client(text=None, error=None, asynchronous=False):
    response = SimpleNamespace(choices=[SimpleNamespace(
        message=SimpleNamespace(content=text, tool_calls=None), finish_reason="stop",
    )])
    create = (AsyncMock if asynchronous else Mock)(return_value=response, side_effect=error)
    return SimpleNamespace(
        base_url="https://test.invalid/v1", api_key="offline-test-only",
        chat=SimpleNamespace(completions=SimpleNamespace(create=create)),
    )


def invoke(ac, task="compression", asynchronous=False, **kwargs):
    messages = [{"role": "user", "content": "offline routing test"}]
    if asynchronous:
        return asyncio.run(ac.async_call_llm(task=task, messages=messages, **kwargs))
    return ac.call_llm(task=task, messages=messages, **kwargs)


@pytest.mark.parametrize("task", ["compression", "title_generation", "approval", "vision"])
@pytest.mark.parametrize("asynchronous", [False, True])
def test_unavailable_selected_main_never_uses_discovery(router, task, asynchronous):
    ac, config, transport, discovery = router
    with pytest.raises(RuntimeError, match="No LLM provider"):
        invoke(ac, task=task, asynchronous=asynchronous)
    discovery.assert_not_called()


@pytest.mark.parametrize("provider,model", [
    ("nous", "meituan/longcat-2.0:free"),
    ("opencode-free", "space-bunny-free"),
])
def test_unavailable_main_uses_configured_free_fallback(router, provider, model):
    ac, config, transport, discovery = router
    config["fallback_providers"] = [{"provider": provider, "model": model}]
    fallback = client("configured fallback")
    transport.side_effect = lambda selected, model=None, *args, **kwargs: (
        (fallback, model) if selected == provider else (None, None)
    )
    response = invoke(ac)
    assert response.choices[0].message.content == "configured fallback"
    assert fallback.chat.completions.create.call_args.kwargs["model"] == model
    discovery.assert_not_called()


@pytest.mark.parametrize("asynchronous", [False, True])
@pytest.mark.parametrize("status", [401, 402, 429, None])
@pytest.mark.parametrize("persisted_provider", ["openai-codex", "auto"])
def test_failed_live_main_never_uses_discovery(router, monkeypatch, asynchronous, status, persisted_provider):
    ac, config, transport, discovery = router
    config["model"]["provider"] = persisted_provider
    error = RuntimeError("offline provider failure") if status else ConnectionError("offline provider failure")
    error.status_code = status
    primary = client(error=error, asynchronous=asynchronous)
    monkeypatch.setattr(ac, "_get_cached_client", lambda *args, **kwargs: (primary, "gpt-6.1-sol"))
    with pytest.raises((RuntimeError, ConnectionError), match="offline provider failure"):
        invoke(ac, asynchronous=asynchronous, main_runtime={
            "provider": "openai-codex", "model": "gpt-6.1-sol",
        })
    discovery.assert_not_called()


@pytest.mark.parametrize("asynchronous", [False, True])
def test_rate_limit_uses_configured_free_fallback(router, monkeypatch, asynchronous):
    ac, config, transport, discovery = router
    config["fallback_providers"] = [{"provider": "nous", "model": "meituan/longcat-2.0:free"}]
    error = RuntimeError("offline provider failure")
    error.status_code = 429
    primary = client(error=error, asynchronous=asynchronous)
    fallback = client("configured fallback", asynchronous=asynchronous)
    monkeypatch.setattr(ac, "_get_cached_client", lambda *args, **kwargs: (primary, "gpt-6.1-sol"))
    transport.return_value = (fallback, "meituan/longcat-2.0:free")
    monkeypatch.setattr(ac, "_to_async_client", lambda candidate, model, **kwargs: (candidate, model))
    response = invoke(ac, asynchronous=asynchronous)
    assert response.choices[0].message.content == "configured fallback"
    assert fallback.chat.completions.create.call_args.kwargs["model"] == "meituan/longcat-2.0:free"
    discovery.assert_not_called()


@pytest.mark.parametrize("asynchronous", [False, True])
def test_explicit_vision_provider_failure_does_not_widen_to_auto(router, asynchronous):
    ac, config, transport, discovery = router
    config["model"]["provider"] = "auto"
    config["auxiliary"]["vision"] = {"provider": "nvidia", "model": "chosen-vision-model"}
    with pytest.raises(RuntimeError, match="No LLM provider"):
        invoke(ac, task="vision", asynchronous=asynchronous)
    discovery.assert_not_called()


def test_vision_on_free_nous_main_preserves_selected_model(router):
    ac, config, transport, discovery = router
    config["model"] = {"provider": "nous", "default": "meituan/longcat-2.0:free"}
    selected = client("selected model")
    transport.return_value = (selected, "meituan/longcat-2.0:free")
    response = invoke(ac, task="vision")
    assert response.choices[0].message.content == "selected model"
    assert selected.chat.completions.create.call_args.kwargs["model"] == "meituan/longcat-2.0:free"
    discovery.assert_not_called()


def test_vision_can_use_configured_free_fallback(router):
    ac, config, transport, discovery = router
    config["fallback_providers"] = [{"provider": "nous", "model": "meituan/longcat-2.0:free"}]
    fallback = client("configured vision fallback")
    transport.side_effect = lambda provider, model=None, *args, **kwargs: (
        (fallback, model) if provider == "nous" else (None, None)
    )
    response = invoke(ac, task="vision")
    assert response.choices[0].message.content == "configured vision fallback"
    discovery.assert_not_called()


@pytest.mark.parametrize("task", ["compression", "vision"])
def test_discovery_remains_available_without_selected_main(router, task):
    ac, config, transport, discovery = router
    config["model"]["provider"] = "auto"
    response = invoke(ac, task=task)
    assert response.choices[0].message.content == "unselected response"
    discovery.assert_called()


@pytest.mark.parametrize("task", ["compression", "vision"])
def test_explicit_auxiliary_model_is_honored(router, task):
    ac, config, transport, discovery = router
    config["auxiliary"][task] = {"provider": "nvidia", "model": "explicit-paid-model"}
    selected = client("explicit override")
    transport.return_value = (selected, "explicit-paid-model")
    response = invoke(ac, task=task)
    assert response.choices[0].message.content == "explicit override"
    assert selected.chat.completions.create.call_args.kwargs["model"] == "explicit-paid-model"
    discovery.assert_not_called()


def test_task_fallback_precedes_main_fallback(router):
    ac, config, transport, discovery = router
    config["auxiliary"]["compression"] = {"fallback_chain": [
        {"provider": "opencode-free", "model": "space-bunny-free"},
    ]}
    config["fallback_providers"] = [{"provider": "nous", "model": "meituan/longcat-2.0:free"}]
    fallback = client("task fallback")
    transport.side_effect = lambda provider, model=None, *args, **kwargs: (
        (fallback, model) if provider != "openai-codex" else (None, None)
    )
    response = invoke(ac)
    assert response.choices[0].message.content == "task fallback"
    assert fallback.chat.completions.create.call_args.kwargs["model"] == "space-bunny-free"
    discovery.assert_not_called()


@pytest.mark.parametrize("asynchronous", [False, True])
def test_stale_configured_fallback_never_uses_discovery(router, monkeypatch, asynchronous):
    ac, config, transport, discovery = router
    config["fallback_providers"] = [{"provider": "nous", "model": "meituan/longcat-2.0:free"}]
    primary_error = RuntimeError("offline primary failure")
    primary_error.status_code = 429
    primary = client(error=primary_error, asynchronous=asynchronous)
    stale_error = RuntimeError("offline stale fallback")
    stale_error.status_code = 401
    fallback = client(error=stale_error, asynchronous=asynchronous)
    monkeypatch.setattr(ac, "_get_cached_client", lambda *args, **kwargs: (primary, "gpt-6.1-sol"))
    transport.return_value = (fallback, "meituan/longcat-2.0:free")
    with pytest.raises(RuntimeError, match="offline primary failure"):
        invoke(ac, asynchronous=asynchronous)
    assert fallback.chat.completions.create.called
    discovery.assert_not_called()


@pytest.mark.parametrize("asynchronous", [False, True])
def test_explicit_auxiliary_stale_fallback_never_uses_discovery(router, monkeypatch, asynchronous):
    ac, config, transport, discovery = router
    config["model"]["provider"] = "auto"
    config["auxiliary"]["compression"] = {
        "provider": "nvidia", "model": "explicit-model",
        "fallback_chain": [{"provider": "nous", "model": "meituan/longcat-2.0:free"}],
    }
    primary_error = RuntimeError("offline primary failure")
    primary_error.status_code = 429
    primary = client(error=primary_error, asynchronous=asynchronous)
    stale_error = RuntimeError("offline stale fallback")
    stale_error.status_code = 401
    fallback = client(error=stale_error, asynchronous=asynchronous)
    monkeypatch.setattr(ac, "_get_cached_client", lambda *args, **kwargs: (primary, "explicit-model"))
    transport.return_value = (fallback, "meituan/longcat-2.0:free")
    with pytest.raises(RuntimeError, match="offline primary failure"):
        invoke(ac, asynchronous=asynchronous)
    assert fallback.chat.completions.create.call_count == 1
    discovery.assert_not_called()
