defmodule HerrFreud.IAMQ.HttpClient do
  @moduledoc """
  HTTP polling client for IAMQ.

  Polls the IAMQ inbox at regular intervals and falls back to a
  file-based JSON queue when the service is unreachable.
  """
  use GenServer
  require Logger

  @poll_interval Application.compile_env(:herr_freud, :iamq_poll_ms, 60_000)
  @agent_id Application.compile_env(:herr_freud, :iamq_agent_id, "herr_freud_agent")
  @queue_path Application.compile_env(:herr_freud, :iamq_queue_path)

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  @doc """
  Send a message via IAMQ HTTP.
  """
  def send(message) do
    GenServer.call(__MODULE__, {:send, message})
  end

  @doc """
  Trigger a manual inbox poll.
  """
  def poll_inbox do
    GenServer.cast(__MODULE__, :poll_inbox)
  end

  # Server

  @impl true
  def init(_opts) do
    state = %{
      inbox_url: "#{base_url()}/messages",
      outbox_url: "#{base_url()}/messages/outbox",
      queue_path: Application.get_env(:herr_freud, :iamq_queue_path),
      poll_timer: nil
    }

    # Schedule first poll
    timer = schedule_poll()
    {:ok, %{state | poll_timer: timer}}
  end

  @impl true
  def handle_call({:send, message}, _from, state) do
    result = do_send(message, state)

    # Also persist to file fallback if configured
    if is_binary(state.queue_path) and byte_size(state.queue_path) > 0 do
      persist_to_file_fallback(message)
    end

    {:reply, result, state}
  end

  @impl true
  def handle_cast(:poll_inbox, state) do
    do_poll_inbox(state)
    {:noreply, state}
  end

  @impl true
  def handle_info(:poll, state) do
    do_poll_inbox(state)
    timer = schedule_poll()
    {:noreply, %{state | poll_timer: timer}}
  end

  @impl true
  def terminate(_reason, state) do
    if state.poll_timer, do: Process.cancel_timer(state.poll_timer)
    :ok
  end

  # Internal

  defp base_url do
    Application.get_env(:herr_freud, :iamq_http_url) || "http://127.0.0.1:18790"
  end

  defp schedule_poll do
    Process.send_after(self(), :poll, @poll_interval)
  end

  defp do_send(message, state) do
    body = %{
      from: message[:from] || @agent_id,
      to: message.to,
      type: message[:type] || "request",
      priority: message[:priority] || "NORMAL",
      subject: message.subject,
      body: message.body
    }

    headers = [
      {"Content-Type", "application/json"},
      {"X-Agent-ID", @agent_id}
    ]

    case :hackney.post(
           state.outbox_url,
           headers,
           Jason.encode!(body),
           [:with_body]
         ) do
      {:ok, status, _headers, _body} when status in 200..299 ->
        Logger.info("IAMQ message sent: #{inspect(message.subject)}")
        :ok

      {:ok, status, _headers, body} ->
        Logger.warning("IAMQ send failed (#{status}): #{body}")
        {:error, {:http_error, status}}

      {:error, reason} ->
        Logger.warning("IAMQ network error: #{inspect(reason)}, using file fallback")
        {:error, {:network_error, reason}}
    end
  end

  defp do_poll_inbox(state) do
    headers = [{"X-Agent-ID", @agent_id}]

    case :hackney.get(state.inbox_url, headers, [:with_body]) do
      {:ok, 200, _headers, body} ->
        case Jason.decode(body) do
          {:ok, messages} when is_list(messages) ->
            Enum.each(messages, &handle_inbox_message/1)

          _ ->
            :ok
        end

      {:ok, _, _, _} ->
        :ok

      {:error, reason} ->
        Logger.debug("IAMQ poll failed (will retry): #{inspect(reason)}")
        read_from_file_fallback()
    end
  end

  defp handle_inbox_message(msg) do
    subject = msg["subject"] || msg[:subject]

    case subject do
      "style_switch" ->
        style_name = msg["body"]["style"]
        HerrFreud.Style.Manager.switch_style(style_name)
        Logger.info("Style switched to: #{style_name}")

      "session_request" ->
        # Triggered programmatically — process the specified input
        Logger.info("Session request received")

      "direct_message" ->
        handle_direct_message(msg)

      "cron::daily_nudge_check" ->
        HerrFreud.Cron.Handler.run_daily_nudge_check()

      "cron::weekly_summary" ->
        HerrFreud.Cron.Handler.run_weekly_summary()

      _ ->
        Logger.debug("Unknown message subject: #{inspect(subject)}")
    end
  rescue
    e ->
      Logger.error("Error handling inbox message: #{inspect(e)}")
  end

  defp handle_direct_message(msg) do
    sender = msg["from"] || msg["body"] && msg["body"]["from"] || "unknown"
    patient_text = msg["body"] && msg["body"]["text"] || ""

    if patient_text != "" do
      system_prompt = HerrFreud.Identity.Prompt.build_chat_prompt()

      messages = [
        %{role: "system", content: system_prompt},
        %{role: "user", content: patient_text}
      ]

      response_text = case llm_mod().chat(messages, temperature: 0.7, max_tokens: 1024) do
        {:ok, text} -> text
        {:error, _} -> "I'm sorry — I'm having trouble responding right now. Please try again in a moment."
      end

      send_direct_reply(sender, response_text)
    end
  end

  defp send_direct_reply(to_agent, text) do
    reply = %{
      from: @agent_id,
      to: to_agent,
      type: "reply",
      subject: "direct_reply",
      body: %{
        text: text,
        timestamp: DateTime.utc_now() |> DateTime.to_iso8601()
      }
    }

    do_send(reply, %{})
  end

  defp llm_mod, do: Application.get_env(:herr_freud, :llm_mod, HerrFreud.LLM.MiniMax)

  defp persist_to_file_fallback(message) do
    fallback_dir = Path.dirname(@queue_path || "/tmp/iamq_fallback.json")
    File.mkdir_p!(fallback_dir)

    entry = %{
      timestamp: DateTime.utc_now() |> DateTime.to_iso8601(),
      message: message
    }

    # Append to JSON array file
    fallback_file = Path.join(fallback_dir, "herr_freud_outbox.jsonl")
    File.write(fallback_file, Jason.encode!(entry) <> "\n", [:append])
  end

  defp read_from_file_fallback do
    fallback_file = Path.join(Path.dirname(@queue_path || "/tmp"), "iamq_inbox_fallback.jsonl")

    if File.exists?(fallback_file) do
      fallback_file
      |> File.stream!()
      |> Stream.map(&Jason.decode!/1)
      |> Enum.each(fn %{message: msg} -> handle_inbox_message(msg) end)

      File.rm!(fallback_file)
    end
  end
end
