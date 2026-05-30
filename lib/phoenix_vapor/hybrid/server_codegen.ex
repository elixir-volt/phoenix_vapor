defmodule PhoenixVapor.Hybrid.ServerCodegen do
  @moduledoc """
  Generates Elixir code (AST) for the server side of a hybrid component.

  Produces:
  - `mount/3` — initializes LiveView assigns
  - `render/1` — produces `%Rendered{}` with server slots + props payload
  - `handle_event/3` — one clause per server action
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
  def gen_render(
        split,
        classification,
        _props,
        computeds \\ %{},
        component_name \\ nil,
        client_version \\ nil,
        partial_props \\ false
      ) do
    escaped_split = Macro.escape(split)
    client_props = Macro.escape(classification.client_props)
    slot_owners = classify_slots(split.slots, classification)
    escaped_slot_owners = Macro.escape(slot_owners)

    ref_defaults = extract_ref_defaults(classification)
    escaped_ref_defaults = Macro.escape(ref_defaults)

    computed_exprs = extract_computed_exprs(classification, computeds)
    escaped_computed_exprs = Macro.escape(computed_exprs)

    escaped_component_name = Macro.escape(component_name)
    escaped_client_version = Macro.escape(client_version)

    quote do
      def render(var!(assigns)) do
        PhoenixVapor.Hybrid.ServerCodegen.build_rendered(
          unquote(escaped_split),
          var!(assigns),
          unquote(client_props),
          unquote(escaped_slot_owners),
          unquote(escaped_ref_defaults),
          unquote(escaped_computed_exprs),
          unquote(escaped_component_name),
          unquote(escaped_client_version),
          unquote(partial_props)
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

  Handles:
  - Full initial render (all slots evaluated for first paint)
  - Props JSON payload injected into the statics via a wrapper
  - Change tracking: client-owned slots still re-evaluate when their
    underlying server prop changes (for LV diff correctness)
  """
  def build_rendered(
        split,
        assigns,
        client_props,
        _slot_owners,
        ref_defaults,
        computed_exprs,
        component_name \\ nil,
        client_version \\ nil,
        partial_props \\ false
      ) do
    props_json =
      assigns
      |> PhoenixVapor.Hybrid.Props.build_envelope(client_props,
        component: component_name,
        client_version: client_version,
        partial: partial_props
      )
      |> PhoenixVapor.Hybrid.Props.encode_envelope!()

    escaped_props = props_json |> Phoenix.HTML.html_escape() |> Phoenix.HTML.safe_to_string()

    full_assigns =
      assigns
      |> seed_ref_defaults(ref_defaults)
      |> seed_props_alias(client_props)
      |> eval_computed_defaults(computed_exprs, ref_defaults)

    wrapped_statics = wrap_statics(split.statics, escaped_props, component_name, client_version)
    PhoenixVapor.Renderer.split_to_rendered(wrapped_statics, split.slots, full_assigns)
  end

  defp seed_props_alias(assigns, client_props) do
    props_map =
      Enum.reduce(client_props, %{}, fn prop, acc ->
        key = if is_atom(prop), do: prop, else: String.to_atom(prop)
        value = Map.get(assigns, key, Map.get(assigns, prop))
        Map.put(acc, prop, value)
      end)

    assigns
    |> Map.put(:props, props_map)
    |> Map.put("props", props_map)
  end

  defp seed_ref_defaults(assigns, ref_defaults) do
    ref_values = PhoenixVapor.ScriptSetup.eval_initial_state(ref_defaults)

    Enum.reduce(ref_values, assigns, fn {key, value}, acc ->
      string_key = to_string(key)
      acc |> Map.put_new(key, value) |> Map.put_new(string_key, value)
    end)
  end

  defp eval_computed_defaults(assigns, computed_exprs, ref_defaults) do
    if computed_exprs == %{} do
      assigns
    else
      eval_computeds_via_quickbeam(assigns, computed_exprs, ref_defaults)
    end
  end

  defp eval_computeds_via_quickbeam(assigns, computed_exprs, ref_defaults) do
    if Code.ensure_loaded?(QuickBEAM) do
      {:ok, rt} = QuickBEAM.start()

      ref_names = MapSet.new(Map.keys(ref_defaults))

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

      Enum.reduce(computed_exprs, assigns, fn {name, expr}, acc ->
        js_expr = wrap_computed_expr(expr)

        case QuickBEAM.eval(rt, js_expr, vars: vars) do
          {:ok, value} ->
            atom_key = String.to_atom(name)
            acc |> Map.put(atom_key, value) |> Map.put(name, value)

          _ ->
            acc
        end
      end)
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

  defp wrap_statics([first | rest], escaped_props, component_name, client_version) do
    hook_attrs =
      if component_name do
        version_attr = if client_version, do: ~s( data-pv-version="#{client_version}"), else: ""
        ~s( phx-hook="PhoenixVaporHybrid" data-pv-client="#{component_name}"#{version_attr})
      else
        ""
      end

    hook_id = if component_name, do: ~s( id="pv-#{component_name}"), else: ""

    wrapper_open =
      ~s(<div#{hook_id} data-pv data-pv-props=") <> escaped_props <> ~s("#{hook_attrs}>)

    case rest do
      [] ->
        [wrapper_open <> first <> "</div>"]

      _ ->
        last = List.last(rest)
        middle = rest |> Enum.drop(-1)
        [wrapper_open <> first | middle] ++ [last <> "</div>"]
    end
  end

  defp wrap_statics([], escaped_props, component_name, client_version) do
    hook_attrs =
      if component_name do
        version_attr = if client_version, do: ~s( data-pv-version="#{client_version}"), else: ""
        ~s( phx-hook="PhoenixVaporHybrid" data-pv-client="#{component_name}"#{version_attr})
      else
        ""
      end

    [~s(<div data-pv data-pv-props=") <> escaped_props <> ~s("#{hook_attrs}></div>)]
  end

  @doc """
  Generate `handle_event/3` clauses for server actions.
  """
  def gen_handle_events(classification) do
    action_names =
      classification.handlers
      |> Enum.filter(fn {_name, kind} -> match?({:server_action, _}, kind) end)
      |> Enum.map(fn {name, _} -> name end)

    [
      quote do
        @__hybrid_server_actions__ unquote(action_names)

        @before_compile PhoenixVapor.Hybrid.ServerCodegen
      end
    ]
  end

  defmacro __before_compile__(env) do
    actions = Module.get_attribute(env.module, :__hybrid_server_actions__, [])
    has_handle_event = Module.defines?(env.module, {:handle_event, 3})

    if has_handle_event do
      []
    else
      deferred_event =
        quote do
          def handle_event("pv:deferred", %{"group" => group}, socket) do
            {:noreply, PhoenixVapor.Hybrid.Props.resolve_deferred(socket, group)}
          end
        end

      action_events =
        for name <- actions do
          quote do
            def handle_event(unquote(name), _params, socket) do
              {:noreply, socket}
            end
          end
        end

      [deferred_event | action_events]
    end
  end

  @doc """
  Classify each slot in the Vapor IR as server-owned or client-owned.

  A slot is client-owned if any of its referenced identifiers belong to
  a client ref, client computed, or mixed computed.
  """
  def classify_slots(slots, classification) do
    Enum.map(slots, fn slot ->
      refs = slot_references(slot)

      is_client =
        Enum.any?(refs, fn ref ->
          case Map.get(classification.bindings, ref) do
            {:client_ref, _} -> true
            :client_computed -> true
            {:mixed_computed, _, _} -> true
            _ -> false
          end
        end)

      if is_client, do: :client, else: :server
    end)
  end

  defp slot_references(%{kind: kind, values: values}) when kind in [:set_text, :set_prop] do
    values
    |> Enum.flat_map(fn
      {:static_, _} -> []
      expr when is_binary(expr) -> Classifier.free_variables(expr)
    end)
    |> Enum.uniq()
  end

  defp slot_references(%{kind: kind, value: expr}) when kind in [:set_html, :v_show, :v_model] do
    Classifier.free_variables(expr)
  end

  defp slot_references(%{kind: :if_node, condition: cond_expr}) do
    Classifier.free_variables(cond_expr)
  end

  defp slot_references(%{kind: :for_node, source: source}) do
    Classifier.free_variables(source)
  end

  defp slot_references(%{kind: :create_component, props: props}) do
    props
    |> Enum.flat_map(fn prop ->
      prop.values
      |> Enum.flat_map(fn
        {:static_, _} -> []
        expr when is_binary(expr) -> Classifier.free_variables(expr)
      end)
    end)
    |> Enum.uniq()
  end

  defp slot_references(_), do: []
end
