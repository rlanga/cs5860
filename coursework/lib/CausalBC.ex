defmodule CausalBC do
  @moduledoc """
  Causal Broadcast algorithm implementation.
  Certain functions have been adapted from the TOBroadcast Module from Moodle
  """

  def init_state(name, participants) do
    %{
      name: name,
      participants: participants,
      pending: [],
      outbox: [],
      vt: %{}
    }
  end

  def start(name, participants) do
    in_state = update_in(init_state(name, participants), [:vt], fn v -> for p <- participants, into: v, do: {p, 0} end)
    pid = spawn(CausalBC, :run, [in_state])
    send(pid, {:register_globally})
  end

  def co_bc_send(msg, name) do
    send(:global.whereis_name(name), {:input, :co_bc_send, msg})
  end

  def co_bc_recv(msg, upper_layer, origin) do
    send(upper_layer, {:bc_rcvd, msg, origin})
  end

  def run(state) do
#    IO.puts("#{state.name}'s timestamp estimates (ts): " <> inspect(state.vt))
    state = receive do
      {:register_globally} ->
        :global.register_name(state.name, self())
        state
      {:input, :co_bc_send, msg} ->
        :global.whereis_name(state.name)
        state = update_in(state, [:vt, state.name], fn(t) -> t+1 end)
        co_bc_recv(msg, self(), state.name)
        bc_send(state, {:bc_msg, msg, state.vt, state.name})
      {:bc_msg, msg, vt, origin_name} ->
        bc_recv(state, msg, vt, origin_name)
      {:bc_rcvd, msg, origin} ->
        IO.puts("OUTPUT: #{state.name} CO-BCAST-delivered broadcast msg #{msg} from #{origin}\n")
        Process.sleep(1000)
        state
    end
    state = remove_pending(state, state.pending)

    out = state.outbox
    state = put_in(state, [:outbox], [])
    if Enum.empty?(out) == false do
      for o <- out do
        co_bc_recv(o.msg, self(), o.origin)
      end
    end
    run(state)
  end

  def bc_send(state, msg) do
    for p <- List.delete(state.participants, state.name) do
      case :global.whereis_name(p) do
        :undefined -> IO.puts("ERROR participant #{p} has already terminated!")
        pid -> send(pid, msg)
      end
    end
    state
  end

  def bc_recv(state, msg, vt, origin_name) do
    update_in(state,
      [:pending],
      fn(ls) ->
        [%{msg: msg, vt: vt, origin: origin_name} | ls]
      end
    )
  end

  @doc """
  Gets messages to remove from 'pending' that satisfy the 3 conditions of co_bc_recv.
  Attempts have been made Tail-recursive optimise it
  """
  def remove_pending(state, pending, acc \\ [])
  def remove_pending(state, [], acc) do
    if Enum.empty?(acc) do
      state
    else
      # remove (m, w, j) from pending
      update_in(state, [:outbox], fn m -> m ++ acc end)
      |> update_in([:pending], fn p -> p -- acc end)
    end
  end
  def remove_pending(state, [pend | rest], acc) do
    parts_except_j = List.delete(state.participants, pend.origin)
    
    # w[k] ≤ vt[k] for all k ≠ j
    condition3 =  length(Enum.filter(parts_except_j, fn k -> pend.vt[k] <= state.vt[k] end)) == length(parts_except_j)

    if pend.vt[pend.origin] == state.vt[pend.origin] + 1 and condition3 do
#      IO.puts("all conds met")
      # do: vt[j]++
      state = update_in(state, [:vt, pend.origin], fn(t) -> t+1 end)
      remove_pending(state, rest, [pend | acc])
    else
#      IO.puts("conds not met")
      remove_pending(state, rest, acc)
    end
  end
end

# CausalBC.start("p1", ["p1","p2","p3","p4"])
# CausalBC.start("p2", ["p1","p2","p3","p4"])
# CausalBC.start("p3", ["p1","p2","p3","p4"])
# CausalBC.start("p4", ["p1","p2","p3","p4"])

# Process.sleep(500)

# CausalBC.co_bc_send("Hi", "p2")
# Process.sleep(50)
# CausalBC.co_bc_send("How are you?", "p2")
# Process.sleep(50)
# CausalBC.co_bc_send("I'm good myself", "p2")
# Process.sleep(50)
# CausalBC.co_bc_send("Hi p1!", "p1")
