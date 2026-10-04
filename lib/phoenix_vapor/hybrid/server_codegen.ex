defmodule PhoenixVapor.Hybrid.ServerCodegen do
  @moduledoc """
  Generates Elixir code (AST) for the server side of a hybrid component.

  Produces:
  - `render/1` — produces `%Rendered{}` with server slots + props payload
  - `handle_event/3` — no-op fallbacks for server actions, when the module
    defines no `handle_event/3` of its own
  """

  @doc """
  Generate `render/1`, and `replay_render/1` for a session replayer.

  The rendered output includes:
  - All slots evaluated for the initial/full render (SEO, first paint)
  - A `data-pv-props` attribute with JSON-encoded client-consumed props
  - Change tracking that skips client-owned slots when only client props changed

  ## Options

    * `:values` — the refs' initial values and the computeds of only those,
      by atom, the same on every render
    * `:constant` and `:computeds` — the computeds that read only refs, and
      those that read props, compiled and ordered, from
      `PhoenixVapor.Hybrid.Computeds.compile/1`
    * `:component` — the component's name, for its wrapper element
  """
  def gen_render(split, classification, opts \\ []) do
    spec = %{
      split: split,
      client_props: classification.client_props,
      refs: for({name, {:client_ref, _init}} <- classification.bindings, do: name),
      values: Keyword.get(opts, :values, %{}),
      constant: Keyword.get(opts, :constant, []),
      computeds: Keyword.get(opts, :computeds, []),
      component: opts[:component]
    }

    quote do
      defp __pv_hybrid__, do: unquote(Macro.escape(spec))

      def render(var!(assigns)),
        do: PhoenixVapor.Hybrid.ServerCodegen.build_rendered(__pv_hybrid__(), var!(assigns))

      @doc """
      Renders the component as a session replay shows it: with the refs the
      client reported while recording, and without the client hook, so the
      server's render is what's shown at each step.
      """
      def replay_render(var!(assigns)),
        do:
          PhoenixVapor.Hybrid.ServerCodegen.build_rendered(
            __pv_hybrid__(),
            var!(assigns),
            :replay
          )
    end
  end

  @doc """
  Build the `%Phoenix.LiveView.Rendered{}` struct at runtime.

  The component renders inside a wrapper whose `data-pv-props` attribute
  carries the client props as JSON. The wrapper has `phx-update="ignore"` when
  a client component owns its children: LiveView still merges its `data-*`
  attributes, and the hook's `updated/0` passes the new props to the client.
  The props are a dynamic of the wrapper, so a prop change sends only the new
  JSON instead of new statics.

  Refs the client reported while the session was recorded, in the
  `:__pv_refs__` assign, take the place of their initial values. In `:replay`
  mode the wrapper has no hook and isn't ignored, so the server's render shows.
  """
  def build_rendered(spec, assigns, mode \\ :live) do
    {values, computeds} = with_recorded_refs(spec, assigns)

    full_assigns =
      assigns
      |> seed_ref_values(values)
      |> seed_props_alias(spec.client_props)
      |> eval_computeds(computeds, values)

    # The wrapper div is the root tag; the component itself may render text,
    # comments, or several elements.
    inner = %{
      PhoenixVapor.Renderer.to_rendered(spec.split, full_assigns)
      | root: false
    }

    static = wrapper_statics(spec.component, mode)

    %Phoenix.LiveView.Rendered{
      static: static,
      dynamic: fn track_changes? ->
        props =
          if track_changes? and not client_props_changed?(assigns, spec.client_props) do
            nil
          else
            assigns
            |> encode_client_props(spec.client_props)
            |> Phoenix.HTML.html_escape()
            |> Phoenix.HTML.safe_to_string()
          end

        [props, inner]
      end,
      fingerprint: :erlang.phash2({__MODULE__, static}),
      root: true
    }
  end

  # The client's reported refs replace their initial values, so the computeds
  # of only refs are evaluated again too. Only declared refs are taken.
  defp with_recorded_refs(spec, %{__pv_refs__: recorded}) when map_size(recorded) > 0 do
    refs =
      for name <- spec.refs, Map.has_key?(recorded, name), into: %{} do
        {PhoenixVapor.Renderer.Names.existing(name), recorded[name]}
      end

    {Map.merge(spec.values, refs), spec.constant ++ spec.computeds}
  end

  defp with_recorded_refs(spec, _assigns), do: {spec.values, spec.computeds}

  defp wrapper_statics(nil, _mode), do: [~s(<div data-pv data-pv-props="), ~s(">), "</div>"]

  defp wrapper_statics(component_name, :replay) do
    [
      ~s(<div id="pv-#{component_name}" data-pv data-pv-props="),
      ~s(" data-pv-client="#{component_name}">),
      "</div>"
    ]
  end

  defp wrapper_statics(component_name, :live) do
    [
      ~s(<div id="pv-#{component_name}" data-pv data-pv-props="),
      ~s(" phx-hook="PhoenixVaporHybrid" phx-update="ignore" data-pv-client="#{component_name}">),
      "</div>"
    ]
  end

  defp client_props_changed?(%{__changed__: changed}, client_props) when is_map(changed) do
    Enum.any?(client_props, fn prop ->
      Map.has_key?(changed, prop) or
        Enum.any?(Map.keys(changed), &(is_atom(&1) and Atom.to_string(&1) == prop))
    end)
  end

  defp client_props_changed?(_assigns, _client_props), do: true

  defp seed_props_alias(assigns, client_props) do
    props_map =
      Enum.reduce(client_props, %{}, fn prop, acc ->
        key = if is_atom(prop), do: prop, else: PhoenixVapor.Renderer.Names.existing(prop)
        value = Map.get(assigns, key, Map.get(assigns, prop))
        Map.put(acc, prop, value)
      end)

    assigns
    |> Map.put(:props, props_map)
    |> Map.put("props", props_map)
  end

  defp seed_ref_values(assigns, ref_values) do
    Enum.reduce(ref_values, assigns, fn {key, value}, acc ->
      acc |> Map.put_new(key, value) |> Map.put_new(to_string(key), value)
    end)
  end

  # Computeds that read props, evaluated as template expressions are; one whose
  # inputs didn't change since the process's last render keeps its value.
  defp eval_computeds(assigns, [], _values), do: assigns

  defp eval_computeds(assigns, computeds, values) do
    {_values, assigns} =
      PhoenixVapor.Hybrid.Computeds.evaluate(computeds, values, assigns, memo: true)

    assigns
  end

  defp encode_client_props(assigns, client_props) do
    client_props
    |> Map.new(fn prop ->
      key = if is_atom(prop), do: prop, else: PhoenixVapor.Renderer.Names.existing(prop)
      value = Map.get(assigns, key, Map.get(assigns, prop))
      {prop, value}
    end)
    |> Jason.encode!()
  end

  @doc """
  Generate `handle_event/3` clauses for server actions.
  """
  def gen_handle_events(classification) do
    action_names =
      classification.handlers
      |> Enum.filter(fn {_name, kind} -> match?({:server_action, _}, kind) end)
      |> Enum.map(fn {name, _} -> name end)

    if action_names == [] do
      []
    else
      [
        quote do
          @__hybrid_server_actions__ unquote(action_names)

          @before_compile PhoenixVapor.Hybrid.ServerCodegen
        end
      ]
    end
  end

  defmacro __before_compile__(env) do
    actions = Module.get_attribute(env.module, :__hybrid_server_actions__, [])
    has_handle_event = Module.defines?(env.module, {:handle_event, 3})

    if has_handle_event do
      []
    else
      for name <- actions do
        quote do
          def handle_event(unquote(name), _params, socket) do
            {:noreply, socket}
          end
        end
      end
    end
  end
end
