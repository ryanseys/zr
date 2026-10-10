# frozen_string_literal: true

# The encodings ruby hands Onigmo (OnigEncodingType): what the shared
# helpers of regenc.c do over each encoding's primitives, the
# single-byte encodings (enc/ascii.c, us_ascii.c, iso_8859_*.c,
# koi8_*.c, windows_125*.c), and which one reads each of ruby's
# encodings. The Unicode encodings are in encoding_unicode.rb, the
# other multibyte ones in encoding_multibyte.rb. A pattern or subject
# is a binary String and a position is a byte offset into it. A port
# under the BSD-2-Clause license reproduced in regexp.rb.
class Regexp
  module Onig
    module Enc
      # ONIGENC_CONSTRUCT_MBCLEN_INVALID
      INVALID = -1

      # The shared helpers of regenc.c, over the per-encoding primitives.
      class Base
        # onigenc_mbclen: the length of the character at `p`, cut at
        # `e`; an invalid byte counts one.
        def len(s, p, e)
          ret = precise_len(s, p, e)
          if ret > 0
            ret = e - p if p + ret > e
            ret
          elsif ret < -1
            e - p
          else
            p < e ? 1 : 0
          end
        end

        # rb_enc_precise_mbclen over the rest of `bytes`: a positive length,
        # or the negative ONIGENC_CONSTRUCT_MBCLEN_* of an invalid or cut
        # character.
        def precise_mbclen(bytes, i)
          left = bytes.bytesize - i
          return -2 if left <= 0

          n = precise_len(bytes, i, bytes.bytesize)
          n > 0 && left < n ? -1 - (n - left) : n
        end

        # rb_enc_mbclen: the character's length, or the encoding's shortest
        # where no whole character starts.
        def mbclen(bytes, i)
          left = bytes.bytesize - i
          n = precise_mbclen(bytes, i)
          return n if n > 0 && n <= left

          min_len <= left ? min_len : left
        end

        # rb_enc_ascget: [the ASCII character at `i`, its byte length], or
        # nil when the character there is past ASCII or no character.
        # `compat` says the encoding is ASCII-compatible.
        def ascget(bytes, i, compat)
          return nil if i >= bytes.bytesize

          if compat
            c = bytes.getbyte(i)
            return c < 0x80 ? [c, 1] : nil
          end
          n = precise_mbclen(bytes, i)
          return nil if n <= 0

          c = mbc_to_code(bytes, i, bytes.bytesize)
          c < 0x80 ? [c, n] : nil
        end

        # onigenc_mbclen_approximate: the length the lead byte announces
        # even past `e`.
        def len_approx(s, p, e)
          ret = precise_len(s, p, e)
          if ret > 0 then ret
          elsif ret < -1 then (e - p) + (-1 - ret)
          else 1
          end
        end

        # enclen (regenc.h:94)
        def enclen(s, p, e) = max_len == min_len ? (p < e ? min_len : 0) : len(s, p, e)

        def right_adjust_char_head(s, start, p, e)
          q = left_adjust_char_head(s, start, p, e)
          q += enclen(s, q, e) if q < p
          q
        end

        def prev_char_head(s, start, p, e)
          return nil if p <= start

          left_adjust_char_head(s, start, p - 1, e)
        end

        def step_back(s, start, p, e, n)
          while !p.nil? && n > 0
            n -= 1
            return nil if p <= start

            p = left_adjust_char_head(s, start, p - 1, e)
          end
          p
        end

        def step(s, p, e, n)
          q = p
          n.times { q += len(s, q, e) }
          q <= e ? q : nil
        end

        def strlen(s, p, e)
          n = 0
          q = p
          while q < e
            q += len(s, q, e)
            n += 1
          end
          n
        end

        # onigenc_with_ascii_strncmp: `sascii` (ASCII bytes) against the
        # next `n` characters at `p`; 0 when they agree.
        def with_ascii_strncmp(s, p, e, sascii, n)
          n.times do |i|
            return sascii.getbyte(i) if p >= e

            x = sascii.getbyte(i) - mbc_to_code(s, p, e)
            return x if x != 0

            p += enclen(s, p, e)
          end
          0
        end

        def with_ascii_strnicmp(s, p, e, sascii, n)
          n.times do |i|
            return sascii.getbyte(i) if p >= e

            c = mbc_to_code(s, p, e)
            c = ascii_lower(c) if c < 0x80
            x = ascii_lower(sascii.getbyte(i)) - c
            return x if x != 0

            p += enclen(s, p, e)
          end
          0
        end

        # ONIGENC_ASCII_CODE_TO_LOWER_CASE, for a code under 256.
        def ascii_lower(c) = c >= 0x41 && c <= 0x5a ? c + 0x20 : c

        # ONIGENC_IS_ASCII_CODE_CTYPE over OnigEncAsciiCtypeTable.
        def ascii_code_ctype?(code, ctype) = code < 128 && Enc.ascii_ctype?(code, ctype)

        # CTYPE_IS_WORD_GRAPH_PRINT
        def word_graph_print?(ctype) = ctype == CType::WORD || ctype == CType::GRAPH || ctype == CType::PRINT

        def mbc_word?(s, p, e) = code_ctype?(mbc_to_code(s, p, e), CType::WORD)
        def mbc_ascii_word?(s, p, e) = ascii_code_ctype?(mbc_to_code(s, p, e), CType::WORD)
        def mbc_newline?(s, p, e) = p < e && s.getbyte(p) == 0x0a
        def allowed_reverse_match?(_s, _p, _e) = true
        def singlebyte? = max_len == 1
        def unicode? = false
        def ctype_code_range(_ctype) = nil

        # onigenc_ascii_apply_all_case_fold
        def ascii_apply_all_case_fold
          (0x41..0x5a).each do |upper|
            lower = upper + 0x20
            yield upper, [lower]
            yield lower, [upper]
          end
        end

        # onigenc_ascii_get_case_fold_codes_by_str: [[byte length, codes]]
        def ascii_case_fold_codes_by_str(s, p)
          c = s.getbyte(p)
          if c >= 0x41 && c <= 0x5a then [[1, [c + 0x20]]]
          elsif c >= 0x61 && c <= 0x7a then [[1, [c - 0x20]]]
          else []
          end
        end

        # onigenc_apply_all_case_fold_with_map
        def apply_all_case_fold_with_map(map, ess_tsett, &block)
          ascii_apply_all_case_fold(&block)
          map&.each_slice(2) do |from, to|
            yield from, [to]
            yield to, [from]
          end
          yield 0xdf, [0x73, 0x73] if ess_tsett
        end

        # onigenc_get_case_fold_codes_by_str_with_map, for a byte map.
        def case_fold_codes_by_str_with_map(map, ess_tsett, s, p, e)
          c = s.getbyte(p)
          if c >= 0x41 && c <= 0x5a
            items = [[1, [c + 0x20]]]
            items << [2, [0xdf]] if c == 0x53 && ess_tsett && e > p + 1 && (s.getbyte(p + 1) == 0x53 || s.getbyte(p + 1) == 0x73)
            items
          elsif c >= 0x61 && c <= 0x7a
            items = [[1, [c - 0x20]]]
            items << [2, [0xdf]] if c == 0x73 && ess_tsett && e > p + 1 && (s.getbyte(p + 1) == 0x73 || s.getbyte(p + 1) == 0x53)
            items
          elsif c == 0xdf && ess_tsett
            [[1, [0x73, 0x73]], [1, [0x53, 0x53]], [1, [0x73, 0x53]], [1, [0x53, 0x73]]]
          else
            map&.each_slice(2) do |from, to|
              return [[1, [to]]] if c == from
              return [[1, [from]]] if c == to
            end
            []
          end
        end

        # onigenc_minimum_property_name_to_ctype
        MINIMUM_PROPERTIES = {
          "Alnum" => CType::ALNUM, "Alpha" => CType::ALPHA, "Blank" => CType::BLANK,
          "Cntrl" => CType::CNTRL, "Digit" => CType::DIGIT, "Graph" => CType::GRAPH,
          "Lower" => CType::LOWER, "Print" => CType::PRINT, "Punct" => CType::PUNCT,
          "Space" => CType::SPACE, "Upper" => CType::UPPER, "XDigit" => CType::XDIGIT,
          "ASCII" => CType::ASCII, "Word" => CType::WORD,
        }.freeze

        # The name at `p` is read under `reader`: the encoding itself, or
        # ASCII for the names the parser writes (propname2ctype).
        def minimum_property_name_to_ctype(s, p, e, reader = self)
          len = reader.strlen(s, p, e)
          MINIMUM_PROPERTIES.each do |name, ctype|
            return ctype if len == name.bytesize && reader.with_ascii_strnicmp(s, p, e, name, name.bytesize) == 0
          end
          Err::INVALID_CHAR_PROPERTY_NAME
        end

        def property_name_to_ctype(s, p, e, reader = self) = minimum_property_name_to_ctype(s, p, e, reader)

        # What the kernel's matcher reads of this encoding (lib/zr/runtime/kernel/
        # onig_enc.rb): the kind of its primitives, then the tables they
        # read, as lib/zr/runtime/core/regexp/onig/program.rb lays them out.
        def descriptor
          Enc.descriptors[name] ||= Enc.descriptor(kernel_kind, min_len, max_len, kernel_tables).freeze
        end

        def kernel_tables = {}
      end

      # The kinds of encoding that the kernel's matcher distinguishes, in
      # lib/zr/runtime/kernel/onig_enc.rb's numbering.
      KIND_SINGLE_BYTE = 0
      KIND_UTF8 = 1
      KIND_EUC_JP = 2
      KIND_SHIFT_JIS = 3
      KIND_TRAIL = 4
      KIND_EUC_KR = 5
      KIND_EUC_TW = 6
      KIND_GB18030 = 7
      KIND_EMACS_MULE = 8
      KIND_CESU8 = 9
      KIND_UTF16LE = 10
      KIND_UTF16BE = 11
      KIND_UTF32LE = 12
      KIND_UTF32BE = 13

      # The descriptor's header: eight 64-bit words (kind, min_len,
      # max_len, flags, then the offsets of the len, trail, lower and
      # word tables), two more (trans, map) and the tables after it. An
      # offset of 0 is a table the encoding has none of.
      DESCRIPTOR_TABLES = %i[len trail lower word trans map].freeze
      @descriptors = {}

      def self.descriptors = @descriptors
      FLAG_SHARP_S = 1

      def self.descriptor(kind, min_len, max_len, tables)
        flags = tables[:sharp_s] ? FLAG_SHARP_S : 0
        header_size = (4 + DESCRIPTOR_TABLES.size) * 8
        body = "".b
        offsets = DESCRIPTOR_TABLES.map do |name|
          table = tables[name]
          next 0 if table.nil?

          at = header_size + body.bytesize
          body << table.b
          body << "\0".b * (((body.bytesize + 7) & ~7) - body.bytesize)
          at
        end
        ([kind, min_len, max_len, flags] + offsets).pack("q<*") << body
      end

      # OnigEncAsciiCtypeTable
      def self.ascii_ctype?(code, ctype)
        bits = EncTables::ASCII_CTYPE.getbyte(code * 2) | (EncTables::ASCII_CTYPE.getbyte((code * 2) + 1) << 8)
        bits[ctype] == 1
      end

      # A single-byte encoding: ASCII-8BIT and US-ASCII with the ASCII
      # tables, the others with their own ctype bits, lower-case table
      # and fold pairs (EncTables::SINGLE_BYTE).
      class SingleByte < Base
        attr_reader :name

        # `ctype` nil reads the ASCII table (onigenc_ascii_is_code_ctype);
        # `fold` is :ascii (onigenc_ascii_*), :map (the *_with_map pair)
        # or :iso_8859_1 (its own get_case_fold_codes_by_str).
        def initialize(name, ctype, lower, fold, sharp_s, map, ess_tsett, us_ascii: false)
          @name = name
          @ctype = ctype
          @lower = lower
          @fold = fold
          @sharp_s = sharp_s
          @map = map&.bytes
          @ess_tsett = ess_tsett != 0
          @us_ascii = us_ascii
        end

        def max_len = 1
        def min_len = 1

        # onigenc_single_byte_mbc_enc_len; us_ascii_mbc_enc_len refuses
        # a byte past ASCII.
        def precise_len(s, p, _e) = @us_ascii && s.getbyte(p) >= 0x80 ? INVALID : 1
        def mbc_to_code(s, p, _e) = s.getbyte(p)

        # onigenc_single_byte_code_to_mbclen and _code_to_mbc as ruby
        # builds them: one byte for any code, and a code past a byte
        # refused as ruby refuses it.
        def code_to_mbclen(_code) = 1

        def code_to_mbc(code)
          raise RangeError, "#{code} out of char range" if code > 0xff

          code.chr.b
        end

        def left_adjust_char_head(_s, _start, p, _e) = p

        def code_ctype?(code, ctype)
          return ascii_code_ctype?(code, ctype) if @ctype.nil?
          return false if code >= 256

          (@ctype.getbyte(code * 2) | (@ctype.getbyte((code * 2) + 1) << 8))[ctype] == 1
        end

        # [the folded bytes, the bytes read]
        def mbc_case_fold(flag, s, p, _e)
          c = s.getbyte(p)
          return [ascii_lower(c).chr.b, 1] if @fold == :ascii
          return ["ss".b, 1] if @sharp_s && c == 0xdf && (flag & CASE_FOLD_MULTI_CHAR) != 0

          [@lower.getbyte(c).chr.b, 1]
        end

        def apply_all_case_fold(_flag, &block)
          return ascii_apply_all_case_fold(&block) if @fold == :ascii

          apply_all_case_fold_with_map(@map, @ess_tsett, &block)
        end

        def case_fold_codes_by_str(_flag, s, p, e)
          case @fold
          when :ascii then ascii_case_fold_codes_by_str(s, p)
          when :map then case_fold_codes_by_str_with_map(@map, @ess_tsett, s, p, e)
          else iso_8859_1_case_fold_codes_by_str(s, p, e)
          end
        end

        # iso_8859_1.c get_case_fold_codes_by_str
        def iso_8859_1_case_fold_codes_by_str(s, p, e)
          c = s.getbyte(p)
          if c >= 0x41 && c <= 0x5a
            items = [[1, [c + 0x20]]]
            items << [2, [0xdf]] if c == 0x53 && e > p + 1 && (s.getbyte(p + 1) == 0x53 || s.getbyte(p + 1) == 0x73)
            items
          elsif c >= 0x61 && c <= 0x7a
            items = [[1, [c - 0x20]]]
            items << [2, [0xdf]] if c == 0x73 && e > p + 1 && (s.getbyte(p + 1) == 0x73 || s.getbyte(p + 1) == 0x53)
            items
          elsif c >= 0xc0 && c <= 0xcf
            [[1, [c + 0x20]]]
          elsif c >= 0xd0 && c <= 0xdf
            if c == 0xdf
              [[1, [0x73, 0x73]], [1, [0x53, 0x53]], [1, [0x73, 0x53]], [1, [0x53, 0x73]]]
            elsif c != 0xd7
              [[1, [c + 0x20]]]
            else
              []
            end
          elsif c >= 0xe0 && c <= 0xef
            [[1, [c - 0x20]]]
          elsif c >= 0xf0 && c <= 0xfe && c != 0xf7
            [[1, [c - 0x20]]]
          else
            []
          end
        end

        def kernel_kind = KIND_SINGLE_BYTE

        # The lower-case byte of each byte (the ASCII one for an :ascii
        # fold) and whether each byte is a word character.
        def kernel_tables
          lower = Array.new(256) { |b| @fold == :ascii ? ascii_lower(b) : @lower.getbyte(b) }
          word = Array.new(256) { |b| code_ctype?(b, CType::WORD) ? 1 : 0 }
          { lower: lower.pack("C*"), word: word.pack("C*"), sharp_s: @fold != :ascii && @sharp_s }
        end
      end

      ASCII_ENC = SingleByte.new("ASCII-8BIT", nil, nil, :ascii, false, nil, 0).freeze
      US_ASCII_ENC = SingleByte.new("US-ASCII", nil, nil, :ascii, false, nil, 0, us_ascii: true).freeze

      @encodings = {}

      # The Onigmo encoding a String in `encoding` is read with: a dummy
      # encoding reads as ASCII-8BIT, which ruby replicates it from.
      def self.reader(encoding) = encoding.dummy? ? ASCII_ENC : self.for(encoding)

      # The Onigmo encoding that reads ruby's `encoding` (a replica reads
      # with its base's), made once.
      def self.for(encoding)
        base = EncTables::BASES.fetch(encoding.name) { raise ArgumentError, "no Onigmo encoding reads #{encoding.name}" }
        @encodings[base] ||= build(base)
      end

      def self.build(name)
        case name
        when "ASCII-8BIT" then ASCII_ENC
        when "US-ASCII" then US_ASCII_ENC
        when "UTF-8" then UTF8_ENC
        when "UTF-16LE" then UTF16LE.new.freeze
        when "UTF-16BE" then UTF16BE.new.freeze
        when "UTF-32LE" then UTF32LE.new.freeze
        when "UTF-32BE" then UTF32BE.new.freeze
        when "CESU-8" then CESU8.new.freeze
        when "EUC-JP" then EUCJP.new.freeze
        when "Shift_JIS" then ShiftJIS.new(name, EncTables::SHIFT_JIS_PROPS).freeze
        when "Windows-31J" then ShiftJIS.new(name, EncTables::WINDOWS_31J_PROPS).freeze
        when "Big5" then Trail.new(name, EncTables::BIG5).freeze
        when "GBK" then Trail.new(name, EncTables::GBK).freeze
        when "CP949" then Trail.new(name, EncTables::CP949).freeze
        when "EUC-KR" then EUCKR.new.freeze
        when "EUC-TW" then EUCTW.new.freeze
        when "GB18030" then GB18030.new.freeze
        when "Emacs-Mule" then EmacsMule.new.freeze
        else SingleByte.new(name, *EncTables::SINGLE_BYTE.fetch(name)).freeze
        end
      end
    end
  end
end

class Regexp
  # The descriptor through which the kernel reads the characters of
  # `encoding` (lib/zr/runtime/kernel/onig_enc.rb), as the matcher reads
  # them. The C API's rb_encoding keeps its address, and Enc.descriptors
  # keeps it alive.
  def self.onig_descriptor(encoding)
    Primitive.attr! :hidden
    Onig::Enc.reader(encoding).descriptor
  end

  # onig_new: a Regexp of `source` under ONIG_OPTION_* bits `options`,
  # whose low three are Ruby's IGNORECASE, EXTENDED and MULTILINE; or,
  # for a pattern that does not compile, the Onigmo code of its error,
  # which the RegexpError's cause keeps.
  def self.c_onig_new(source, options)
    Primitive.attr! :hidden
    new(source, options & (IGNORECASE | EXTENDED | MULTILINE))
  rescue RegexpError => e
    e = e.cause until e.nil? || e.is_a?(Onig::Error)
    e ? e.code : Onig::Err::PARSER_BUG
  end

  # onig_error_code_to_str: Onigmo's text for the error `code`.
  def self.c_onig_error(code)
    Primitive.attr! :hidden
    Onig::Err.text(code)
  end
end
