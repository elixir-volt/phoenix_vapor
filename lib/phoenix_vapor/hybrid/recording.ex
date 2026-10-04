defmodule PhoenixVapor.Hybrid.Recording do
  @moduledoc false

  # A hybrid component's refs live in the browser, so a session recorder that
  # captures assigns never sees them. While a session is being recorded, the
  # client reports its refs, debounced, as the `__pv_refs` event, and they're
  # kept in one assign, `:__pv_refs__`, which the recorder captures like any
  # other and the server's render applies over the refs' initial values.
  #
  # Whether a session is being recorded is PhoenixReplay's to say, through
  # `PhoenixReplay.recording?/1`. Without it, nothing is reported, and this
  # costs one check when the LiveView mounts.

  import Phoenix.LiveView, only: [attach_hook: 4, connected?: 1, push_event: 3]

  @doc "Starts the client's ref reports when the session is being recorded."
  def on_mount(:default, _params, _session, socket) do
    if connected?(socket) and recording?(socket) do
      {:cont,
       socket
       |> push_event("pv:record", %{})
       |> attach_hook(__MODULE__, :handle_event, &handle_event/3)}
    else
      {:cont, socket}
    end
  end

  defp handle_event("__pv_refs", refs, socket) when is_map(refs),
    do: {:halt, Phoenix.Component.assign(socket, :__pv_refs__, refs)}

  defp handle_event(_event, _params, socket), do: {:cont, socket}

  defp recording?(socket) do
    Code.ensure_loaded?(PhoenixReplay) and function_exported?(PhoenixReplay, :recording?, 1) and
      apply(PhoenixReplay, :recording?, [socket])
  end
end
