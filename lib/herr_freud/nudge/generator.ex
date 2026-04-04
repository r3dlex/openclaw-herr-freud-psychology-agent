defmodule HerrFreud.Nudge.Generator do
  @moduledoc """
  Generates nudge content and weekly summaries via the LLM.
  """

  @doc """
  Generate a gentle nudge to encourage the patient to share.
  """
  def generate_nudge(profile, recent_memories) do
    prompt = build_nudge_prompt(profile, recent_memories)

    messages = [
      %{
        role: "system",
        content: HerrFreud.Identity.Prompt.build_nudge_prompt()
      },
      %{role: "user", content: prompt}
    ]

    case llm_call(messages, temperature: 0.8, max_tokens: 300) do
      {:ok, response} -> {:ok, String.trim(response)}
      {:error, _} = error -> error
    end
  end

  @doc """
  Generate a weekly summary of therapy sessions.
  """
  def generate_weekly_summary(sessions) when is_list(sessions) do
    session_summaries =
      Enum.map_join(sessions, "\n---\n", fn s ->
        """
        Date: #{s.date || "unknown"}
        Style: #{s.style_used}
        Transcript excerpt: #{String.slice(s.english_transcript || "", 0, 200)}...
        Response excerpt: #{String.slice(s.response || "", 0, 200)}...
        """
      end)

    prompt = """
    The following are excerpts from therapy sessions from the past week:

    #{session_summaries}

    Write a brief, compassionate summary of the week's themes and progress.
    Focus on recurring emotions, relationships, or insights that emerged.
    Max 200 words. Write as if speaking gently to the patient about what you noticed.
    """

    messages = [
      %{
        role: "system",
        content: "You are Herr Freud, writing a weekly therapeutic summary."
      },
      %{role: "user", content: prompt}
    ]

    case llm_call(messages, temperature: 0.5, max_tokens: 500) do
      {:ok, response} -> {:ok, String.trim(response)}
      {:error, _} = error -> error
    end
  end

  defp build_nudge_prompt(profile, memories) do
    profile_text =
      if map_size(profile) == 0 do
        "No profile information yet."
      else
        Enum.map_join(profile, "\n", fn {k, v} -> "- #{k}: #{v}" end)
      end

    memories_text =
      if memories == [] do
        "No previous memories."
      else
        Enum.map_join(memories, "\n", fn m -> "- #{m.content}" end)
      end

    """
    Patient profile:
    #{profile_text}

    Recent session memories:
    #{memories_text}

    Write a warm, gentle nudge message.
    """
  end

  defp llm_call(messages, opts) do
    llm_mod().chat(messages, opts)
  end

  defp llm_mod do
    Application.get_env(:herr_freud, :llm_mod, HerrFreud.LLM.Stub)
  end
end
