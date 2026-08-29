defmodule CallAssistant.VoiceCommand do
  @moduledoc """
  Pure parsing for the voice-command calling flow (see
  CallAssistantWeb.VoiceCommandComponents and the LiveViews that use it) -
  no DB, no LiveView, just turning a raw speech transcript into a decision.
  Kept separate and dependency-free so it's trivial to unit test without a
  browser or a real SpeechRecognition session.
  """

  @fillers ~r/\b(please|for me|right now|now|thanks|thank you|today)\b/i

  @doc """
  Parses a "call <name>" voice command. Case-insensitive, tolerates a few
  filler words/phrases and trailing punctuation Web Speech API often
  attaches (e.g. "Please call Jane." -> "Jane").
  """
  def parse_call_command(transcript) when is_binary(transcript) do
    case Regex.run(~r/\bcall\s+(.+)/i, String.trim(transcript)) do
      [_, name] ->
        case clean_name(name) do
          "" -> :no_match
          cleaned -> {:ok, cleaned}
        end

      nil ->
        :no_match
    end
  end

  def parse_call_command(_), do: :no_match

  @doc """
  Pulls the first digit-heavy run out of a transcript - spoken phone
  numbers still tend to come through Web Speech API mostly as digits.
  """
  def extract_phone(transcript) when is_binary(transcript) do
    case Regex.run(~r/\(?\d[\d\s\-\(\)]{6,}/, transcript) do
      [match] -> {:ok, String.trim(match)}
      nil -> :no_match
    end
  end

  def extract_phone(_), do: :no_match

  @affirmative ~r/\b(yes|yeah|yep|confirm|correct|sure|go ahead)\b/i
  @negative ~r/\b(no|nope|cancel|stop|nevermind|never mind)\b/i

  def affirmative?(transcript) when is_binary(transcript), do: transcript =~ @affirmative
  def affirmative?(_), do: false

  def negative?(transcript) when is_binary(transcript), do: transcript =~ @negative
  def negative?(_), do: false

  defp clean_name(name) do
    name
    |> String.replace(@fillers, "")
    |> String.replace(~r/[.?!]+\s*$/, "")
    |> String.replace(~r/\s+/, " ")
    |> String.trim()
  end
end
