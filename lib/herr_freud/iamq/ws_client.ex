defmodule HerrFreud.IAMQ.WsClient do
  @moduledoc """
  WebSocket client for real-time IAMQ communication.
  Uses WebSockex for the WebSocket connection.
  """
  use WebSockex
  require Logger

  @agent_id Application.compile_env(:herr_freud, :iamq_agent_id, "herr_freud_agent")
  @heartbeat_ms Application.compile_env(:herr_freud, :iamq_heartbeat_ms, 300_000)

  def start_link(_opts) do
    ws_url = Application.get_env(:herr_freud, :iamq_ws_url) || "ws://127.0.0.1:18793/ws"
    WebSockex.start_link(ws_url, __MODULE__, %{}, name: __MODULE__)
  end

  @impl true
  def handle_connect(_conn, state) do
    Logger.info("IAMQ WebSocket connected")
    register()

    # Start heartbeat
    heartbeat_timer = schedule_heartbeat()

    {:ok, %{state | heartbeat_timer: heartbeat_timer}}
  end

  @impl true
  def handle_disconnect(conn_data, state) do
    Logger.warning("IAMQ WebSocket disconnected: #{inspect(conn_data)}")

    if state.heartbeat_timer do
      Process.cancel_timer(state.heartbeat_timer)
    end

    # Attempt reconnect
    schedule_reconnect()

    {:ok, %{state | heartbeat_timer: nil}}
  end

  @impl true
  def handle_frame({:text, frame}, state) do
    case Jason.decode(frame) do
      {:ok, message} ->
        handle_ws_message(message)
        {:ok, state}

      _ ->
        {:ok, state}
    end
  end

  def handle_frame(_frame, state), do: {:ok, state}

  @impl true
  def handle_info(:heartbeat, state) do
    send_heartbeat()
    timer = schedule_heartbeat()
    {:ok, %{state | heartbeat_timer: timer}}
  end

  def handle_info(:reconnect, state) do
    ws_url = Application.get_env(:herr_freud, :iamq_ws_url) || "ws://127.0.0.1:18793/ws"
    WebSockex.start_link(ws_url, __MODULE__, %{})
    {:ok, state}
  end

  defp register do
    register_msg = %{
      agent_id: @agent_id,
      capabilities: [
        "diary_intake",
        "session_response",
        "memory_recall",
        "style_switch",
        "patient_nudge",
        "session_archive"
      ]
    }

    send_frame(Jason.encode!(register_msg))
  end

  defp send_heartbeat do
    heartbeat_msg = %{
      type: "heartbeat",
      agent_id: @agent_id,
      timestamp: DateTime.utc_now() |> DateTime.to_iso8601()
    }

    try do
      send_frame(Jason.encode!(heartbeat_msg))
    rescue
      _ -> :ok
    end
  end

  defp schedule_heartbeat do
    Process.send_after(self(), :heartbeat, @heartbeat_ms)
  end

  defp schedule_reconnect do
    Process.send_after(self(), :reconnect, 30_000)
  end

  defp send_frame(frame) do
    WebSockex.send_frame(__MODULE__, {:text, frame})
  rescue
    _ -> :ok
  end

  defp handle_ws_message(msg) do
    subject = msg["subject"]

    case subject do
      "style_switch" ->
        style_name = msg["body"] && msg["body"]["style"]
        if style_name, do: HerrFreud.Style.Manager.switch_style(style_name)

      "cron::daily_nudge_check" ->
        HerrFreud.Cron.Handler.run_daily_nudge_check()

      "cron::weekly_summary" ->
        HerrFreud.Cron.Handler.run_weekly_summary()

      "session_request" ->
        Logger.info("Session request via WebSocket")

      "direct_message" ->
        handle_direct_message(msg)

      _ ->
        Logger.debug("WebSocket message: #{inspect(subject)}")
    end
  rescue
    e ->
      Logger.error("WS message error: #{inspect(e)}")
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

      case llm_mod().chat(messages, temperature: 0.7, max_tokens: 1024) do
        {:ok, response} ->
          send_direct_reply(sender, response)

        {:error, reason} ->
          Logger.error("Direct message LLM error: #{inspect(reason)}")
          send_direct_reply(sender, "I'm sorry — I'm having trouble responding right now. Please try again in a moment.")
      end
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

    try do
      send_frame(Jason.encode!(reply))
    rescue
      _ -> :ok
    end
  end

  defp llm_mod, do: Application.get_env(:herr_freud, :llm_mod, HerrFreud.LLM.MiniMax)
end
