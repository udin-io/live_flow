defmodule LiveFlow.Changes.NodeChange do
  @moduledoc """
  Node change event types for LiveFlow.

  Node changes describe mutations to nodes that are sent from the JS hook
  to the LiveView. These follow the xyflow pattern of immutable state changes.

  ## Change Types

    * `:position` - Node was moved
    * `:dimensions` - Node dimensions were measured/changed
    * `:select` - Node selection changed
    * `:remove` - Node was removed
    * `:add` - Node was added
    * `:replace` - Node was replaced entirely

  ## Examples

      # Position change from JS drag
      %{"type" => "position", "id" => "node-1", "position" => %{"x" => 100, "y" => 200}, "dragging" => false}

      # Dimensions change after node render
      %{"type" => "dimensions", "id" => "node-1", "width" => 150, "height" => 50}
  """

  alias LiveFlow.{Node, State}
  alias LiveFlow.Changes.Guard

  @type position_change :: %{
          type: :position,
          id: String.t(),
          position: %{x: number(), y: number()},
          dragging: boolean()
        }

  @type dimensions_change :: %{
          type: :dimensions,
          id: String.t(),
          width: number(),
          height: number()
        }

  @type selection_change :: %{
          type: :select,
          id: String.t(),
          selected: boolean()
        }

  @type remove_change :: %{
          type: :remove,
          id: String.t()
        }

  @type add_change :: %{
          type: :add,
          node: map()
        }

  @type replace_change :: %{
          type: :replace,
          node: map()
        }

  @type t ::
          position_change()
          | dimensions_change()
          | selection_change()
          | remove_change()
          | add_change()
          | replace_change()

  @doc """
  Applies a single change to the state.
  """
  @spec apply_change(State.t(), map()) :: State.t()
  def apply_change(state, %{"type" => "position"} = change) do
    id = change["id"]
    position = normalize_position(change["position"])
    dragging = change["dragging"] || false

    State.update_node(state, id, fn node ->
      %{node | position: position, dragging: dragging}
    end)
  end

  def apply_change(state, %{"type" => "dimensions"} = change) do
    id = change["id"]
    width = change["width"]
    height = change["height"]

    State.update_node(state, id, fn node ->
      Node.set_dimensions(node, width, height)
    end)
  end

  def apply_change(state, %{"type" => "select"} = change) do
    id = change["id"]
    selected = change["selected"]

    if selected do
      State.select_node(state, id, multi: true)
    else
      State.deselect_node(state, id)
    end
  end

  def apply_change(state, %{"type" => "remove"} = change) do
    State.remove_node(state, change["id"])
  end

  def apply_change(state, %{"type" => "add"} = change) do
    node_data = change["node"]

    node =
      Node.new(
        node_data["id"],
        normalize_position(node_data["position"]),
        Map.get(node_data, "data", %{}),
        type: parse_node_type(node_data["type"])
      )

    State.add_node(state, node)
  end

  def apply_change(state, %{"type" => "replace"} = change) do
    node_data = change["node"]

    node =
      Node.new(
        node_data["id"],
        normalize_position(node_data["position"]),
        Map.get(node_data, "data", %{}),
        type: parse_node_type(node_data["type"])
      )

    state
    |> State.remove_node(node.id)
    |> State.add_node(node)
  end

  # Handle atom keys (when created from Elixir)
  def apply_change(state, %{type: _} = change) do
    apply_change(state, stringify_keys(change))
  end

  def apply_change(state, _unknown_change), do: state

  @doc """
  Applies a list of changes from the browser to the state.

  The changes pass through `allowed_changes/3` first, so a change the browser
  would never send for a locked node is dropped. Use `apply_change/2` for
  changes your own server code makes.

  ## Options

  Pass the flow's own read-only options (a keyword list or a map), the same
  ones the Flow component gets:

    * `:nodes_draggable` - `false` drops position changes
    * `:elements_selectable` - `false` drops changes that select a node
  """
  @spec apply_changes(State.t(), [map()], keyword() | map()) :: State.t()
  def apply_changes(state, changes, opts \\ []) when is_list(changes) do
    state
    |> allowed_changes(changes, opts)
    |> Enum.reduce(state, &apply_change(&2, &1))
  end

  @doc """
  Returns the changes from the browser that the server lets through.

  A node keeps what its own fields turn off, and the flow keeps what its
  options turn off (see `apply_changes/3`):

    * `draggable: false` or `nodes_draggable: false` - position changes are
      dropped, and a resize keeps the node where it is
    * `selectable: false` or `elements_selectable: false` - select changes
      are dropped; deselecting still works
    * `deletable: false`, or an ID the flow does not hold - remove changes
      are dropped. Removing a node
      still removes its edges and children, as `State.delete_selected/1` does
    * any of `draggable`, `connectable`, `selectable` or `deletable` set to
      `false` - an add or replace with the node's ID is dropped, so the
      browser cannot swap the node for an unlocked copy; with any of the
      flow options above set to `false`, no add or replace may reuse an
      existing node's ID

  Positions that a client-side layout sends are position changes too: lay out
  flows with locked nodes on the server (`LiveFlow.Layout`).
  """
  @spec allowed_changes(State.t(), [map()], keyword() | map()) :: [map()]
  def allowed_changes(state, changes, opts \\ []) when is_list(changes) do
    Enum.flat_map(changes, &allow(state, &1, opts))
  end

  @locks [:draggable, :connectable, :selectable, :deletable]

  defp allow(state, change, opts) do
    node = State.get_node(state, Guard.field(change, "id"))

    case Guard.type(change) do
      "position" ->
        keep(change, Guard.position?(Guard.field(change, "position")) and draggable?(node, opts))

      "resize" ->
        position = Guard.field(change, "position")

        cond do
          not (is_nil(position) or Guard.position?(position)) -> []
          draggable?(node, opts) -> [change]
          true -> [without_position(change)]
        end

      "select" ->
        keep(change, not Guard.selects?(change) or selectable?(node, opts))

      "remove" ->
        keep(change, match?(%Node{deletable: true}, node))

      type when type in ["add", "replace"] ->
        new = Guard.field(change, "node")
        stored = State.get_node(state, Guard.field(new, "id"))

        keep(
          change,
          is_map(new) and is_binary(Guard.field(new, "id")) and
            Guard.position?(Guard.field(new, "position")) and
            not Guard.locked?(stored, @locks) and
            (is_nil(stored) or read_write?(opts))
        )

      _ ->
        [change]
    end
  end

  # A read-only flow never swaps an existing node, which would move or reset it
  defp read_write?(opts),
    do:
      Enum.all?(
        [:nodes_draggable, :nodes_connectable, :elements_selectable],
        &Guard.enabled?(opts, &1)
      )

  defp keep(change, true), do: [change]
  defp keep(_change, false), do: []

  defp draggable?(node, opts),
    do: Guard.enabled?(opts, :nodes_draggable) and not match?(%Node{draggable: false}, node)

  defp selectable?(node, opts),
    do: Guard.enabled?(opts, :elements_selectable) and not match?(%Node{selectable: false}, node)

  defp without_position(change), do: Map.drop(change, ["position", :position])

  @doc """
  Creates a position change.
  """
  @spec position(String.t(), map(), boolean()) :: map()
  def position(id, position, dragging \\ false) do
    %{
      "type" => "position",
      "id" => id,
      "position" => position,
      "dragging" => dragging
    }
  end

  @doc """
  Creates a dimensions change.
  """
  @spec dimensions(String.t(), number(), number()) :: map()
  def dimensions(id, width, height) do
    %{
      "type" => "dimensions",
      "id" => id,
      "width" => width,
      "height" => height
    }
  end

  @doc """
  Creates a selection change.
  """
  @spec select(String.t(), boolean()) :: map()
  def select(id, selected) do
    %{
      "type" => "select",
      "id" => id,
      "selected" => selected
    }
  end

  @doc """
  Creates a remove change.
  """
  @spec remove(String.t()) :: map()
  def remove(id) do
    %{
      "type" => "remove",
      "id" => id
    }
  end

  defp normalize_position(%{"x" => x, "y" => y}), do: %{x: x / 1.0, y: y / 1.0}
  defp normalize_position(%{x: x, y: y}), do: %{x: x / 1.0, y: y / 1.0}

  defp stringify_keys(map) when is_map(map) do
    map
    |> Enum.map(fn
      {k, v} when is_atom(k) -> {Atom.to_string(k), stringify_keys(v)}
      {k, v} -> {k, stringify_keys(v)}
    end)
    |> Map.new()
  end

  defp stringify_keys(value), do: value

  # A node type the client names must already exist as an atom; anything else
  # draws as a default node instead of crashing the page.
  defp parse_node_type(type) when is_binary(type) do
    String.to_existing_atom(type)
  rescue
    ArgumentError -> :default
  end

  defp parse_node_type(type) when is_atom(type) and not is_nil(type), do: type
  defp parse_node_type(_type), do: :default
end
