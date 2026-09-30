# frozen_string_literal: true

require "test_helper"
require_relative "../support/harness/kernel_jit"
require_relative "../../lib/zr/runtime"

# Compares the kernel matcher (runtime/kernel/onig_*.rb) with ruby's own
# engine. The core compiles each pattern under this ruby. The test
# JIT-loads the kernel unit, which does the search. `Regexp` on the same
# subject gives the expected position and byte offsets of each capture.
Zr::RuntimeSources.require_onig

class OnigMatchTest < Minitest::Test
  O = Regexp::Onig
  def self.port
    @port ||= Zr::Harness::KernelJIT.new("onig_*.rb", constants: { "CLOCK_MONOTONIC" => 6 })
  end

  def setup
    skip "needs an aarch64-apple-darwin host" unless Zr::Target::AARCH64_DARWIN.native?
  end

  # The kernel's result: nil, [:error, code], or [position, offsets].
  def kernel(pat, opts, subject, start: 0, backward: false, at: false, limit: 0)
    enc = O::Enc.for(subject.encoding)
    reg, = O.compile(pat.b, opts, enc)
    prog = O::Program.pack(reg)
    pbuf = Fiddle::Pointer.malloc(prog.bytesize, Fiddle::RUBY_FREE)
    pbuf[0, prog.bytesize] = prog
    sbuf = Fiddle::Pointer.malloc(subject.bytesize + 1, Fiddle::RUBY_FREE)
    sbuf[0, subject.bytesize] = subject.b if subject.bytesize > 0
    n = reg.num_mem + 1
    region = Fiddle::Pointer.malloc(16 * n, Fiddle::RUBY_FREE)
    str = sbuf.to_i
    stop = str + subject.bytesize
    r = if at
          self.class.port.call("zr_onig_match", pbuf.to_i, str, stop, str + start, region.to_i, limit)
        else
          self.class.port.call("zr_onig_search", pbuf.to_i, str, stop, str + start, backward ? str : stop, region.to_i, limit)
        end
    return [:error, r] if r < -1
    return nil if r == -1

    [at ? r : r, region[0, 16 * n].unpack("q<*")]
  end

  # ruby's result in the same shape. It gives the search position only
  # where ruby shows it (`=~`, from the start, forward).
  def oracle(pat, opts, subject, start: 0, backward: false, at: false)
    re = Regexp.new(pat.dup.force_encoding(subject.encoding), opts)
    char_start = subject.byteslice(0, start).length
    md = if at
           re.match(subject, char_start)&.then { |m| m.byteoffset(0)[0] == start ? m : nil }
         elsif backward
           subject.rindex(re, char_start) && Regexp.last_match
         else
           re.match(subject, char_start)
         end
    return nil unless md

    offsets = (0...md.size).flat_map { |i| md.begin(i) ? md.byteoffset(i) : [-1, -1] }
    pos = if at
            md.byteoffset(0)[1] - start
          elsif start == 0 && !backward && (i = subject =~ re)
            subject[0, i].bytesize
          end
    [pos, offsets]
  end

  def check(pat, subject, opts = 0, **how)
    subject = subject.dup.force_encoding("UTF-8") if subject.encoding == Encoding::US_ASCII
    want = oracle(pat, opts, subject, **how)
    got = kernel(pat, opts, subject, **how)
    got[0] = nil if got && want && want[0].nil?
    label = "/#{pat}/#{opts.zero? ? "" : " opts=#{opts}"} on #{subject.inspect} #{how}"
    want.nil? ? assert_nil(got, label) : assert_equal(want, got, label)
  end

  CASES = [
    ["abc", "xxabcxx"], ["a|b", "xxb"], ["a*b+c?", "aaabbc"], ["a{2,3}?x", "aaax"], ["(?<a>a)(?<n>b)\\k<n>\\k<a>", "abba"],
    ["[a-z0-9&&[^aeiou]]+", "hello world 42"], ["(?i:ab)c", "ABc"], ["hello", "say hello"], ["^$", ""], ["x*", ""],
    ["\\d+\\.\\d+", "pi is 3.14!"], ["[abc]+", "zzabcabz"], ["\\p{Alpha}+", "12 héllo 34"], ["a\\X", "áb"],
    ["(?:ab){10}", "ab" * 12], ["(ab){2,}", "xababab"], ["(?<n>a)\\g<n>", "aa"], ["(a|b)*c", "ababc"],
    ["\\bfoo\\b", "a foo b"], ["\\Bfoo", "afoo"], ["^abc$", "abc"], ["abc$", "xabc\n"], ["abc\\Z", "xabc\n"], ["abc\\z", "xabc\n"],
    ["(?=a)(?!b)a", "xa"], ["(?<=c)x", "acx"], ["(?<!c)x", "abx"], ["(?<=a|bc)x", "bcx"], ["(?<!a|bc)x", "ddx"],
    ["(?>a+)b", "aaab"], ["(?~abc)", "xxabcxx"], ["a\\Kb", "ab"], ["(?(1)a|b)(x)?", "b"], ["(x)(?(1)a|b)", "xa"],
    ["x(a*)*y", "xaaay"], [".*abc", "zzzabc"], ["(?m).*abc", "z\nzabc"], ["\\h+", "xx1f"],
    ["ss", "STRASSE", Regexp::IGNORECASE], ["ß", "STRASSE", Regexp::IGNORECASE], ["k", "K", Regexp::IGNORECASE],
    ["(a)\\1", "aA", Regexp::IGNORECASE], ["hello world", "HELLO WORLD", Regexp::IGNORECASE], ["ω+", "ΩΩω", Regexp::IGNORECASE],
    ["日本", "こんにちは日本語"], ["[あ-ん]+", "xxあいうxx"], [".", "\u{1F600}"], ["\\w+", "héllo wörld"], ["(?a)\\w+", "héllo"],
    ["a{100000}", "a" * 10], ["(a+)+b", "aaaaaaaaaac"], ["(?<r>a\\g<r>?)", "aaaa"], ["\\G\\d", "12x3"],
    ["$", "abc\n"], ["^", "\nabc"], ["(?m:.)*", "a\nb"], ["\\A\\z", ""], ["a$", "a\n"], ["\\R", "a\r\nb"], ["\\R", "a\rb"],
    ["\\p{^Alpha}+", "abc123"], ["[[:alpha:]]+", "abc123"], ["[[:^alpha:]]+", "abc123"], ["[^a]", "é"], ["\\S+", "  x  "],
    ["(a)|(b)", "b"], ["(?<x>a)|(?<x>b)\\k<x>", "bb"], ["(?<x>a)\\k<x+0>", "aa"],["(?<a>.)(?<b>.)\\k<a+0>", "abab"],
    ["a(?=b)", "ab"], ["(?:(a)|b)*", "abab"], ["(a*)+", "aaa"], ["(a|)+b", "aab"], ["(?:a?)*b", "aab"], ["()*", "x"],
    ["[[:upper:]]+", "abcDEFghi"], ["\\p{Hiragana}+", "abcあいうdef"], ["\\p{In_Basic_Latin}+", "abcあ"], ["\\p{Emoji}", "x\u{1F600}"],
    ["(?i)straße", "STRASSE"], ["(?i)ǆ", "ǅ"], ["(?i)[k]", "K"], ["(?i)[^k]", "K"], ["(?i)\\p{Lu}", "a"],
    ["a.c", "a\nc"], ["(?m)a.c", "a\nc"], ["a\\nc", "a\nc"], ["\\x41", "A"],["\\p{Word}+", "héllo_1"],
    ["(?<!^)x", "x\nx"], ["(?<=^)x", "\nx"], ["(?<=\\A)x", "x"], ["(?<=a{2})b", "aab"], ["(?<=a|b|cd)x", "cdx"],
    ["\\A(?:a|ab)(?:c|bcd)(?:d*)\\z", "abcd"], ["^(?:(?:a|b)c)+$", "acbc"], ["(?:x+x+)+y", "xxxxxxxxxxy"],
  ].freeze

  CASES.each_with_index do |(pat, subject, opts), i|
    define_method("test_case_#{i}_#{pat.gsub(/[^a-z0-9]/i, "_")[0, 30]}") { check(pat, subject, opts || 0) }
  end

  def test_search_from_an_offset
    check("a+", "aaa aa a", start: 2)
    check("a+", "aaa aa a", start: 3)
    check("\\bx", "xx x", start: 1)
    check("^x", "x\nx", start: 1)
    check("^x", "x\nx", start: 2)
    check("(?<=a)b", "ab", start: 1)
    check("日", "日本日本", start: 3)
  end

  def test_backward_search
    check("a", "xaxax", backward: true, start: 5)
    check("ab", "abab", backward: true, start: 3)
    check("ab", "abab", backward: true, start: 2)
    check("a+", "aaa", backward: true, start: 3)
    check("^a", "a\na", backward: true, start: 3)
    check("a$", "a\na", backward: true, start: 3)
    check("日本", "日本日本", backward: true, start: 12)
    check("x", "日本", backward: true, start: 6)
    check("(?i)ab", "AbaB", backward: true, start: 4)
    check("\\z", "abc", backward: true, start: 3)
    check("", "abc", backward: true, start: 3)
    check("[a-z]+", "ab1cd", backward: true, start: 5)
    check("cd$", "ab1cd", backward: true, start: 5)
  end

  def test_match_at_a_position
    check("a+", "xaaa", at: true, start: 1)
    check("a+", "xaaa", at: true, start: 0)
    check("\\Ga", "xa", at: true, start: 1)
    check("(x)(y)", "xy", at: true, start: 0)
    check("日本", "日本", at: true, start: 0)
  end

  def test_ascii_subjects_match_bytewise
    check("\\w+", "h\xE9llo".b)
    check("[^a]", "\xE9".b)
    check("(?i)k", "\xE2\x84\xAA".b)
    check(".", "\xE2\x84\xAA".b)
    check("a.b", "a\xFFb".b)
    check("\\p{Alpha}", "A".b)
  end

  def test_the_time_limit_stops_a_match
    got = kernel("(a+)+b\\1", 0, "a" * 40 + "c", limit: 1)
    assert_equal [:error, -23], got
    assert_nil kernel("(a+)+b", 0, "aaac", limit: 10_000_000_000)
  end

  # The match cache: patterns that backtrack exponentially without it
  # finish in linear time with it, as they do under ruby.
  def test_the_match_cache_keeps_matching_linear
    check("(a+)+$", "a" * 40 + "!")
    check("(a*)*b", "a" * 40 + "!")
    check("(?:a|a)*c", "a" * 40)
    check("(a|aa)+$", "a" * 60 + "b")
    check("^(?:a?){40}a{40}$", "a" * 40)
    check("(?:(?=a)a|b)*c", "a" * 30 + "b")
    check("(?>a|ab)*c", "ab" * 20 + "d")
    check("(x+x+)+y", "x" * 40)
    check("(?:.*a){20}b", "a" * 30)
    check("(?:a+)+(?!b)c", "a" * 40 + "b")
  end
end
