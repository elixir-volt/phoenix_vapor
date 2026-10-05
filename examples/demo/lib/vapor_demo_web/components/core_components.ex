defmodule VaporDemoWeb.CoreComponents do
  @moduledoc "The few HEEx components the layout uses: flash messages and icons."

  use Phoenix.Component

  alias Phoenix.LiveView.JS

  @doc "A flash message of `kind`, dismissed on click."
  attr :id, :string, doc: "the optional id of flash container"
  attr :flash, :map, default: %{}, doc: "the map of flash messages to display"
  attr :title, :string, default: nil
  attr :kind, :atom, values: [:info, :error], doc: "used for styling and flash lookup"
  attr :rest, :global, doc: "the arbitrary HTML attributes to add to the flash container"
  slot :inner_block, doc: "the optional inner block that renders the flash message"

  def flash(assigns) do
    assigns = assign_new(assigns, :id, fn -> "flash-#{assigns.kind}" end)

    ~H"""
    <div
      :if={msg = render_slot(@inner_block) || Phoenix.Flash.get(@flash, @kind)}
      id={@id}
      phx-click={JS.push("lv:clear-flash", value: %{key: @kind}) |> hide("##{@id}")}
      role="alert"
      class={[
        "fixed right-4 top-4 z-50 w-80 rounded-lg border px-4 py-3 text-sm shadow-md",
        @kind == :info && "border-emerald-200 bg-emerald-50 text-emerald-900",
        @kind == :error && "border-red-200 bg-red-50 text-red-900"
      ]}
      {@rest}
    >
      <p :if={@title} class="font-semibold">{@title}</p>
      <p>{msg}</p>
    </div>
    """
  end

  @doc "A [Heroicon](https://heroicons.com), such as `hero-arrow-path`."
  attr :name, :string, required: true
  attr :class, :string, default: "size-4"

  def icon(%{name: "hero-" <> _} = assigns) do
    ~H"""
    <span class={[@name, @class]} />
    """
  end

  def show(js \\ %JS{}, selector),
    do:
      JS.show(js,
        to: selector,
        time: 200,
        transition: {"transition-opacity", "opacity-0", "opacity-100"}
      )

  def hide(js \\ %JS{}, selector),
    do:
      JS.hide(js,
        to: selector,
        time: 200,
        transition: {"transition-opacity", "opacity-100", "opacity-0"}
      )
end
