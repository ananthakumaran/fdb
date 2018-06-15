defmodule FDB.OptionTest do
  use ExUnit.Case
  import FDB.Option

  test "verify" do
    assert verify_network_option(network_option_buggify_enable()) == true

    assert_raise ArgumentError, fn ->
      verify_network_option(network_option_buggify_enable(), 0)
    end

    assert_raise ArgumentError, fn ->
      verify_network_option(network_option_cluster_file())
    end

    assert_raise ArgumentError, fn ->
      verify_network_option(network_option_cluster_file(), <<0xFFFF>>)
    end

    assert_raise ArgumentError, fn ->
      verify_network_option(network_option_cluster_file(), 1)
    end

    assert_raise ArgumentError, fn ->
      verify_network_option(network_option_tls_ca_bytes(), 1)
    end

    assert_raise ArgumentError, fn ->
      verify_network_option(network_option_external_client_transport_id(), "hello")
    end

    assert_raise ArgumentError, fn ->
      verify_network_option(network_option_external_client_transport_id(), 1.0)
    end

    assert verify_network_option(network_option_cluster_file(), "test") == true
    assert verify_network_option(network_option_tls_ca_bytes(), "test") == true
    assert verify_network_option(network_option_tls_ca_bytes(), <<0xFFFF>>) == true

    assert verify_network_option(network_option_external_client_transport_id(), 1) == true
  end
end
