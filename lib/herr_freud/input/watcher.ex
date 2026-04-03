defmodule HerrFreud.Input.Watcher do
  @moduledoc """
  Watches the input directory for new audio/text files.
  Uses FileSystem (fs) library for cross-platform file watching.
  """
  use GenServer
  require Logger

  @debounce_ms 2000
  @supported_extensions [".mp3", ".wav", ".m4a", ".ogg", ".webm", ".txt", ".md"]

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    input_dir = Application.get_env(:herr_freud, :herr_freud_data_folder) || "./data"
    watch_dir = Path.join(input_dir, "input")

    # Ensure directory exists
    File.mkdir_p!(watch_dir)

    {:ok, %{watch_dir: watch_dir, debounce_timers: %{}}, {:continue, :start_watching}}
  end

  @impl true
  def handle_continue(:start_watching, %{watch_dir: watch_dir} = state) do
    # Use FileSystem to watch the directory
    {:ok, watcher} = FileSystem.start_link(dirs: [watch_dir])

    FileSystem.subscribe(watcher)

    Logger.info("Input.Watcher started watching: #{watch_dir}")

    {:noreply, %{state | watch_dir: watch_dir, watcher: watcher}}
  end

  @impl true
  def handle_info({:file_event, _watcher, {:stop, _path}}, state) do
    {:noreply, state}
  end

  def handle_info({:file_event, _watcher, {path, _events}}, state) do
    # Debounce: cancel any pending timer for this path
    timer_key = Path.basename(path)
    _ = cancel_debounce_timer(state.debounce_timers, timer_key)

    # Set new debounce timer
    timer = Process.send_after(self(), {:process_file, path}, @debounce_ms)
    timers = Map.put(state.debounce_timers, timer_key, timer)

    {:noreply, %{state | debounce_timers: timers}}
  end

  def handle_info({:process_file, path}, state) do
    if valid_input_file?(path) do
      Logger.info("Processing input file: #{path}")
      spawn_processing(path)
    end

    timers = Map.delete(state.debounce_timers, Path.basename(path))
    {:noreply, %{state | debounce_timers: timers}}
  end

  @doc """
  Check if a file path is a valid supported input file.
  """
  def valid_input_file?(path) do
    ext = Path.extname(path) |> String.downcase()
    not File.dir?(path) and ext in @supported_extensions
  end

  defp spawn_processing(path) do
    Task.Supervisor.start_child(
      HerrFreud.Session.TaskSupervisor,
      fn -> HerrFreud.Session.Processor.process_file(path) end,
      restart: :temporary
    )
  end

  defp cancel_debounce_timer(timers, key) do
    case Map.get(timers, key) do
      nil -> :ok
      timer ->
        Process.cancel_timer(timer)
        Map.delete(timers, key)
    end
  end
end
