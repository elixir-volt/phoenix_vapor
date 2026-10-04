defmodule PhoenixVapor.JS.SessionTest do
  use ExUnit.Case, async: true

  alias PhoenixVapor.JS.Session

  test "starts the runtime on first use and loads each key once" do
    Session.with_session(fn session ->
      assert Session.once(session, :answer, &QuickBEAM.eval(&1, "globalThis.n = 41")) == {:ok, 41}
      assert Session.once(session, :answer, fn _runtime -> flunk("loaded twice") end) == {:ok, 41}
      assert {:ok, 42} = QuickBEAM.eval(Session.runtime(session), "n + 1")
    end)
  end

  test "stops the runtime when what it runs raises" do
    parent = self()

    assert_raise RuntimeError, fn ->
      Session.with_session(fn session ->
        send(parent, {:runtime, Session.runtime(session)})
        raise "compile error"
      end)
    end

    assert_received {:runtime, runtime}
    refute Process.alive?(runtime)
  end

  test "starts nothing when nothing needs JavaScript" do
    Session.with_session(fn session -> assert %Session{} = session end)
  end
end
