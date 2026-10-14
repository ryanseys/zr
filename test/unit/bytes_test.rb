# frozen_string_literal: true

require "test_helper"
require_relative "../../lib/zr/bytes"

# `Zr::Bytes` replaced a dozen private copies of the same alignment,
# padding and LEB128 arithmetic across the object writers and backends.
# This checks the formulas against known values, not just against
# themselves.
class BytesTest < Minitest::Test
  def test_align_rounds_up_to_the_next_multiple
    assert_equal 16, Zr::Bytes.align(9, 16)
  end

  def test_align_leaves_an_already_aligned_value
    assert_equal 16, Zr::Bytes.align(16, 16)
  end

  def test_align_with_alignment_one_is_the_identity
    assert_equal 9, Zr::Bytes.align(9, 1)
  end

  def test_pad_appends_zero_bytes_to_reach_the_size
    bytes = +"ab".b

    result = Zr::Bytes.pad(bytes, 5)

    assert_equal "ab\0\0\0".b, result
  end

  def test_pad_does_nothing_when_already_at_size
    bytes = +"abcde".b

    result = Zr::Bytes.pad(bytes, 5)

    assert_equal "abcde".b, result
  end

  def test_pad_align_appends_zero_bytes_to_the_next_multiple
    bytes = +"abcde".b

    result = Zr::Bytes.pad_align(bytes, 4)

    assert_equal "abcde\0\0\0".b, result
  end

  def test_pad_align_leaves_an_aligned_string
    bytes = +"abcd".b

    result = Zr::Bytes.pad_align(bytes, 4)

    assert_equal "abcd".b, result
  end

  def test_pad_returns_the_same_string_it_mutated
    bytes = +"a".b

    result = Zr::Bytes.pad(bytes, 3)

    assert_same bytes, result
  end

  def test_uleb_encodes_a_value_under_128_as_one_byte
    assert_equal "\x00".b, Zr::Bytes.uleb(0)
    assert_equal "\x7F".b, Zr::Bytes.uleb(127)
  end

  # 128 is 0b1000_0000: the low 7 bits are zero, so the continuation byte
  # carries the high bit and the next byte holds the rest.
  def test_uleb_encodes_a_value_at_the_byte_boundary
    assert_equal "\x80\x01".b, Zr::Bytes.uleb(128)
  end

  # The worked example from the WASM and DWARF specs.
  def test_uleb_encodes_a_multi_byte_value
    assert_equal "\xE5\x8E\x26".b, Zr::Bytes.uleb(624_485)
  end

  def test_uleb_size_matches_the_length_of_uleb
    [0, 1, 127, 128, 16_384, 624_485].each do |n|
      assert_equal Zr::Bytes.uleb(n).bytesize, Zr::Bytes.uleb_size(n)
    end
  end

  def test_leb_is_the_same_encoding_as_uleb
    assert_equal Zr::Bytes.uleb(624_485), Zr::Bytes.leb(624_485)
  end

  def test_sleb_encodes_a_small_positive_value_as_one_byte
    assert_equal "\x02".b, Zr::Bytes.sleb(2)
  end

  def test_sleb_encodes_a_small_negative_value_as_one_byte
    assert_equal "\x7E".b, Zr::Bytes.sleb(-2)
  end

  # The worked example from the DWARF spec.
  def test_sleb_encodes_a_multi_byte_negative_value
    assert_equal "\x9B\xF1\x59".b, Zr::Bytes.sleb(-624_485)
  end

  def test_sleb_round_trips_through_a_decoder
    [-624_485, -128, -1, 0, 1, 127, 128, 624_485].each do |n|
      assert_equal n, decode_sleb(Zr::Bytes.sleb(n))
    end
  end

  private

  # A minimal SLEB128 decoder, independent of `Zr::Bytes`, to check
  # `sleb` against something other than itself.
  def decode_sleb(bytes)
    result = 0
    shift = 0
    byte = 0
    bytes.each_byte do |b|
      byte = b
      result |= (b & 0x7F) << shift
      shift += 7
      break if (b & 0x80).zero?
    end
    result |= (-1 << shift) if shift < 64 && (byte & 0x40) != 0
    result
  end
end
