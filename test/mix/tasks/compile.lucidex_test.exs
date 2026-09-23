defmodule Mix.Tasks.Compile.LucidexTest do
  use ExUnit.Case, async: false

  alias Mix.Tasks.Compile.Lucidex, as: Compiler

  # Each test runs inside a throwaway Mix project. Fixture modules are
  # compiled in this VM, so real HEEx output is scanned, and their .beam
  # files are written to the project's compile path, as `mix compile` would.
  setup do
    root = Path.join(System.tmp_dir!(), "lucidex-compiler-#{System.unique_integer([:positive])}")
    File.mkdir_p!(root)
    Mix.shell(Mix.Shell.Process)

    on_exit(fn ->
      Mix.shell(Mix.Shell.IO)

      for key <- [:extra_icons, :output_path],
          do: Application.delete_env(:lucidex, key)

      File.rm_rf!(root)
    end)

    %{root: root}
  end

  test "finds literal icon names however the call is written", %{root: root} do
    in_fixture(root, fn ->
      compile!("""
      defmodule Fixture.Page do
        use Phoenix.Component
        import Lucidex, only: [icon: 1]
        alias Lucidex, as: L

        def remote(assigns), do: ~H[<Lucidex.icon name="house" />]
        def imported(assigns), do: ~H[<.icon name={"zap"} class="x" />]
        def aliased(assigns), do: ~H[<L.icon name="circle" />]
        def dynamic(assigns), do: ~H[<Lucidex.icon name={@icon} />]
        def hinted, do: Lucidex.lucidex_hint(~w[chevron-up chevron-down])
      end
      """)

      assert {:ok, []} = run()
      assert symbols() == ["chevron-down", "chevron-up", "circle", "house", "zap"]
    end)
  end

  test "ignores other icon components and non-literal text", %{root: root} do
    in_fixture(root, fn ->
      compile!("""
      defmodule Fixture.CoreComponents do
        use Phoenix.Component
        attr :name, :string, required: true
        def icon(assigns), do: ~H[<span class={@name} />]
      end

      defmodule Fixture.Other do
        use Phoenix.Component
        import Fixture.CoreComponents

        @moduledoc ~S(<Lucidex.icon name="mail" />)
        def page(assigns) do
          ~H\"\"\"
          <.icon name="hero-x-mark" />
          <input name="search" />
          <Lucidex.icon name="house" />
          \"\"\"
        end
      end
      """)

      assert {:ok, []} = run()
      assert symbols() == ["house"]
    end)
  end

  test "unknown names fail the build at the calling line", %{root: root} do
    in_fixture(root, fn ->
      file = Path.join(root, "lib/page.ex")

      compile!(
        """
        defmodule Fixture.Typo do
          use Phoenix.Component

          def page(assigns) do
            ~H\"\"\"
            <Lucidex.icon name="house" />
            <Lucidex.icon name="hous" />
            \"\"\"
          end
        end
        """,
        file
      )

      assert {:error, [diagnostic]} = run()
      assert diagnostic.message =~ ~s(unknown icon "hous")
      assert diagnostic.file == file
      assert diagnostic.position == 7
      refute File.exists?(sprite())
    end)
  end

  test "unknown names in :extra_icons fail the build", %{root: root} do
    in_fixture(root, fn ->
      Application.put_env(:lucidex, :extra_icons, ["zapp"])

      assert {:error, [diagnostic]} = run()
      assert diagnostic.message =~ ~s(unknown icon "zapp" in config :lucidex, :extra_icons)
    end)
  end

  test "tracks changes per module, including removals", %{root: root} do
    in_fixture(root, fn ->
      compile!(~S|defmodule Fixture.A do
        use Phoenix.Component
        def a(assigns), do: ~H[<Lucidex.icon name="house" />]
      end|)

      compile!(~S|defmodule Fixture.B do
        use Phoenix.Component
        def b(assigns), do: ~H[<Lucidex.icon name="zap" />]
      end|)

      assert {:ok, []} = run()
      assert symbols() == ["house", "zap"]
      assert {:noop, []} = run()

      File.rm!(beam(Fixture.B))
      assert {:ok, []} = run()
      assert symbols() == ["house"]

      File.rm!(beam(Fixture.A))
      assert {:ok, []} = run()
      assert symbols() == []
    end)
  end

  test "warns about modules compiled without debug info", %{root: root} do
    in_fixture(root, fn ->
      compile!(
        ~S|defmodule Fixture.NoDebug do
          use Phoenix.Component
          def a(assigns), do: ~H[<Lucidex.icon name="house" />]
        end|,
        "nofile",
        false
      )

      assert {:ok, [warning]} = run()
      assert warning.severity == :warning
      assert warning.message =~ "Elixir.Fixture.NoDebug.beam"
    end)
  end

  test "writes to :output_path", %{root: root} do
    in_fixture(root, fn ->
      Application.put_env(:lucidex, :extra_icons, ["house"])
      Application.put_env(:lucidex, :output_path, "priv/static/icons/sprite.svg")

      assert {:ok, []} = run()
      assert symbols(Path.expand("priv/static/icons/sprite.svg")) == ["house"]
    end)
  end

  test "refuses to run before the Elixir compiler", %{root: root} do
    in_fixture(root, [compilers: [:lucidex, :elixir, :app]], fn ->
      assert {:error, [diagnostic]} = run()
      assert diagnostic.message =~ "must run after :elixir"
    end)
  end

  defp in_fixture(root, opts \\ [], fun) do
    compilers = Keyword.get(opts, :compilers, [:elixir, :app, :lucidex])
    name = :"fixture#{System.unique_integer([:positive])}"
    module = Module.concat(["Fixture#{System.unique_integer([:positive])}", MixProject])

    File.write!(Path.join(root, "mix.exs"), """
    defmodule #{inspect(module)} do
      use Mix.Project
      def project, do: [app: #{inspect(name)}, version: "0.1.0", compilers: #{inspect(compilers)}]
    end
    """)

    Mix.Project.in_project(name, root, fn _ ->
      File.mkdir_p!(Mix.Project.compile_path())

      try do
        fun.()
      after
        for {mod, _} <- :code.all_loaded(),
            String.starts_with?(Atom.to_string(mod), "Elixir.Fixture.") do
          :code.purge(mod)
          :code.delete(mod)
        end
      end
    end)
  end

  # `mix test` turns debug_info off while `mix compile` keeps it on, so match
  # a real build unless a test says otherwise.
  defp compile!(source, file \\ "nofile", debug_info \\ true) do
    previous = Code.get_compiler_option(:debug_info)
    Code.put_compiler_option(:debug_info, debug_info)

    try do
      for {module, bin} <- Code.compile_string(source, file) do
        File.write!(beam(module), bin)
      end
    after
      Code.put_compiler_option(:debug_info, previous)
    end
  end

  defp beam(module), do: Path.join(Mix.Project.compile_path(), "#{module}.beam")

  defp sprite, do: Path.expand("priv/static/images/lucide.svg")

  # Diagnostics are printed to stderr as well as returned.
  defp run do
    parent = self()
    ExUnit.CaptureIO.capture_io(:stderr, fn -> send(parent, {:result, Compiler.run([])}) end)
    assert_received {:result, result}
    result
  end

  defp symbols(path \\ sprite()) do
    ~r/id="lucide-([^"]+)"/
    |> Regex.scan(File.read!(path), capture: :all_but_first)
    |> List.flatten()
  end
end
