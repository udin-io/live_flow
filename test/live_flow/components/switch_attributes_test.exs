defmodule LiveFlow.Components.SwitchAttributesTest do
  # The hook reads a switch as on unless its data attribute says "false", so
  # a switch turned off must render that word, not drop the attribute.
  use ExUnit.Case, async: true
  import Phoenix.ConnTest
  import Phoenix.LiveViewTest

  @endpoint LiveFlow.TestEndpoint

  defmodule SwitchLive do
    use Phoenix.LiveView

    alias LiveFlow.{Handle, Node, State}

    def mount(_params, session, socket) do
      on = Map.fetch!(session, "on")

      node =
        Node.new("a", %{x: 0, y: 0}, %{},
          draggable: on,
          connectable: on,
          selectable: on,
          handles: [Handle.new(:source, :right, connectable: on)]
        )

      {:ok, assign(socket, flow: State.new(nodes: [node]), on: on)}
    end

    def render(assigns) do
      ~H"""
      <.live_component
        module={LiveFlow.Components.Flow}
        id="flow"
        flow={@flow}
        opts={
          %{
            pan_on_drag: @on,
            zoom_on_scroll: @on,
            nodes_draggable: @on,
            nodes_connectable: @on,
            elements_selectable: @on
          }
        }
      />
      """
    end
  end

  @canvas ~w(data-pan-on-drag data-zoom-on-scroll data-nodes-draggable data-nodes-connectable data-elements-selectable)
  @node ~w(data-draggable data-connectable data-selectable)

  defp attrs(on) do
    {:ok, _view, html} = live_isolated(build_conn(), SwitchLive, session: %{"on" => on})
    doc = LazyHTML.from_fragment(html)
    one = fn selector, name -> doc |> LazyHTML.query(selector) |> LazyHTML.attribute(name) end

    @canvas
    |> Map.new(&{&1, one.("#flow", &1)})
    |> Map.merge(Map.new(@node, &{&1, one.(".lf-node", &1)}))
    |> Map.put("data-handle-connectable", one.(".lf-handle", "data-handle-connectable"))
  end

  test "a switch turned off renders \"false\"" do
    for {name, value} <- attrs(false), do: assert({name, value} == {name, ["false"]})
  end

  test "a switch turned on renders \"true\"" do
    for {name, value} <- attrs(true), do: assert({name, value} == {name, ["true"]})
  end
end
