defmodule PhoenixVapor.Hybrid.ServerCodegen do
  @moduledoc false

  # Generates Elixir code (AST) for the server side of a hybrid component.
  #
  # Produces:
  # - `render/1` — produces `%Rendered{}` with server slots + props payload
  # - `handle_event/3` — no-op fallbacks for server actions, when the module
  # defines no `handle_event/3` of its own

  alias PhoenixVapor.Renderer.Names

  @doc """
  Generate `render/1`, and `replay_render/1` for a session replayer.

  The rendered output includes:
  - All slots evaluated for the initial/full render (SEO, first paint)
  - A `data-pv-props` attribute with JSON-encoded client-consumed props
  - Change tracking that skips client-owned slots when only client props changed

  ## Options

    * `:values` — the refs' initial values and the computeds of only those,
      by atom, the same on every render
    * `:constants` — the component's top-level constants, by atom
    * `:constant` and `:computeds` — the computeds that read only refs, and
      those that read props, compiled and ordered, from
      `PhoenixVapor.Hybrid.Computeds.compile/1`
    * `:component` — the component's name, for its wrapper element
    * `:client` — the names bound by composables and other calls only the
      browser runs; a render without their values leaves out what reads them
    * `:recorded` — the client state a replay takes from
      `@phoenix_replay_state`; by default, the refs
  """
  def gen_render(split, classification, opts \\ []) do
    models = Map.get(classification, :models, [])

    spec = %{
      split: split,
      client_props: classification.client_props,
      models: models,
      recorded:
        Keyword.get_lazy(opts, :recorded, fn ->
          for {name, {:client_ref, _init}} <- classification.bindings, do: name
        end),
      values: Keyword.get(opts, :values, %{}),
      constants: Keyword.get(opts, :constants, %{}),
      constant: Keyword.get(opts, :constant, []),
      computeds: Keyword.get(opts, :computeds, []),
      component: opts[:component],
      client: Keyword.get(opts, :client, [])
    }

    # Rendering finds each declared name's atom with `Names.existing/1`,
    # never creating one. An atom made while compiling exists only in the
    # compiling VM; one in the spec is a literal of the compiled module, so it
    # exists wherever the module is loaded, such as a server replaying a
    # recorded composable's value.
    spec = Map.put(spec, :names, declared_names(spec, classification))

    quote do
      defp __pv_hybrid__, do: unquote(Macro.escape(spec))

      def render(var!(assigns)),
        do: PhoenixVapor.Hybrid.ServerCodegen.build_rendered(__pv_hybrid__(), var!(assigns))

      @doc """
      Renders the component as a session replay shows it: with the client
      state reported while recording, from `@phoenix_replay_state`, and
      without the client hook, so the server's render is what's shown. The
      optional callback of `PhoenixReplay.Replay.View`, which renders it in
      full at every step.
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

  In `:replay` mode, for a session replayer, the wrapper has no hook and isn't
  ignored, so the server's render shows, and the client state reported while
  the session was recorded, under the component's state key in the
  `:phoenix_replay_state` assign, takes the place of the refs' initial
  values. A replayer renders every step in full, with `__changed__: nil`.
  """
  def build_rendered(spec, assigns, mode \\ :live) do
    {values, computeds} = refs_for(mode, spec, assigns)

    full_assigns =
      assigns
      |> Map.put(:__absent__, absent(mode, spec, assigns))
      |> seed_ref_values(Map.get(spec, :constants, %{}))
      |> seed_ref_values(values)
      |> seed_props_alias(spec.client_props)
      |> eval_computeds(computeds, models(values, spec, assigns))

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

  defp declared_names(spec, classification) do
    computeds = for {name, _expr} <- spec.constant ++ spec.computeds, do: name

    (Map.keys(classification.bindings) ++ spec.recorded ++ spec.client ++ spec.models ++ computeds)
    |> Enum.uniq()
    |> Enum.map(&Names.atom!/1)
  end

  @doc """
  The key a hybrid component's refs are reported and replayed under:
  `phoenix_vapor:` and its wrapper's id, which the browser's bridge uses too.
  """
  @spec state_key(String.t()) :: String.t()
  def state_key(component), do: "phoenix_vapor:pv-" <> component

  # A replay's recorded refs replace their initial values, so the computeds
  # of only refs are evaluated again too. Only declared refs are taken.
  defp refs_for(:replay, %{component: component} = spec, assigns) when is_binary(component) do
    recorded = get_in(assigns, [Access.key(:phoenix_replay_state, %{}), state_key(component)])

    case recorded do
      %{} = recorded when map_size(recorded) > 0 ->
        refs =
          for name <- spec.recorded, Map.has_key?(recorded, name), into: %{} do
            {PhoenixVapor.Renderer.Names.existing(name), recorded[name]}
          end

        {Map.merge(spec.values, refs), spec.constant ++ spec.computeds}

      _none ->
        {spec.values, spec.computeds}
    end
  end

  defp refs_for(_mode, spec, _assigns), do: {spec.values, spec.computeds}

  # The client state this render doesn't have: a composable's value, which
  # only the browser knows, unless a replay recorded it.
  defp absent(:replay, %{component: component} = spec, assigns) when is_binary(component) do
    recorded = get_in(assigns, [Access.key(:phoenix_replay_state, %{}), state_key(component)])
    spec.client |> Enum.reject(&is_map_key(recorded || %{}, &1)) |> MapSet.new()
  end

  defp absent(_mode, spec, _assigns), do: MapSet.new(spec.client)

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

  # Script setup reads a model as `.value`, as it does a ref, so the
  # computeds see each model's assign among the values they wrap.
  defp models(values, spec, assigns) do
    for model <- Map.get(spec, :models, []),
        key = Names.existing(model),
        Map.has_key?(assigns, key),
        into: values,
        do: {key, Map.fetch!(assigns, key)}
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
