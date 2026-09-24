# frozen_string_literal: true

# The multibyte encodings, read off ruby: which bytes make a character,
# and which code point each character stands for. One walk answers both
# questions.
#
#   rake gen:cjk
#   rake gen:enc_mb
#
# `rt/core/cjk.rb` carries the code points. Where a character ends is
# `gen:enc_mb`'s question, answered from Onigmo's own tables. Bytes
# below 128 stand for themselves in every one of them.

require "set"
require_relative "../lib/zr/record"

module Gen
  module Cjk
    module_function

    ROOT = File.expand_path("..", __dir__)
    # How many bytes a character may hold, and how many rows this tool reads
    # before it calls an encoding partial. GB18030's four-byte characters
    # run to 150,000 rows, which no program needs written out: the runtime
    # walks them and refuses to convert them, by name.
    DEPTH = 4
    BUDGET = 3000
    # The bytes a walk tries when it asks whether a character can go on. An
    # encoding ruby holds no converter for is read this way.
    SAMPLE = [0x30, 0x39, 0x40, 0x41, 0x7E, 0x80, 0x81, 0xA1, 0xB0, 0xC1, 0xFE].freeze

    CONVERTS = {}

    def converts?(encoding)
      CONVERTS.fetch(encoding) do
        CONVERTS[encoding] = begin
          Encoding::Converter.new(encoding, pivot(encoding))
          true
        rescue StandardError
          false
        end
      end
    end

    # The carriers' own encodings, which ruby converts through the carrier's
    # UTF-8: an emoji reads as the carrier's private-use code point, and
    # only the step from that UTF-8 to Unicode's makes it Unicode's emoji.
    HUBS = { "SJIS-DoCoMo" => "UTF8-DoCoMo", "SJIS-KDDI" => "UTF8-KDDI", "SJIS-SoftBank" => "UTF8-SoftBank",
             "stateless-ISO-2022-JP-KDDI" => "UTF8-KDDI" }.freeze

    # What a converter is asked to write into while the bytes are read. UTF-8
    # reaches itself through no converter, so it is read into UTF-16BE; a
    # carrier's encoding is read into the carrier's UTF-8, whose bytes are
    # UTF-8's; and everything else is read into UTF-8.
    def pivot(encoding) = encoding == Encoding::UTF_8 ? "UTF-16BE" : HUBS.fetch(encoding.name, "UTF-8")

    # What `bytes` are in `encoding`, as ruby's own character count reads
    # them: one whole character, the start of one that needs more bytes, or
    # neither. Where a character ends is a question about the encoding, and
    # a String answers it whether or not ruby holds a converter.
    def probe(encoding, bytes)
      return :whole if whole?(encoding, bytes)

      completes?(encoding, bytes) ? :more : :none
    end

    # Whether these bytes are one whole character of the encoding, which is
    # the one question every walk of it is built on.
    def whole?(encoding, bytes)
      text = bytes.pack("C*").dup.force_encoding(encoding)
      text.length == 1 && text.valid_encoding?
    end

    # What a conversion out of `encoding` makes of `bytes`: the code point
    # they stand for, the text where one code point is not enough, :undef
    # where the encoding holds the character and gives it none, :more where
    # the converter waits for another byte, and :none where it refuses them.
    # A converter can be narrower than the encoding it reads: ruby counts
    # 8F A1 A1 as one CP51932 character and its own converter refuses the 8F
    # alone. So the two questions are asked apart, and a conversion follows
    # this answer while a walk follows the one above.
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


    # What ruby's own character count says about these bytes, which is what
    # the runtime has to answer too.
    def by_length(encoding, bytes)
      text = bytes.pack("C*").dup.force_encoding(encoding)
      [text.length, text.valid_encoding?, text.each_char.map(&:bytesize)]
    end

    # The shapes that tell a UTF-8 walk from any other: a two-byte
    # character, a three-byte one, a four-byte one, a byte that starts none,
    # an overlong pair, a surrogate, and a lead with the wrong byte after it.
    SHAPES = [[0xC3], [0xC3, 0xA9], [0xE3, 0x81, 0x82], [0xF0, 0x9F, 0x98, 0x80],
              [0x80], [0xC0, 0x80], [0xED, 0xA0, 0x80], [0xC3, 0x41]].freeze

    def utf8_shape?(encoding)
      SHAPES.all? { |bytes| by_length(encoding, bytes) == by_length(Encoding::UTF_8, bytes) }
    end

    # Whether some longer bytes that start with these make a character.
    # Every byte is tried for the first two places, and a handful of endings
    # for the places past them, which is as deep as ruby's characters go.
    def completes?(encoding, bytes)
      return false if bytes.size >= DEPTH

      endings = bytes.size < 2 ? (0..255) : SAMPLE
      endings.any? do |byte|
        longer = bytes + [byte]
        whole?(encoding, longer) || completes?(encoding, longer)
      end
    end

    # What one walk of an encoding finds: which bytes may sit at each place
    # inside a character, and how long the character a lead byte starts is.
    # `partial` says the walk stopped short of the whole encoding, which
    # GB18030's four-byte characters make it do, and `irregular` that it
    # found a shape these rules cannot hold.
    class Walk < Zr::Record
      FIELDS = %i[trails lengths partial irregular].freeze
      attr_accessor :trails, :lengths, :partial, :irregular

      def initialize(trails = nil, lengths = nil, partial = nil, irregular = nil)
        @trails = trails
        @lengths = lengths
        @partial = partial
        @irregular = irregular
      end

      def to_a = [@trails, @lengths, @partial, @irregular]
    end

    # What a conversion out of an encoding needs: the code point of every
    # character its converter reads, the few characters one code point is
    # not enough for, and the rows both are written from.
    class Rows < Zr::Record
      FIELDS = %i[rows mapped multi partial].freeze
      attr_accessor :rows, :mapped, :multi, :partial

      def initialize(rows = nil, mapped = nil, multi = nil, partial = nil)
        @rows = rows
        @mapped = mapped
        @multi = multi
        @partial = partial
      end

      def to_a = [@rows, @mapped, @multi, @partial]
    end

    # Every prefix a character starts with, in turn. `kind` names the method
    # that answers what a sequence of bytes is, and the block is given each
    # prefix with what each byte after it makes. Answers whether the walk
    # stopped short of the whole encoding.
    def walk(encoding, kind)
      budget = BUDGET
      partial = false
      queue = [[]]
      until queue.empty?
        prefix = queue.shift
        found = (0..255).to_h { |byte| [byte, send(kind, encoding, prefix + [byte])] }
        yield prefix, found
        # A byte that ends a character here can start a longer one as well,
        # and then the walk goes on under it too. Only a walk of the encoding
        # itself asks: a converter reading one byte at a time never calls a
        # character whole while a longer one can still start with its bytes,
        # so `:more` alone carries that walk on.
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

    # One row of the table: what a conversion makes of the characters that
    # start with the row's own bytes. A slot holds 0 where the converter
    # refuses them, 1 where it holds the character and gives it no code
    # point, 2 where a longer character starts there, 3 where one code point
    # is not enough and MB_MULTI holds the text, and otherwise 4 plus how far
    # the code point lies from the one before it in the row, folded onto the
    # positive numbers.
    def pack_row(prefix, found)
      live = found.reject { |byte, what| what == :none || (prefix.empty? && byte < 0x80) }
      return nil if live.empty?

      first = live.keys.min
      last = live.keys.max
      point = 0
      packed = +"".b
      (first..last).each do |byte|
        case (what = found[byte])
        when :none then packed << varint(0)
        when :undef then packed << varint(1)
        when :more then packed << varint(2)
        when Integer
          packed << varint(4 + zigzag(what - point))
          point = what
        else packed << varint(3)
        end
      end
      [first, last - first + 1, packed]
    end

    def varint(value)
      out = +"".b
      loop do
        byte = value & 0x7F
        value >>= 7
        out << (value.zero? ? byte : byte | 0x80)
        break if value.zero?
      end
      out
    end

    def zigzag(value) = value >= 0 ? value * 2 : (-value * 2) - 1

    # A row holds the same bytes for one encoding as for another more often
    # than not: EUC-JP and eucJP-ms part in a handful of rows, Big5 and
    # CP950 in fewer. So each row is written once.
    class Pool
      def initialize
        @ids = {}
        @rows = []
      end

      def id(packed)
        @ids[packed] ||= (@rows << packed; @rows.size - 1)
      end

      def rows = @rows
    end

    # The bytes ruby itself writes for each code point, against the lowest
    # sequence the rows hold for it. Where the two part, the rows alone
    # cannot answer `encode`, so the pair is written out. Every scalar is
    # asked, because a conversion is not a table read backwards: ruby writes
    # U+2015 as EUC-JP A1 BD, and reads A1 BD back as U+2014.
    def overrides(encoding, mapped, kept, partial)
      return {} if kept.empty?

      lowest = {}
      # The shortest sequence first, and the lowest bytes of that length:
      # ruby writes a character as its own plane spells it, never as a longer
      # plane that happens to start with a lower byte.
      mapped.sort_by { |sequence, _| [sequence.bytesize, sequence] }.each do |sequence, point|
        next unless kept.include?(sequence.byteslice(0, sequence.bytesize - 1))

        lowest[point] ||= sequence
      end
      out = {}
      (0x80..0x2FFFF).each do |point|
        next if point.between?(0xD800, 0xDFFF)

        written = (point.chr(Encoding::UTF_8).force_encoding(HUBS.fetch(encoding.name, "UTF-8")).encode(encoding).b rescue nil)
        next if written.nil? || written == lowest[point]
        # A partial encoding's longer characters are refused by name, so the
        # rows say nothing about them here either.
        next if partial && written.bytesize > 2

        out[point] = written
      end
      out
    end

    # How ruby words a failure for an encoding, read off a deliberate one,
    # in the shape rt/core/transcode.rb writes: whether a conversion into it
    # reads as one step, the name it answers to there, and whether a
    # conversion out of it reads as one step.
    UNMAPPED = "\u{1F600}"

    def shape_of(encoding)
      message = (UNMAPPED.encode(encoding) rescue $!.message)
      return nil if message.start_with?("code converter not found")

      short = !message.include?(" in conversion from ")
      step = short ? encoding.name : message[/\AU\+\h+ to (.*?) in conversion from /, 1]
      [short, step, from_short(encoding)]
    end

    # The same question for the other direction, asked with a character the
    # encoding holds and gives no code point.
    def from_short(encoding)
      sequence = (0x80..0xFF).lazy.flat_map { |a| [[a]] + (0x00..0xFF).map { |b| [a, b] } }
                             .find { |bytes| convert(encoding, bytes) == :undef }
      return true if sequence.nil?

      message = (sequence.pack("C*").dup.force_encoding(encoding).encode("UTF-8") rescue $!.message)
      !message.include?(" in conversion from ")
    end
    def write
      warn "reading the multibyte encodings off ruby ..."
      plain = [Encoding::UTF_8, Encoding::US_ASCII, Encoding::BINARY]
      candidates = Encoding.list.reject(&:dummy?).select do |encoding|
        next false if plain.include?(encoding) || !encoding.ascii_compatible?

        (0x80..0xFF).any? { |a| (0x30..0xFF).any? { |b| whole?(encoding, [a, b]) } }
      end

      # An encoding that walks exactly as UTF-8 does needs no rules of its
      # own: the runtime walks UTF-8 already, and only the form parts.
      utf8_like = candidates.select { |encoding| utf8_shape?(encoding) }
      own = (candidates - utf8_like).to_h do |encoding|
        warn "  walking #{encoding.name} ..."
        [encoding, walk_of(encoding)]
      end

      # A partial encoding's longer characters follow one rule, whatever the
      # lead: every row that was read must agree on the bytes at each place,
      # and on which second bytes make a character longer. The rule then holds
      # for the leads the walk never reached.
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
        table.lengths.each_value { |seconds| seconds.merge!(rule) if seconds.values.include?(2) } unless rule.empty?
      end
      irregular = own.select { |_, table| table.irregular }
      own = own.reject { |encoding, _| irregular.key?(encoding) }

      # CESU-8 writes a character past the BMP as its two surrogates, three
      # bytes each: six bytes, deeper than a walk reads, so its rule adds them.
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
        # The multibyte encodings' tables, generated by `rake gen:cjk`. A row
        # holds the bytes that can end a character whose earlier bytes are the
        # row's own key: the first such byte, how many follow it, and what a
        # conversion makes of each one, as one varint each -- 0 where the
        # converter refuses the bytes, 1 for a character it gives no code
        # point, 2 for the start of a longer one, 3 for a character one code
        # point is not enough for, and otherwise 4 plus how far the code point
        # lies from the one before it in the row, folded onto the positive
        # numbers. Rows repeat between encodings, so each one is written once
        # in MB_ROWS. Where a character ends is another question, which
        # rt/kernel/enc_mb.rb answers from Onigmo's own tables: ruby's
        # converters are narrower than its own character counts.
        class Encoding
      HEAD
      # Rows are written for the characters a conversion can reach. An
      # encoding ruby holds no converter for needs none, and a partial one
      # needs only the characters whose rows were all read: the runtime walks
      # the longer ones and refuses to convert them, by name.
      kept_by_name = {}
      rows_by_name = own.keys.to_h do |encoding|
        table = tables.fetch(encoding)
        rows = table.partial ? table.rows.reject { |prefix, _| prefix.bytesize >= 2 } : table.rows
        kept_by_name[encoding.name] = rows.keys.to_set
        [encoding.name, rows.map { |prefix, (first, count, packed)| [prefix, first, count, pool.id(packed)] }]
      end
      core << "  MB = {\n"
      rows_by_name.each do |name, rows|
        core << "    #{name.inspect} => [\n"
        rows.each { |prefix, first, count, id| core << "      [#{prefix.inspect}, #{first}, #{count}, #{id}],\n" }
        core << "    ],\n"
      end
      core << "  }.freeze\n\n"
      core << "  MB_ROWS = [\n"
      pool.rows.each { |packed| core << "    #{[packed].pack("m0").inspect},\n" }
      core << "  ].freeze\n\n"
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
          blob << varint(code - point) << varint(bytes.bytesize) << bytes
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

          path = (Encoding::Converter.search_convpath(a, b) rescue nil)
          edges << [a.name, b.name] if path.is_a?(Array) && path.size == 1 && path.first.is_a?(Array)
        end
      end
      compat = Encoding.list.to_h { |encoding| [encoding.name, (Encoding::Converter.asciicompat_encoding(encoding)&.name rescue nil)] }
                            .reject { |_, value| value.nil? }
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
      core << "  private_constant :MB, :MB_ROWS, :MB_PARTIAL, :MB_UTF8, :MB_ENCODE, :MB_MULTI, :MB_SHAPES, :MB_HUBS, :CONVERTERS,\n"
      core << "                   :ASCII_COMPAT, :CONVERTER_FLAGS\n"
      core << "end\n"
      File.write(File.join(ROOT, "rt/core/cjk.rb"), core)

      warn "tables: #{own.size}, partial: #{tables.select { |_, t| t.partial }.keys.map(&:name).join(',')}"
      warn "as UTF-8: #{utf8_like.map(&:name).join(',')}"
      warn "refused: #{irregular.keys.map(&:name).join(',')}"
      warn "rows: #{pool.rows.size}, encode rows written out: #{written}, of more than one code point: #{multi_written}"
      warn "converter pairs: #{edges.size}"
      warn "core: #{core.bytesize} bytes"

    end
  end
end

namespace :gen do
  desc "Write rt/core/cjk.rb"
  task(:cjk) { Gen::Cjk.write }
end
