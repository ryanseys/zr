# frozen_string_literal: true

require_relative "../gen"
require_relative "../../lib/zr/bytes"
require_relative "../lib/zr/dev/vendor_tree"
require "base64"
require "strscan"

module Zr
  module Dev
    module Commands
      class Gen
        # The nkf gem's conversion tables, read out of its C source and
        # written as the data lib/zr/runtime/ext/nkf.so.rb converts with. nkf keeps
        # its own tables in utf8tbl.c -- JIS X 0208 and 0212 to Unicode and
        # back, the CP932, eucJP-ms, Mac and JIS X 0213 variants, and the
        # Shift_JIS rows it swaps -- and they part from ruby's transcoders
        # in many places, so the port reads nkf's own.
        #
        #   zr-dev gen nkf                         the .gem that vendor/vendor.lock names
        #   zr-dev gen nkf --source path/to/utf8tbl.c
        #
        # utf8tbl.c declares three shapes of table, and each keeps its shape:
        #
        # - a list of numbers (`unsigned short name[]`), written as a leaf;
        # - a list of rows (`unsigned short name[3][189]`, or the struct
        #   pairs of the normalization table), written as one leaf and the
        #   row width;
        # - a list of other tables (`unsigned short *const name[]`), written
        #   as the names of those tables, with nil where C holds a null
        #   pointer.
        #
        # A leaf is one base64 string of varints. A 0 starts a run of zeros,
        # and the varint after it counts the run. Any other varint is one
        # more than the distance from the last nonzero value, folded onto
        # the positive numbers.
        #
        # Most leaves repeat another table with a few changes, so a leaf can
        # be written as a patch over a base: 0 where the value is the
        # base's, and one more than the value where it is not. A base is
        # either another leaf (utf8_to_euc_E4_x0213 over utf8_to_euc_E4) or,
        # for a Unicode-to-JIS leaf, the inverse of the JIS-to-Unicode
        # tables over the leaf's code points. The generator writes each leaf
        # in its smallest form, then loads the file it wrote and checks
        # every table against the C source.
        class Nkf < Generator
          host_ruby!
          writes "lib/zr/runtime/ext/nkf/tables.rb"
          usage "[--source PATH] [--check]"

          # The field widths of `struct normalization_pair`: NFC in 3 bytes,
          # NFD in 9.
          STRUCT_WIDTHS = { "normalization_pair" => [3, 9] }.freeze

          # The suffixes that name a variant of a table.
          VARIANT = /_(?:ms|932|mac|x0213)\z/

          Table = Struct.new(:name, :kind, :width, :items)

          DECLARATION = /
            (?:static\s+)?const\s+
            (?:unsigned\s+short|struct\s+(?<struct>\w+))\s*
            (?<stars>(?:\*\s*const\s*)*)
            (?<name>\w+)\s*
            (?<dims>(?:\[[^\]]*\]\s*)+)
            =\s*(?=\{)
          /x

          def defaults
            super
            @source = nil
            @nkf_gem = nil
          end

          def options(o)
            super
            o.on("--source PATH", "the gem's utf8tbl.c (default: the locked nkf .gem's)") { |v| @source = v }
          end

          def run(_argv)
            Dev.pinned!(name)
            tables = read_tables(plain_source(source))
            starts = unicode_starts(tables)
            inverse = inverse_map(tables)
            ok = Dev.write(self.class.writes, check: check?) { |io| write(io, tables, starts, inverse) }
            verify(tables) if ok
            ok
          end

          UTF8TBL = "ext/nkf/nkf-utf8/utf8tbl.c"

          # The C of `--source`, then of `NKF_SRC`, then of the nkf .gem that
          # vendor/vendor.lock names, so the tables do not depend on the
          # gems of this ruby.
          def source
            path = @source || ENV["NKF_SRC"]
            return File.binread(path) if path

            nkf_gem.last.fetch(UTF8TBL) { fail!("the nkf .gem has no #{UTF8TBL}") }
          end

          # The locked nkf .gem: its version and its files.
          def nkf_gem = @nkf_gem ||= VendorTree.locked_gem("nkf", fail: method(:fail!))

          # The source with its comments and preprocessor lines taken out.
          # Every #ifdef in utf8tbl.c names an option config.h turns on, so
          # every table stays.
          def plain_source(text) = text.gsub(%r{/\*.*?\*/}m, " ").gsub(/^[ \t]*#.*$/, "")

          # One brace initializer, as nested arrays of Integers and Symbols.
          def parse_initializer(scanner)
            scanner.skip(/\s*\{/) or raise "expected { at #{scanner.pos}"
            items = []
            loop do
              scanner.skip(/\s*/)
              if scanner.skip(/\}/)
                return items
              elsif scanner.check(/\{/)
                items << parse_initializer(scanner)
              elsif (number = scanner.scan(/0[xX]\h+|\d+/))
                items << Integer(number)
              elsif (name = scanner.scan(/[A-Za-z_]\w*/))
                items << name.to_sym
              else
                raise "unexpected text at #{scanner.pos}: #{scanner.peek(20).inspect}"
              end
              scanner.skip(/\s*,/)
            end
          end

          def read_tables(source)
            scanner = StringScanner.new(source)
            tables = {}
            while scanner.skip_until(DECLARATION)
              fields = DECLARATION.names.zip(scanner.captures).to_h
              table = classify(fields, parse_initializer(scanner))
              tables[table.name] = table
            end
            tables
          end

          def classify(fields, items)
            name = fields.fetch("name").to_sym
            if fields["struct"]
              widths = STRUCT_WIDTHS.fetch(fields["struct"])
              rows = items.map { |row| row.zip(widths).flat_map { |field, width| pad(field, width) } }
              Table.new(name, :leaf, widths.sum, rows.flatten)
            elsif !fields.fetch("stars").empty?
              Table.new(name, :pointers, nil, items.map { |item| item == 0 ? nil : item })
            elsif items.first.is_a?(Array)
              width = fields.fetch("dims").scan(/\[([^\]]*)\]/).flatten.last
              width = width.match?(/\A\d+\z/) ? Integer(width) : items.map(&:size).max
              Table.new(name, :leaf, width, items.flat_map { |row| pad(row, width) })
            else
              Table.new(name, :leaf, nil, items)
            end
          end

          def pad(values, width) = values + [0] * (width - values.size)

          # A table as the converter reads it: Integers, rows, or nested
          # tables.
          def resolve(tables, name)
            table = tables.fetch(name)
            return table.items.map { |child| child && resolve(tables, child) } if table.kind == :pointers

            table.width ? table.items.each_slice(table.width).to_a : table.items
          end

          # The first Unicode code point of each Unicode-to-JIS leaf, found
          # by walking the tables that index them by UTF-8 lead and middle
          # bytes.
          def unicode_starts(tables)
            starts = {}
            tables.each_value do |table|
              case table.name
              when /\Autf8_to_euc_2bytes/
                table.items.each_with_index do |leaf, index|
                  starts[leaf] ||= ((index + 0x80) & 0x1F) << 6 if leaf
                end
              when /\Autf8_to_euc_3bytes/
                table.items.each_with_index do |middle, lead|
                  next unless middle

                  tables.fetch(middle).items.each_with_index do |leaf, index|
                    starts[leaf] ||= (lead << 12) | (index << 6) if leaf
                  end
                end
              end
            end
            starts
          end

          # JIS X 0208 and JIS X 0212 read backwards: the code of the first
          # JIS character each Unicode code point stands for, with 0x8000
          # set for JIS X 0212. lib/zr/runtime/ext/nkf/tables.rb builds the same
          # map the same way.
          def inverse_map(tables)
            map = {}
            [[:euc_to_utf8_2bytes, 0], [:x0212_to_utf8_2bytes, 0x8000]].each do |name, flag|
              resolve(tables, name).each_with_index do |row, ku|
                row&.each_with_index do |code, ten|
                  map[code] ||= flag | ((ku + 0x21) << 8) | (ten + 0x21) unless code.zero?
                end
              end
            end
            map
          end

          def pack(values)
            out = +"".b
            previous = 0
            index = 0
            while index < values.size
              if values[index].zero?
                run = values[index..].take_while(&:zero?).size
                out << Bytes.uleb(0) << Bytes.uleb(run)
                index += run
              else
                out << Bytes.uleb(Bytes.zigzag(values[index] - previous) + 1)
                previous = values[index]
                index += 1
              end
            end
            Base64.strict_encode64(out)
          end

          def patch(values, under) = values.each_with_index.map { |value, index| value == (under[index] || 0) ? 0 : value + 1 }

          # A leaf in its smallest form: [width, data] or [width, data, base].
          def encode_leaf(table, tables, starts, inverse)
            forms = [[table.width, pack(table.items)]]
            base = table.name.to_s.sub(VARIANT, "").to_sym
            if base != table.name && tables[base]&.kind == :leaf && tables[base].items.size == table.items.size
              forms << [table.width, pack(patch(table.items, tables[base].items)), base]
            end
            if (start = starts[table.name])
              under = Array.new(table.items.size) { |index| inverse.fetch(start + index, 0) }
              forms << [table.width, pack(patch(table.items, under)), start]
            end
            forms.min_by { |form| form[1].size }
          end

          def write(io, tables, starts, inverse)
            io.print(<<~HEAD)
              # frozen_string_literal: true

              # The conversion tables of nkf #{version}, generated by `zr-dev gen nkf`
              # from the gem's utf8tbl.c. Do not edit. Derived from nkf 2.1.5
              # (zlib-style); see THIRD_PARTY_NOTICES.md.
              #
              # PACKED holds each list of numbers as [width, data] or [width, data,
              # base]. The width is nil for a flat list and the row width for a
              # list of rows. The data is a base64 string of varints: 0 starts a run
              # of zeros whose length follows, and any other varint is one more than
              # the distance from the last nonzero value, folded onto the positive
              # numbers. A list with a base is a patch over that base -- 0 keeps the
              # base's value, and any other value is one more than the value to use.
              # A Symbol base names another list; an Integer base is the first of
              # the Unicode code points the list covers, read through JIS X 0208 and
              # JIS X 0212 backwards. POINTERS holds each list of tables as the
              # names of those tables, nil for a null pointer.
              #
              # NKF::Tables[name] unpacks a table the first time a conversion asks
              # for it.
              module NKF
                module Tables
                  PACKED = {
            HEAD
            tables.each_value.select { |table| table.kind == :leaf }.each do |table|
              io.puts "      #{table.name}: #{encode_leaf(table, tables, starts, inverse).inspect},"
            end
            io.puts "    }.freeze", "", "    POINTERS = {"
            tables.each_value.select { |table| table.kind == :pointers }.each do |table|
              io.puts "      #{table.name}: [#{table.items.map(&:inspect).join(", ")}],"
            end
            io.puts "    }.freeze"
            io.print(<<~TAIL.gsub(/^(?=.)/, "    "))

              @cache = {}

              class << self
                # The table utf8tbl.c names `name`: an Array of Integers, an Array
                # of rows, or an Array of tables.
                def [](name)
                  @cache[name] ||= build(name)
                end

                private

                def build(name)
                  if (children = POINTERS[name])
                    return children.map { |child| child && self[child] }.freeze
                  end

                  width, data, base = PACKED.fetch(name)
                  values = unpack(data)
                  values = patch(values, base) if base
                  (width ? values.each_slice(width).map(&:freeze) : values).freeze
                end

                def patch(values, base)
                  under = base.is_a?(Symbol) ? self[base] : Array.new(values.size) { |index| inverse.fetch(base + index, 0) }
                  values.each_with_index.map { |value, index| value.zero? ? under[index] || 0 : value - 1 }
                end

                # The JIS code of the first JIS X 0208 character, then the first
                # JIS X 0212 character (with 0x8000 set), each code point stands for.
                def inverse
                  @inverse ||= [[:euc_to_utf8_2bytes, 0], [:x0212_to_utf8_2bytes, 0x8000]].each_with_object({}) do |(name, flag), map|
                    self[name].each_with_index do |row, ku|
                      row&.each_with_index do |code, ten|
                        map[code] ||= flag | ((ku + 0x21) << 8) | (ten + 0x21) unless code.zero?
                      end
                    end
                  end
                end

                def unpack(data)
                  bytes = data.unpack1("m0").bytes
                  values = []
                  previous = 0
                  position = 0
                  while position < bytes.size
                    token, position = read_varint(bytes, position)
                    if token.zero?
                      run, position = read_varint(bytes, position)
                      values.fill(0, values.size, run)
                    else
                      delta = token - 1
                      previous += delta.odd? ? -(delta + 1) / 2 : delta / 2
                      values << previous
                    end
                  end
                  values
                end

                def read_varint(bytes, position)
                  value = 0
                  shift = 0
                  loop do
                    byte = bytes[position]
                    position += 1
                    value |= (byte & 0x7F) << shift
                    return [value, position] if byte < 0x80

                    shift += 7
                  end
                end
              end
            TAIL
            io.puts "  end", "  private_constant :Tables", "end"
          end

          def version = nkf_gem.first

          # Every table the written file answers, against the C source.
          def verify(tables)
            load Dev.path(self.class.writes)
            wrong = tables.each_key.reject { |name| NKF.const_get(:Tables)[name] == resolve(tables, name) }
            fail!("tables that do not match utf8tbl.c: #{wrong.join(", ")}") unless wrong.empty?
          end
        end
      end
    end
  end
end
