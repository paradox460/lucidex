defmodule LucidexTest do
  use ExUnit.Case, async: false

  import Phoenix.LiveViewTest, only: [render_component: 2]

  describe "render_nodes/1" do
    test "renders Lucide's 2-element nodes as self-closing tags" do
      assert Lucidex.render_nodes([["path", %{"d" => "M1 1"}]]) == ~s(<path d="M1 1"/>)
    end

    test "renders 3-element nodes with children" do
      nodes = [["g", %{"id" => "a"}, [["circle", %{"r" => "2"}]]]]
      assert Lucidex.render_nodes(nodes) == ~s(<g id="a"><circle r="2"/></g>)
    end

    test "escapes attribute values" do
      assert Lucidex.render_nodes([["path", %{"d" => ~s(a"b<c&d)}]]) ==
               ~s(<path d="a&quot;b&lt;c&amp;d"/>)
    end

    test "renders every icon in the bundled dataset" do
      all = Lucidex.icon_data_path() |> File.read!() |> JSON.decode!()
      svg = Lucidex.build_sprite(Map.keys(all), all)
      assert svg =~ ~s(id="lucide-house")
    end
  end

  describe "build_sprite/2" do
    test "includes only requested, known icons" do
      all = %{"a" => [["path", %{"d" => "A"}]], "b" => [["path", %{"d" => "B"}]]}
      svg = Lucidex.build_sprite(["b", "missing"], all)

      assert svg =~ ~s(id="lucide-b")
      refute svg =~ ~s(id="lucide-a")
      refute svg =~ "missing"
    end
  end

  describe "icon/1 with the default :external delivery" do
    test "references the external sprite" do
      html = render_component(&Lucidex.icon/1, name: "house", size: 16, class: "w-4")

      assert html =~ ~s(href="/images/lucide.svg#lucide-house")
      assert html =~ ~s(width="16")
      assert html =~ ~s(class="w-4")
    end

    test "raises on an unknown icon name" do
      assert_raise ArgumentError, ~r/unknown icon "nope-not-real"/, fn ->
        render_component(&Lucidex.icon/1, name: "nope-not-real")
      end
    end

    test "sprite_tag/0 emits nothing" do
      assert Lucidex.sprite_tag() == {:safe, ""}
    end
  end

  describe "inline_sprite/0" do
    setup do
      path = Application.app_dir(:lucidex, "priv/static/images/lucide.svg")
      File.rm_rf!(Path.dirname(path))

      on_exit(fn ->
        Application.delete_env(:lucidex, :otp_app)
        File.rm_rf!(Application.app_dir(:lucidex, "priv/static"))
      end)

      %{path: path}
    end

    test "embeds every icon when no :otp_app is configured" do
      svg = Lucidex.inline_sprite()
      assert svg =~ ~s(id="lucide-house")
      assert svg =~ ~s(id="lucide-zap")
    end

    test "falls back to every icon when the host sprite is missing" do
      Application.put_env(:lucidex, :otp_app, :lucidex)
      assert Lucidex.inline_sprite() =~ ~s(id="lucide-zap")
    end

    test "serves the host's pruned sprite and picks up rewrites", %{path: path} do
      Application.put_env(:lucidex, :otp_app, :lucidex)
      File.mkdir_p!(Path.dirname(path))

      File.write!(path, "<svg>one</svg>")
      assert Lucidex.inline_sprite() == "<svg>one</svg>"

      File.write!(path, "<svg>second</svg>")
      assert Lucidex.inline_sprite() == "<svg>second</svg>"
    end
  end
end
