# frozen_string_literal: true

module Zr
  module Hir
    # The error for a source that does not parse, built as CRuby builds it
    # from prism's diagnostics (`pm_parse_process_error` in
    # prism_compile.c). It is a SyntaxError whose message gives the first
    # error's line, then shows each line with an error, the lines around
    # it, and one caret line per diagnostic. A diagnostic about an
    # argument (an unknown encoding comment) is an ArgumentError, and one
    # about a load is a LoadError.
    class SyntaxReport
      # A line is cut this many bytes after its last caret, or before the
      # first caret if it is this far in.
      TRUNCATE = 30

      Row = Data.define(:error, :line, :column_start, :column_end)

      def self.error(result, file) = new(result, file).error

      def initialize(result, file)
        @result = result
        @file = file
        @bytes = result.source.source.b
        @offsets = result.source.offsets
        @start_line = result.source.start_line
      end

      def error
        errors = @result.errors
        errors.each do |e|
          return argument_error(e) if e.level == :argument
          return LoadError.new(e.message) if e.level == :load
        end

        text = "#{@file}:#{errors.first.location.start_line}: syntax error#{"s" if errors.size > 1} found\n".b
        if errors.all? { |e| utf8?(e.location) }
          text << annotated(errors, inline: true)
        else
          # A source line that is not UTF-8 cannot go in the message, so
          # each error is its own line of text instead.
          text << errors.map { |e| "#{@file}:#{e.location.start_line}: #{e.message}" }.join("\n").b
        end
        exc = SyntaxError.new(text.force_encoding(@result.encoding))
        exc.instance_variable_set(:@path, @file)
        exc
      end

      private

      # Its message is bytes, as CRuby's `rb_exc_new` makes it.
      def argument_error(e)
        text = "#{@file}:#{e.location.start_line}: #{e.message}".b
        text << "\n" << annotated([e], inline: false) if utf8?(e.location)
        ArgumentError.new(text)
      end

      # Whether every line the location touches is valid UTF-8.
      def utf8?(location)
        from = @offsets[location.start_line - @start_line]
        last = location.end_line - @start_line
        to = last >= @offsets.size - 1 ? @bytes.bytesize : @offsets[last + 1]
        @bytes.byteslice(from, to - from).force_encoding(Encoding::UTF_8).valid_encoding?
      end

      # The errors in source order, each with its line and byte columns.
      # An error at the same position as an earlier one goes before it.
      def sorted(errors)
        errors.each_with_object([]) do |e, rows|
          loc = e.location
          column_end = loc.end_line == loc.start_line ? loc.end_column : line_length(loc.start_line)
          column_end += 1 if column_end == loc.start_column
          at = rows.index { |r| r.line > loc.start_line || (r.line == loc.start_line && r.column_start >= loc.start_column) }
          rows.insert(at || rows.size, Row.new(e, loc.start_line, loc.start_column, column_end))
        end
      end

      def line_length(line)
        index = line - @start_line
        @offsets[index + 1] - @offsets[index] - 1
      end

      def annotated(errors, inline:)
        rows = sorted(errors)
        widest = [rows.first.line, rows.last.line].map { |n| n.negative? ? -n * 10 : n }.max
        digits = [widest.to_s.size, 5].min
        number = "%#{digits}d | "
        blank = "#{" " * digits} | "
        divider = "  #{"~" * [digits + 4, 8].min}\n"

        out = "".b
        last_line = @start_line - 1
        last_column_start = 0
        rows.each_with_index do |row, index|
          # Up to two source lines before the error, and a divider if some
          # lines are not shown.
          if row.line - last_line > 1
            if row.line - last_line > 2
              out << divider if index != 0 && row.line - last_line > 3
              out << "  " << source_line(number, row.line - 2)
            end
            out << "  " << source_line(number, row.line - 1)
          end

          if index.zero? || row.line != last_line
            last_column_start = row.column_start
            column_end = rows[index..].take_while { |r| r.line == row.line }.map(&:column_end).max
            out << "> " << source_line(number, row.line, row.column_start, column_end)
          end

          start = @offsets[row.line - @start_line]
          out << "\n" if start == @bytes.bytesize
          out << "  " << blank << carets(row, start, last_column_start)
          out << " " << row.error.message.b if inline
          out << "\n"

          # Up to two lines after it, before the next error's lines.
          last_line = row.line
          next_line = rows[index + 1]&.line || last_source_line + 1
          2.times do
            break unless next_line - last_line > 1

            last_line += 1
            out << "  " << source_line(number, last_line)
          end
        end
        out
      end

      def last_source_line
        lines = @offsets.size
        lines -= 1 if @offsets.last == @bytes.bytesize
        @start_line + lines - 1
      end

      # A space for each character before the error, a caret for its
      # first, a tilde for each after.
      def carets(row, start, last_column_start)
        out = "".b
        column = 0
        if last_column_start >= TRUNCATE
          out << "    "
          column = last_column_start
        end
        while column < row.column_start
          out << " "
          column += step(start + column)
        end
        out << "^"
        column += step(start + column)
        while column < row.column_end
          out << "~"
          column += step(start + column)
        end
        out
      end

      # Line `line` of the source with its number, cut after `column_end`
      # and before `column_start` if either is far into the line.
      def source_line(number, line, column_start = 0, column_end = 0)
        index = line - @start_line
        start = @offsets[index]
        finish = index >= @offsets.size - 1 ? @bytes.bytesize : @offsets[index + 1]
        out = (number % line).b
        cut = column_end != 0 && finish - (start + column_end) >= TRUNCATE
        if cut
          candidate = start + column_end + TRUNCATE
          at = start
          while at < candidate
            width = char_width(at)
            break if width.zero?

            if at + width > candidate
              candidate = at
              break
            end
            at += width
          end
          finish = candidate
        end
        if column_start >= TRUNCATE
          out << "... "
          start += column_start
        end
        out << @bytes.byteslice(start, finish - start)
        if cut
          out << " ...\n"
        elsif finish == @bytes.bytesize && @bytes.getbyte(finish - 1) != 10
          out << "\n"
        end
        out
      end

      def step(at) = [char_width(at), 1].max

      # The byte count of the character at `at` in the source's encoding,
      # or 0 if there is none or it is not valid.
      def char_width(at)
        return 0 if at >= @bytes.bytesize

        char = @bytes.byteslice(at, 4).force_encoding(@result.encoding)[0]
        char.valid_encoding? ? char.bytesize : 0
      end
    end
  end
end
