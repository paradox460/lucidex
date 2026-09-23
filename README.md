# Lucidex

[Lucide](https://lucide.dev) icons for Phoenix, delivered as an SVG sprite that
contains only the icons your app uses.

After your code compiles, a Mix compiler finds every `Lucidex.icon` call with a
literal name and writes `priv/static/images/lucide.svg` with just those icons.
Each icon renders as an
`<svg><use href="/images/lucide.svg#lucide-house"/></svg>`, so the browser
downloads the sprite once and caches it. Misspelled icon names fail the build.

## Installation

With [Igniter](https://hexdocs.pm/igniter), run:

```sh
mix igniter.install lucidex
```

This adds the dependency, registers the `:lucidex` compiler, puts
`Lucidex.sprite_tag/0` at the top of `<body>` in your root layout, enables
inline delivery in `config/dev.exs`, and gitignores the generated sprite.

Alternatively, do it yourself. Add `lucidex` to your dependencies and register its
compiler after the default ones in `mix.exs`:

```elixir
def project do
  [
    # ...
    compilers: Mix.compilers() ++ [:lucidex]
  ]
end

def deps do
  [
    {:lucidex, "~> 0.1.0"}
  ]
end
```

Put the sprite tag at the top of `<body>` in your root layout. With the default
delivery it renders nothing, but it's what makes inline delivery work:

```heex
<body>
  <%= Lucidex.sprite_tag() %>
  ...
</body>
```

## Usage

```heex
<Lucidex.icon name="house" />
<Lucidex.icon name="arrow-up-right" size={20} class="text-zinc-500" />
```

Any other attribute is passed to the outer `<svg>`. Names are the kebab-case
names from [lucide.dev/icons](https://lucide.dev/icons/). `import Lucidex` lets
you write `<.icon name="house" />`; the compiler finds those calls too, and
ignores other `icon` components such as the one in Phoenix's generated
`CoreComponents`.

The compiler only sees literal names. For names chosen at runtime, list them
next to the code that picks them:

```elixir
Lucidex.lucidex_hint(~w[chevron-up chevron-down])
```

or in config with `config :lucidex, extra_icons: ~w[chevron-up chevron-down]`.

The compiler reads the debug info Mix stores in compiled modules. That's on by
default; a module built with `debug_info: false` is skipped with a warning.

## Inline delivery for development

To embed the sprite in each page instead of serving a static file:

```elixir
# config/dev.exs
config :lucidex, delivery: :inline, otp_app: :my_app
```

`sprite_tag/0` then reads your app's generated sprite and picks up changes
without a server restart. `:delivery` is read when lucidex compiles, so run
`mix deps.compile lucidex --force` after changing it.

## Configuration

| Option | Default | Read at |
|---|---|---|
| `:delivery` | `:external` | compile time |
| `:otp_app` | none; inline mode then embeds every icon | runtime |
| `:output_path` | `"priv/static/images/lucide.svg"` | build |
| `:sprite_url` | `"/images/lucide.svg"` | compile time |
| `:extra_icons` | `[]` | build |
| `:icon_nodes_path` | the copy bundled with lucidex | compile time |

## Newer Lucide icons

Lucidex ships a copy of Lucide's `icon-nodes.json`. To pull a newer Lucide
release without waiting for a lucidex update, run this in your project:

```sh
mix lucidex.download                 # latest lucide-static
mix lucidex.download --version 1.47.0
```

It writes `priv/lucidex/icon-nodes.json` and prints the config line that
points lucidex at it. Once that config is set, later downloads recompile
lucidex for you.

## Development

The icon data isn't kept in git; it's only bundled into the Hex package. After
cloning, fetch it before running the tests:

```sh
mix lucidex.download
mix test
```

`mix hex.build` and `mix hex.publish` download the Lucide release pinned by
`@lucide_version` in `mix.exs` first, so the package always ships that
version. A path or git dependency on lucidex needs the same download inside
its checkout.

## License

MIT. Lucide icons are licensed under the
[ISC license](https://lucide.dev/license).
