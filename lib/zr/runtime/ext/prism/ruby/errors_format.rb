# frozen_string_literal: true
# shareable_constant_value: literal

module Prism
  module Ruby
    # errors_format.c: the message of the error a parse with the
    # `raise_error` option raises, with source snippets as CRuby shows
    # syntax errors.
    module ErrorsFormat
      # pm_errors_format_type_t
      PLAIN = 1
      STYLE = 2
      COLOR = 3

      BOLD = "\e[1m"
      GRAY = "\e[2m"
      RED = "\e[1;31m"
      RESET = "\e[m"
      TRUNCATE = 30

      # pm_rich_error_t
      RichError = Struct.new(:diagnostic, :line, :column_start, :column_end, :index)

      # pm_error_line_format_t
      LineFormat = Struct.new(:number_prefix, :blank_prefix, :divider)

      module_function

      # pm_errors_format: the message bytes, and the level of the error to
      # raise (:syntax, :argument or :load).
      def format(parser, type)
        buffer = "".b
        filepath = parser.filepath
        rich_errors = []
        utf8 = true

        parser.errors.each do |diagnostic|
          case diagnostic.level
          when :syntax
            utf8 &&= location_utf8?(parser, diagnostic.start, diagnostic.end)
            rich_errors << rich_error(parser, diagnostic, rich_errors.size)
          when :argument
            # An argument error alone, with its snippet when that is UTF-8.
            line = line_column(parser, diagnostic.start, parser.start_line).first
            buffer << filepath << ":#{line}: " << diagnostic.message.b
            if location_utf8?(parser, diagnostic.start, diagnostic.end)
              buffer << "\n"
              rich_errors_format(parser, buffer, type, [rich_error(parser, diagnostic, 0)], false)
            end
            return [buffer, :argument]
          when :load
            return [buffer << diagnostic.message.b, :load]
          end
        end

        # The header names the line of the first error in parse order.
        buffer << filepath << ":#{rich_errors.first.line}: syntax error#{"s" if rich_errors.size > 1} found\n"

        if utf8
          # In source order; at one place, the later error first.
          sorted = rich_errors.sort_by { |error| [error.line, error.column_start, -error.index] }
          rich_errors_format(parser, buffer, type, sorted, true)
        else
          # No snippets of a source that is not UTF-8, in parse order.
          rich_errors.each_with_index do |error, index|
            buffer << "\n" if index > 0
            buffer << filepath << ":#{error.line}: " << error.diagnostic.message.b
          end
        end

        [buffer, :syntax]
      end

      # pm_line_offset_list_line_column: the line and column of an offset.
      def line_column(parser, offset, start_line)
        offsets = parser.newlines
        index = (offsets.bsearch_index { |line_start| line_start > offset } || offsets.size) - 1
        [index + start_line, offset - offsets[index]]
      end

      # location_is_utf8: whether the lines that a location touches are
      # valid UTF-8.
      def location_utf8?(parser, start, finish)
        offsets = parser.newlines
        start_line = line_column(parser, start, 1).first
        end_line = line_column(parser, finish, 1).first
        from = offsets[start_line - 1]
        to = end_line == offsets.size ? parser.source.bytesize : offsets[end_line]
        parser.source.byteslice(from, to - from).dup.force_encoding(::Encoding::UTF_8).valid_encoding?
      end

      # pm_rich_error_init
      def rich_error(parser, diagnostic, index)
        offsets = parser.newlines
        start_line = parser.start_line
        line, column_start = line_column(parser, diagnostic.start, start_line)
        end_line, end_column = line_column(parser, diagnostic.end, start_line)

        column_end =
          if line == end_line
            end_column
          else
            offsets[line - start_line + 1] - offsets[line - start_line] - 1
          end

        # At least one column.
        column_end += 1 if column_start == column_end

        RichError.new(diagnostic, line, column_start, column_end, index)
      end

      # pm_error_line_format_init: the widths follow the largest line
      # number; a negative one takes a column for its sign.
      def line_format(type, first_line, last_line)
        first_line = -first_line * 10 if first_line.negative?
        last_line = -last_line * 10 if last_line.negative?
        width = [[first_line, last_line].max.to_s.size, 5].min
        divider = "  #{"~" * [width + 4, 8].min}"
        if type > PLAIN
          LineFormat.new("#{GRAY}%#{width}d | #{RESET}", "#{GRAY}#{" " * (width + 1)}| #{RESET}", "#{GRAY}#{divider}#{RESET}\n")
        else
          LineFormat.new("%#{width}d | ", "#{" " * (width + 1)}| ", "#{divider}\n")
        end
      end

      def char_width(parser, at)
        source = parser.source
        parser.encoding.char_width(source, at, source.bytesize - at)
      end

      # pm_error_format_line: a line of the source, cut to the part around
      # the columns when it is long.
      def format_line(parser, buffer, number_prefix, line, column_start, column_end)
        source = parser.source
        offsets = parser.newlines
        index = line - parser.start_line
        start = offsets[index]
        finish = index >= offsets.size - 1 ? source.bytesize : offsets[index + 1]

        buffer << Kernel.format(number_prefix, line).b

        truncate_end = false
        if column_end != 0 && (finish - start) - column_end >= TRUNCATE
          candidate = start + column_end + TRUNCATE
          cursor = start
          while cursor < candidate
            width = char_width(parser, cursor)
            break if width == 0

            if cursor + width > candidate
              candidate = cursor
              break
            end
            cursor += width
          end

          finish = candidate
          truncate_end = true
        end

        if column_start >= TRUNCATE
          buffer << "... "
          start += column_start
        end

        buffer << source.byteslice(start, finish - start).b

        if truncate_end
          buffer << " ...\n"
        elsif finish == source.bytesize && finish > 0 && source.getbyte(finish - 1) != 0x0A
          buffer << "\n"
        end
      end

      # pm_rich_errors_format: each error under its line, with up to two
      # lines around it.
      def rich_errors_format(parser, buffer, type, rich_errors, inline_messages)
        format = line_format(type, rich_errors.first.line, rich_errors.last.line)
        source = parser.source
        offsets = parser.newlines
        last_line = parser.start_line - 1
        last_column_start = 0

        rich_errors.each_with_index do |error, index|
          if error.line - last_line > 1
            if error.line - last_line > 2
              buffer << format.divider if index != 0 && error.line - last_line > 3

              buffer << "  "
              format_line(parser, buffer, format.number_prefix, error.line - 2, 0, 0)
            end

            buffer << "  "
            format_line(parser, buffer, format.number_prefix, error.line - 1, 0, 0)
          end

          # The line of the error, once for the errors on it.
          if index == 0 || error.line != last_line
            buffer << case type
                      when PLAIN then "> "
                      when STYLE then "#{BOLD}> #{RESET}"
                      else "#{RED}> #{RESET}"
                      end

            last_column_start = error.column_start

            column_end = error.column_end
            rich_errors[(index + 1)..].each do |next_error|
              break if next_error.line != error.line

              column_end = next_error.column_end if next_error.column_end > column_end
            end

            format_line(parser, buffer, format.number_prefix, error.line, error.column_start, column_end)
          end

          start = offsets[error.line - parser.start_line]
          buffer << "\n" if start == source.bytesize

          buffer << "  " << format.blank_prefix

          column = 0
          if last_column_start >= TRUNCATE
            buffer << "    "
            column = last_column_start
          end

          while column < error.column_start
            buffer << " "
            width = char_width(parser, start + column)
            column += width == 0 ? 1 : width
          end

          buffer << case type
                    when PLAIN then "^"
                    when STYLE then "#{BOLD}^"
                    else "#{RED}^"
                    end

          width = char_width(parser, start + column)
          column += width == 0 ? 1 : width

          while column < error.column_end
            buffer << "~"
            width = char_width(parser, start + column)
            column += width == 0 ? 1 : width
          end

          buffer << RESET if type != PLAIN
          buffer << " " << error.diagnostic.message.b if inline_messages
          buffer << "\n"

          # Up to two lines after the error, before the next one.
          last_line = error.line
          if index == rich_errors.size - 1
            next_line = offsets.size + parser.start_line
            # A source that ends in a newline shows no line after it.
            next_line -= 1 if offsets.last == source.bytesize
          else
            next_line = rich_errors[index + 1].line
          end

          2.times do
            next unless next_line - last_line > 1

            buffer << "  "
            format_line(parser, buffer, format.number_prefix, last_line += 1, 0, 0)
          end
        end
      end
    end
  end
end
