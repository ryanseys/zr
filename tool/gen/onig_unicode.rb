# frozen_string_literal: true

require_relative "../gen"
require "rbconfig"

module Zr
  module Dev
    class Gen
      # Onigmo's Unicode 17.0 tables, checked against the ruby the
      # .ruby-version pins and written as the tables the runtime's Regexp
      # engine reads: the property tables and case folds the plain-Ruby
      # parser reads (lib/zr/runtime/core/regexp/unicode_tables.rb) and the byte
      # tables the kernel matcher reads (lib/zr/runtime/kernel/onig_tables.rb).
      #
      #   zr-dev gen onig_unicode
      #
      # The structure comes from CRuby's own generated headers, read at
      # development time and never vendored: which keyword names which
      # table and the order of the code ranges from
      # enc/unicode/17.0.0/name2ctype.h, the fold rows and their order
      # from casefold.h, the Latin-1 ctype bits from enc/unicode.c. Every
      # table's content is then held to ruby itself: each property to a
      # scan of every code point, each fold to String#downcase(:fold),
      # each unfold to the fold's inverse. A table ruby disagrees with
      # stops the run.
      #
      # The Latin-1 ctype bits and the full case folds each cross into
      # both files: CTYPE_BITS (the core file) and zr_onig_ctype_bits
      # (the kernel file) carry the same 256 words, one packed as
      # 16-bit words for the String the parser decodes and the other as
      # 32-bit words for the kernel's byte table; CASE_FOLD and
      # zr_onig_fold_rows carry the same fold rows, one BER-packed and
      # the other fixed-width. This generator computes each value once
      # and writes it twice, so the two files cannot drift apart.
      class OnigUnicode < Command
        host_ruby!
        usage "[--check]"

        UNICODE = "17.0.0"

        def defaults = @check = false

        def options(o) = o.on("--check", "write nothing; fail when a file is out of date") { @check = true }

        def run(_argv)
          Dev.pinned!(name)
          fail!("Unicode #{UNICODE} expected; ruby has #{RbConfig::CONFIG["UNICODE_VERSION"]}") unless RbConfig::CONFIG["UNICODE_VERSION"] == UNICODE

          tables, order, properties = name2ctype
          ctype_bits = latin1_ctype_bits
          case_fold, unfold1, unfold2, unfold3 = casefold_rows

          hold_properties_to_ruby(tables, order, properties)
          note_latin1_bits(tables, order, ctype_bits)
          hold_folds_to_ruby(case_fold, unfold1, unfold2, unfold3)

          @current = true
          @current &= Dev.write("lib/zr/runtime/core/regexp/unicode_tables.rb", check: @check) do |io|
            write_core(io, properties, order, tables, ctype_bits, case_fold, unfold1, unfold2, unfold3)
          end
          @current &= Dev.write("lib/zr/runtime/kernel/onig_tables.rb", check: @check) do |io|
            write_kernel(io, tables, order, ctype_bits, case_fold)
          end
          @current
        end

        private

        # ---- name2ctype.h: the code range tables and the keyword list ----

        # The header with its #ifdef blocks resolved for the macros
        # CRuby defines (regenc.h:139-140). `#if` bodies (the character
        # set check) are never taken.
        def preprocess(text, defined)
          out = +""
          stack = []
          active = true
          text.each_line do |line|
            case line
            when /\A#\s*(ifdef|ifndef|if)\b\s*(\w+)?/
              taken = case $1
                      when "ifdef" then defined.include?($2)
                      when "ifndef" then !defined.include?($2)
                      else false
                      end
              stack << [active, taken]
              active &&= taken
            when /\A#\s*else/
              parent, taken = stack.last
              active = parent && !taken
              stack[-1] = [parent, true]
            when /\A#\s*endif/
              active, = stack.pop
            else
              out << line if active
            end
          end
          out
        end

        def name2ctype
          names = preprocess(Dev.cruby("enc/unicode/#{UNICODE}/name2ctype.h"), %w[USE_UNICODE_PROPERTIES USE_UNICODE_AGE_PROPERTIES])

          tables = {}
          names.scan(/static const OnigCodePoint (CR_\w+)\[\] = \{\s*(\d+),\s*((?:0x[0-9a-f]+, 0x[0-9a-f]+,\s*)*)\};/m) do |tname, count, body|
            pairs = body.scan(/0x([0-9a-f]+), 0x([0-9a-f]+)/).map { |lo, hi| [lo.hex, hi.hex] }
            fail!("#{tname}: #{pairs.size} ranges, #{count} announced") unless pairs.size == count.to_i

            pairs.each_cons(2) { |a, b| fail!("#{tname}: ranges out of order") unless a[1] < b[0] }
            tables[tname] = pairs
          end
          # A property whose ranges are another's is a #define of that
          # table's name.
          names.scan(/^#define (CR_\w+) (CR_\w+)$/) { |alias_name, tname| tables[alias_name] = tables.fetch(tname) }

          order = names[/CodeRanges\[\] = \{(.*?)\};/m, 1].scan(/CR_\w+/)
          fail!("a CodeRanges entry has no table") unless order.all? { |tname| tables.key?(tname) }
          fail!("#{order.size} tables; 685 expected") unless order.size == 685

          pool = names.scan(/char uniname2ctype_pool_(str\d+)\[sizeof\("([^"]*)"\)\]/).to_h
          properties = {}
          names.scan(/\{uniname2ctype_offset\((str\d+)\), (\d+)\}/) do |str, ctype|
            keyword = pool.fetch(str)
            fail!("#{keyword} named twice") if properties.key?(keyword)

            properties[keyword] = ctype.to_i
          end
          fail!("#{properties.size} keywords; 944 expected") unless properties.size == 944
          fail!("a keyword names a table past the end") unless properties.values.all? { |i| i < order.size }

          [tables, order, properties]
        end

        # ---- enc/unicode.c: the Latin-1 ctype bits ----

        def latin1_ctype_bits
          unicode_c = Dev.cruby("enc/unicode.c")
          bits = unicode_c[/EncUNICODE_ISO_8859_1_CtypeTable\[256\] = \{(.*?)\};/m, 1].scan(/0x[0-9a-f]+/).map(&:hex)
          fail!("#{bits.size} ctype entries; 256 expected") unless bits.size == 256

          bits
        end

        # ---- casefold.h: the fold and unfold rows ----

        def table_body(text, tname) = text[/#{tname}\[\] = \{(.*?)\n\};/m, 1] || fail!("no #{tname} in casefold.h")

        def code_list(text) = text.scan(/0x[0-9a-f]+/).map(&:hex)

        def fold_rows(body)
          body.scan(/\{0x([0-9a-f]+), \{(\d+)[^,]*, \{([^}]*)\}\}\}/).map do |from, n, codes|
            codes = code_list(codes)
            fail!("a fold row announces #{n} codes and holds #{codes.size}") unless codes.size == n.to_i

            [from.hex, codes]
          end
        end

        def unfold_rows(body, width)
          body.scan(/\{\{([^}]*)\}, \{(\d+), \{([^}]*)\}\}\}/).map do |from, n, codes|
            from = code_list(from)
            codes = code_list(codes)
            fail!("an unfold row keys #{from.size} codes; #{width} expected") unless from.size == width
            fail!("an unfold row announces #{n} codes and holds #{codes.size}") unless codes.size == n.to_i

            [from, codes]
          end
        end

        def casefold_rows
          folds = Dev.cruby("enc/unicode/#{UNICODE}/casefold.h")
          case_fold = fold_rows(table_body(folds, "CaseFold_11_Table")).to_h
          unfold1 = fold_rows(table_body(folds, "CaseUnfold_11_Table")).to_h
          unfold2 = unfold_rows(table_body(folds, "CaseUnfold_12_Table"), 2).to_h
          unfold3 = unfold_rows(table_body(folds, "CaseUnfold_13_Table"), 3).to_h
          { "fold" => [case_fold, 1585], "unfold1" => [unfold1, 1451], "unfold2" => [unfold2, 59], "unfold3" => [unfold3, 14] }.each do |what, (table, expected)|
            fail!("#{table.size} #{what} rows; #{expected} expected") unless table.size == expected
          end
          [case_fold, unfold1, unfold2, unfold3]
        end

        # ---- ruby as the oracle ----

        # Every code point ruby can hold, as one String, and the code
        # point at each character offset of it (the surrogates are
        # skipped).
        def all_codes = @all_codes ||= (0..0x10FFFF).grep_v(0xD800..0xDFFF).pack("U*").freeze

        def code_at(offset) = offset < 0xD800 ? offset : offset + 0x800

        # The ranges ruby's \p{keyword} matches, from a scan of every
        # code point.
        def ruby_ranges(keyword)
          re = Regexp.new("\\p{#{keyword}}+")
          out = []
          all_codes.scan(re) do
            m = Regexp.last_match
            from = m.begin(0)
            to = m.end(0) - 1
            lo = code_at(from)
            hi = code_at(to)
            # A run may straddle the surrogate gap: split it as the
            # table does.
            if from < 0xD800 && to >= 0xD800
              out << [lo, 0xD7FF]
              out << [0xE000, hi]
            else
              out << [lo, hi]
            end
          end
          merge(out)
        end

        # Adjacent ranges joined, as a scan of `+` runs joins them.
        def merge(ranges)
          ranges.each_with_object([]) do |(lo, hi), out|
            if out.any? && out.last[1] + 1 >= lo
              out.last[1] = hi if hi > out.last[1]
            else
              out << [lo, hi]
            end
          end
        end

        # The surrogates are code points the tables may name but ruby
        # cannot hold, so a table is compared with them cut out.
        def without_surrogates(ranges)
          ranges.flat_map do |lo, hi|
            next [] if lo >= 0xD800 && hi <= 0xDFFF
            next [[lo, hi]] if hi < 0xD800 || lo > 0xDFFF

            out = []
            out << [lo, 0xD7FF] if lo < 0xD800
            out << [0xE000, hi] if hi > 0xDFFF
            out
          end
        end

        def hold_properties_to_ruby(tables, order, properties)
          failures = []
          by_index = properties.group_by { |_, i| i }.transform_values { |pairs| pairs.map(&:first) }
          order.each_with_index do |tname, index|
            keywords = by_index[index]
            next if keywords.nil? # NEWLINE has no keyword

            expected = merge(without_surrogates(tables[tname]))
            keywords.each do |keyword|
              got = ruby_ranges(keyword)
              next if got == expected

              failures << "#{tname} (\\p{#{keyword}}): ruby #{got.size} ranges, header #{expected.size}; first difference #{(got - expected).first.inspect} vs #{(expected - got).first.inspect}"
            end
          end
          report(failures)
        end

        # The Latin-1 bits beside the tables for code points under 256.
        # They part at a few code points (soft hyphen, NEL, section and
        # pilcrow, the superscript digits and fractions), and Onigmo
        # reads each where it reads it: the bits for a single code
        # point's class (\\b, \\w as an opcode), the tables for a
        # class's ranges past 0x7f. Both go on record.
        def note_latin1_bits(tables, order, ctype_bits)
          notes = []
          (0..14).each do |ctype|
            table = tables[order[ctype]]
            (0..255).each do |code|
              in_bits = ctype_bits[code][ctype] == 1
              in_table = table.any? { |lo, hi| code.between?(lo, hi) }
              notes << "#{order[ctype].delete_prefix("CR_")} at 0x#{code.to_s(16)}: bit #{in_bits}, table #{in_table}" unless in_bits == in_table
            end
          end
          warn "the Latin-1 bits part from the tables at #{notes.size} places (as in the C)"
        end

        # The folds against downcase(:fold), and the unfolds as the
        # fold's inverse (the header keeps its own order of the codes;
        # the sets must agree).
        def hold_folds_to_ruby(case_fold, unfold1, unfold2, unfold3)
          failures = []
          inverse1 = Hash.new { |h, k| h[k] = [] }
          inverse2 = Hash.new { |h, k| h[k] = [] }
          inverse3 = Hash.new { |h, k| h[k] = [] }
          all_codes.each_char do |char|
            cp = char.ord
            folded = char.downcase(:fold).codepoints
            if folded == [cp]
              failures << "fold #{cp.to_s(16)}: ruby keeps it, the header folds it to #{case_fold[cp].inspect}" if case_fold.key?(cp)
              next
            end
            failures << "fold #{cp.to_s(16)}: ruby folds to #{folded.inspect}, the header #{case_fold[cp].inspect}" unless case_fold[cp] == folded
            case folded.size
            when 1 then inverse1[folded[0]] << cp
            when 2 then inverse2[folded] << cp
            when 3 then inverse3[folded] << cp
            end
          end
          { "unfold1" => [unfold1, inverse1], "unfold2" => [unfold2, inverse2], "unfold3" => [unfold3, inverse3] }.each do |what, (table, inverse)|
            # A folded code unfolds to every code that folds to it, and
            # (when it is not its own fold) to itself: the header lists
            # the others.
            inverse.each do |key, froms|
              expected = froms.sort
              got = (table[key] || []).sort
              failures << "#{what} #{key.inspect}: ruby's inverse #{expected.inspect}, header #{got.inspect}" unless got == expected
            end
            table.each_key do |key|
              failures << "#{what} #{key.inspect}: in the header, not in ruby's inverse" unless inverse.key?(key)
            end
          end
          report(failures)
        end

        def report(failures)
          return if failures.empty?

          failures.first(40).each { |line| warn "  #{line}" }
          fail!("#{failures.size} disagreement(s) with ruby")
        end

        # ---- written ----
        #
        # Every table is one String literal, which a module carries as
        # data. Written as Hash and Array literals, the file's body was
        # one function of 725 KB of wasm that alone cost wasmtime 3.6 GB
        # to compile; as Strings it is a handful of instructions, and
        # the engine decodes a table the first time a pattern needs it
        # (Unicode in encoding.rb).

        # A String literal of `bytes` the Ruby parser reads back byte
        # for byte, in lines of about 96 columns joined by escaped
        # newlines.
        def literal(bytes)
          chars = bytes.each_byte.map do |b|
            if b >= 0x20 && b < 0x7F && b != 0x22 && b != 0x5C && b != 0x23
              b.chr
            else
              format("\\x%02X", b)
            end
          end
          rows = []
          row = +""
          chars.each do |c|
            if row.size + c.size > 96
              rows << row
              row = +""
            end
            row << c
          end
          rows << row
          "\"#{rows.join("\\\n")}\".b.freeze"
        end

        # A table as BER-packed (gap, span) pairs: gap from the end of
        # the range before (from -1 for the first), span from its low to
        # its high.
        def packed(ranges)
          last = -1
          words = ranges.flat_map do |lo, hi|
            pair = [lo - last - 1, hi - lo]
            last = hi
            pair
          end
          words.pack("w*")
        end

        # Fold rows as BER-packed words: the key's codes, how many codes
        # it maps to, then those codes, in the table's own order.
        def fold_words(hash) = hash.flat_map { |key, list| [*key, list.size, *list] }.pack("w*")

        def write_core(io, properties, order, tables, ctype_bits, case_fold, unfold1, unfold2, unfold3)
          range_bytes = order.map { |tname| packed(tables[tname]) }
          range_ends = range_bytes.each_with_object([]) { |bytes, ends| ends << (ends.last || 0) + bytes.bytesize }

          io.print(<<~RUBY)
            # Generated by `zr-dev gen onig_unicode` from ruby #{RUBY}'s
            # enc/unicode/#{UNICODE} headers. Do not edit.
            #
            # The tables Onigmo's parser reads: every property keyword and the
            # code ranges of the table it names, the case folds and their
            # inverses, and the Latin-1 ctype bits. Each is a String the engine
            # decodes on first use (Regexp::Onig::Unicode in encoding.rb).
            class Regexp
              module Onig
                module Unicode
                  # Each keyword the way property_name_to_ctype normalizes it (no
                  # spaces, hyphens or underscores; lowercased), space-separated,
                  # and the index of the table each names, BER-packed in the same
                  # order.
                  PROPERTY_NAMES = #{literal(properties.keys.join(" "))}
                  PROPERTY_TABLES = #{literal(properties.values.pack("w*"))}

                  # The #{order.size} tables in Onigmo's order, the first fifteen being
                  # the POSIX classes ([[:alpha:]] is 1) and NEWLINE 0. Each holds
                  # its ranges as BER-packed (gap, span) pairs, one after another;
                  # RANGE_ENDS has the byte offset where each ends, BER-packed.
                  RANGES = #{literal(range_bytes.join)}
                  RANGE_ENDS = #{literal(range_ends.pack("w*"))}

                  # The 8859-1 ctype table: bit `ctype` of the little-endian 16-bit
                  # entry `code` says a code point under 256 has the class
                  # (unicode.c).
                  CTYPE_BITS = #{literal(ctype_bits.pack("v*"))}

                  # Full case folding: a code point to the code(s) it folds to
                  # (CaseFold_11 with the locale rows), as fold rows.
                  CASE_FOLD = #{literal(fold_words(case_fold))}

                  # A folded code point to the other code points that fold to it
                  # (CaseUnfold_11 with the locale row).
                  CASE_UNFOLD_1 = #{literal(fold_words(unfold1))}

                  # A two-code fold to the code points that fold to it
                  # (CaseUnfold_12 with the locale row).
                  CASE_UNFOLD_2 = #{literal(fold_words(unfold2))}

                  # A three-code fold to the code points that fold to it (CaseUnfold_13).
                  CASE_UNFOLD_3 = #{literal(fold_words(unfold3))}
                end
              end
            end
          RUBY
        end

        # A def of `Zr::Kern` that gives `bytes`. The later lines of the
        # literal are inside the String, so they have no indent.
        def emit_bytes(io, ename, bytes, comment)
          rows = bytes.each_slice(32).map { |row| row.map { |b| format("\\x%02X", b) }.join }
          io.print "  # #{comment}\n"
          io.print "  #: () -> ptr\n"
          io.print "  def #{ename}\n"
          io.print "    Machine.bytes(\n"
          io.print "    \"#{rows.join("\\\n")}\")\n"
          io.print "  end\n"
        end

        def write_kernel(io, tables, order, ctype_bits, case_fold)
          utf8_len = (0..255).map do |b|
            if b < 0xC2 then 1
            elsif b < 0xE0 then 2
            elsif b < 0xF0 then 3
            elsif b < 0xF5 then 4
            else 1
            end
          end

          word = tables[order[12]]
          rows = case_fold.sort.map { |from, list| [from, list.size, *list, *[0] * (3 - list.size)] }

          io.print(<<~RUBY)
            # Generated by `zr-dev gen onig_unicode` from ruby #{RUBY}'s
            # enc/unicode/#{UNICODE} headers. Do not edit.
            #
            # The byte tables the kernel's Onigmo matcher reads; the license is in
            # lib/zr/runtime/kernel/regexp.rb.

            module Zr::Kern
          RUBY
          emit_bytes(io, "zr_onig_utf8_len", utf8_len, "EncLen_UTF8: the length a UTF-8 lead byte announces, 256 bytes (utf_8.c).")
          io.print "\n"
          emit_bytes(io, "zr_onig_ctype_bits", ctype_bits.pack("V*").bytes, "The 8859-1 ctype bits of each code point under 256, as 256 words (unicode.c).")
          io.print "\n"
          emit_bytes(io, "zr_onig_word_ranges", ([word.size] + word.flatten).pack("V*").bytes, "CR_Word: the count, then (low, high) pairs of code points, as words.")
          io.print "\n"
          emit_bytes(io, "zr_onig_fold_rows", ([rows.size] + rows.flatten).pack("V*").bytes, "CaseFold_11 sorted by code point: the count, then rows of five words (from, how many, three codes).")
          io.print "end\n"
        end
      end
    end
  end
end
