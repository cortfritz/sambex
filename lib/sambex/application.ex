defmodule Sambex.Application do
  @moduledoc """
  Application module for Sambex.

  This module starts the connection supervisor that manages
  SMB connection processes and their registry.
  """

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      Sambex.ConnectionSupervisor
    ]

    opts = [strategy: :one_for_one, name: Sambex.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
