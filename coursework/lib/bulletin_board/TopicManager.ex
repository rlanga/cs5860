defmodule TopicManager do

  def init_state(topic_name, initial_role) do
    %{
      topic_name: topic_name,
      subscribers: [],
      inbox: [],
      role: initial_role
    }
  end

  '''
  A new topic will be started by spawning a topic process and adding this to the global registry
  User will then be added to the newly created topic
  Topic manager can have a role of either :master or :replica
  '''
  def start(topic_name, role) do
    pid = spawn(TopicManager, :run, [init_state(topic_name, role)])
    :global.register_name(topic_name, pid)
    pid
  end

  def run(state) do
    receive do
      {:subscribe, user_name} ->
        state = update_in(state, [:subscribers], fn(subs) -> [user_name | subs] end)
    end
  end

  defp update_replicas()
end