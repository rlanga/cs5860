defmodule UserTest do
  use ExUnit.Case
  doctest User

  test "creating a new user" do
    assert User.start("User") == {:ok, "User registration successful"}
  end

  test "subscribing a user to a topic" do
    user = "user"
    topic = "test"
    User.start(user)
    assert User.subscribe(user, topic) == {:ok, "#{user} subscribed to #{topic}"}
  end

  test "unsubscribing a user fom a topic" do
    user = "user"
    topic = "test"
    User.start(user)
    User.subscribe(user, topic)
    assert User.unsubscribe(user, topic) == {:ok, "#{user} unsubscribed from #{topic}"}
  end

#  test "posting content to a topic" do
#    nodes = LocalCluster.start_nodes("test_cluster", 3)
#
#    [node1, node2] = nodes
#
#    for node <- nodes do
#      Node.spawn(node, User, :start, ["user #{:rand.uniform(20)}"])
#      Node.spawn(node, User, :subscribe, ["user #{:rand.uniform(20)}"])
#    end
#
#    :ok = LocalCluster.stop()
#  end
end
