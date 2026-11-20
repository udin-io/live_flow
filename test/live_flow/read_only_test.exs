defmodule LiveFlow.ReadOnlyTest do
  @moduledoc false
  # The browser hides drag, connect and select when a flow or an element turns
  # them off. These tests send the events a browser would send anyway and
  # check the server refuses them.
  use ExUnit.Case, async: true

  alias LiveFlow.{Edge, Node, State}
  alias LiveFlow.Changes.{EdgeChange, NodeChange}
  alias LiveFlow.Components.Flow
  alias LiveFlow.Validation.Connection

  defp flow(node_opts \\ [], edge_opts \\ []) do
    State.new(
      nodes: [
        Node.new("a", %{x: 0, y: 0}, %{}, node_opts),
        Node.new("b", %{x: 100, y: 0}, %{}),
        Node.new("c", %{x: 200, y: 0}, %{})
      ],
      edges: [Edge.new("e1", "a", "b", edge_opts)]
    )
  end

  defp move(id), do: %{"type" => "position", "id" => id, "position" => %{"x" => 50, "y" => 60}}
  defp select(id, selected \\ true), do: %{"type" => "select", "id" => id, "selected" => selected}

  defp add_edge(id, source, target),
    do: %{"type" => "add", "edge" => %{"id" => id, "source" => source, "target" => target}}

  defp position(flow, id), do: {flow.nodes[id].position.x, flow.nodes[id].position.y}

  describe "a node that is not draggable" do
    test "keeps its place when a position change arrives" do
      moved = NodeChange.apply_changes(flow(draggable: false), [move("a")])
      assert position(moved, "a") == {0.0, 0.0}
    end

    test "a draggable node still moves" do
      moved = NodeChange.apply_changes(flow(), [move("a")])
      assert position(moved, "a") == {50.0, 60.0}
    end
  end

  describe "an element that is not selectable" do
    test "a node stays unselected through a change and through selection" do
      f = flow(selectable: false)

      refute NodeChange.apply_changes(f, [select("a")]).nodes["a"].selected
      refute NodeChange.apply_changes(f, [select("a", "yes")]).nodes["a"].selected

      selected = State.apply_selection_change(f, %{"nodes" => ["a", "b"], "edges" => []})
      assert MapSet.to_list(selected.selected_nodes) == ["b"]
    end

    test "an edge stays unselected through a change and through selection" do
      f = flow([], selectable: false)

      refute EdgeChange.apply_changes(f, [select("e1")]).edges["e1"].selected

      selected = State.apply_selection_change(f, %{"nodes" => [], "edges" => ["e1"]})
      assert MapSet.size(selected.selected_edges) == 0
    end

    test "selectable elements are still selected" do
      f = flow()

      assert NodeChange.apply_changes(f, [select("a")]).nodes["a"].selected
      assert EdgeChange.apply_changes(f, [select("e1")]).edges["e1"].selected

      selected = State.apply_selection_change(f, %{"nodes" => ["a"], "edges" => ["e1"]})
      assert MapSet.to_list(selected.selected_nodes) == ["a"]
      assert MapSet.to_list(selected.selected_edges) == ["e1"]
    end
  end

  describe "a node that is not connectable" do
    test "refuses a connection from or to it" do
      f = flow(connectable: false)

      assert {:error, _} = Connection.validate_and_create(f, %{"source" => "a", "target" => "c"})
      assert {:error, _} = Connection.validate_and_create(f, %{"source" => "c", "target" => "a"})
    end

    test "connectable nodes still connect" do
      assert {:ok, %Edge{source: "b", target: "c"}} =
               Connection.validate_and_create(flow(connectable: false), %{
                 "source" => "b",
                 "target" => "c"
               })
    end
  end

  describe "flow options passed to the server" do
    test "nodes_draggable: false drops position changes" do
      assert position(NodeChange.apply_changes(flow(), [move("a")], nodes_draggable: false), "a") ==
               {0.0, 0.0}

      assert position(
               NodeChange.apply_changes(flow(), [move("a")], %{nodes_draggable: false}),
               "a"
             ) ==
               {0.0, 0.0}
    end

    test "elements_selectable: false drops selecting but keeps deselecting" do
      f = NodeChange.apply_changes(flow(), [select("b")])

      after_changes =
        NodeChange.apply_changes(f, [select("a"), select("b", false)], elements_selectable: false)

      refute after_changes.nodes["a"].selected
      refute after_changes.nodes["b"].selected

      refute EdgeChange.apply_changes(flow(), [select("e1", 1)], elements_selectable: false).edges[
               "e1"
             ].selected

      assert State.apply_selection_change(f, %{"nodes" => ["a"]}, %{elements_selectable: false}) ==
               f
    end

    test "nodes_connectable: false drops new edges and refuses connections" do
      refute Map.has_key?(
               EdgeChange.apply_changes(flow(), [add_edge("e2", "b", "c")],
                 nodes_connectable: false
               ).edges,
               "e2"
             )

      assert {:error, _} =
               Connection.validate_and_create(flow(), %{"source" => "b", "target" => "c"},
                 nodes_connectable: false
               )

      assert {:error, _} =
               Connection.validate_and_create(flow(), %{"source" => "b", "target" => "c"}, %{
                 nodes_connectable: false
               })
    end

    test "options left on apply every change" do
      f =
        flow()
        |> NodeChange.apply_changes([move("a"), select("a")],
          nodes_draggable: true,
          elements_selectable: true
        )
        |> EdgeChange.apply_changes([add_edge("e2", "b", "c")], nodes_connectable: true)

      assert position(f, "a") == {50.0, 60.0}
      assert f.nodes["a"].selected
      assert Map.has_key?(f.edges, "e2")
    end
  end

  describe "the flow component's own event handlers" do
    defp socket(opts, test_pid) do
      %Phoenix.LiveView.Socket{
        assigns: %{
          __changed__: %{},
          flow: flow(),
          opts: opts,
          on_nodes_change: &send(test_pid, {:nodes_change, &1}),
          on_edges_change: &send(test_pid, {:edges_change, &1}),
          on_selection_change: &send(test_pid, {:selection_change, &1})
        }
      }
    end

    test "follow the read-only options it was given" do
      opts = %{nodes_draggable: false, nodes_connectable: false, elements_selectable: false}
      s = socket(opts, self())

      {:noreply, s} = Flow.handle_event("lf:node_change", %{"changes" => [move("a")]}, s)
      assert position(s.assigns.flow, "a") == {0.0, 0.0}
      assert_received {:nodes_change, []}

      {:noreply, s} =
        Flow.handle_event("lf:edge_change", %{"changes" => [add_edge("e2", "b", "c")]}, s)

      refute Map.has_key?(s.assigns.flow.edges, "e2")
      assert_received {:edges_change, []}

      {:noreply, s} =
        Flow.handle_event("lf:selection_change", %{"nodes" => ["a"], "edges" => ["e1"]}, s)

      assert MapSet.size(s.assigns.flow.selected_nodes) == 0
      assert MapSet.size(s.assigns.flow.selected_edges) == 0
    end

    test "apply every change when the options are on" do
      s = socket(%{}, self())

      {:noreply, s} = Flow.handle_event("lf:node_change", %{"changes" => [move("a")]}, s)
      assert position(s.assigns.flow, "a") == {50.0, 60.0}

      {:noreply, s} =
        Flow.handle_event("lf:selection_change", %{"nodes" => ["a"], "edges" => ["e1"]}, s)

      assert MapSet.member?(s.assigns.flow.selected_nodes, "a")
      assert MapSet.member?(s.assigns.flow.selected_edges, "e1")
    end
  end

  describe "other changes the browser can send" do
    defp resize(id),
      do: %{
        "type" => "resize",
        "id" => id,
        "width" => 300,
        "height" => 200,
        "position" => %{"x" => 999, "y" => 999}
      }

    defp replace_node(type, id),
      do: %{"type" => type, "node" => %{"id" => id, "position" => %{"x" => 5, "y" => 5}}}

    test "a resize keeps a locked node in place but still takes the size" do
      for {f, opts} <- [{flow(draggable: false), []}, {flow(), [nodes_draggable: false]}] do
        resized = NodeChange.apply_changes(f, [resize("a")], opts)
        assert position(resized, "a") == {0.0, 0.0}
        assert resized.nodes["a"].width == 300
      end

      assert position(NodeChange.apply_changes(flow(), [resize("a")]), "a") == {999.0, 999.0}
    end

    test "a replace or add cannot swap a locked node for an unlocked copy" do
      for type <- ["replace", "add"] do
        swapped = NodeChange.apply_changes(flow(selectable: false), [replace_node(type, "a")])
        assert swapped.nodes["a"].selectable == false
        assert position(swapped, "a") == {0.0, 0.0}
      end

      replaced = NodeChange.apply_changes(flow(), [replace_node("replace", "a")])
      assert position(replaced, "a") == {5.0, 5.0}
    end

    test "remove skips nodes and edges that are not deletable" do
      remove = fn id -> %{"type" => "remove", "id" => id} end

      kept_node = NodeChange.apply_changes(flow(deletable: false), [remove.("a")])
      kept_edge = EdgeChange.apply_changes(flow([], deletable: false), [remove.("e1")])
      assert Map.has_key?(kept_node.nodes, "a")
      assert Map.has_key?(kept_edge.edges, "e1")

      refute Map.has_key?(NodeChange.apply_changes(flow(), [remove.("a")]).nodes, "a")
      refute Map.has_key?(EdgeChange.apply_changes(flow(), [remove.("e1")]).edges, "e1")
    end

    test "an edge change cannot connect to a node that is not connectable" do
      f = flow(connectable: false)

      moved_end = %{
        "type" => "replace",
        "edge" => %{"id" => "e1", "source" => "a", "target" => "c"}
      }

      new_edge = %{
        "type" => "replace",
        "edge" => %{"id" => "e9", "source" => "b", "target" => "c"}
      }

      refute Map.has_key?(EdgeChange.apply_changes(f, [add_edge("e2", "c", "a")]).edges, "e2")
      assert EdgeChange.apply_changes(f, [moved_end]).edges["e1"].target == "b"

      refute Map.has_key?(
               EdgeChange.apply_changes(flow(), [new_edge], nodes_connectable: false).edges,
               "e9"
             )

      assert Map.has_key?(EdgeChange.apply_changes(f, [add_edge("e2", "b", "c")]).edges, "e2")
      assert EdgeChange.apply_changes(flow(), [moved_end]).edges["e1"].target == "c"
    end

    test "a read-only flow refuses an add or replace over an existing node" do
      for opts <- [
            [nodes_draggable: false],
            [nodes_connectable: false],
            %{elements_selectable: false}
          ],
          type <- ["replace", "add"] do
        assert position(NodeChange.apply_changes(flow(), [replace_node(type, "a")], opts), "a") ==
                 {0.0, 0.0}
      end

      added = NodeChange.apply_changes(flow(), [replace_node("add", "z")], nodes_draggable: false)
      assert position(added, "z") == {5.0, 5.0}
    end

    test "a change with no ID or a bad position changes nothing" do
      f = flow(deletable: false)

      for change <- [
            %{"type" => "remove"},
            %{"type" => "remove", "id" => nil},
            %{"type" => "remove", "id" => "missing"},
            %{"type" => "replace", "node" => %{"position" => %{"x" => 1, "y" => 1}}},
            %{"type" => "add", "node" => %{"id" => "z"}},
            %{"type" => "position", "id" => "b", "position" => %{"x" => "1", "y" => 2}},
            %{"type" => "position", "id" => "b"}
          ] do
        assert NodeChange.apply_changes(f, [change]) == f
      end

      assert State.remove_node(f, nil) == f
    end

    test "an add or replace without a node or edge is dropped" do
      for type <- ["add", "replace"] do
        assert NodeChange.apply_changes(flow(), [%{"type" => type, "node" => nil}]) == flow()
        assert EdgeChange.apply_changes(flow(), [%{"type" => type, "edge" => "x"}]) == flow()
      end
    end

    test "a replace cannot unlock an edge" do
      replace = %{
        "type" => "replace",
        "edge" => %{"id" => "e1", "source" => "a", "target" => "b"}
      }

      kept = EdgeChange.apply_changes(flow([], selectable: false), [replace])
      assert kept.edges["e1"].selectable == false
    end
  end

  describe "reconnecting an edge" do
    defp reconnect(f, end_, node_id, opts \\ []) do
      params = %{"edge_id" => "e1", "end" => end_, "node_id" => node_id}
      State.reconnect_edge(f, params, opts).edges["e1"]
    end

    test "moves only an edge marked reconnectable" do
      assert reconnect(flow(), "target", "c").target == "b"
      assert reconnect(flow([], reconnectable: true), "target", "c").target == "c"
    end

    test "refuses a node that is not connectable, the flow option and an unknown end" do
      f =
        State.new(
          nodes: [
            Node.new("a", %{x: 0, y: 0}),
            Node.new("b", %{x: 1, y: 0}),
            Node.new("c", %{x: 2, y: 0}, %{}, connectable: false),
            Node.new("d", %{x: 3, y: 0})
          ],
          edges: [Edge.new("e1", "a", "b", reconnectable: true)]
        )

      assert reconnect(f, "target", "c").target == "b"
      assert reconnect(f, "source", "d", nodes_connectable: false).source == "a"
      assert reconnect(f, "source", "d", %{nodes_connectable: false}).source == "a"
      assert reconnect(f, "middle", "d") == f.edges["e1"]
      assert reconnect(f, "source", "d").source == "d"
    end

    test "keeps an edge on a node that is not connectable where it is" do
      f =
        State.new(
          nodes: [
            Node.new("lock", %{x: 0, y: 0}, %{}, connectable: false),
            Node.new("a", %{x: 1, y: 0}),
            Node.new("c", %{x: 2, y: 0})
          ],
          edges: [Edge.new("e1", "lock", "a", reconnectable: true)]
        )

      assert reconnect(f, "target", "c").target == "a"

      unlocked = State.update_node(f, "lock", connectable: true)
      assert reconnect(unlocked, "target", "c").target == "c"
    end

    test "runs the connection checks a new edge gets" do
      f = flow([], reconnectable: true) |> State.add_edge(Edge.new("e2", "a", "c"))

      assert reconnect(f, "target", "a").target == "b"
      assert reconnect(f, "target", "c").target == "b"

      refuse_c = fn _flow, params ->
        if params.target == "c", do: {:error, "no"}, else: :ok
      end

      f = flow([], reconnectable: true)
      assert reconnect(f, "target", "c", validators: [refuse_c]).target == "b"
      assert reconnect(f, "target", "c").target == "c"
    end
  end
end
