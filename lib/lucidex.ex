defmodule Lucidex do
  @moduledoc """
  Auto tree-shaken Lucide icons for Phoenix.

  ## Usage

  In any template:

      <Lucidex.icon name="house" class="w-5 h-5" />
      <Lucidex.icon name="circle" size={20} />

  `import Lucidex` lets you write `<.icon name="house" />` instead.

  ## How it works

  `Mix.Tasks.Compile.Lucidex` reads your compiled modules after each build
  and writes a pruned `priv/static/images/lucide.svg` containing only the
  icons used. Register it after the default compilers in `mix.exs`:

      compilers: Mix.compilers() ++ [:lucidex]


  Icons are rendered using [svg
  sprites](https://css-tricks.com/svg-sprites-use-better-icon-fonts/) via
  `<use>` references.

  Icon names are validated against the bundled `priv/icon-nodes.json`;
  run `mix lucidex.download` to use a newer Lucide release.

  In the case of icon names that are dynamically called at runtime, such as a
  conditional switching between two icons, you must _hint_ the compiler, so it
  emits both icons. See `lucidex_hint/1` for details.

  ## Root layout setup

  Place `Lucidex.sprite_tag/0` once at the top of `<body>`:

      # root.html.heex
      <%= Lucidex.sprite_tag() %>

  ## Delivery modes

  The default delivery is `:external`: `sprite_tag/0` emits nothing and icons
  reference `/images/lucide.svg`, which the browser fetches and caches once.

  For development you can embed the sprite in the page instead, so no static
  file needs serving:

      # config/dev.exs
      config :lucidex, delivery: :inline, otp_app: :my_app

  This has added advantage that hot reloads can render new sprites without
  additional network requests.

  In `:inline` mode `sprite_tag/0` reads the pruned sprite from `:otp_app`
  (at `:output_path`) and re-reads it whenever the compiler rewrites it.
  Without `:otp_app` it embeds every icon.

  `:delivery`, `:sprite_url` and `:icon_nodes_path` are read at compile time,
  so run `mix deps.compile lucidex --force` after changing them.

  ## Serving the static file

  Phoenix's default `Plug.Static` setup serves `priv/static/images`, which is
  where the sprite is written, so the defaults need no configuration.
  If you serve static files from elsewhere, set both the file location and the
  URL it is served at:

      config :lucidex,
        output_path: "priv/static/assets/lucide.svg",
        sprite_url: "/assets/lucide.svg"

  ## Icon data

  `mix lucidex.download` fetches Lucide's `icon-nodes.json`. To use a copy
  newer than the one bundled with lucidex, point `:icon_nodes_path` at it
  (the path must be absolute):

      config :lucidex, icon_nodes_path: Path.expand("../priv/lucidex/icon-nodes.json", __DIR__)
  """

  use Phoenix.Component

  # Compile-time: load the full icon map so every icon works in dev/test.
  # @external_resource tells Mix to recompile this module when the file changes.
  # Hosts may point at their own downloaded copy (see `mix lucidex.download`);
  # the path must be absolute because deps compile with cwd = deps/lucidex.
  @icon_data_path (case Application.compile_env(:lucidex, :icon_nodes_path) do
                     nil ->
                       Application.app_dir(:lucidex, "priv/icon-nodes.json")

                     path when is_binary(path) ->
                       Path.type(path) == :absolute ||
                         raise ArgumentError,
                               "config :lucidex, :icon_nodes_path must be an absolute path, got: #{inspect(path)}. " <>
                                 ~s|Use Path.expand("../priv/lucidex/icon-nodes.json", __DIR__) in config/config.exs.|

                       path
                   end)
  @external_resource @icon_data_path
  @all_icons (if File.exists?(@icon_data_path) do
                @icon_data_path |> File.read!() |> JSON.decode!()
              else
                IO.warn(
                  "Lucidex: icon data not found at #{@icon_data_path}; no icons are available. " <>
                    "Run `mix lucidex.download`.",
                  []
                )

                %{}
              end)

  @doc false
  def icon_data_path, do: @icon_data_path

  # Compile-time delivery mode. Defaults to :external; opt into :inline per env.
  @delivery Application.compile_env(:lucidex, :delivery, :external)

  unless @delivery in [:inline, :external] do
    raise ArgumentError,
          "config :lucidex, :delivery must be :inline or :external, got: #{inspect(@delivery)}"
  end

  @doc """
  Renders a Lucide icon.

  ## Attributes

  * `name` (required) kebab-case icon name, e.g. `"house"`, `"arrow-up-right"`
  * `size` integer pixel size applied to `width` and `height` (default `24`)
  * `class` CSS class string
  * `stroke_width` integer stroke width (default `2`)
  * Any other attribute is forwarded to the outer `<svg>` element.

  ## Examples

      <Lucidex.icon name="house" />
      <Lucidex.icon name="loader" class="loading-icon" size={20} />
  """
  attr :name, :string, required: true
  attr :size, :integer, default: 24
  attr :class, :string, default: nil
  attr :stroke_width, :integer, default: 2
  attr :rest, :global

  def icon(%{name: name} = assigns) do
    # Name validation, to make debugging easier.
    unless Map.has_key?(@all_icons, name) do
      raise ArgumentError,
            "Lucidex: unknown icon #{inspect(name)}. " <>
              "Check the spelling against https://lucide.dev/icons/ ."
    end

    ~H"""
    <svg
      xmlns="http://www.w3.org/2000/svg"
      width={@size}
      height={@size}
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      stroke-width={@stroke_width}
      stroke-linecap="round"
      stroke-linejoin="round"
      class={["lucide-icon", @class]}
      {@rest}
    >
      <use href={icon_href(@name)} />
    </svg>
    """
  end

  @doc """
  Marks icon names as used so the compiler includes them in the sprite.

  Use it for names only known at runtime, next to the code that picks them:

      icon = if @open, do: "chevron-up", else: "chevron-down"
      Lucidex.lucidex_hint(~w[chevron-up chevron-down])

  The compiler counts the literal strings in the list, so `~w[...]` works
  and names built at runtime don't. Returns the list unchanged.
  """
  def lucidex_hint(names) when is_list(names), do: names

  @doc """
  Emits the SVG sprite element to be placed once in your root layout.

  In `:inline` delivery mode this embeds the sprite as a hidden `<svg>` block
  so that `<use href="#lucide-...">` fragment references resolve without an
  extra HTTP request. The sprite is read from
  `priv/static/images/lucide.svg` of the app configured as `:otp_app`, and
  re-read whenever that file changes. Without `:otp_app`, or before the
  compiler has written the file, every icon is embedded.

  In `:external` delivery mode (the default) this emits nothing; the sprite is
  served from `:sprite_url` and components reference it with a full path.

  Place this at the very top of `<body>` in `root.html.heex`:

      <body>
        <%= Lucidex.sprite_tag() %>
        ...
      </body>
  """
  if @delivery == :inline do
    def sprite_tag, do: {:safe, inline_sprite()}
  else
    def sprite_tag, do: {:safe, ""}
  end

  # Decided at compile time, so there's zero branching at runtime.
  if @delivery == :external do
    @sprite_url Application.compile_env(:lucidex, :sprite_url, "/images/lucide.svg")
    defp icon_href(name), do: "#{@sprite_url}#lucide-#{name}"
  else
    defp icon_href(name), do: "#lucide-#{name}"
  end

  @sprite_key {__MODULE__, :inline_sprite}

  # Inline mode is a dev convenience, so a File.stat per sprite_tag call is an
  # acceptable price for picking up compiler reruns without a restart. The
  # persistent_term is only rewritten when the file's mtime or size changes
  # (mtime alone has one-second granularity).
  @doc false
  def inline_sprite do
    with app when not is_nil(app) <- Application.get_env(:lucidex, :otp_app),
         output = Application.get_env(:lucidex, :output_path, "priv/static/images/lucide.svg"),
         path = Path.expand(output, Application.app_dir(app)),
         {:ok, %File.Stat{mtime: mtime, size: size}} <- File.stat(path, time: :posix) do
      cached({path, mtime, size}, fn -> File.read!(path) end)
    else
      _ -> cached(:full, fn -> build_sprite(Map.keys(@all_icons), @all_icons) end)
    end
  end

  defp cached(version, build) do
    case :persistent_term.get(@sprite_key, nil) do
      {^version, svg} ->
        svg

      _ ->
        svg = build.()
        :persistent_term.put(@sprite_key, {version, svg})
        svg
    end
  end

  @doc false
  def build_sprite(icon_names, all_icons) do
    symbols =
      icon_names
      |> Enum.sort()
      |> Enum.map_join("\n", fn name ->
        case Map.fetch(all_icons, name) do
          {:ok, nodes} ->
            inner = render_nodes(nodes)

            """
              <symbol id="lucide-#{escape(name)}" viewBox="0 0 24 24"
                      fill="none" stroke="currentColor"
                      stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
                #{inner}
              </symbol>
            """

          :error ->
            ""
        end
      end)

    """
    <svg xmlns="http://www.w3.org/2000/svg" style="display:none" aria-hidden="true">
    #{symbols}
    </svg>
    """
  end

  @doc false
  def render_nodes(nodes) do
    Enum.map_join(nodes, fn
      [tag, attrs] -> render_node(tag, attrs, [])
      [tag, attrs, children] -> render_node(tag, attrs, children)
    end)
  end

  defp render_node(tag, attrs, children) do
    tag = escape(tag)
    attr_str = Enum.map_join(attrs, " ", fn {k, v} -> ~s(#{escape(k)}="#{escape(v)}") end)
    inner = render_nodes(children)

    if inner == "" do
      "<#{tag} #{attr_str}/>"
    else
      "<#{tag} #{attr_str}>#{inner}</#{tag}>"
    end
  end

  # build_sprite/2 output is emitted as {:safe, ...}, bypassing HEEx escaping.
  defp escape(value) do
    {:safe, iodata} = Phoenix.HTML.html_escape(to_string(value))
    IO.iodata_to_binary(iodata)
  end
end
