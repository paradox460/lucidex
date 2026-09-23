defmodule Mix.Tasks.Lucidex.InstallTest do
  use ExUnit.Case, async: true

  import Igniter.Test

  @layout "lib/my_app_web/components/layouts/root.html.heex"

  @files %{
    "mix.exs" => """
    defmodule MyApp.MixProject do
      use Mix.Project

      def project do
        [
          app: :my_app,
          version: "0.1.0",
          compilers: [:phoenix_live_view] ++ Mix.compilers(),
          deps: []
        ]
      end
    end
    """,
    @layout => """
    <!DOCTYPE html>
    <html lang="en">
      <head>
      </head>
      <body>
        {@inner_content}
      </body>
    </html>
    """,
    ".gitignore" => "/_build/\n/deps/\n"
  }

  defp project(overrides \\ %{}) do
    files =
      @files
      |> Map.merge(overrides)
      |> Map.reject(fn {_path, contents} -> is_nil(contents) end)

    test_project(app_name: :my_app, files: files)
  end

  defp install(igniter), do: Igniter.compose_task(igniter, "lucidex.install", [])

  defp mix_exs(compilers_line) do
    """
    defmodule MyApp.MixProject do
      use Mix.Project

      def project do
        [
          app: :my_app,
          version: "0.1.0",#{compilers_line}
          deps: []
        ]
      end
    end
    """
  end

  defp content(igniter, path) do
    igniter.rewrite |> Rewrite.source!(path) |> Rewrite.Source.get(:content)
  end

  test "installs into a Phoenix project" do
    project()
    |> install()
    |> assert_has_patch("mix.exs", """
    - |      compilers: [:phoenix_live_view] ++ Mix.compilers(),
    + |      compilers: [:phoenix_live_view] ++ Mix.compilers() ++ [:lucidex],
    """)
    |> assert_has_patch(@layout, """
      |  <body>
    + |    <%= Lucidex.sprite_tag() %>
      |    {@inner_content}
    """)
    |> assert_creates("config/dev.exs", fn contents ->
      assert contents =~ "config :lucidex"
      assert contents =~ "delivery: :inline"
      assert contents =~ "otp_app: :my_app"
    end)
    |> assert_has_patch(".gitignore", """
    + |/priv/static/images/lucide.svg
    """)
  end

  test "adds the compilers key when absent" do
    project(%{"mix.exs" => mix_exs("")})
    |> install()
    |> assert_has_patch("mix.exs", """
    + |      compilers: Mix.compilers() ++ [:lucidex]
    """)
  end

  test "appends to a literal compiler list" do
    project(%{"mix.exs" => mix_exs("\n      compilers: [:elixir, :app],")})
    |> install()
    |> assert_has_patch("mix.exs", """
    + |      compilers: [:elixir, :app, :lucidex],
    """)
  end

  test "running twice changes nothing" do
    project()
    |> install()
    |> apply_igniter!()
    |> install()
    |> assert_unchanged()
  end

  test "warns and continues when the root layout is missing" do
    project(%{@layout => nil})
    |> install()
    |> assert_has_warning(&(&1 =~ "Lucidex.sprite_tag()"))
    |> assert_has_patch("mix.exs", """
    + |      compilers: [:phoenix_live_view] ++ Mix.compilers() ++ [:lucidex],
    """)
  end

  test "keeps existing delivery config" do
    igniter =
      project(%{"config/dev.exs" => "import Config\nconfig :lucidex, delivery: :external\n"})
      |> install()
      |> apply_igniter!()

    contents = content(igniter, "config/dev.exs")
    assert contents =~ "delivery: :external"
    refute contents =~ "delivery: :inline"
  end
end
