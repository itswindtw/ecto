defmodule Ecto.Integration.TransactionTest do
  # We can keep this test async as long as it
  # is the only one access the transactions table
  use ExUnit.Case, async: true

  import Ecto.Query
  require Ecto.Integration.PoolRepo, as: PoolRepo
  require Ecto.Integration.TestRepo, as: TestRepo

  defmodule UniqueError do
    defexception [:message]
  end

  setup do
    PoolRepo.delete_all "transactions"
    :ok
  end

  defmodule Trans do
    use Ecto.Model

    schema "transactions" do
      field :text, :string
    end
  end

  test "transaction returns value" do
    x = PoolRepo.transaction(fn ->
      PoolRepo.transaction(fn ->
        42
      end)
    end)
    assert x == {:ok, {:ok, 42}}
  end

  test "transaction re-raises" do
    assert_raise UniqueError, fn ->
      PoolRepo.transaction(fn ->
        PoolRepo.transaction(fn ->
          raise UniqueError
        end)
      end)
    end
  end

  test "transaction commits" do
    PoolRepo.transaction(fn ->
      e = PoolRepo.insert!(%Trans{text: "1"})
      assert [^e] = PoolRepo.all(Trans)
      assert [] = TestRepo.all(Trans)
    end)

    assert [%Trans{text: "1"}] = TestRepo.all(Trans)
  end

  test "transaction rolls back" do
    try do
      PoolRepo.transaction(fn ->
        e = PoolRepo.insert!(%Trans{text: "2"})
        assert [^e] = PoolRepo.all(Trans)
        assert [] = TestRepo.all(Trans)
        raise UniqueError
      end)
    rescue
      UniqueError -> :ok
    end

    assert [] = TestRepo.all(Trans)
  end

  test "nested transaction partial rollback" do
    PoolRepo.transaction(fn ->
      e1 = PoolRepo.insert!(%Trans{text: "3"})
      assert [^e1] = PoolRepo.all(Trans)

      try do
        PoolRepo.transaction(fn ->
          e2 = PoolRepo.insert!(%Trans{text: "4"})
          assert [^e1, ^e2] = PoolRepo.all(from(t in Trans, order_by: t.text))
          raise UniqueError
        end)
      rescue
        UniqueError -> :ok
      end

      e3 = PoolRepo.insert!(%Trans{text: "5"})
      assert [^e1, ^e3] = PoolRepo.all(from(t in Trans, order_by: t.text))
      assert [] = TestRepo.all(Trans)
    end)

    assert [%Trans{text: "3"}, %Trans{text: "5"}] =
           TestRepo.all(from(t in Trans, order_by: t.text))
  end

  test "manual rollback doesnt bubble up" do
    x = PoolRepo.transaction(fn ->
      e = PoolRepo.insert!(%Trans{text: "6"})
      assert [^e] = PoolRepo.all(Trans)
      PoolRepo.rollback(:oops)
    end)

    assert x == {:error, :oops}
    assert [] = TestRepo.all(Trans)
  end

  test "transactions are not shared in repo" do
    pid = self

    new_pid = spawn_link fn ->
      PoolRepo.transaction(fn ->
        e = PoolRepo.insert!(%Trans{text: "7"})
        assert [^e] = PoolRepo.all(Trans)
        send(pid, :in_transaction)
        receive do
          :commit -> :ok
        after
          5000 -> raise "timeout"
        end
      end)
      send(pid, :committed)
    end

    receive do
      :in_transaction -> :ok
    after
      5000 -> raise "timeout"
    end
    assert [] = PoolRepo.all(Trans)

    send(new_pid, :commit)
    receive do
      :committed -> :ok
    after
      5000 -> raise "timeout"
    end

    assert [%Trans{text: "7"}] = PoolRepo.all(Trans)
  end

  ## Failures when logging

  test "log raises after begin, drops the whole transaction" do
    try do
      PoolRepo.transaction(fn ->
        PoolRepo.insert!(%Trans{text: "8"})
        Process.put(:on_log, fn -> raise UniqueError end)
        PoolRepo.transaction(fn -> flunk "log did not raise" end)
      end)
    rescue
      UniqueError -> :ok
    end

    assert [] = PoolRepo.all(Trans)
  end

  test "log raises after commit, does commit" do
    try do
      PoolRepo.transaction(fn ->
        PoolRepo.insert!(%Trans{text: "10"})
        Process.put(:on_log, fn -> raise UniqueError end)
      end)
    rescue
      UniqueError -> :ok
    end

    assert [%Trans{text: "10"}] = PoolRepo.all(Trans)
  end

  test "log raises after rollback, does rollback" do
    try do
      PoolRepo.transaction(fn ->
        PoolRepo.insert!(%Trans{text: "11"})
        Process.put(:on_log, fn -> raise UniqueError end)
        PoolRepo.rollback(:rollback)
      end)
    rescue
      UniqueError -> :ok
    end

    assert [] = PoolRepo.all(Trans)
  end

  ## Timeouts

  test "transaction exit includes :timeout on begin timeout" do
    assert match?({:timeout, _},
      catch_exit(PoolRepo.transaction(fn ->
        PoolRepo.transaction([timeout: 0], fn -> flunk "did not timeout" end)
      end)))
  end

  test "transaction exit includes :timeout on query timeout" do
    assert match?({:timeout, _},
      catch_exit(PoolRepo.transaction(fn ->
        PoolRepo.insert!(%Trans{text: "12"}, [timeout: 0])
      end)))

    assert [] = PoolRepo.all(Trans)
  end

  test "transaction exit includes :timeout on nested query timeout" do
    assert match?({:timeout, _},
      catch_exit(PoolRepo.transaction(fn ->
        PoolRepo.transaction(fn ->
          PoolRepo.insert!(%Trans{text: "13"}, [timeout: 0])
        end)
      end)))

    assert [] = PoolRepo.all(Trans)
  end
end