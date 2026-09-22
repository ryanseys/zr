# frozen_string_literal: true

require "spec_helper"

describe "String: the byte kernels a word at a time" do
  it "compares hashes scans and splits bytes eight at a time as one at a time" do
    result = ze0(<<~'RUBY')
      # The kernels behind ==, <=>, hash, ascii_only?, valid_encoding?,
      # index and split(" ") read eight bytes a step and the rest one at a
      # time. Every length from 0 to 129 and every place a difference can
      # sit, including the first and last byte of a word and the tail, and
      # every offset a search puts the word at, must answer as the byte
      # loop did -- which `bytes`, `scan` and the constructions here say
      # without those kernels. What prints is a count of the checks and
      # the facts that failed, so a broken kernel names itself.
      checks = 0
      failed = []
      note = ->(fact, ok) { checks += 1; failed << fact unless ok }
      (0..129).each do |len|
        a = ("a".."z").cycle.first(len).join
        note.call("== #{len}", a == a.dup && a.dup == a)
        note.call("<=> #{len}", (a <=> a.dup) == 0)
        note.call("hash #{len}", a.hash == a.dup.hash)
        note.call("ascii #{len}", a.ascii_only?)
        note.call("valid #{len}", a.dup.force_encoding("UTF-8").valid_encoding?)
        [0, 1, 6, 7, 8, 9, 15, 16, 17, len - 9, len - 8, len - 2, len - 1].uniq.each do |at|
          next unless at >= 0 && at < len
          b = a.dup
          b.setbyte(at, a.getbyte(at) + 1)
          note.call("!= #{len}@#{at}", a != b && b != a)
          note.call("<=> less #{len}@#{at}", (a <=> b) == (a.bytes <=> b.bytes) && (b <=> a) == (b.bytes <=> a.bytes))
          note.call("hash differs #{len}@#{at}", a.hash != b.hash)
          c = a.dup
          c.setbyte(at, 0xC3)
          note.call("not ascii #{len}@#{at}", !c.ascii_only?)
          note.call("invalid #{len}@#{at}", !c.dup.force_encoding("UTF-8").valid_encoding?)
          d = a.dup
          d.setbyte(at, 32)
          note.call("split #{len}@#{at}", d.split(" ") == d.scan(/\S+/))
          note.call("word end #{len}@#{at}", d.strip == d.sub(/\A\s+/, "").sub(/\s+\z/, ""))
        end
        # A zero-padded extension differs from the string it extends.
        note.call("padded hash #{len}", a.hash != (a + "\0").hash)
      end
      # Every offset a search puts the needle at: the compare starts
      # unaligned.
      hay = ("0".."9").cycle.first(40).join
      (0..12).each do |off|
        (1..20).each do |len|
          needle = hay[off, len]
          note.call("index #{off},#{len}", hay.index(needle) == (hay.bytes.each_cons(len).to_a.index(needle.bytes)))
          note.call("start_with #{off},#{len}", hay[off..].start_with?(needle))
        end
      end
      # A shorter string sorts first on a shared prefix, and longer words
      # than a step compare past their first word.
      note.call("prefix", ("abcdefghij" <=> "abcdefghijk") == -1 && ("abcdefghijk" <=> "abcdefghij") == 1)
      note.call("second word", ("abcdefgh1" <=> "abcdefgh2") == -1 && ("abcdefghijklmnop" <=> "abcdefghijklmnoq") == -1)
      note.call("high byte", ("a\xFF".b <=> "a\x01".b) == 1)
      note.call("valid multibyte", ("abcdefghé" * 3).valid_encoding? && !"abcdefgh\xC3".dup.force_encoding("UTF-8").valid_encoding?)
      # Characters counted eight bytes at a time: every mix of one, two,
      # three and four byte characters, at every length.
      pieces = ["a", "é", "€", "😀"]
      (0..40).each do |k|
        text = (0...k).map { |j| pieces[(j * 7) % 4] }.join
        note.call("length #{k}", text.length == k && text.size == text.chars.size)
      end
      puts checks
      puts failed.first(10)
    RUBY

    _(result).must_answer "12167\n"
  end
end
