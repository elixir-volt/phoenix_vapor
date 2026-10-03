defmodule PhoenixVapor.Hybrid.ServerCodegen do
  @moduledoc """
  Generates Elixir code (AST) for the server side of a hybrid component.

  Produces:
  - `render/1` — produces `%Rendered{}` with server slots + props payload
  - `handle_event/3` — no-op fallbacks for server actions, when the module
    defines no `handle_event/3` of its own
  """

  alias PhoenixVapor.Hybrid.Classifier

  @doc """
  Generate all server-side function ASTs for a hybrid component.

  Returns a list of quoted expressions to be injected into the LiveView module.
  """
  @spec generate(
          split :: map(),
          classification :: Classifier.classification(),
          opts :: keyword()
        ) :: [Macro.t()]
  def generate(split, classification, opts \\ []) do
    props = Keyword.get(opts, :props, [])

    [
      gen_render(split, classification, props),
      gen_handle_events(classification)
    ]
    |> List.flatten()
  end

  @doc """
  Generate the `render/1` function.

  The rendered output includes:
  - All slots evaluated for the initial/full render (SEO, first paint)
  - A `data-pv-props` attribute with JSON-encoded client-consumed props
  - Change tracking that skips client-owned slots when only client props changed
  """
  def gen_render(split, classification, _props, computeds \\ %{}, component_name \\ nil) do
    escaped_split = Macro.escape(split)
    client_props = Macro.escape(classification.client_props)

    # Ref initializers don't depend on assigns, so evaluate them once here.
    ref_values =
      classification
      |> extract_ref_defaults()
      |> PhoenixVapor.ScriptSetup.eval_initial_state()

    escaped_ref_values = Macro.escape(ref_values)

    computed_exprs = extract_computed_exprs(classification, computeds)
    escaped_computed_exprs = Macro.escape(computed_exprs)

    escaped_component_name = Macro.escape(component_name)

    quote do
      def render(var!(assigns)) do
        PhoenixVapor.Hybrid.ServerCodegen.build_rendered(
          unquote(escaped_split),
          var!(assigns),
          unquote(client_props),
          unquote(escaped_ref_values),
          unquote(escaped_computed_exprs),
          unquote(escaped_component_name)
        )
      end
    end
  end

  defp extract_ref_defaults(classification) do
    classification.bindings
    |> Enum.flat_map(fn
      {name, {:client_ref, init_expr}} -> [{name, init_expr}]
      _ -> []
    end)
    |> Map.new()
  end

  defp extract_computed_exprs(classification, computeds) do
    computed_names =
      classification.bindings
      |> Enum.flat_map(fn
        {name, {:mixed_computed, _, _}} -> [name]
        {name, :client_computed} -> [name]
        _ -> []
      end)
      |> MapSet.new()

    computeds
    |> Enum.filter(fn {name, _} -> MapSet.member?(computed_names, name) end)
    |> Map.new()
  end

  @doc """
  Build the `%Phoenix.LiveView.Rendered{}` struct at runtime.

  The component renders inside a wrapper whose `data-pv-props` attribute
  carries the client props as JSON. The wrapper has `phx-update="ignore"` when
  a client component owns its children: LiveView still merges its `data-*`
  attributes, and the hook's `updated/0` passes the new props to the client.
  The props are a dynamic of the wrapper, so a prop change sends only the new
  JSON instead of new statics.
  """
  def build_rendered(
        split,
        assigns,
        client_props,
        ref_values,
        computed_exprs,
        component_name \\ nil
      ) do
    full_assigns =
      assigns
      |> seed_ref_values(ref_values)
      |> seed_props_alias(client_props)
      |> eval_computed_defaults(computed_exprs, ref_values)

    # The wrapper div is the root tag; the component itself may render text,
    # comments, or several elements.
    inner = %{
      PhoenixVapor.Renderer.to_rendered(split, full_assigns)
      | root: false
    }

    static = wrapper_statics(component_name)

    %Phoenix.LiveView.Rendered{
      static: static,
      dynamic: fn track_changes? ->
        props =
          if track_changes? and not client_props_changed?(assigns, client_props) do
            nil
          else
            assigns
            |> encode_client_props(client_props)
            |> Phoenix.HTML.html_escape()
            |> Phoenix.HTML.safe_to_string()
          end

        [props, inner]
      end,
      fingerprint: :erlang.phash2({__MODULE__, static}),
      root: true
    }
  end

  defp wrapper_statics(nil), do: [~s(<div data-pv data-pv-props="), ~s(">), "</div>"]

  defp wrapper_statics(component_name) do
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
        key = if is_atom(prop), do: prop, else: PhoenixVapor.Names.existing(prop)
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

  defp eval_computed_defaults(assigns, computed_exprs, ref_values) do
    if computed_exprs == %{} do
      assigns
    else
      eval_computeds_via_quickbeam(assigns, computed_exprs, ref_values)
    end
  end

  defp eval_computeds_via_quickbeam(assigns, computed_exprs, ref_values) do
    if Code.ensure_loaded?(QuickBEAM) do
      ref_names = MapSet.new(Map.keys(ref_values), &to_string/1)

      vars =
        assigns
        |> Enum.filter(fn {k, _} -> is_atom(k) and k not in [:__changed__, :__components__] end)
        |> Map.new(fn {k, v} ->
          name = Atom.to_string(k)

          if MapSet.member?(ref_names, name) do
            {name, %{"value" => v}}
          else
            {name, v}
          end
        end)

      {:ok, rt} = QuickBEAM.start()

      try do
        Enum.reduce(computed_exprs, assigns, fn {name, expr}, acc ->
          case QuickBEAM.eval(rt, wrap_computed_expr(expr), vars: vars) do
            {:ok, value} ->
              Map.put(acc, name, value)

            _ ->
              acc
          end
        end)
      after
        QuickBEAM.stop(rt)
      end
    else
      assigns
    end
  end

  defp wrap_computed_expr(expr) do
    trimmed = String.trim(expr)

    if String.starts_with?(trimmed, "{") do
      "(function() #{trimmed})()"
    else
      "(#{trimmed})"
    end
  end

  defp encode_client_props(assigns, client_props) do
    client_props
    |> Map.new(fn prop ->
      key = if is_atom(prop), do: prop, else: PhoenixVapor.Names.existing(prop)
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
