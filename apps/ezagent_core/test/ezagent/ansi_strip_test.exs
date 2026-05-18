defmodule Ezagent.AnsiStripTest do
  use ExUnit.Case, async: true

  alias Ezagent.AnsiStrip

  test "strips CSI sequences leaving printable text" do
    # ESC [ 1 m bold ESC [ 0 m
    raw = "\e[1mhello\e[0m world"
    assert AnsiStrip.strip(raw) =~ "hello"
    assert AnsiStrip.strip(raw) =~ "world"
  end

  test "CSI replaced with space prevents word-squish" do
    # \e[1C is cursor-forward 1 col — claude uses this to lay out words
    raw = "Loading\e[1Cdevelopment\e[1Cchannels"
    assert AnsiStrip.strip(raw) =~ "Loading development channels"
  end

  test "strips OSC (title set)" do
    # ESC ] 0 ; title BEL
    raw = "before\e]0;my-title\x07after"
    stripped = AnsiStrip.strip(raw)
    assert stripped =~ "before"
    assert stripped =~ "after"
    refute stripped =~ "my-title"
  end

  test "drops bare control chars but keeps newline + tab" do
    raw = "line1\nline2\ttab\x08\x0E\x0F"
    stripped = AnsiStrip.strip(raw)
    assert stripped == "line1\nline2\ttab"
  end

  test "empty string returns empty" do
    assert AnsiStrip.strip("") == ""
  end
end
