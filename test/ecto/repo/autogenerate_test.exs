alias Ecto.TestRepo

defmodule Ecto.Repo.AutogenerateTest do
  use ExUnit.Case, async: true

  defmodule Manager do
    use Ecto.Schema

    @timestamps_opts [inserted_at: :created_on]
    schema "manager" do
      timestamps updated_at: :updated_on, type: :utc_datetime
    end
  end

  defmodule Company do
    use Ecto.Schema

    schema "default" do
      field :code, Ecto.UUID, autogenerate: true
      has_one :manager, Manager
      timestamps()
    end
  end

  defmodule NaiveMod do
    use Ecto.Schema

    schema "naive_mod" do
      timestamps(type: :naive_datetime)
    end
  end

  defmodule NaiveUsecMod do
    use Ecto.Schema

    schema "naive_usec_mod" do
      timestamps(type: :naive_datetime_usec)
    end
  end

  defmodule UtcMod do
    use Ecto.Schema

    schema "utc_mod" do
      timestamps(type: :utc_datetime)
    end
  end

  defmodule UtcUsecMod do
    use Ecto.Schema

    schema "utc_usec_mod" do
      timestamps(type: :utc_datetime_usec)
    end
  end

  ## Autogenerate

  @uuid "30313233-3435-4637-9839-616263646566"

  test "autogenerates values" do
    schema = TestRepo.insert!(%Company{})
    assert byte_size(schema.code) == 36

    changeset = Ecto.Changeset.cast(%Company{}, %{}, [])
    schema = TestRepo.insert!(changeset)
    assert byte_size(schema.code) == 36

    changeset = Ecto.Changeset.cast(%Company{}, %{code: nil}, [])
    schema = TestRepo.insert!(changeset)
    assert byte_size(schema.code) == 36

    changeset = Ecto.Changeset.force_change(changeset, :code, nil)
    schema = TestRepo.insert!(changeset)
    assert schema.code == nil

    changeset = Ecto.Changeset.cast(%Company{}, %{code: @uuid}, [:code])
    schema = TestRepo.insert!(changeset)
    assert schema.code == @uuid
  end

  ## Timestamps

  test "sets inserted_at and updated_at values" do
    default = TestRepo.insert!(%Company{})
    assert %NaiveDateTime{microsecond: {0, 0}} = default.inserted_at
    assert %NaiveDateTime{microsecond: {0, 0}} = default.updated_at
    assert_received {:insert, _}

    # No change
    changeset = Ecto.Changeset.change(%Company{id: 1})
    default = TestRepo.update!(changeset)
    refute default.inserted_at
    refute default.updated_at
    refute_received {:update, _}

    # Change in children
    changeset = Ecto.Changeset.change(%Company{id: 1})
    default = TestRepo.update!(Ecto.Changeset.put_assoc(changeset, :manager, %Manager{}))
    refute default.inserted_at
    refute default.updated_at
    assert_received {:insert, _}
    refute_received {:update, _}

    # Force change
    changeset = Ecto.Changeset.change(%Company{id: 1})
    default = TestRepo.update!(changeset, force: true)
    refute default.inserted_at
    assert %NaiveDateTime{microsecond: {0, 0}} = default.updated_at
    assert_received {:update, _}
  end

  test "does not set inserted_at and updated_at values if they were previously set" do
    naive_datetime = ~N[2000-01-01 00:00:00]
    default = TestRepo.insert!(%Company{inserted_at: naive_datetime,
                                        updated_at: naive_datetime})
    assert default.inserted_at == naive_datetime
    assert default.updated_at == naive_datetime

    changeset = Ecto.Changeset.change(%Company{id: 1}, updated_at: naive_datetime)
    default = TestRepo.update!(changeset)
    refute default.inserted_at
    assert default.updated_at == naive_datetime
  end

  test "sets custom inserted_at and updated_at values" do
    default = TestRepo.insert!(%Manager{})
    assert %DateTime{time_zone: "Etc/UTC", microsecond: {0, 0}} = default.created_on
    assert %DateTime{time_zone: "Etc/UTC", microsecond: {0, 0}} = default.updated_on

    default = TestRepo.update!(%Manager{id: 1} |> Ecto.Changeset.change, force: true)
    refute default.created_on
    assert %DateTime{time_zone: "Etc/UTC", microsecond: {0, 0}} = default.updated_on
  end

  test "sets the timestamps type to naive_datetime" do
    default = TestRepo.insert!(%NaiveMod{})
    assert %NaiveDateTime{microsecond: {0, 0}} = default.inserted_at
    assert %NaiveDateTime{microsecond: {0, 0}} = default.updated_at

    default = TestRepo.update!(%NaiveMod{id: 1} |> Ecto.Changeset.change, force: true)
    refute default.inserted_at
    assert %NaiveDateTime{microsecond: {0, 0}} = default.updated_at
  end

  test "sets the timestamps type to naive_datetime_usec" do
    default = TestRepo.insert!(%NaiveUsecMod{})
    assert %NaiveDateTime{microsecond: {_, 6}} = default.inserted_at
    assert %NaiveDateTime{microsecond: {_, 6}} = default.updated_at

    default = TestRepo.update!(%NaiveUsecMod{id: 1} |> Ecto.Changeset.change, force: true)
    refute default.inserted_at
    assert %NaiveDateTime{microsecond: {_, 6}} = default.updated_at
  end

  test "sets the timestamps type to utc_datetime" do
    default = TestRepo.insert!(%UtcMod{})
    assert %DateTime{time_zone: "Etc/UTC", microsecond: {0, 0}} = default.inserted_at
    assert %DateTime{time_zone: "Etc/UTC", microsecond: {0, 0}} = default.updated_at

    default = TestRepo.update!(%UtcMod{id: 1} |> Ecto.Changeset.change, force: true)
    refute default.inserted_at
    assert %DateTime{time_zone: "Etc/UTC", microsecond: {0, 0}} = default.updated_at
  end

  test "sets the timestamps type to utc_datetime_usec" do
    default = TestRepo.insert!(%UtcUsecMod{})
    assert %DateTime{time_zone: "Etc/UTC", microsecond: {_, 6}} = default.inserted_at
    assert %DateTime{time_zone: "Etc/UTC", microsecond: {_, 6}} = default.updated_at

    default = TestRepo.update!(%UtcUsecMod{id: 1} |> Ecto.Changeset.change, force: true)
    refute default.inserted_at
    assert %DateTime{time_zone: "Etc/UTC", microsecond: {_, 6}} = default.updated_at
  end
end
