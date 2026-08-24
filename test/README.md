# Test layout

- `phoenix_vapor/` contains focused tests and mirrors `lib/phoenix_vapor/`.
- `integration/` covers behavior spanning multiple PhoenixVapor modules, Vize, or Volt.
- `e2e/` runs executable Vue behavior through QuickBEAM and is excluded from the default `mix test` run.
- `fixtures/` contains shared Vue SFC fixtures.
- `support/` contains test-only Elixir support modules.

Run each tier independently:

```sh
mix test.unit
mix test.integration
mix test.e2e
```

Run every tier with `mix ci`.
