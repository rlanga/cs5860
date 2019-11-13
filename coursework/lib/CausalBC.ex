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
      vt: for p <- participants, into: %{}, do: {p, 0}
    }
  end

  def start(name, participants) do
    pid = spawn(CausalBC, :run, [init_state(name, participants)])
    case :global.register_name(name, pid) do
      :yes -> pid
      :no -> :error
    end
  end

  def co_bc_send(msg, pid) do
    send(pid,{:input, :co_bc_send, msg})
  end

  def co_bc_recv(state, msg, vt, origin_name) do
    remove_pending(state, state.pending)
  end

  def run(state) do
    state = receive do
      {:input, :co_bc_send, msg} ->
        state = update_in(state, [:vt, state.name], fn(t) -> t+1 end)
        co_bc_recv(state, msg)
        bc_send(state, {:bc_msg, msg, state.vt[state], state.name})
        # Process i adds the triple (m,ts[i],i) to its pending list:
        update_in(state,
          [:pending],
          fn(ls) ->
            [{msg,state.vt[state.name], state.name} | ls]
          end
        )

      {:bc_msg, msg, vt, origin_name} ->
        bc_recv(msg, origin_name)
    end
    run(state)
  end

  def bc_send(msg, name) do

  end

  def bc_recv(state, msg, origin_name) do
    update_in(state,
      [:pending],
      fn(ls) ->
        [{msg, state.vt[origin_name], origin_name} | ls]
      end
    )
  end

  # code adapted from TO_Broadcast.
  # Attempts have been made Tail-recursive optimise it
  def remove_pending(_, [], _), do: []
  def remove_pending(state, [{msg, v, j} | rest], acc \\ []) do
    checks = for p <- state.participants do
      v <= state.vt[p]
    end

    if not(Enum.member?(checks,false)) do
      # all the checks passed, so this message can be removed from pending.
      # To do so, we append it to the list that we return.
      # Then we recursively process the rest of the "pending" list:
      remove_pending(state, rest, [{msg, v, j} | acc])
    else
      # at least one of the checks failed, so this message can't be removed yet,
      # and hence we do not add it to the returned result list.
      # Now, we look at the next message in pending:
      remove_pending(state, rest, acc)
    end
  end

end
