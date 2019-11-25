defmodule User do
  import TopicManager

#  def init_state(user_name, other_nodes) do
#    %{
#      name: user_name,
#      nodes: other_nodes
#    }
#  end

  def start(user_name) do
    pid = spawn(User, :run, [init_state(user_name)])
    case :global.register_name(name, pid) do
      :yes -> {:ok, "User registration successful"}
      :no ->
        send(pid, {:shutdown})
        {:error, "User name already registered"}
    end
  end

  def run(state) do
    receive do
      # This creates a 'replica' topic manager process on nodes other than master topic manager
      {:new_topic, topic_name} -> TopicManager.start(topic_name, :replica) # use bc-recv and bc-send
      {:shutdown} -> exit(:normal)
    end
  end
  
  def subscribe(user_name, topic_name) do
    case :global.whereis_name(topic_name) do
      pid -> send(pid, {:subscribe, user_name})
      :undefined ->
        pid = TopicManager.start(topic_name, :master)
        Process.sleep(1000)
        send(pid, {:subscribe, user_name})
    end
  end

  def unsubscribe(user_name, topic_name) do
  end

  def post(user_name, topic_name, content) do
  end

  def fetch_news() do
  end
end