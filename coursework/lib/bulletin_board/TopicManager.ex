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
    case role do
      :master ->
        pid = spawn(TopicManager, :run, [init_state(topic_name, role, 201)]) # higher ballot number than the rest
        :global.register_name(topic_name, pid)
        Enum.each(Node.list, fn n -> Node.spawn(n, TopicManager, :start, [topic_name, :replica]) end)
      :replica ->
        rid = spawn(TopicManager, :run, [init_state(topic_name, role, :rand.uniform(200))])
        send(rid, {:monitor_master})
        send(rid, {:register_globally})
    end
  end

  def run(state) do
    state = receive do
        {:monitor_master} ->
          Process.monitor(:global.whereis_name(state.topic_name))
          state
        {:register_globally} ->
          :global.register_name("#{state.topic_name}_replica_#{Node.self()}", self())
          state
        {:subscribe, user_name} ->
          # send(:global.whereis_name("mon"), {Node.self(), "#{user_name} subscribed to #{state.topic_name}"})
          add_subscriber(state, user_name)
        {:unsubscribe, user_name} ->
          # send(:global.whereis_name("mon"), {Node.self(), "#{user_name} unsubscribed from #{state.topic_name}"})
          remove_subscriber(state, user_name)
        {:publish, user, content} ->
          # send(:global.whereis_name("mon"), {Node.self(), "Publishing new content for #{state.topic_name}"})
          state = put_in(state, [:subscribers], Enum.filter(state.subscribers, fn s -> :global.whereis_name(s) != :undefined end))
          for u <- state.subscribers do
            send(:global.whereis_name(u), {:new_post, state.topic_name, user, content})
          end
          state
        {:DOWN, _, :process, _, _} ->
          # send(:global.whereis_name("mon"), {Node.self(), "Topic master down. Begin leader selection. Ballot: #{state.ballot_num}"})
          if length(Node.list) == 0 do
            # send(:global.whereis_name("mon"), {Node.self(), "Last one standing, becoming leader!"})
            :global.unregister_name("#{state.topic_name}_replica_#{Node.self()}")
            :global.register_name(state.topic_name, self())
            put_in(state, [:role], :master)
          else
            # use multi-Paxos algorithm to elect new leader
            # Phase 1: PREPARE leader
            state = update_in(state, [:ballot_num], fn(b) -> b + 1 end)
            for replica <- Node.list do
              send(:global.whereis_name("#{state.topic_name}_replica_#{replica}"), {:prepare, self(), state.ballot_num})
            end
            state
          end
        {:prepare, leader, ballot_num} ->
          # send(:global.whereis_name("mon"), {Node.self(), "PREPARE"})
          # Phase 1: PREPARE acceptor
          if ballot_num >= state.ballot_num do
            send(leader, {:promise, ballot_num, state.accept_num, state.accept_val})
            put_in(state, [:ballot_num], ballot_num)
          else
            state
          end
        {:promise, bal, accept_num, accept_val} ->
          # send(:global.whereis_name("mon"), {self(), "PROPOSE: #{accept_num} #{accept_val}"})
          if bal == state.ballot_num do
            propose(state, bal, accept_num, accept_val)
          else
            state
          end
        {:propose, b, v} ->
          # send(:global.whereis_name("mon"), {self(), "COMMIT #{b} #{v}"})
          commit(state, b, v)
        {:accept, b, v} -> decide(state, b, v)
        {:decide, v} -> put_in(state, [:subscribers], v)
      end
    run(state)
  end

  
  # Subscribes the new user to all the replicas and the master node
  defp add_subscriber(state, user) do
    if Enum.member?(state.subscribers, user) == false do
      state = update_in(state, [:subscribers], fn(subs) -> [user | subs] end)
      for replica <- Node.list do
        rid = :global.whereis_name("#{state.topic_name}_replica_#{replica}")
        case rid do
          :undefined ->
            Node.spawn(replica, TopicManager, :start, [state.topic_name, :replica])
            send(:global.whereis_name("#{state.topic_name}_replica_#{replica}"), {:propose, state.ballot_num, state.subscribers})
          r -> send(r, {:propose, state.ballot_num, state.subscribers})
        end
      end
      state
    else
      state
    end
  end

  # Removes a user from the subscriber list and sends PROPOSE instruction to update replica states  
   defp remove_subscriber(state, user) do
    state = update_in(state, [:subscribers], fn(subs) -> subs -- user end)
    for replica <- Node.list do
      send(:global.whereis_name("#{state.topic_name}_replica_#{replica}"), {:propose, state.ballot_num, state.subscribers})
    end
    state
   end

  '''
   Paxos phase 2: PROPOSE leader.
   This processes a PROMISE message if it's ballot number is equal to state.ballot_num.
   N.B: the ballot check is done in the run 'receive' function.
  '''
  defp propose(state, bal, accept_num, accept_val) do
    state = %{state | promises: [%{ballot: bal, accept_num: accept_num, accept_val: accept_val} | state.promises]}
    if length(state.promises) > length(Node.list) / 2 do
      state = put_in(state, [:role], :master)
      :global.unregister_name("#{state.topic_name}_replica_#{Node.self()}")
      :global.register_name(state.topic_name, self())
      # send(:global.whereis_name("mon"), {Node.self(), "node is now master topic manager"})
      # if all vals == null, mvVal = initial_val
      if Enum.map(state.promises, fn p -> p.accept_val end) |> Enum.empty? do
        put_in(state, [:subscribers], state.subscribers)
      else
        prom = hd(Enum.sort(state.promises, fn x, y -> x.ballot > y.ballot end))
        state = put_in(state, [:subscribers], prom.accept_val)
        Enum.each(Node.list, fn r -> send(:global.whereis_name("#{state.topic_name}_replica_#{r}"), {:propose, bal, prom.accept_val}) end)
        put_in(state, [:promises], [])
      end
    else
      state
    end
  end

  # Paxos phase 2: COMMIT acceptor. This is run when a PROPOSE message is received.
  defp commit(state, b, v) do
    if b >= state.ballot_num do
      state = put_in(state, [:accept_num], b) |> put_in([:accept_val], v)
      send_to_all(state, {:accept, b, v})
      state
    else
      state
    end
  end

  # Paxos - Deciding.
  defp decide(state, b, v) do
    state = %{state | accepts: [%{ballot: b, val: v} | state.accepts]}
    if length(state.accepts) > length(Node.list) / 2 do
      put_in(state, [:subscribers], v) |> put_in([:accepts], [])
    end
    state
  end

  defp send_to_all(state, msg) do
    Enum.map(Node.list,
      fn n ->
        if :global.whereis_name("#{state.topic_name}_replica_#{n}") == :undefined do
          :global.whereis_name(state.topic_name)
        else
          :global.whereis_name("#{state.topic_name}_replica_#{n}")
        end
      end)
    |> Enum.each(fn r -> send(r, msg) end)
  end

end