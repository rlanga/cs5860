defmodule TopicManager do

  def init_state(topic_name, initial_role, ballot_num) do
    %{
      topic_name: topic_name,
      subscribers: [],
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
    pid = spawn(TopicManager, :run, [init_state(topic_name, role, :rand.uniform(200))])
    case role do
      :master ->
        :global.register_name(topic_name, pid)
        Enum.each(Node.list, fn n -> send(:global.whereis_name(n), {:new_topic, topic_name}) end)
      :replica ->
        # monitor only master?
        Node.monitor(topic_name, true)
    end
    pid
  end

  def run(state) do
    receive do
      {:subscribe, user_name} ->
        state = add_subscriber(state, user_name)
      {:unsubscribe, user_name} ->
        state = remove_subscriber(state, user_name)
      {:publish, user, content} ->
        for u <- List.delete(state.subscribers, user) do
          send(:global.whereis_name(u), {:new_post, state.topic_name, content})
        end
      {:nodedown, _} ->
        # use multi-Paxos algorithm to elect new leader
        # Phase 1: PREPARE leader
        state = update_in(state, [:ballot, :num], fn(b) -> b + 1 end)
        for node <- Node.list do
          send(:global.whereis_name(node), {:prepare, self(), state.ballot})
        end
      {:prepare, leader, ballot_num} ->
        # Phase 1: PREPARE acceptor
        if ballot_num >= state.ballot_num
          state = put_in(state, [:ballot_num], ballot_num)
          send(leader, {:promise, ballot_num, state.accept_num, state.accept_val})
      {:promise, bal, accept_num, accept_val} ->
        if bal == state.ballot_num do
          state = propose(state, bal, accept_num, accept_val)
        end
      {:propose, b, v} ->
        state = commit(state, b, v)
      {:accept, b, v} -> 2
      {:decide, v} ->
        state = put_in(state, [:subscribers], v)
    end
    run(state)
  end

  '''
  Subscribes the new user to all the replicas and the master node
  '''
  defp add_subscriber(state, user) do
    for node <- Node.list do
      send(:global.whereis_name(node), {:subscribe, user})
    end
    update_in(state, [:subscribers], fn(subs) -> [user | subs] end)
  end

   defp remove_subscriber(state, user) do
    for node <- Node.list do
      send(:global.whereis_name(node), {:unsubscribe, user})
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
        state = put_in(state, [:subscribers], state.subscribers)
      else
        my_val = hd(Enum.sort(state.promises, &(elem(&1, 0) > elem(&2, 0))))
        state = put_in(state, [:subscribers], my_val)
        Enum.each(Node.list, fn n -> send(:global.whereis_name(n), {:propose, bal, my_val}) end)
        state = put_in(state, [:promises], [])
      end
    end
  end

  # Paxos phase 2: COMMIT acceptor
  defp commit(state, b, v) do
    if b >= state.ballot_num do
      state.accept_num = b
      state.accept_val = v
      Enum.each(Node.list, fn n -> send(:global.whereis_name(n), {:accept, b, v}) end)
    end
    state
  end

  # Paxos - Deciding.
  defp decide(state, b, v) do
    state = %{state | accepts: [%{ballot: b, val: v} | state.accepts]}
    if length(state.accepts) > length(Node.list) / 2 do
      state = put_in(state, [:subscribers], v)
      state = put_in(state, [:accepts], [])
    end
  end

end