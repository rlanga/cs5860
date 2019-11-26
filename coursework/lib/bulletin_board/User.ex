defmodule User do
  import TopicManager

  def init_state(parent_id) do
    %{
#      inbox: [],
      parent_id: parent_id
    }
  end

  def start(user_name) do
    pid = spawn(User, :run, [init_state(self())])
    case :global.register_name(user_name, pid) do
      :yes -> {:ok, "User registration successful"}
      :no ->
        send(pid, {:shutdown})
        {:error, "User name already registered"}
    end
  end

  def run(state) do
    receive do
      # This creates a 'replica' topic manager process on nodes other than master topic manager
      {:new_topic, topic_name} -> TopicManager.start(topic_name, :replica)
      {:new_post, topic, content} ->
#        state = %{state | inbox: state.inbox ++ [%{topic: topic, content: content}]}
        send(state.parent_id, {:inbox, topic, content})
      {:shutdown} -> exit(:normal)
    end
    run(state)
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
    send(:global.whereis_name(topic_name), {:unsubscribe, user_name})
  end

  def post(user_name, topic_name, content) do
    send(:global.whereis_name(topic_name), {:publish, user_name, content})
  end

  def fetch_news() do
    receive do
      {:inbox, topic, content} ->
        IO.puts("#{topic}: #{content}")  # sso-fifo
        fetch_news()
    end
  end
end