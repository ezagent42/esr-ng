defmodule Esr.Behavior.ChatTest do
  @moduledoc """
  Phase 2a-step 3: Chat Behavior contract tests.

  Asserts the Behavior implements the contract surface (actions/0,
  state_slice/0, interface/0, invoke/4 stubs) and that the interface
  schema is well-formed against `Esr.InterfaceValidator`. Per-Kind
  registration + invoke bodies arrive in 2b — this file pins the
  contract so 2b can't accidentally regress it.
  """

  use ExUnit.Case, async: true
  alias Esr.Behavior.Chat
  alias Esr.InterfaceValidator
  alias Esr.Message

  describe "Behavior contract surface" do
    test "actions/0 returns the 4 K-path actions" do
      assert Chat.actions() == [:send, :receive, :join, :leave]
    end

    test "state_slice/0 returns :chat" do
      assert Chat.state_slice() == :chat
    end

    test "init_slice/1 returns empty map (2b fills per-Kind shape)" do
      assert Chat.init_slice(%{}) == %{}
    end

    test "interface/0 declares all 4 actions" do
      keys = Chat.interface() |> Map.keys() |> Enum.sort()
      assert keys == [:join, :leave, :receive, :send]
    end
  end

  describe "invoke/4 (2a stubs)" do
    test "all 4 actions return :not_implemented_in_2a" do
      slice = Chat.init_slice(%{})

      for action <- [:send, :receive, :join, :leave] do
        assert {:error, :not_implemented_in_2a} = Chat.invoke(action, slice, %{}, %{})
      end
    end
  end

  describe "interface schema validates real Message envelope" do
    test ":send action's message schema accepts a fully-formed Message" do
      sender = URI.new!("user://admin")

      message =
        sender
        |> Message.new(%{text: "hi", attachments: []})
        |> Map.from_struct()

      schema = Chat.interface()[:send].args
      assert :ok = InterfaceValidator.validate(%{message: message}, schema)
    end

    test ":join action's args schema accepts a URI member" do
      schema = Chat.interface()[:join].args
      assert :ok = InterfaceValidator.validate(%{member: URI.new!("user://admin")}, schema)
    end

    test ":join rejects bare-string member (URI must be %URI{})" do
      schema = Chat.interface()[:join].args

      assert {:error, {:invalid_args, _}} =
               InterfaceValidator.validate(%{member: "user://admin"}, schema)
    end
  end
end
