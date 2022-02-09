defmodule Upload.Adapters.Test.Server do
  @moduledoc false
  use GenServer
  @timeout 30000

  def start_link(_options) do
    GenServer.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  def init(:ok) do
    {:ok,
     %{
       uploads: %{}
     }}
  end

  #
  # Public interface
  #
  def put_upload(owner_pid, key, value) do
    GenServer.call(__MODULE__, {:put_upload, owner_pid, key, value}, @timeout)
  end

  def get_uploads(owner_pid) do
    GenServer.call(__MODULE__, {:get_uploads, owner_pid}, @timeout)
  end

  def delete_upload(owner_pid, key) do
    GenServer.call(__MODULE__, {:delete_upload, owner_pid, key}, @timeout)
  end

  #
  # GenServer callbacks
  #
  def handle_call({:put_upload, owner_pid, key, value}, _from, state) do
    state =
      if is_nil(state[:uploads][owner_pid]) do
        put_in(state, [:uploads, owner_pid], %{})
      else
        state
      end

    {:reply, :ok, put_in(state, [:uploads, owner_pid, key], value)}
  end

  def handle_call({:get_uploads, owner_pid}, _from, state) do
    {:reply, state[:uploads][owner_pid] || %{}, state}
  end

  def handle_call({:delete_upload, owner_pid, key}, _from, state) do
    exists? = not is_nil(state[:uploads][owner_pid][key])

    if exists? do
      {_discarded_value, state} = pop_in(state, [:uploads, owner_pid, key])

      {:reply, :ok, state}
    else
      {:reply, :ok, state}
    end
  end
end
