defmodule LiveFlow.Collaboration.UserTest do
  use ExUnit.Case, async: true

  alias LiveFlow.Collaboration.User

  describe "collaborator colors" do
    test "a color that is not a plain color value falls back to the default" do
      default = User.new("u1").color

      for bad <- ["red;position:fixed", "url(https://example.com/x)", "#fff\" onload=\"x", 12] do
        assert User.new("u1", color: bad).color == default
      end

      for good <- ["#ef4444", "#abc", "rebeccapurple", "rgb(1, 2, 3)", "hsl(200 50% 40% / 0.5)"] do
        assert User.new("u1", color: good).color == good
      end
    end
  end
end
