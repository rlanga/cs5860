defmodule User do
#  import TopicManager, only: [start: 2]

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
      {:new_post, topic, sender, content} ->
#        state = %{state | inbox: state.inbox ++ [%{topic: topic, content: content}]}
        send(state.parent_id, {:inbox, topic, sender, content})
        IO.puts("New content received! Check inbox")
      {:shutdown} -> exit(:normal)
    end
    run(state)
  end
  
  def subscribe(user_name, topic_name) do
    case :global.whereis_name(topic_name) do
      :undefined ->
        TopicManager.start(topic_name, :master)
        Process.sleep(500)
        send(:global.whereis_name(topic_name), {:subscribe, user_name})
        {:ok, "#{user_name} subscribed to #{topic_name}"}
      pid ->
        send(pid, {:subscribe, user_name})
        {:ok, "#{user_name} subscribed to #{topic_name}"}
    end
  end

  def unsubscribe(user_name, topic_name) do
    send(:global.whereis_name(topic_name), {:unsubscribe, user_name})
    {:ok, "#{user_name} unsubscribed from #{topic_name}"}
  end

  def post(user_name, topic_name, content) do
    send(:global.whereis_name(topic_name), {:publish, user_name, content})
  end

  def fetch_news() do
    receive do
      {:inbox, topic, sender, content} ->
        IO.puts("#{topic} | #{sender}: #{content}")  # sso-fifo
        fetch_news()
    after
      500 -> IO.puts("~~ No more news to report. Check back later :) ~~")
    end
  end
end