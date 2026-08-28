defmodule CallAssistant.Leads.Transcript do
  @moduledoc """
  Parses CALL-E's transcript text into structured turns for display.

  Real transcripts (and the Mock adapter, which mirrors the format) look
  like:

      [00:00:00] BOT: Hi.
      [00:00:05] USER: Hi, how are you?

  Any line that doesn't match that shape is treated as a continuation of
  the previous turn's text (transcripts are plain text, not a documented
  API contract, so this is deliberately forgiving rather than dropping
  content it doesn't recognize).
  """

  @line ~r/^\[(\d{2}:\d{2}:\d{2})\]\s*(BOT|USER):\s*(.*)$/

  @type turn :: %{time: String.t() | nil, speaker: :bot | :user, text: String.t()}

  @spec parse(String.t() | nil) :: [turn()]
  def parse(nil), do: []
  def parse(""), do: []

  def parse(transcript) when is_binary(transcript) do
    transcript
    |> String.split("\n")
    |> Enum.reduce([], fn line, turns ->
      case Regex.run(@line, line) do
        [_, time, speaker, text] ->
          [%{time: time, speaker: speaker(speaker), text: text} | turns]

        nil ->
          append_continuation(turns, line)
      end
    end)
    |> Enum.reverse()
  end

  defp speaker("BOT"), do: :bot
  defp speaker("USER"), do: :user

  defp append_continuation([], line), do: [%{time: nil, speaker: :bot, text: line}]

  defp append_continuation([%{text: text} = turn | rest], line) do
    [%{turn | text: String.trim(text <> "\n" <> line)} | rest]
  end
end
