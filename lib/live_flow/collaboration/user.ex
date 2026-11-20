defmodule LiveFlow.Collaboration.User do
  @moduledoc """
  Represents a user in a collaborative flow session.

  ## Fields

    * `:id` - Unique user identifier (required)
    * `:name` - Display name (auto-generated if not provided)
    * `:color` - Cursor/highlight color as hex string (auto-generated if not provided)

  ## Examples

      iex> user = LiveFlow.Collaboration.User.new("user_123")
      iex> user.id
      "user_123"

      iex> user = LiveFlow.Collaboration.User.new("user_123", name: "Alice", color: "#ef4444")
      iex> user.name
      "Alice"
  """

  @type t :: %__MODULE__{
          id: String.t(),
          name: String.t(),
          color: String.t()
        }

  defstruct [:id, :name, :color]

  @colors ~w(#ef4444 #f97316 #f59e0b #22c55e #14b8a6 #3b82f6 #8b5cf6 #ec4899 #06b6d4 #84cc16)

  @doc """
  Creates a new user with the given ID.

  Options:
    * `:name` - Display name. Defaults to "User N" where N is derived from the ID.
    * `:color` - A hex (`#rgb`, `#rrggbb`, `#rrggbbaa`), `rgb()`/`hsl()` or
      named CSS color. Any other value, or none, gives a color chosen from
      the ID, because other users' pages draw it.
  """
  @spec new(String.t(), keyword()) :: t()
  def new(id, opts \\ []) do
    hash = :erlang.phash2(id)
    default_color = Enum.at(@colors, rem(hash, length(@colors)))

    %__MODULE__{
      id: id,
      name: Keyword.get(opts, :name, "User #{rem(hash, 99) + 1}"),
      color: safe_color(Keyword.get(opts, :color), default_color)
    }
  end

  @color_format ~r/\A(?:#[0-9a-fA-F]{3,8}|[a-zA-Z]{3,20}|(?:rgb|rgba|hsl|hsla)\([0-9.,%\s\/]{1,60}\))\z/

  @doc false
  def safe_color(color, default) when is_binary(color) do
    if Regex.match?(@color_format, color), do: color, else: default
  end

  def safe_color(_color, default), do: default

  @doc """
  Returns the user data as a map suitable for Presence metadata.
  """
  @spec to_presence_meta(t()) :: map()
  def to_presence_meta(%__MODULE__{} = user) do
    %{
      name: user.name,
      color: user.color,
      joined_at: System.system_time(:second)
    }
  end
end
