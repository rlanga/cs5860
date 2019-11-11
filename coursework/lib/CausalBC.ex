defmodule CausalBC do
  @moduledoc false

  def start(name, participants) do
    spawn(CausalBC, :better_name, [])
    :global.register_name(name, self())
  end

  def better_name(participants) do

  end

  def bc_send(msg, name) do

  end

  def listen() do
    receive do
      {:bc_rcvd, msg, origin} ->
        IO.puts("Message received from #{origin}: #{msg}")
    end
  end

end
