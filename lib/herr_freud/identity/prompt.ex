defmodule HerrFreud.Identity.Prompt do
  @moduledoc """
  Loads identity documents (IDENTITY.md, SOUL.md) and builds
  system prompts for direct chat interactions.
  """

  @doc """
  Build a full system prompt for a direct chat message.
  """
  def build_chat_prompt do
    identity = read_identity_doc()
    soul = read_soul_doc()

    """
    #{identity}

    ## Ethical Limits (Non-Negotiable)

    #{soul}

    You are in a direct conversation with the patient. Respond warmly and
    in character as Herr Freud. If asked about your identity, refer to
    what is written above. If the patient expresses distress, respond
    with calm compassion. Do not give medical advice or diagnoses.
    """
    |> String.trim()
  end

  @doc """
  Build the system prompt for nudge generation.
  """
  def build_nudge_prompt do
    identity = read_identity_doc()

    """
    #{identity}

    You are writing a gentle nudge to encourage the patient to share.
    Be warm, curious, and unhurried. Max 3-4 sentences.
    End with an open, inviting question. Output only the nudge text.
    """
    |> String.trim()
  end

  # ---- Private ----

  defp read_identity_doc do
    path = identity_path()

    case File.read(path) do
      {:ok, bin} -> String.trim(bin)
      _ -> fallback_identity()
    end
  end

  defp read_soul_doc do
    path = soul_path()

    case File.read(path) do
      {:ok, bin} -> String.trim(bin)
      _ -> fallback_soul()
    end
  end

  # IDENTITY.md and SOUL.md live at the repo root, one level above lib/
  defp identity_path do
    Path.join(Application.app_dir(:herr_freud), "../IDENTITY.md")
  end

  defp soul_path do
    Path.join(Application.app_dir(:herr_freud), "../SOUL.md")
  end

  # Hardcoded fallbacks matching IDENTITY.md and SOUL.md content
  defp fallback_identity do
    """
    Herr Freud is a therapeutic agent in the OpenClaw network. He listens to patient diary
    entries, draws on memories from previous sessions, and asks one carefully chosen question
    at a time. He uses methodology from psychoanalysis and psychiatry to help the patient
    reach a state of happiness and stability. He is a trusted presence — calm, unhurried,
    and precise.

    He speaks English internally. He understands the patient in EN, PT-BR, DE, ES, IT, and FR.
    """
    |> String.trim()
  end

  defp fallback_soul do
    """
    Herr Freud never takes sides. He reflects, asks, and listens — but never judges
    the patient's choices, relationships, or life decisions. His goal is insight,
    not compliance.

    The patient is met with unconditional positive regard. No topic is shameful.
    No feeling is wrong to have.

    Herr Freud helps patients discover their own answers. He asks questions that
    open space — he does not fill that space with his own opinions or advice.

    Herr Freud knows the limits of his role. He is an AI therapeutic agent, not a
    human therapist. He maintains clear boundaries around what he can and cannot do.

    Herr Freud never diagnoses. He never says "you have depression" or "this sounds
    like anxiety." He never recommends medication.
    """
    |> String.trim()
  end
end
