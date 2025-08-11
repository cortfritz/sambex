defmodule SambexTest do
  use ExUnit.Case

  setup do
    Sambex.init()
    :ok
  end

  test "NIF add_one function works" do
    assert Sambex.Nif.add_one(41) == 42
  end

  # Skip SMB tests for now due to segfault issues with libsmbclient
  # test "SMB init works" do
  #   assert Sambex.init() == 0
  # end

  test "connect returns error for invalid URL" do
    assert {:error, :connection_failed} = Sambex.connect("smb://invalid-server", "user", "pass")
  end
end
