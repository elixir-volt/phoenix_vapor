# VaporDemo

To start your Phoenix server:

* Run `mix setup` to install and setup dependencies
* Start Phoenix endpoint with `mix phx.server` or inside IEx with `iex -S mix phx.server`

Now you can visit [`localhost:4000`](http://localhost:4000) from your browser.

`mix setup` installs browser dependencies, builds the server-side Vue bundle used by `/dialog`, and builds browser assets.

## Tests

Install the browser test driver once, then run the suite:

```sh
mix setup
npm --prefix assets ci
(cd assets && npx playwright install chromium)
mix test
```

The browser tests exercise `/search`, including filtering and clearing the search. Use the configured `localhost` host when testing manually so LiveView's origin check accepts the connection.

Ready to run in production? Please [check our deployment guides](https://hexdocs.pm/phoenix/deployment.html).

## Learn more

* Official website: https://www.phoenixframework.org/
* Guides: https://hexdocs.pm/phoenix/overview.html
* Docs: https://hexdocs.pm/phoenix
* Forum: https://elixirforum.com/c/phoenix-forum
* Source: https://github.com/phoenixframework/phoenix
