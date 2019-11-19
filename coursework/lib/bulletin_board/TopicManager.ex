defmodule TopicManager do

  def init_state(topic_name, initial_role) do
    %{
      topic_name: topic_name,
      subscribers: [],
#      inbox: [],
      role: initial_role,
      ballot: %{num: 1, pid: self()},
      promises: []
    }
  end

  '''
  A new topic will be started by spawning a topic process and adding this to the global registry
  User will then be added to the newly created topic
  Topic manager can have a role of either :master or :replica
  '''
  def start(topic_name, role, other_nodes) do
    pid = spawn(TopicManager, :run, [init_state(topic_name, role)])
    case role do
      :master -> :global.register_name("#{topic_name}_master", pid)
      :replica -> 
        :global.register_name("#{topic_name}_replica", pid)
        # monitor other nodes
        for node <- Node.list do
          Node.monitor(node, true)
        end
    end
    pid
  end

  def run(state) do
    receive do
      {:subscribe, user_name} ->
        state = add_subscriber(state, user_name)
      {:unsubscribe, user_name} ->
        state = remove_subscriber(state, user_name)
      {:post, content} -> 1
      {:nodedown, _} ->
        # use Paxos algorithm to elect new leader
        # Phase 1: PREPARE leader
        state = update_in(state, [:ballot, :num], fn(b) -> b + 1 end)
        for node <- Node.list do
          send(:global.whereis_name(node), {:prepare, self(), state.ballot})
        end
      {:prepare, leader, ballot} ->
        # Phase 1: PREPARE acceptor
        if ballot.num > state.ballot.num || ballot.num == state.ballot.num && ballot.pid > state.ballot.pid
          accept_num = state.ballot.num
          state = put_in(state, [:ballot], ballot)
          send(leader, {:promise, ballot, accept_num, state.subscribers})
      {:promise, bal, accept_num, accept_val} ->

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
  defp propose(state, {bal, accept_num, accept_val}) do
    if length(state.promises) < length(Node.list) / 2 do
      state = %{state | promises: [{bal, accept_num, accept_val} | state.promises]}
    else
      # if all vals == null, mvVal = initial_val
      if Enum.map(state.promises, fn {bal, acc_num, acc_val} -> acc_val end) |> Enum.empty? do
        state = put_in(state, [:subscribers], state.subscribers)
      else
        my_val = hd(Enum.sort(state.promises, &(elem(&1, 0) > elem(&2, 0))))
        state = put_in(state, [:subscribers], accept_val)
        Enum.each(Node.list, fn n -> send(:global.whereis_name(n), {:propose, bal, accept_val}) end)
      end
    end
  end

  # Paxos phase 2: COMMIT acceptor
  defp commit(state, b, v) do
    if b > state.ballot.num do

    end
  end

end