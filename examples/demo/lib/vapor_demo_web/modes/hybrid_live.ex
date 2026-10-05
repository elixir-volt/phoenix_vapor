defmodule VaporDemoWeb.Modes.HybridLive do
  @moduledoc """
  Hybrid mode at its smallest: the browser owns a ref, the server owns the
  saved value, a model, and a `"use server"` function connects them.
  """

  use VaporDemoWeb, :live_view
  use PhoenixVapor, file: "Tally.vue"

  def mount(_params, _session, socket), do: {:ok, assign(socket, page_title: "Hybrid", saved: 0)}

  def handle_event("save", %{"count" => count}, socket) when is_integer(count) and count >= 0,
    do: {:noreply, assign(socket, saved: count)}

  # Declined: `saved` stays as it is, and the browser's optimistic value
  # goes back to it.
  def handle_event("save", %{"count" => _count}, socket),
    do: {:noreply, put_flash(socket, :error, "A count below zero isn't saved.")}
end
