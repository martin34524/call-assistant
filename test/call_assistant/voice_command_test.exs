defmodule CallAssistant.VoiceCommandTest do
  use ExUnit.Case, async: true

  alias CallAssistant.VoiceCommand

  describe "parse_call_command/1" do
    test "extracts a plain name after \"call\"" do
      assert {:ok, "Jane"} = VoiceCommand.parse_call_command("call Jane")
    end

    test "is case-insensitive on the word \"call\"" do
      assert {:ok, "Jane"} = VoiceCommand.parse_call_command("Call Jane")
      assert {:ok, "Jane"} = VoiceCommand.parse_call_command("CALL Jane")
    end

    test "strips filler words and trailing punctuation" do
      assert {:ok, "Jane"} = VoiceCommand.parse_call_command("Please call Jane.")
      assert {:ok, "Jane"} = VoiceCommand.parse_call_command("call Jane please")
      assert {:ok, "Jane"} = VoiceCommand.parse_call_command("call Jane right now!")
      assert {:ok, "Jane Doe"} = VoiceCommand.parse_call_command("can you call Jane Doe for me?")
    end

    test "no match when there's no \"call\" verb" do
      assert :no_match = VoiceCommand.parse_call_command("I need to speak with Jane")
    end

    test "no match when only filler remains after \"call\"" do
      assert :no_match = VoiceCommand.parse_call_command("call please")
    end

    test "non-binary input is not a match" do
      assert :no_match = VoiceCommand.parse_call_command(nil)
    end
  end

  describe "extract_phone/1" do
    test "pulls a digit run out of a longer transcript" do
      assert {:ok, phone} = VoiceCommand.extract_phone("it's 555 123 4567 I think")
      assert phone =~ "555"
      assert phone =~ "4567"
    end

    test "handles dashes and parens" do
      assert {:ok, "(555) 123-4567"} = VoiceCommand.extract_phone("(555) 123-4567")
    end

    test "no match when there aren't enough digits" do
      assert :no_match = VoiceCommand.extract_phone("I don't know it offhand")
    end
  end

  describe "affirmative?/1 and negative?/1" do
    test "recognizes common affirmative phrases" do
      assert VoiceCommand.affirmative?("yes")
      assert VoiceCommand.affirmative?("Yeah, go ahead")
      assert VoiceCommand.affirmative?("that's correct")
      refute VoiceCommand.affirmative?("no")
    end

    test "recognizes common negative phrases" do
      assert VoiceCommand.negative?("no")
      assert VoiceCommand.negative?("cancel that")
      assert VoiceCommand.negative?("never mind")
      refute VoiceCommand.negative?("yes")
    end

    test "neither matches an unrelated transcript" do
      refute VoiceCommand.affirmative?("what's the weather")
      refute VoiceCommand.negative?("what's the weather")
    end
  end
end
