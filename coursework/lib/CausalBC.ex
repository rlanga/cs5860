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
      vt: %{}
    }
  end
  # for p <- participants, into: %{}, do: {p, 0}

  def start(name, participants) do
    in_state = update_in(init_state(name, participants), [:vt], fn v -> for p <- participants, into: v, do: {p, 0} end)
    pid = spawn(CausalBC, :run, [in_state])
    case :global.register_name(name, pid) do
      :yes -> pid
      :no -> :error
    end
  end

  def co_bc_send(msg, pid) do
    send(pid,{:input, :co_bc_send, msg})
  end

  def co_bc_recv(msg, upper_layer, origin) do
    send(upper_layer, {:output, :bc_receive, origin, msg})
  end

  def run(state) do
    state = receive do
      {:input, :co_bc_send, msg} ->
        state = update_in(state, [:vt, state.name], fn(t) -> t+1 end)
        co_bc_recv(msg, self(), self())
        bc_send(state, {:bc_msg, msg, state.vt[state], state.name})
        # Process i adds the triple (m,ts[i],i) to its pending list:
        update_in(state,
          [:pending],
          fn(ls) ->
            [{msg,state.vt[state.name], state.name} | ls]
          end
        )

      {:bc_msg, msg, vt, origin_name} ->
        bc_recv(state, msg, origin_name)

      {:output, :bc_receive, origin_name, msg} ->
        IO.puts("OUTPUT: #{state.name} CO-BCAST-delivered broadcast msg #{msg} from #{origin_name}")
    end
    readyMsgs = remove_pending(state, state.pending)

    if readyMsgs != [] do
      for {msg, _, j} <- readyMsgs do
        co_bc_recv(msg, self(), j)
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
  end

  def bc_recv(state, msg, origin_name) do
    update_in(state,
      [:pending],
      fn(ls) ->
        [{msg, state.vt[origin_name], origin_name} | ls]
      end
    )
  end

  # Gets messages to remove from 'pending' that satisfy the 3 conditions of co_bc_recv.
  # Attempts have been made Tail-recursive optimise it
  # condition 1: message is in pending. This is passed as function input
  def remove_pending(state, pending_msgs, acc \\ [])
  def remove_pending(state, [], acc) do
    # remove (m, w, j) from pending
    state = %{state | pending: state.pending -- acc}
    acc
  end
  def remove_pending(state, [{msg, v, j} | rest], acc) do
    checks = for p <- state.participants do
      # condition 2: w[j] == vt[j] + 1
      case p do
        p when p == j ->
          v == state.vt[p] + 1
        # condition 3: w[k] ≤ vt[k] for all k ≠ j
        p when p != j ->
          v <= state.vt[p]
      end
    end

    if not(Enum.member?(checks,false)) do
      # do: vt[j]++
      state = update_in(state, [:vt, j], fn(t) -> t+1 end)
      remove_pending(state, rest, [{msg, v, j} | acc])
    else
      remove_pending(state, rest, acc)
    end
  end

end
