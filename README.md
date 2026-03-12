# PhoenixVapor

Vue templates as native Phoenix LiveView rendered structs.

Compiles Vue template syntax to `%Phoenix.LiveView.Rendered{}` via
[Vize](https://github.com/nicolo-ribaudo/vize)'s Vapor IR — no JavaScript
runtime needed for template-only components.

## How it works

```
.vue template ──→ Vize.vapor_ir/1 ──→ Elixir IR maps ──→ %Rendered{} struct
                    (Rust NIF)         (Elixir maps)       (LiveView native)
```

1. **Vize** compiles the Vue template to Vapor intermediate representation (IR)
   as native Elixir maps — entirely in Rust, no JS execution
2. **PhoenixVapor** walks the IR and produces `%Rendered{}` structs with proper
   `static`/`dynamic`/`fingerprint` fields
3. The `%Rendered{}` struct participates in LiveView's diff engine — same
   WebSocket, same protocol, same client

No wrapper div. No `phx-update="ignore"`. No JSON props. Vue templates become
first-class LiveView rendered output with per-assign change tracking.

## Usage

### Sigil

```elixir
import PhoenixVapor.Sigil

def render(assigns) do
  ~VUE"""
  <div :class="status">
    <h1>{{ title }}</h1>
    <ul>
      <li v-for="item in items">{{ item.name }}</li>
    </ul>
    <p v-if="showFooter">{{ footerText }}</p>
  </div>
  """
end
```

The template compiles to Vapor IR at **compile time**. At runtime, only the
IR-to-Rendered transformation runs — a fast Elixir data walk.

### Programmatic

```elixir
# Compile once (at compile time or startup)
@ir Vize.vapor_ir!("<div :class=\"status\"><h1>{{ title }}</h1></div>")

# Render against assigns (at runtime)
def render(assigns) do
  PhoenixVapor.render(@ir, assigns)
end
```

### Runtime (for dynamic templates)

```elixir
PhoenixVapor.render("<div>{{ msg }}</div>", %{msg: "Hello"})
```

## Supported Vue features

- `{{ }}` text interpolation with HTML escaping
- `:attr` dynamic attribute binding
- `v-if` / `v-else-if` / `v-else` conditional rendering
- `v-for` list rendering
- Mixed static and dynamic attributes
- Nested elements and deeply nested text
- Multiple interpolations in a single text node
- Dot-access expression resolution (`user.name`, `item.id`)
- Per-assign change tracking (LiveView only sends diffs for changed values)

## Dependencies

- [Vize](https://hex.pm/packages/vize) — Vue compiler as Rust NIF
- [Phoenix LiveView](https://hex.pm/packages/phoenix_live_view) — `%Rendered{}` struct definitions

## Installation

```elixir
def deps do
  [
    {:phoenix_vapor, "~> 0.1.0"},
  ]
end
```
