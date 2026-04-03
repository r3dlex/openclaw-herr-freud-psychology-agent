defmodule HerrFreud.Cron.Handler do
  @moduledoc """
  Handles cron-triggered tasks.

  Registers daily_nudge_check (20:00 UTC) and weekly_summary (09:00 UTC Monday).
  """
  use GenServer
  require Logger

  @nudge_after_days Application.compile_env(:herr_freud, :herr_freud_nudge_after_days, 2)

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  @doc """
  Run the daily nudge check immediately (can be triggered via IAMQ).
  """
  def run_daily_nudge_check do
    GenServer.cast(__MODULE__, :daily_nudge_check)
  end

  @doc """
  Run the weekly summary immediately (can be triggered via IAMQ).
  """
  def run_weekly_summary do
    GenServer.cast(__MODULE__, :weekly_summary)
  end

  # Server

  @impl true
  def init(_opts) do
    Logger.info("Cron.Handler started — daily_nudge_check and weekly_summary registered")

    # Schedule the daily nudge check for 20:00 UTC
    schedule_daily_nudge()

    # Schedule weekly summary for 09:00 UTC Monday
    schedule_weekly_summary()

    {:ok, %{last_nudge_date: nil}}
  end

  @impl true
  def handle_cast(:daily_nudge_check, state) do
    do_daily_nudge_check(state)
    {:noreply, state}
  end

  @impl true
  def handle_cast(:weekly_summary, state) do
    do_weekly_summary()
    {:noreply, state}
  end

  @impl true
  def handle_info(:run_daily_nudge, state) do
    new_state = %{state | last_nudge_date: Date.utc_today()}
    do_daily_nudge_check(new_state)
    schedule_daily_nudge()
    {:noreply, new_state}
  end

  @impl true
  def handle_info(:run_weekly_summary, state) do
    do_weekly_summary()
    schedule_weekly_summary()
    {:noreply, state}
  end

  # Internal

  defp do_daily_nudge_check(state) do
    if state.last_nudge_date == Date.utc_today() do
      Logger.debug("Nudge already sent today, skipping")
      :ok
    else
      case HerrFreud.Memory.Store.get_most_recent_session() do
        nil ->
          generate_and_send_nudge("first_session")

        session ->
          check_and_nudge_if_overdue(session)
      end
    end
  end

  defp check_and_nudge_if_overdue(session) do
    days_since =
      Date.utc_today()
      |> Date.diff(session.date || session.inserted_at |> DateTime.to_date())

    if days_since >= @nudge_after_days do
      generate_and_send_nudge("return_session")
    else
      Logger.debug("Last session was #{days_since} days ago, no nudge needed")
      :ok
    end
  end

  defp generate_and_send_nudge(reason) do
    with {:ok, profile_entries} <- HerrFreud.Profile.Store.get_all(),
         profile_map <- Map.new(profile_entries, fn %{key: k, value: v} -> {k, v} end),
         {:ok, memories} <- HerrFreud.Memory.Retriever.fetch_for_text("nudge", 5),
         {:ok, nudge_content} <- HerrFreud.Nudge.Generator.generate_nudge(profile_map, memories),
         :ok <- persist_and_archive_nudge(nudge_content, reason) do
      :ok
    else
      {:error, reason} ->
        Logger.error("Failed to generate nudge: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp persist_and_archive_nudge(nudge_content, reason) do
    case HerrFreud.Output.Writer.write_nudge(nudge_content) do
      {:ok, path} ->
        HerrFreud.Repo.query(
          "INSERT INTO nudges (id, sent_at, trigger) VALUES (?, ?, ?)",
          [Ecto.UUID.generate(), DateTime.utc_now() |> DateTime.to_iso8601(), "cron"]
        )

        HerrFreud.IAMQ.HttpClient.send(%{
          to: "librarian_agent",
          subject: "archive",
          body: %{
            capability: "archive",
            file_path: path,
            library: "herr_freud",
            tags: ["therapy", "nudge", "proactive"],
            date: Date.utc_today() |> Date.to_iso8601()
          }
        })

        Logger.info("Nudge sent: #{inspect(reason)}")
        :ok

      {:error, reason} ->
        Logger.error("Failed to write nudge: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp do_weekly_summary do
    # Get sessions from the past 7 days
    past_week = Date.utc_today() |> Date.add(-7)

    sessions = HerrFreud.Memory.Store.list_sessions_since(past_week)

    if sessions != [] do
      with {:ok, _summary} <- HerrFreud.Nudge.Generator.generate_weekly_summary(sessions) do
        # Archive to librarian
        HerrFreud.IAMQ.HttpClient.send(%{
          to: "librarian_agent",
          subject: "archive",
          body: %{
            capability: "archive",
            file_path: "/sessions/weekly_summary_#{Date.utc_today() |> Date.to_iso8601()}.md",
            library: "herr_freud",
            tags: ["therapy", "weekly_summary"],
            date: Date.utc_today() |> Date.to_iso8601()
          }
        })

        Logger.info("Weekly summary sent for #{length(sessions)} sessions")
      end
    else
      Logger.debug("No sessions this week, skipping weekly summary")
    end
  end

  # Schedule next daily nudge for 20:00 UTC
  defp schedule_daily_nudge do
    now = DateTime.utc_now()
    target = %{now | hour: 20, minute: 0, second: 0, microsecond: {0, 0}}

    delay =
      if DateTime.compare(target, now) == :lt do
        # Already past 20:00, schedule for tomorrow
        DateTime.add(target, 86_400) |> DateTime.diff(now)
      else
        DateTime.diff(target, now)
      end

    Process.send_after(self(), :run_daily_nudge, delay * 1000)
  end

  # Schedule next weekly summary for 09:00 UTC Monday
  defp schedule_weekly_summary do
    now = DateTime.utc_now()
    days_until_monday = Integer.mod(7 - Date.day_of_week(now), 7)
    days_until_monday = if days_until_monday == 0, do: 7, else: days_until_monday

    target =
      %{now | hour: 9, minute: 0, second: 0, microsecond: {0, 0}}
      |> DateTime.add(days_until_monday * 86_400)

    delay = DateTime.diff(target, now)

    Process.send_after(self(), :run_weekly_summary, delay * 1000)
  end
end
