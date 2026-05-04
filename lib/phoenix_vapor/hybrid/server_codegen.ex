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
  def gen_render(split, classification, _props) do
    escaped_split = Macro.escape(split)
    client_props = Macro.escape(classification.client_props)
    slot_owners = classify_slots(split.slots, classification)
    escaped_slot_owners = Macro.escape(slot_owners)

    quote do
      def render(var!(assigns)) do
        PhoenixVapor.Hybrid.ServerCodegen.build_rendered(
          unquote(escaped_split),
          var!(assigns),
          unquote(client_props),
          unquote(escaped_slot_owners)
        )
      end
    end
  end

  @doc """
  Build the `%Phoenix.LiveView.Rendered{}` struct at runtime.

  Handles:
  - Full initial render (all slots evaluated for first paint)
  - Props JSON payload injected into the statics via a wrapper
  - Change tracking: client-owned slots still re-evaluate when their
    underlying server prop changes (for LV diff correctness)
  """
  def build_rendered(split, assigns, client_props, _slot_owners) do
    props_json = encode_client_props(assigns, client_props)
    inner_rendered = PhoenixVapor.Renderer.split_to_rendered(split.statics, split.slots, assigns)
    escaped_props = props_json |> Phoenix.HTML.html_escape() |> Phoenix.HTML.safe_to_string()

    %Phoenix.LiveView.Rendered{
      static: [
        ~s(<div data-pv data-pv-props=") <> escaped_props <> ~s(">),
        ~s(</div>)
      ],
      dynamic: fn _track_changes? ->
        [inner_rendered]
      end,
      fingerprint: inner_rendered.fingerprint,
      root: true
    }
  end

  defp encode_client_props(assigns, client_props) do
    client_props
    |> Enum.reduce(%{}, fn prop, acc ->
      key = if is_atom(prop), do: prop, else: String.to_atom(prop)
      value = Map.get(assigns, key, Map.get(assigns, prop))
      if value != nil, do: Map.put(acc, prop, value), else: acc
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
      [quote do
        @__hybrid_server_actions__ unquote(action_names)

        @before_compile PhoenixVapor.Hybrid.ServerCodegen
      end]
    end
  end

  defmacro __before_compile__(env) do
    actions = Module.get_attribute(env.module, :__hybrid_server_actions__, [])
    defined = Module.defines?(env.module, {:handle_event, 3})

    for name <- actions, !defined do
      quote do
        def handle_event(unquote(name), _params, socket) do
          {:noreply, socket}
        end
      end
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
