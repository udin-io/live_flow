defmodule LiveFlow.Changes.Guard do
  @moduledoc false
  # Shared reads for the server-side checks on changes a browser sends. The
  # browser hides drag, connect, select and delete when the flow or an element
  # turns them off; these helpers let the server refuse the same changes.

  @doc "Reads a change field by string or atom key."
  def field(change, key) when is_map(change) and is_binary(key) do
    case Map.fetch(change, key) do
      {:ok, value} -> value
      :error -> Map.get(change, String.to_existing_atom(key))
    end
  end

  def field(_change, _key), do: nil

  @doc "The change's type as a string, whether it was written with atoms or strings."
  def type(change) do
    case field(change, "type") do
      type when is_atom(type) and not is_nil(type) -> Atom.to_string(type)
      type -> type
    end
  end

  @doc "True when a select change selects. Any value but `false` or `nil` selects."
  def selects?(change), do: field(change, "selected") not in [false, nil]

  @doc "False only when the flow option is set to `false`."
  def enabled?(opts, key) when is_list(opts) or is_map(opts), do: opts[key] != false
  def enabled?(_opts, _key), do: true

  @doc "True when the stored element exists and turns off any of the given flags."
  def locked?(nil, _flags), do: false
  def locked?(element, flags), do: Enum.any?(flags, &(Map.get(element, &1) == false))

  @doc "True for a map with numeric `x` and `y`, by string or atom keys."
  def position?(position) when is_map(position),
    do: is_number(field(position, "x")) and is_number(field(position, "y"))

  def position?(_position), do: false

  @doc "Turns a keyword list or a map of options into a keyword list."
  def to_keyword(opts) when is_map(opts), do: Map.to_list(opts)
  def to_keyword(opts) when is_list(opts), do: opts
  def to_keyword(_opts), do: []
end
