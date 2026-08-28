defmodule CallAssistant.Leads.TranscriptTest do
  use ExUnit.Case, async: true

  alias CallAssistant.Leads.Transcript

  test "parses nil and empty transcripts as no turns" do
    assert Transcript.parse(nil) == []
    assert Transcript.parse("") == []
  end

  test "parses timestamped BOT/USER lines into turns" do
    transcript = "[00:00:00] BOT: Hi there.\n[00:00:05] USER: Hi, who's this?"

    assert Transcript.parse(transcript) == [
             %{time: "00:00:00", speaker: :bot, text: "Hi there."},
             %{time: "00:00:05", speaker: :user, text: "Hi, who's this?"}
           ]
  end

  test "folds an unrecognized line into the previous turn's text" do
    transcript = "[00:00:00] BOT: Hi there,\nstill talking."

    assert [%{speaker: :bot, text: "Hi there,\nstill talking."}] = Transcript.parse(transcript)
  end
end
