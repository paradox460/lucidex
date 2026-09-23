defmodule Mix.Tasks.Compile.Lucidex do
  @moduledoc """
  A Mix compiler that finds the icons your compiled code uses and writes a
  pruned SVG sprite containing only those icons. Tree-shaking, but without all
  the messy JS.

  It reads the modules the Elixir compiler just built, so it must run after
  compilation:

      # mix.exs
      compilers: Mix.compilers() ++ [:lucidex]

  The sprite is written to `priv/static/images/lucide.svg` in the current
  project, which Phoenix's `Plug.Static` serves at `/images/lucide.svg`.

  ## Dynamic icon names

  For most usage, simply calling `Lucidex.icon/1` with a literal string is sufficient. However, if icon names are dynamically constructed at runtime (such as a conditional on which icon to display), you must "hint" the compiler with `Lucidex.lucidex_hint/1`.

  See `Lucidex.lucidex_hint/1` for more details.

  ## What gets found

  Every call to `Lucidex.icon/1` whose `name` is a literal string, however it
  was written: `<Lucidex.icon name="house" />`, `<.icon name={"house"} />`
  through `import Lucidex`, an alias, or a template loaded with
  `embed_templates`. Calls to other `icon` components, such as the one in a
  generated Phoenix `CoreComponents`, are not counted.

  Names only known at runtime, such as `name={@icon}`, are invisible at build
  time. List them in `:extra_icons` or pass a literal list to
  `Lucidex.lucidex_hint/1`:

      Lucidex.lucidex_hint(["chevron-up", "chevron-down"])

  A name that doesn't exist in the Lucide dataset fails the build, pointing at
  the file and line that referenced it.

  Scanning needs the modules' debug info, which Mix includes by default. A
  module compiled without it is skipped with a warning.

  ## Configuration

      # config/config.exs
      config :lucidex,
        # Extra icon names to always include (for fully dynamic usages)
        extra_icons: ~w[loader circle x],

        # Where the sprite is written, relative to the project root
        output_path: "priv/static/images/lucide.svg"

  ## Recompilation

  The manifest records the icons found in each compiled module. Only modules
  whose `.beam` changed are read again, and the sprite is only rewritten when
  the overall set of icons changes.
  """

  use Mix.Task.Compiler

  @shortdoc "Generates a pruned Lucide SVG sprite from your compiled code"

  @manifest_vsn 4
  @manifest_name "lucidex"
  @default_output "priv/static/images/lucide.svg"

  @impl true
  def manifests, do: [manifest_path()]

  @impl true
  def clean do
    File.rm(manifest_path())
    File.rm(sprite_path())
    :ok
  end

  @impl true
  def run(args) do
    case order_error() do
      nil -> run_checked(args)
      diagnostic -> fail([diagnostic])
    end
  end

  defp run_checked(args) do
    data_path = Lucidex.icon_data_path()

    if File.exists?(data_path) do
      out = sprite_path()
      extra = Application.get_env(:lucidex, :extra_icons, [])
      beams = beam_stats()
      settings = {Application.spec(:lucidex, :vsn), stat(data_path), extra, out}
      manifest = if "--force" in args, do: %{}, else: read_manifest()

      if manifest[:settings] == settings and manifest[:beams] == beams and File.exists?(out) do
        {:noop, []}
      else
        compile(data_path, out, extra, beams, settings, manifest)
      end
    else
      fail([
        diagnostic(
          :error,
          "Lucidex: icon data not found at #{data_path}. Run `mix lucidex.download`.",
          nil,
          0
        )
      ])
    end
  end

  defp compile(data_path, out, extra, beams, settings, manifest) do
    cached = Map.get(manifest, :refs, %{})
    old_beams = Map.get(manifest, :beams, %{})

    # {path => refs | {:skipped, message}}, re-reading only changed beams.
    refs_by_beam =
      Map.new(beams, fn {path, stat} ->
        case {old_beams, cached} do
          {%{^path => ^stat}, %{^path => refs}} -> {path, refs}
          _ -> {path, read_refs(path)}
        end
      end)

    skipped =
      for {path, {:skipped, message}} <- refs_by_beam do
        diagnostic(:warning, "Lucidex: skipped #{Path.relative_to_cwd(path)}: #{message}", nil, 0)
      end

    all_icons = data_path |> File.read!() |> JSON.decode!()

    refs =
      Enum.flat_map(refs_by_beam, fn
        {_path, refs} when is_list(refs) -> refs
        _ -> []
      end) ++ Enum.map(extra, &{&1, nil, 0})

    unknown =
      for {name, file, line} <- Enum.uniq(refs), not Map.has_key?(all_icons, name) do
        unknown_icon(name, file, line)
      end

    icons = refs |> Enum.map(&elem(&1, 0)) |> Enum.uniq() |> Enum.sort()
    Enum.each(skipped ++ unknown, &Code.print_diagnostic/1)

    cond do
      unknown != [] ->
        {:error, skipped ++ unknown}

      icons == manifest[:icons] and File.exists?(out) ->
        write_manifest(settings, beams, refs_by_beam, icons)
        {:noop, skipped}

      true ->
        File.mkdir_p!(Path.dirname(out))
        File.write!(out, Lucidex.build_sprite(icons, all_icons))
        write_manifest(settings, beams, refs_by_beam, icons)

        Mix.shell().info([
          :green,
          "Lucidex ",
          :reset,
          "generated sprite with #{length(icons)} icon(s) → #{Path.relative_to_cwd(out)}"
        ])

        {:ok, skipped}
    end
  end

  # Scanning an earlier compiler's leftovers would silently produce a sprite
  # that lags one build behind, so refuse to run before :elixir.
  defp order_error do
    compilers = Mix.Task.Compiler.compilers()
    lucidex = Enum.find_index(compilers, &(&1 == :lucidex))
    elixir = Enum.find_index(compilers, &(&1 == :elixir))

    if lucidex && elixir && lucidex < elixir do
      diagnostic(
        :error,
        "Lucidex: the :lucidex compiler must run after :elixir. " <>
          "In mix.exs, use: compilers: Mix.compilers() ++ [:lucidex]",
        nil,
        0
      )
    end
  end

  defp fail(diagnostics) do
    Enum.each(diagnostics, &Code.print_diagnostic/1)
    {:error, diagnostics}
  end

  defp beam_stats do
    Mix.Project.compile_path()
    |> Path.join("*.beam")
    |> Path.wildcard()
    |> Map.new(&{&1, stat(&1)})
  end

  defp stat(path) do
    case File.stat(path, time: :posix) do
      {:ok, %File.Stat{mtime: mtime, size: size}} -> {mtime, size}
      {:error, reason} -> reason
    end
  end

  # Returns [{name, file, line}] for the literal icon names a module uses.
  defp read_refs(path) do
    with {:ok, {module, [debug_info: {:debug_info_v1, backend, data}]}} <-
           :beam_lib.chunks(String.to_charlist(path), [:debug_info]),
         {:ok, forms} <- backend.debug_info(:erlang_v1, module, data, []) do
      {_file, refs} = Enum.reduce(forms, {nil, []}, &collect_form/2)
      refs |> Enum.reverse() |> Enum.uniq()
    else
      _ -> {:skipped, "compiled without debug_info, so its icons cannot be detected"}
    end
  end

  defp collect_form({:attribute, _, :file, {file, _}}, {_file, refs}),
    do: {List.to_string(file), refs}

  defp collect_form(form, {file, refs}), do: {file, walk(form, file, refs)}

  # HEEx compiles every <Lucidex.icon ...> / <.icon ...> to a call whose
  # arguments are a capture of Lucidex.icon/1 followed by the assigns map.
  defp walk(
         {:call, _, {:remote, _, {:atom, _, Lucidex}, {:atom, _, :lucidex_hint}}, [list]} = call,
         file,
         refs
       ) do
    walk_children(call, file, literal_list(list, file) ++ refs)
  end

  defp walk({:call, _, _, args} = call, file, refs) do
    walk_children(call, file, icon_args(args, file) ++ refs)
  end

  defp walk(node, file, refs), do: walk_children(node, file, refs)

  defp walk_children(node, file, refs) when is_tuple(node) do
    node |> Tuple.to_list() |> walk_children(file, refs)
  end

  defp walk_children(nodes, file, refs) when is_list(nodes) do
    Enum.reduce(nodes, refs, &walk(&1, file, &2))
  end

  defp walk_children(_leaf, _file, refs), do: refs

  defp icon_args(
         [
           {:fun, anno, {:function, {:atom, _, Lucidex}, {:atom, _, :icon}, {:integer, _, 1}}},
           {:map, _, fields} | _
         ],
         file
       ) do
    for {:map_field_assoc, _, {:atom, _, :name}, value} <- fields,
        name = literal_string(value),
        do: {name, file, :erl_anno.line(anno)}
  end

  defp icon_args([_ | rest], file), do: icon_args(rest, file)
  defp icon_args([], _file), do: []

  defp literal_list({:cons, anno, head, tail}, file) do
    case literal_string(head) do
      nil -> literal_list(tail, file)
      name -> [{name, file, :erl_anno.line(anno)} | literal_list(tail, file)]
    end
  end

  defp literal_list(_, _file), do: []

  defp literal_string({:bin, _, [{:bin_element, _, {:string, _, chars}, :default, :default}]}),
    do: List.to_string(chars)

  defp literal_string({:bin, _, []}), do: ""
  defp literal_string(_), do: nil

  defp unknown_icon(name, nil, _line) do
    diagnostic(
      :error,
      "Lucidex: unknown icon #{inspect(name)} in config :lucidex, :extra_icons. " <>
        "Check the spelling against https://lucide.dev/icons/",
      nil,
      0
    )
  end

  defp unknown_icon(name, file, line) do
    diagnostic(
      :error,
      "Lucidex: unknown icon #{inspect(name)}. Check the spelling against https://lucide.dev/icons/",
      file,
      line
    )
  end

  defp diagnostic(severity, message, file, line) do
    %Mix.Task.Compiler.Diagnostic{
      compiler_name: "lucidex",
      severity: severity,
      message: message,
      file: file && Path.expand(file),
      source: file && Path.expand(file),
      position: line
    }
  end

  defp sprite_path do
    Path.expand(Application.get_env(:lucidex, :output_path, @default_output))
  end

  defp manifest_path do
    Path.join(Mix.Project.manifest_path(), "#{@manifest_name}.manifest")
  end

  defp read_manifest do
    with {:ok, binary} <- File.read(manifest_path()),
         {@manifest_vsn, manifest} <- safe_binary_to_term(binary) do
      manifest
    else
      _ -> %{}
    end
  end

  defp safe_binary_to_term(binary) do
    :erlang.binary_to_term(binary)
  rescue
    ArgumentError -> nil
  end

  defp write_manifest(settings, beams, refs, icons) do
    manifest = %{settings: settings, beams: beams, refs: refs, icons: icons}
    File.mkdir_p!(Path.dirname(manifest_path()))
    File.write!(manifest_path(), :erlang.term_to_binary({@manifest_vsn, manifest}))
  end
end
