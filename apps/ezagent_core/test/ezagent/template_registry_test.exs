defmodule Ezagent.TemplateRegistryTest do
  use ExUnit.Case, async: false

  alias Ezagent.TemplateRegistry

  defmodule FakeClassA do
    @behaviour Ezagent.Kind.Template
    @impl true
    def template_name, do: "registry-test.a-#{System.unique_integer([:positive])}"
    @impl true
    def validate(_), do: :ok
    @impl true
    def instantiate(_, _, _), do: {:ok, []}
  end

  defmodule FakeClassB do
    @behaviour Ezagent.Kind.Template
    @impl true
    def template_name, do: "registry-test.b-#{System.unique_integer([:positive])}"
    @impl true
    def validate(_), do: :ok
    @impl true
    def instantiate(_, _, _), do: {:ok, []}
  end

  describe "register/1 + lookup/1" do
    test "registers a class module under its template_name/0" do
      module = make_class("rt-#{System.unique_integer([:positive])}")
      assert :ok = TemplateRegistry.register(module)

      assert {:ok, ^module} = TemplateRegistry.lookup(module.template_name())
    end

    test "lookup returns :error for unregistered name" do
      assert :error = TemplateRegistry.lookup("never-registered-#{System.unique_integer()}")
    end

    test "registering the same module twice is idempotent" do
      module = make_class("rt-dup-#{System.unique_integer([:positive])}")
      assert :ok = TemplateRegistry.register(module)
      assert :ok = TemplateRegistry.register(module)
    end

    test "registering two different modules with the SAME template_name errors" do
      name = "shared-name-#{System.unique_integer([:positive])}"

      mod_a = make_class_with_name(name, :a)
      mod_b = make_class_with_name(name, :b)

      assert :ok = TemplateRegistry.register(mod_a)

      assert {:error, {:duplicate, ^mod_a, ^mod_b}} = TemplateRegistry.register(mod_b)
    end
  end

  describe "registered_template_names/0" do
    test "lists every registered name" do
      n1 = "list-a-#{System.unique_integer([:positive])}"
      n2 = "list-b-#{System.unique_integer([:positive])}"

      :ok = TemplateRegistry.register(make_class_with_name(n1, :a))
      :ok = TemplateRegistry.register(make_class_with_name(n2, :b))

      names = TemplateRegistry.registered_template_names()
      assert n1 in names
      assert n2 in names
    end
  end

  # --- helpers (define throwaway modules per-test for isolation) -------

  defp make_class(name) do
    module_name = String.to_atom("Elixir.TestClass_#{name}")
    body =
      quote do
        @behaviour Ezagent.Kind.Template
        @impl true
        def template_name, do: unquote(name)
        @impl true
        def validate(_), do: :ok
        @impl true
        def instantiate(_, _, _), do: {:ok, []}
      end

    Module.create(module_name, body, Macro.Env.location(__ENV__))
    module_name
  end

  defp make_class_with_name(name, tag) do
    module_name = String.to_atom("Elixir.TestClass_#{name}_#{tag}")
    body =
      quote do
        @behaviour Ezagent.Kind.Template
        @impl true
        def template_name, do: unquote(name)
        @impl true
        def validate(_), do: :ok
        @impl true
        def instantiate(_, _, _), do: {:ok, []}
      end

    Module.create(module_name, body, Macro.Env.location(__ENV__))
    module_name
  end
end
