defmodule TopicManager do

  def init_state(topic_name, initial_role, ballot_num) do
    %{
      topic_name: topic_name,
      subscribers: [],
      replica_ids: [],
      role: initial_role,
      ballot_num: ballot_num,
      accept_num: 1,
      accept_val: [],
      promises: [],
      accepts: []
    }
  end

  '''
  A new topic will be started by spawning a topic process and adding this to the global registry
  User will then be added to the newly created topic
  Topic manager can have a role of either :master or :replica
  '''
  def start(topic_name, role) do
    case role do
      :master ->
        pid = spawn(TopicManager, :run, [init_state(topic_name, role, 201)]) # higher ballot number than the rest
        :global.register_name(topic_name, pid)
        Enum.each(Node.list, fn n -> Node.spawn(n, TopicManager, :start, [topic_name, :replica]) end)
      :replica ->
        # monitor only master?
        Process.monitor(:global.whereis_name(topic_name))
        rid = spawn(TopicManager, :run, [init_state(topic_name, role, :rand.uniform(200))])
        send(:global.whereis_name(topic_name), {:replica_id, rid})
    end
  end

  def run(state) do
    state = receive do
        {:replica_id, id} ->
          IO.puts("Replica added")
          add_replica(state, id)
        {:subscribe, user_name} ->
          IO.puts("#{user_name} subscribed to #{state.topic_name}")
          add_subscriber(state, user_name)
        {:unsubscribe, user_name} ->
          IO.puts("#{user_name} unsubscribed from #{state.topic_name}")
          remove_subscriber(state, user_name)
        {:publish, user, content} ->
          IO.puts("Publishing new content for #{state.topic_name}")
          for u <- List.delete(state.subscribers, user) do
            send(:global.whereis_name(u), {:new_post, state.topic_name, user, content})
          end
          state
        {:DOWN, _, :process, _, _} ->
          IO.puts("Topic master down. Begin leader selection")
          # use multi-Paxos algorithm to elect new leader
          # Phase 1: PREPARE leader
          state = update_in(state, [:ballot_num], fn(b) -> b + 1 end)
          for replica <- state.replica_ids do
            send(:global.whereis_name(replica), {:prepare, self(), state.ballot_num})
          end
          state
        {:prepare, leader, ballot_num} ->
          # Phase 1: PREPARE acceptor
          if ballot_num >= state.ballot_num do
            send(leader, {:promise, ballot_num, state.accept_num, state.accept_val})
            put_in(state, [:ballot_num], ballot_num)
          else
            state
          end
        {:promise, bal, accept_num, accept_val} ->
          if bal == state.ballot_num do
            propose(state, bal, accept_num, accept_val)
          else
            state
          end
        {:propose, b, v} ->
          commit(state, b, v)
        {:accept, b, v} -> 2
        {:decide, v} ->
          put_in(state, [:subscribers], v)
      end
    run(state)
  end

  defp add_replica(state, id) do
    update_in(state, [:replica_ids], fn r -> [id | r] end)
  end

  '''
  Subscribes the new user to all the replicas and the master node
  '''
  defp add_subscriber(state, user) do
    for replica <- state.replica_ids do
      send(replica, {:subscribe, user})
    end
    update_in(state, [:subscribers], fn(subs) -> [user | subs] end)
  end

   defp remove_subscriber(state, user) do
    for replica <- state.replica_ids do
      send(replica, {:unsubscribe, user})
    end
    %{state | subscribers: state.subscribers -- user}
   end

  # Paxos phase 2: PROPOSE leader
  defp propose(state, bal, accept_num, accept_val) do
    state = %{state | promises: [%{ballot: bal, acc_num: accept_num, acc_val: accept_val} | state.promises]}
    if length(state.promises) > length(Node.list) / 2 do
      state = put_in(state, [:role], :master)
      :global.register_name(state.topic_name, self())
      IO.puts("node is now master topic manager")
      # if all vals == null, mvVal = initial_val
      if Enum.map(state.promises, fn p -> p.accept_val end) |> Enum.empty? do
        put_in(state, [:subscribers], state.subscribers)
      else
        my_val = hd(Enum.sort(state.promises, &(elem(&1, 0) > elem(&2, 0))))
        state = put_in(state, [:subscribers], my_val)
        Enum.each(state.replica_ids, fn r -> send(r, {:propose, bal, my_val}) end)
        put_in(state, [:promises], [])
      end
    else
      state
    end
  end

  # Paxos phase 2: COMMIT acceptor
  defp commit(state, b, v) do
    if b >= state.ballot_num do
      state = put_in(state, [:accept_num], b) |> put_in([:accept_val], v)
      List.delete(state.replicas, self())
      |> Enum.each(fn r -> send(r, {:accept, b, v}) end)
      state
    else
      state
    end
  end

  # Paxos - Deciding.
  defp decide(state, b, v) do
    %{state | accepts: [%{ballot: b, val: v} | state.accepts]}
    if length(state.accepts) > length(Node.list) / 2 do
      put_in(state, [:subscribers], v) |> put_in([:accepts], [])
    end
  end

end