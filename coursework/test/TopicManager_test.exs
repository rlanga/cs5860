defmodule TopicManagerTest do
  use ExUnit.Case
  doctest TopicManager

#  test "something with a required cluster" do
#    :ok = LocalCluster.start()
#
#    nodes = LocalCluster.start_nodes("my-cluster", 3)
#
#    [node1, node2, node3] = nodes
#
#    assert Node.ping(node1) == :pong
#    assert Node.ping(node2) == :pong
#    assert Node.ping(node3) == :pong
#
#    :ok = LocalCluster.stop_nodes([node1])
#
#    assert Node.ping(node1) == :pang
#    assert Node.ping(node2) == :pong
#    assert Node.ping(node3) == :pong
#
#    :ok = LocalCluster.stop()
#
#    assert Node.ping(node1) == :pang
#    assert Node.ping(node2) == :pang
#    assert Node.ping(node3) == :pang
#  end
end
