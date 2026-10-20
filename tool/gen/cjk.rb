# frozen_string_literal: true

require_relative "../gen"
require_relative "../../lib/zr/bytes"

module Zr
  module Dev
    module Commands
      class Gen
        # Reads the multibyte encodings from ruby: which bytes make a character,
        # and which code point each character represents. One walk over the
        # bytes finds both.
        #
        #   zr-dev gen cjk
        #   zr-dev gen enc_mb
        #
        # `lib/zr/runtime/core/cjk.rb` contains the code points. `zr-dev gen enc_mb` finds
        # where a character ends, from Onigmo's tables. In all these encodings,
        # a byte below 128 represents itself.
        class Cjk < Generator
          host_ruby!
          writes "lib/zr/runtime/core/cjk.rb"

          # The maximum bytes in a character, and the maximum rows this tool
          # reads before it marks an encoding as partial. GB18030's four-byte
          # characters need 150,000 rows, and no program needs them written out.
          # The runtime walks them and refuses to convert them, with a message
          # that gives the encoding.
          DEPTH = 4
          BUDGET = 3000
          # The bytes that a walk tries to find if a character can continue.
          # The walk also uses them for an encoding that has no ruby converter.
          SAMPLE = [0x30, 0x39, 0x40, 0x41, 0x7E, 0x80, 0x81, 0xA1, 0xB0, 0xC1, 0xFE].freeze

          def converts?(encoding)
            @converts ||= {}
            @converts.fetch(encoding) do
              @converts[encoding] = begin
                Encoding::Converter.new(encoding, pivot(encoding))
                true
              rescue StandardError
                false
              end
            end
          end

          # The mobile carriers' encodings. Ruby converts them through the
          # carrier's UTF-8. There, an emoji is the carrier's private-use code
          # point. Only the step from that UTF-8 to Unicode gives the Unicode emoji.
          HUBS = { "SJIS-DoCoMo" => "UTF8-DoCoMo", "SJIS-KDDI" => "UTF8-KDDI", "SJIS-SoftBank" => "UTF8-SoftBank",
                   "stateless-ISO-2022-JP-KDDI" => "UTF8-KDDI" }.freeze

          # The encoding that the converter writes into. UTF-8 has no converter to
          # itself, so it converts into UTF-16BE. A carrier's encoding converts
          # into the carrier's UTF-8, which has the same bytes as UTF-8. All
          # other encodings convert into UTF-8.
          def pivot(encoding) = encoding == Encoding::UTF_8 ? "UTF-16BE" : HUBS.fetch(encoding.name, "UTF-8")

          # Returns what `bytes` are in `encoding`, by ruby's character count:
          # one whole character (:whole), the start of a longer one (:more), or
          # neither (:none). A String gives this for every encoding, also for an
          # encoding that has no ruby converter.
          def probe(encoding, bytes)
            return :whole if whole?(encoding, bytes)

            completes?(encoding, bytes) ? :more : :none
          end

          # Whether these bytes are one whole character of the encoding. Every
          # walk of the encoding uses this test.
          def whole?(encoding, bytes)
            text = bytes.pack("C*").dup.force_encoding(encoding)
            text.length == 1 && text.valid_encoding?
          end

          # Returns what a conversion from `encoding` makes of `bytes`:
          # - the code point that they represent
          # - the text, when one code point is not sufficient
          # - :undef when the encoding has the character but no code point for it
          # - :more when the converter waits for another byte
          # - :none when the converter refuses the bytes
          # A converter can accept less than its encoding. Ruby counts 8F A1 A1 as
          # one CP51932 character, but its converter refuses 8F alone. Thus a
          # conversion uses this method, and a walk uses `probe`.
          def convert(encoding, bytes)
            return :none unless converts?(encoding)

            source = bytes.pack("C*").b
            out = +"".b
            result = Encoding::Converter.new(encoding, pivot(encoding)).primitive_convert(source, out, nil, nil, partial_input: true)
            return :none if result == :invalid_byte_sequence || !source.empty?
            return :undef if result == :undefined_conversion
            return :more if out.empty?

            text = pivot(encoding) == "UTF-16BE" ? out.force_encoding("UTF-16BE").encode("UTF-8") : out.force_encoding("UTF-8")
            text.length == 1 ? text.ord : text
          end

          # Ruby's character count for these bytes. The runtime must return the
          # same result.
          def by_length(encoding, bytes)
            text = bytes.pack("C*").dup.force_encoding(encoding)
            [text.length, text.valid_encoding?, text.each_char.map(&:bytesize)]
          end

          # Byte sequences that identify a UTF-8 walk: a lead byte alone, a
          # two-byte, three-byte and four-byte character, a byte that starts no
          # character, an overlong pair, a surrogate, and a lead byte followed by
          # an incorrect byte.
          SHAPES = [[0xC3], [0xC3, 0xA9], [0xE3, 0x81, 0x82], [0xF0, 0x9F, 0x98, 0x80],
                    [0x80], [0xC0, 0x80], [0xED, 0xA0, 0x80], [0xC3, 0x41]].freeze

          def utf8_shape?(encoding)
            SHAPES.all? { |bytes| by_length(encoding, bytes) == by_length(Encoding::UTF_8, bytes) }
          end

          # Whether a longer sequence that starts with these bytes makes a
          # character. It tries every byte for the first two positions, and the
          # SAMPLE bytes after them, up to DEPTH (ruby's longest character).
          def completes?(encoding, bytes)
            return false if bytes.size >= DEPTH

            endings = bytes.size < 2 ? (0..255) : SAMPLE
            endings.any? do |byte|
              longer = bytes + [byte]
              whole?(encoding, longer) || completes?(encoding, longer)
            end
          end

          # The result of one walk of an encoding: which bytes can be at each
          # position in a character, and the length of the character that each
          # lead byte starts. `partial` is true when the walk stopped before the
          # end of the encoding (GB18030's four-byte characters cause this).
          # `irregular` is true when the walk found a form these rules cannot
          # represent.
          Walk = Struct.new(:trails, :lengths, :partial, :irregular)

          # The data that a conversion from an encoding needs: the code point of
          # each character that its converter reads, the few characters that need
          # more than one code point, and the rows that contain both.
          Rows = Struct.new(:rows, :mapped, :multi, :partial)

          # Yields each prefix that a character can start with, one at a time.
          # `kind` is the method (`probe` or `convert`) that classifies a byte
          # sequence. The block gets each prefix and the result for each next
          # byte. Returns true if the walk stopped before the end of the encoding.
          def walk(encoding, kind)
            budget = BUDGET
            partial = false
            queue = [[]]
            until queue.empty?
              prefix = queue.shift
              found = (0..255).to_h { |byte| [byte, send(kind, encoding, prefix + [byte])] }
              yield prefix, found
              # A byte that ends a character here can also start a longer one.
              # Then the walk continues after it too. Only a `probe` walk needs
              # this test: a converter never calls a character whole while a
              # longer one can start with its bytes, so `:more` is sufficient.
              deeper = found.select do |byte, what|
                what == :more || (what == :whole && byte >= 0x80 && completes?(encoding, prefix + [byte]))
              end.keys
              next if deeper.empty?

              if prefix.size + 1 >= DEPTH || deeper.size > budget
                partial = true
              else
                budget -= deeper.size
                deeper.each { |byte| queue << prefix + [byte] }
              end
            end
            partial
          end

          def walk_of(encoding)
            trails = {}
            lengths = Hash.new { |table, lead| table[lead] = {} }
            irregular = false
            partial = walk(encoding, :probe) do |prefix, found|
              live = found.reject { |_, what| what == :none }.keys.sort
              unless prefix.empty?
                key = [prefix.first, prefix.size]
                irregular = true if trails.key?(key) && trails[key] != live
                trails[key] = live
              end
              found.each do |byte, what|
                next unless what == :whole

                sequence = prefix + [byte]
                next if sequence.first < 0x80

                lengths[sequence.first][sequence.size > 1 ? sequence[1] : nil] = sequence.size
              end
            end
            Walk.new(trails, lengths, partial, irregular)
          end

          def rows_of(encoding)
            rows = {}
            mapped = {}
            multi = {}
            partial = walk(encoding, :convert) do |prefix, found|
              found.each do |byte, what|
                next if what == :none || what == :more || what == :undef

                sequence = (prefix + [byte]).pack("C*")
                what.is_a?(Integer) ? mapped[sequence] = what : multi[sequence] = what
              end
              row = pack_row(prefix, found)
              rows[prefix.pack("C*")] = row if row
            end
            Rows.new(rows, mapped, multi, partial)
          end

          # Packs one row of the table: what a conversion makes of the characters
          # that start with the row's prefix. Each slot contains:
          # 0 when the converter refuses the bytes,
          # 1 when the character has no code point,
          # 2 when a longer character starts there,
          # 3 when the character needs more than one code point (see MB_MULTI),
          # else 4 plus the zigzag-encoded difference from the previous code point.
          # The slots are BER numbers, which `unpack("w*")` reads.
          def pack_row(prefix, found)
            live = found.reject { |byte, what| what == :none || (prefix.empty? && byte < 0x80) }
            return nil if live.empty?

            first = live.keys.min
            last = live.keys.max
            point = 0
            slots = (first..last).map do |byte|
              case (what = found[byte])
              when :none then 0
              when :undef then 1
              when :more then 2
              when Integer
                slot = 4 + Bytes.zigzag(what - point)
                point = what
                slot
              else 3
              end
            end
            [first, last - first + 1, slots.pack("w*")]
          end

          # Many rows are the same in different encodings: EUC-JP and eucJP-ms
          # differ in only a few rows, and Big5 and CP950 in fewer. Thus the pool
          # writes each row only once.
          class Pool
            def initialize
              @ids = {}
              @rows = []
            end

            def id(packed)
              @ids[packed] ||= @rows.push(packed).size - 1
            end

            attr_reader :rows
          end

          # Compares the bytes that ruby writes for each code point with the lowest
          # sequence that the rows contain for it. When they differ, the rows
          # cannot give the result of `encode`, so the pair is written out. This
          # tests every scalar, because encoding is not the inverse of decoding:
          # ruby writes U+2015 as EUC-JP A1 BD, but reads A1 BD as U+2014.
          def overrides(encoding, mapped, kept, partial)
            return {} if kept.empty?

            lowest = {}
            # Sort by length first, then by bytes. Ruby writes a character in its
            # own plane, never in a longer plane that starts with a lower byte.
            mapped.sort_by { |sequence, _| [sequence.bytesize, sequence] }.each do |sequence, point|
              next unless kept.include?(sequence.byteslice(0, sequence.bytesize - 1))

              lowest[point] ||= sequence
            end
            out = {}
            (0x80..0x2FFFF).each do |point|
              next if point.between?(0xD800, 0xDFFF)

              written = converted { point.chr(Encoding::UTF_8).force_encoding(HUBS.fetch(encoding.name, "UTF-8")).encode(encoding).b }
              next if written.nil? || written == lowest[point]
              # The runtime refuses the longer characters of a partial encoding,
              # so the table does not include them here either.
              next if partial && written.bytesize > 2

              out[point] = written
            end
            out
          end

          # Reads how ruby writes a conversion error for an encoding, from an
          # error that this method causes. The result has the form that
          # lib/zr/runtime/core/transcode.rb uses: whether a conversion into the encoding
          # shows as one step, the encoding name in the message, and whether a
          # conversion from the encoding shows as one step.
          UNMAPPED = "\u{1F600}"

          def shape_of(encoding)
            message = conversion_message { UNMAPPED.encode(encoding) }
            return nil if message.start_with?("code converter not found")

            short = !message.include?(" in conversion from ")
            step = short ? encoding.name : message[/\AU\+\h+ to (.*?) in conversion from /, 1]
            [short, step, short_from?(encoding)]
          end

          # The same test for the other direction. It uses a character that the
          # encoding has but that has no code point.
          def short_from?(encoding)
            sequence = (0x80..0xFF).lazy.flat_map { |a| [[a]] + (0x00..0xFF).map { |b| [a, b] } }
                                   .find { |bytes| convert(encoding, bytes) == :undef }
            return true if sequence.nil?

            message = conversion_message { sequence.pack("C*").dup.force_encoding(encoding).encode("UTF-8") }
            !message.include?(" in conversion from ")
          end
          # The BMP characters that GB18030 writes in four bytes, as runs of
          # the first code point, the four-byte count it starts at, and the
          # run's length, from ruby's own converter.
          def gb18030_runs
            (0x80..0xFFFF).each_with_object([]) do |code, runs|
              next if (0xD800..0xDFFF).cover?(code)

              bytes = code.chr(Encoding::UTF_8).encode(Encoding::GB18030).bytes
              next unless bytes.size == 4

              count = ((((((bytes[0] - 0x81) * 10) + bytes[1] - 0x30) * 126) + bytes[2] - 0x81) * 10) + bytes[3] - 0x30
              last = runs.last
              if last && last[0] + last[2] == code && last[1] + last[2] == count
                last[2] += 1
              else
                runs << [code, count, 1]
              end
            end
          end

          # The ISO-8859-1 byte of each IBM037 byte, in hex.
          def ebcdic_hex = (0..255).map { |byte| byte.chr.force_encoding("IBM037").encode("ISO-8859-1").ord }.pack("C*").unpack1("H*")

          def write(io)
            warn "reading the multibyte encodings off ruby ..."
            plain = [Encoding::UTF_8, Encoding::US_ASCII, Encoding::BINARY]
            candidates = Encoding.list.reject(&:dummy?).select do |encoding|
              next false if plain.include?(encoding) || !encoding.ascii_compatible?

              (0x80..0xFF).any? { |a| (0x30..0xFF).any? { |b| whole?(encoding, [a, b]) } }
            end

            # An encoding that walks the same as UTF-8 needs no rules of its own.
            # The runtime already walks UTF-8; only the written form is different.
            utf8_like = candidates.select { |encoding| utf8_shape?(encoding) }
            own = (candidates - utf8_like).to_h do |encoding|
              warn "  walking #{encoding.name} ..."
              [encoding, walk_of(encoding)]
            end

            # The longer characters of a partial encoding follow one rule for all
            # lead bytes. All rows that the walk read must agree on the bytes at
            # each position, and on which second bytes make a longer character.
            # The rule then applies to the lead bytes that the walk did not reach.
            own.each_value do |table|
              next unless table.partial

              by_place = {}
              table.trails.each do |(_, place), live|
                if by_place.key?(place) && by_place[place] != live
                  table.irregular = true
                else
                  by_place[place] = live
                end
              end
              table.trails.each_key { |key| table.trails[key] = by_place[key[1]] }
              varying = table.lengths.select { |_, seconds| seconds.values.uniq.size > 1 }
              rule = varying.values.each_with_object({}) do |seconds, out|
                seconds.each do |second, length|
                  table.irregular = true if out.key?(second) && out[second] != length
                  out[second] = length
                end
              end
              table.lengths.each_value { |seconds| seconds.merge!(rule) if seconds.value?(2) } unless rule.empty?
            end
            irregular = own.select { |_, table| table.irregular }
            own = own.reject { |encoding, _| irregular.key?(encoding) }

            # CESU-8 writes a character above the BMP as two surrogates of three
            # bytes each. A walk does not read six bytes, so this adds them.
            if (cesu = own[Encoding::CESU_8])
              (0xA0..0xAF).each { |second| cesu.lengths[0xED][second] = 6 }
              cesu.trails[[0xED, 1]] = (0x80..0xAF).to_a
              cesu.trails[[0xED, 3]] = [0xED]
              cesu.trails[[0xED, 4]] = (0xB0..0xBF).to_a
              cesu.trails[[0xED, 5]] = (0x80..0xBF).to_a
            end

            warn "reading the conversions off ruby ..."
            tables = own.keys.to_h do |encoding|
              warn "  converting #{encoding.name} ..."
              [encoding, rows_of(encoding)]
            end

            pool = Pool.new
            core = +"# frozen_string_literal: true\n\n"
            core << <<~HEAD
              # Derived from CRuby's enc/trans tables (Ruby or BSD-2-Clause, and the
              # mapping data's own notices); see THIRD_PARTY_NOTICES.md.
              #
              # The multibyte encodings' tables, generated by `zr-dev gen cjk`. A row
              # holds the bytes that can end a character whose earlier bytes are the
              # row's own key: the first such byte, how many follow it, and what a
              # conversion makes of each one, as one BER number each -- 0 where the
              # converter refuses the bytes, 1 for a character it gives no code
              # point, 2 for the start of a longer one, 3 for a character one code
              # point is not enough for, and otherwise 4 plus how far the code point
              # lies from the one before it in the row, folded onto the positive
              # numbers. Rows repeat between encodings, so each one is written once,
              # as one base64 line of mb_pool. Where a character ends is another
              # question, which lib/zr/runtime/kernel/enc_mb.rb answers from Onigmo's
              # own tables: ruby's converters are narrower than its own character
              # counts.
              class Encoding
            HEAD
            # Write rows only for characters that a conversion can reach. An
            # encoding without a ruby converter needs no rows. A partial encoding
            # needs only the characters whose rows the walk read completely. The
            # runtime walks the longer characters and refuses to convert them.
            kept_by_name = {}
            rows_by_name = own.keys.to_h do |encoding|
              table = tables.fetch(encoding)
              rows = table.partial ? table.rows.reject { |prefix, _| prefix.bytesize >= 2 } : table.rows
              kept_by_name[encoding.name] = rows.keys.to_set
              [encoding.name, rows.map { |prefix, (first, count, packed)| [prefix, first, count, pool.id(packed)] }]
            end
            core << "  # Each encoding's rows, in base64: for each, the size of its key, the\n"
            core << "  # key's bytes, its first byte, how many follow, and the line of\n"
            core << "  # mb_pool that holds it, as BER numbers.\n"
            core << "  MB = {\n"
            rows_by_name.each do |name, rows|
              numbers = rows.flat_map { |prefix, first, count, id| [prefix.bytesize, *prefix.bytes, first, count, id] }
              core << "    #{name.inspect} => #{[numbers.pack("w*")].pack("m0").inspect},\n"
            end
            core << "  }.freeze\n\n"
            core << "  # The rows that MB names, one base64 line each. A method gives them,\n"
            core << "  # so the core makes no String of them until a conversion reads one.\n"
            core << "  def self.mb_pool\n"
            core << "    Primitive.attr! :hidden\n"
            core << "    <<~ROWS\n"
            pool.rows.each { |packed| core << "      #{[packed].pack("m0")}\n" }
            core << "    ROWS\n"
            core << "  end\n\n"
            core << "  # An encoding whose longer characters these rows leave out: the\n"
            core << "  # runtime walks them and refuses to convert them, by name.\n"
            core << "  MB_PARTIAL = #{tables.select { |_, table| table.partial }.keys.map(&:name).inspect}.freeze\n\n"
            core << "  # The encodings that walk as UTF-8 walks. Their code points are\n"
            core << "  # Unicode's own; what parts is the form they are written in.\n"
            core << "  MB_UTF8 = #{utf8_like.map(&:name).inspect}.freeze\n\n"
            core << "  # Where ruby writes bytes for a code point that are not the first\n"
            core << "  # ones these rows hold for it: how far the code point lies from the\n"
            core << "  # one before it, how many bytes it takes, and the bytes.\n"
            core << "  MB_ENCODE = {\n"
            written = 0
            tables.each do |encoding, table|
              extra = overrides(encoding, table.mapped, kept_by_name.fetch(encoding.name), table.partial)
              next if extra.empty?

              written += extra.size
              blob = +"".b
              point = 0
              extra.sort.each do |code, bytes|
                blob << Bytes.uleb(code - point) << Bytes.uleb(bytes.bytesize) << bytes
                point = code
              end
              core << "    #{encoding.name.inspect} => #{[blob].pack("m0").inspect},\n"
            end
            core << "  }.freeze\n\n"
            core << "  # The characters one code point is not enough for: the bytes of the\n"
            core << "  # character, and the text ruby reads it as. The carriers' own\n"
            core << "  # encodings hold a handful each.\n"
            core << "  MB_MULTI = {\n"
            multi_written = 0
            tables.each do |encoding, table|
              kept = kept_by_name.fetch(encoding.name)
              rows = table.multi.select { |sequence, _| kept.include?(sequence.byteslice(0, sequence.bytesize - 1)) }
              next if rows.empty?

              multi_written += rows.size
              core << "    #{encoding.name.inspect} => {\n"
              rows.sort.each { |sequence, text| core << "      #{sequence.b.inspect} => #{text.b.inspect},\n" }
              core << "    },\n"
            end
            core << "  }.freeze\n\n"
            core << "  # How a failure names each of these encodings, as SHAPES does.\n"
            core << "  MB_SHAPES = {\n"
            (own.keys + utf8_like).each { |encoding| core << "    #{encoding.name.inspect} => #{shape_of(encoding).inspect},\n" }
            core << "  }.freeze\n\n"

            warn "reading the converter paths ..."
            edges = []
            Encoding.list.each do |a|
              Encoding.list.each do |b|
                next if a == b

                path = converted { Encoding::Converter.search_convpath(a, b) }
                edges << [a.name, b.name] if path.is_a?(Array) && path.size == 1 && path.first.is_a?(Array)
              end
            end
            compat = Encoding.list.to_h { |encoding| [encoding.name, converted { Encoding::Converter.asciicompat_encoding(encoding)&.name }] }
                                  .compact
            core << "  # The pairs ruby converts in one step, which a conversion path is\n  # searched over.\n"
            core << "  CONVERTERS = [\n"
            edges.each { |a, b| core << "    [#{a.inspect}, #{b.inspect}],\n" }
            core << "  ].freeze\n\n"
            core << "  # Encoding::Converter's own flags, as ruby numbers them.\n"
            core << "  CONVERTER_FLAGS = {\n"
            Encoding::Converter.constants.sort.each { |name| core << "    #{name.to_s.inspect} => #{Encoding::Converter.const_get(name)},\n" }
            core << "  }.freeze\n\n"
            core << "  # The encoding each one meets ASCII in.\n"
            core << "  ASCII_COMPAT = {\n"
            compat.each { |name, other| core << "    #{name.inspect} => #{other.inspect},\n" }
            core << "  }.freeze\n\n"
            core << "  # The carriers' encodings, each read through its carrier's UTF-8:\n"
            core << "  # these rows hold that UTF-8's code points, emoji and all.\n"
            core << "  MB_HUBS = #{HUBS.inspect}.freeze\n\n"
            core << "  # The runs of BMP characters GB18030 writes in four bytes: each run's\n"
            core << "  # first code point, the four-byte count it starts at, and its length.\n"
            core << "  # This file runs before Enumerable, so the triples are literals.\n"
            core << "  GB18030_RUNS = [\n"
            gb18030_runs.each_slice(6) { |row| core << "    #{row.map(&:inspect).join(", ")},\n" }
            core << "  ].freeze\n"
            core << "  # The four-byte count of U+10000, where the supplementary planes start.\n"
            core << "  GB18030_PLANES = 189_000\n\n"
            core << "  # The ISO-8859-1 byte that each IBM037 byte represents, by position, in\n"
            core << "  # hex: the core library reads this file before Array#pack is defined.\n"
            core << "  EBCDIC_HEX = #{ebcdic_hex.scan(/.{1,64}/).map(&:inspect).join(" \\\n               ")}.freeze\n\n"
            core << "  private_constant :MB, :MB_PARTIAL, :MB_UTF8, :MB_ENCODE, :MB_MULTI, :MB_SHAPES, :MB_HUBS, :CONVERTERS,\n"
            core << "                   :ASCII_COMPAT, :CONVERTER_FLAGS\n"
            core << "end\n"
            io.print core

            warn "tables: #{own.size}, partial: #{tables.select { |_, t| t.partial }.keys.map(&:name).join(",")}"
            warn "as UTF-8: #{utf8_like.map(&:name).join(",")}"
            warn "refused: #{irregular.keys.map(&:name).join(",")}"
            warn "rows: #{pool.rows.size}, encode rows written out: #{written}, of more than one code point: #{multi_written}"
            warn "converter pairs: #{edges.size}"
            warn "core: #{core.bytesize} bytes"

          end
        end
      end
    end
  end
end
