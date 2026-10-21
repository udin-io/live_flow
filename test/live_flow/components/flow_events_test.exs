defmodule LiveFlow.Components.FlowEventsTest do
  # The atom table is global: async tests loading modules would add atoms
  # while these tests count them.
  use ExUnit.Case, async: false
  @moduletag :capture_log
  import Phoenix.ConnTest
  import Phoenix.LiveViewTest

  @endpoint LiveFlow.TestEndpoint

  defmodule CanvasLive do
    use Phoenix.LiveView

    alias LiveFlow.{Node, State}

    def mount(_params, _session, socket) do
      {:ok, assign(socket, flow: State.new(nodes: [Node.new("a", %{x: 0, y: 0}, %{})]))}
    end

    def render(assigns) do
      ~H"""
      <.live_component module={LiveFlow.Components.Flow} id="flow" flow={@flow} />
      """
    end
  end

  defp mount_canvas do
    {:ok, view, _html} = live_isolated(build_conn(), CanvasLive)
    {view, element(view, "#flow")}
  end

  defp connection_line(view) do
    view
    |> render()
    |> LazyHTML.from_fragment()
    |> LazyHTML.query(".lf-connection-line")
    |> LazyHTML.attribute("d")
  end

  defp connect_start(canvas, position) do
    render_hook(canvas, "lf:connect_start", %{
      "node_id" => "a",
      "from_x" => 0,
      "from_y" => 0,
      "to_x" => 200,
      "to_y" => 100,
      "from_position" => position
    })
  end

  describe "lf:connect_start" do
    test "creates no atom for start sides the canvas never sends" do
      # Before the fix each unknown side made an atom and then crashed the
      # page as it drew; a browser reconnects and the next one adds another.
      # Remount after a crash so the count covers the whole run.
      Process.flag(:trap_exit, true)
      {_view, canvas} = mount_canvas()
      connect_start(canvas, "right")

      run = System.unique_integer([:positive])
      before = :erlang.system_info(:atom_count)

      {_canvas, crashes} =
        Enum.reduce(1..1_000, {canvas, 0}, fn i, {canvas, crashes} ->
          try do
            connect_start(canvas, "side_#{run}_#{i}")
            {canvas, crashes}
          catch
            :exit, _ -> {elem(mount_canvas(), 1), crashes + 1}
          end
        end)

      assert :erlang.system_info(:atom_count) - before < 10
      assert crashes == 0
    end

    test "draws the line from each of the four sides" do
      {view, canvas} = mount_canvas()

      paths =
        for side <- ~w(top right bottom left) do
          connect_start(canvas, side)
          [d] = connection_line(view)
          d
        end

      assert paths |> Enum.uniq() |> length() == 4
    end

    test "draws an unknown or missing side as a drag from the right" do
      {view, canvas} = mount_canvas()
      connect_start(canvas, "right")
      [right] = connection_line(view)

      for position <- ["diagonal", nil, %{"x" => 1}, 7] do
        connect_start(canvas, position)
        assert connection_line(view) == [right]
      end
    end
  end

  describe "lf:connect_start coordinates" do
    test "draws a line from 0 for coordinates that are not numbers instead of crashing" do
      Process.flag(:trap_exit, true)
      {view, canvas} = mount_canvas()

      render_hook(canvas, "lf:connect_start", %{"from_position" => "right"})
      [zero] = connection_line(view)

      try do
        render_hook(canvas, "lf:connect_start", %{
          "from_x" => "abc",
          "from_y" => %{"a" => 1},
          "to_x" => [1],
          "to_y" => true,
          "from_position" => "right"
        })
      catch
        :exit, _ -> flunk("the page crashed on coordinates that are not numbers")
      end

      assert connection_line(view) == [zero]
    end
  end

  describe "lf:node_change" do
    for kind <- ["add", "replace"] do
      test "#{kind} with an unknown node type draws a default node and makes no atom" do
        {view, canvas} = mount_canvas()
        type = "lf_type_#{System.unique_integer([:positive])}"

        Process.flag(:trap_exit, true)

        change = %{
          "type" => unquote(kind),
          "node" => %{"id" => "b", "type" => type, "position" => %{"x" => 50, "y" => 50}}
        }

        try do
          render_hook(canvas, "lf:node_change", %{"changes" => [change]})
        catch
          :exit, _ -> flunk("the page crashed on an unknown node type")
        end

        assert has_element?(view, "[data-node-id='b']")
        assert_raise ArgumentError, fn -> String.to_existing_atom(type) end
      end
    end

    test "keeps a node type an Elixir caller passes as an atom" do
      change = %{
        "type" => "add",
        "node" => %{"id" => "b", "type" => :status, "position" => %{"x" => 0, "y" => 0}}
      }

      flow = LiveFlow.Changes.NodeChange.apply_changes(LiveFlow.State.new(), [change])

      assert flow.nodes["b"].type == :status
    end
  end
end
