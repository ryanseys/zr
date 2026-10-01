# frozen_string_literal: true

require "test_helper"
require "prism"
require_relative "../../lib/zr/runtime/core/regexp/unicode_tables"

# lib/zr/runtime/core/regexp/unicode_tables.rb (the plain-Ruby parser's tables)
# and lib/zr/runtime/kernel/onig_tables.rb (the kernel matcher's byte tables)
# each carry the Latin-1 ctype bits and the full case folds a second
# time, in a different encoding: 16-bit words in a String constant
# against 32-bit words in a "machine def" byte table, and BER-packed
# variable-width rows against fixed-width zero-padded ones.
# `zr-dev gen onig_unicode` (tool/gen/onig_unicode.rb) computes each
# value once and writes it twice, so the two files cannot drift apart.
# This test decodes both encodings straight from the committed files
# and checks that they hold the same data.
class OnigUnicodeTest < Minitest::Test
  KERNEL_PATH = File.join(ROOT, "lib/zr/runtime/kernel/onig_tables.rb")

  def test_the_generated_files_are_current
    out, ok = Checks.generate("onig_unicode")

    assert ok, out
  end

  def test_ctype_bits_are_the_same_256_words_in_both_files
    core_words = Regexp::Onig::Unicode::CTYPE_BITS.unpack("v*")

    kernel_words = machine_bytes(KERNEL_PATH, :zr_onig_ctype_bits).unpack("V*")

    assert_equal core_words, kernel_words
  end

  def test_case_fold_is_the_same_map_in_both_files
    core_fold = decode_ber_fold(Regexp::Onig::Unicode::CASE_FOLD)

    kernel_fold = decode_word_fold(machine_bytes(KERNEL_PATH, :zr_onig_fold_rows))

    assert_equal core_fold, kernel_fold
  end

  private

  # The bytes a kernel file's `machine def function_name` passes to
  # Machine.bytes, read with prism the way zr's own lowering reads them
  # (lib/zr/machine/lower.rb): `machine def name ... end` is a call to
  # `machine` with the def as its argument, since `def` is itself an
  # expression.
  def machine_bytes(path, function_name)
    program = Prism.parse_file(path).value
    call = program.statements.body.find do |node|
      node.is_a?(Prism::CallNode) && node.name == :machine &&
        node.arguments.arguments.first.is_a?(Prism::DefNode) &&
        node.arguments.arguments.first.name == function_name
    end
    call or raise "no machine def #{function_name} in #{path}"

    defn = call.arguments.arguments.first
    bytes_call = defn.body.body.find { |node| node.is_a?(Prism::CallNode) && node.receiver && node.name == :bytes }
    bytes_call.arguments.arguments.first.unescaped
  end

  # CASE_FOLD's rows (tool/gen/onig_unicode.rb's `fold_words`): a
  # from code, how many codes it folds to, then those codes,
  # BER-packed one row after another.
  def decode_ber_fold(bytes)
    words = bytes.unpack("w*")
    rows = {}
    index = 0
    while index < words.size
      from, count = words[index, 2]
      rows[from] = words[index + 2, count]
      index += 2 + count
    end
    rows
  end

  # zr_onig_fold_rows's rows: a row count, then that many fixed-width
  # rows of (from, how many codes, three codes zero-padded).
  def decode_word_fold(bytes)
    words = bytes.unpack("V*")
    count = words.shift
    words.each_slice(5).first(count).to_h { |from, n, *codes| [from, codes.first(n)] }
  end
end
