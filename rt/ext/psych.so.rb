# frozen_string_literal: true

# The parser and the emitter psych ships as a libyaml binding, in ruby.
# The gem's own ruby half (vendor/ext/psych/lib) reaches them the way it
# reaches CRuby's, so everything above this file is the gem as written.
# The emitter is a handler, which is the one thing this file needs
# from the gem's ruby half before the gem requires it.
require "psych/handler"
# The parser raises Psych::SyntaxError, so the class must stand before
# the gem's own half loads, which is where CRuby's psych.so seats it too.
require "psych/syntax_error"

module Psych
  def self.libyaml_version = [0, 2, 5]

  # Reads a YAML stream and calls the handler for every event in it.
  # The events are libyaml's, so a tree builder, an emitter or a gem's
  # own handler all see what they see under CRuby.
  class Parser
    ANY = 0
    UTF8 = 1
    UTF16LE = 2
    UTF16BE = 3

    def _native_parse(handler, yaml, path)
      text = yaml.respond_to?(:read) ? yaml.read : yaml
      Scanner.new(text.to_str, path, handler, self).run
      self
    end

    def mark = @mark ||= Mark.new(0, 0, 0)

    # The reading position, kept so `parser.mark` answers after an event
    # as it does under libyaml.
    private def mark!(index, line, column)
      @mark = Mark.new(index, line, column)
    end
  end
end

module Psych
  class Parser
    # A YAML 1.1 stream, read as the events a handler wants. The reader
    # walks the text once with an index and an indentation column; a
    # block collection ends where a line starts at or before it.
    class Scanner
      CORE_TAGS = { "!" => "!", "!!" => "tag:yaml.org,2002:" }.freeze
      BLANK = " \t"
      INDICATORS = "-?:,[]{}#&*!|>'\"%@`"

      def initialize(text, path, handler, parser)
        @text = text
        @path = path
        @handler = handler
        @parser = parser
        @at = 0
        @line = 0
        @column = 0
        @tags = CORE_TAGS.dup
      end

      def run
        @handler.start_stream(Parser::UTF8)
        seek_content
        document while !eof? || pending_document?
        @handler.end_stream
        nil
      end

      private

      # --- the text ------------------------------------------------------

      def eof? = @at >= @text.length

      def peek(ahead = 0) = @text[@at + ahead]

      def at?(text) = @text[@at, text.length] == text

      def advance(count = 1)
        count.times do
          break if eof?

          if @text[@at] == "\n"
            @line += 1
            @column = 0
          else
            @column += 1
          end
          @at += 1
        end
        note
      end

      def note
        @parser.send(:mark!, @at, @line, @column)
      end

      def line_end? = eof? || peek == "\n"

      def blank? = BLANK.include?(peek.to_s)

      def skip_blanks
        advance while !eof? && blank?
      end

      def skip_line
        advance until line_end?
        advance unless eof?
      end

      # The next character that carries content: blank lines and whole
      # comment lines go by, and the column reads where content starts.
      def seek_content
        loop do
          skip_blanks
          break unless line_end? || peek == "#"

          skip_line
          break if eof?
        end
      end


      # --- documents -----------------------------------------------------

      # Whether a document is still owed: a stream of directives or a
      # bare `---` names one whose content is empty.
      def pending_document? = false

      def document
        version = []
        directives = false
        @tags = CORE_TAGS.dup
        while at?("%")
          version = directive || version
          directives = true
          seek_content
        end
        explicit = at?("---") && boundary?
        if explicit
          advance(3)
          seek_content
        end
        # A directive belongs to a document, which has to open itself.
        fail!("expected '<document start>'") if directives && !explicit
        @handler.start_document(version, tag_directives, !explicit && !directives)
        empty_document? ? empty_scalar : node(-1)
        seek_content
        # Indented text that no node could take, and that opens no
        # document of its own, belongs to nothing at all.
        fail!("did not find expected key") if !eof? && @column.positive? && !(boundary? && (at?("---") || at?("...")))
        closed = at?("...") && boundary?
        advance(3) if closed
        @handler.end_document(!closed)
        seek_content
        nil
      end

      def tag_directives
        @tags.reject { |handle, prefix| CORE_TAGS[handle] == prefix }.to_a
      end

      def empty_document?
        eof? || (boundary? && (at?("---") || at?("...")))
      end

      # A `---` or `...` counts only at the start of a line and with
      # nothing but space after it.
      def boundary?
        return false unless @column.zero?

        rest = @text[@at + 3]
        rest.nil? || BLANK.include?(rest) || rest == "\n"
      end

      # %YAML answers the version; %TAG adds a handle to the table.
      def directive
        advance
        name = read_while { |c| !BLANK.include?(c) && c != "\n" }
        skip_blanks
        rest = read_while { |c| c != "\n" }.strip
        case name
        when "YAML" then rest.split(".").map(&:to_i)
        when "TAG"
          handle, prefix = rest.split(/\s+/, 2)
          @tags[handle] = prefix
          nil
        end
      end

      def read_while
        from = @at
        advance while !eof? && yield(peek)
        @text[from...@at]
      end


      # --- nodes ---------------------------------------------------------

      # A node whose content must begin past column `indent`. An anchor
      # and a tag may come first, on this line or their own. A mapping
      # value takes a block sequence at the mapping's own column, which
      # is the one thing that may sit level with its parent.
      def node(indent, level_sequence: false)
        anchor, tag, mark = properties
        seek_content
        return empty_scalar(anchor, tag) if eof? || (boundary? && (at?("---") || at?("...")))
        if indent >= 0 && @column <= indent
          return empty_scalar(anchor, tag) unless level_sequence && @column == indent && at?("-") && entry_ahead?
        end

        case peek
        when "*" then read_alias
        when "[", "{" then flow_node(anchor, tag)
        # These close or separate a flow collection, and no flow
        # collection is open here.
        when "]", "}", "," then fail!("did not find expected node content")
        when "|", ">" then block_scalar(anchor, tag, indent)
        when "-" then entry_ahead? ? block_sequence(anchor, tag) : scalar_or_mapping(anchor, tag, indent)
        when "?" then explicit_ahead? ? block_mapping(anchor, tag, nil, @column) : scalar_or_mapping(anchor, tag, indent)
        else scalar_or_mapping(anchor, tag, indent, mark == @line)
        end
      end

      # `&name` and `!tag`, in either order, each at most once.
      def properties
        anchor = nil
        tag = nil
        mark = nil
        loop do
          seek_content
          case peek
          when "&"
            advance
            anchor = read_while { |c| plain_name?(c) }
            fail!("did not find expected alphabetic or numeric character") if anchor.empty?
          when "!" then tag = read_tag
          else break
          end
          mark = @line
        end
        [anchor, tag, mark]
      end

      def plain_name?(char)
        !char.nil? && !BLANK.include?(char) && !"\n,[]{}".include?(char)
      end

      # `!!str`, `!local`, `!<tag:x>` and a %TAG handle, as the tag text
      # the handler sees.
      def read_tag
        advance
        if peek == "<"
          advance
          text = read_while { |c| c != ">" }
          advance
          return text
        end
        handle = "!"
        if peek == "!"
          advance
          handle = "!!"
        end
        name = read_while { |c| plain_name?(c) && c != "!" }
        if peek == "!"
          advance
          handle = "!#{name}!"
          name = read_while { |c| plain_name?(c) }
        end
        # A lone `!` is a tag of its own; a handle with nothing after it
        # names nothing.
        fail!("did not find expected tag URI") if name.empty? && handle != "!"

        prefix = @tags[handle] || handle
        prefix == "!" ? "!#{name}" : "#{prefix}#{name}"
      end

      def read_alias
        advance
        name = read_while { |c| plain_name?(c) }
        fail!("did not find expected alphabetic or numeric character") if name.empty?

        @handler.alias(name)
      end

      def empty_scalar(anchor = nil, tag = nil)
        @handler.scalar("", anchor, tag, tag.nil?, false, Nodes::Scalar::PLAIN)
      end

      # Whether a `-` opens a block entry rather than a plain scalar
      # like `-5`.
      def entry_ahead?
        rest = peek(1)
        rest.nil? || BLANK.include?(rest) || rest == "\n"
      end

      def explicit_ahead?
        rest = peek(1)
        rest.nil? || BLANK.include?(rest) || rest == "\n"
      end

      # --- block collections ---------------------------------------------

      def block_sequence(anchor, tag)
        column = @column
        @handler.start_sequence(anchor, tag, tag.nil?, Nodes::Sequence::BLOCK)
        while !eof? && @column == column && at?("-") && entry_ahead?
          advance
          skip_blanks
          node(column)
          seek_content
          break if boundary? && (at?("---") || at?("..."))
        end
        @handler.end_sequence
      end

      # A block mapping, whose first key's events are already recorded
      # when a scalar turned out to be one.
      def block_mapping(anchor, tag, key, column)
        @handler.start_mapping(anchor, tag, tag.nil?, Nodes::Mapping::BLOCK)
        loop do
          if key
            replay(key)
          elsif at?("?") && explicit_ahead?
            advance
            skip_blanks
            node(column)
            seek_content
          else
            recorded = simple_key(column)
            break unless recorded

            replay(recorded)
          end
          key = nil
          seek_content
          if at?(":") && value_ahead?
            advance
            skip_blanks
            fail!("block sequence entries are not allowed in this context") if at?("-") && entry_ahead?

            node(column, level_sequence: true)
          else
            empty_scalar
          end
          seek_content
          break if eof? || @column != column || (boundary? && (at?("---") || at?("...")))
          break if at?("-") && entry_ahead?
        end
        @handler.end_mapping
      end

      def value_ahead?
        rest = peek(1)
        rest.nil? || BLANK.include?(rest) || rest == "\n"
      end


      # --- scalars, and the key they may turn out to be -------------------

      # A scalar, or the mapping it opens when a `:` follows it.
      # An anchor and a tag belong to the node that follows them. Where
      # that node is a simple key, they belong to the key and not to the
      # mapping it opens, which is what `own_line` tells apart: a tag on
      # the key's own line is the key's.
      def scalar_or_mapping(anchor, tag, indent, own_line = false)
        column = @column
        recorded = simple_key(column, own_line ? anchor : nil, own_line ? tag : nil)
        return block_mapping(own_line ? nil : anchor, own_line ? nil : tag, recorded, column) if recorded
        return quoted_scalar(anchor, tag) if peek == "'" || peek == '"'

        plain_scalar(anchor, tag, indent)
      end

      # The events of a node that is followed by `:`, or nil. A simple
      # key stays on its own line, so the reading never crosses one.
      def simple_key(column, anchor = nil, tag = nil)
        return nil unless @column == column

        state = [@at, @line, @column]
        events = []
        keep = @handler
        @handler = Recorder.new(events)
        begin
          single_line_node(anchor, tag)
        rescue SyntaxError
          @handler = keep
          restore(state)
          return nil
        end
        @handler = keep
        skip_blanks
        return events if at?(":") && value_ahead?

        restore(state)
        nil
      end

      def restore(state)
        @at, @line, @column = state
        note
      end

      def replay(events)
        events.each { |name, args| @handler.public_send(name, *args) }
      end

      # The node a simple key may be: a scalar or a flow collection, all
      # on one line.
      def single_line_node(anchor = nil, tag = nil)
        read_anchor, read_tag = properties
        anchor ||= read_anchor
        tag ||= read_tag
        fail!("did not find expected key") if line_end?

        case peek
        when "[", "{" then flow_node(anchor, tag)
        when "*" then read_alias
        when "'", '"' then quoted_scalar(anchor, tag)
        else
          text = read_while { |c| c != "\n" && !(c == ":" && key_break?) && !comment_break?(c) }
          fail!("did not find expected key") if text.strip.empty?

          @handler.scalar(text.strip, anchor, tag, tag.nil?, false, Nodes::Scalar::PLAIN)
        end
      end

      # A `:` ends a plain scalar when a space or a line end follows it.
      def key_break?
        rest = peek(1)
        rest.nil? || BLANK.include?(rest) || rest == "\n"
      end

      # A `#` opens a comment only after a space.
      def comment_break?(char)
        char == "#" && (@at.zero? || BLANK.include?(@text[@at - 1].to_s))
      end

      # A plain scalar, which folds the more-indented lines that follow
      # it into one line each.
      def plain_scalar(anchor, tag, indent)
        column = @column
        lines = [read_while { |c| c != "\n" && !(c == ":" && key_break?) && !comment_break?(c) }.rstrip]
        loop do
          state = [@at, @line, @column]
          seek_content
          break if eof? || @column <= indent
          break if boundary? && (at?("---") || at?("..."))

          piece = read_while { |c| c != "\n" && !(c == ":" && key_break?) && !comment_break?(c) }.rstrip
          if piece.empty? || (at?(":") && key_break?)
            restore(state)
            break
          end
          lines << piece
        end
        @handler.scalar(fold(lines), anchor, tag, tag.nil?, false, Nodes::Scalar::PLAIN)
      end

      # YAML folding: a blank line is a newline, every other break is a
      # space.
      def fold(lines)
        out = +""
        lines.each_with_index do |line, i|
          if i.zero?
            out << line
          elsif line.empty?
            out << "\n"
          else
            out << " " unless out.end_with?("\n")
            out << line
          end
        end
        out
      end

      def quoted_scalar(anchor, tag)
        quote = peek
        text = quote == "'" ? single_quoted : double_quoted
        style = quote == "'" ? Nodes::Scalar::SINGLE_QUOTED : Nodes::Scalar::DOUBLE_QUOTED
        # The quoted flag is libyaml's quoted_implicit: the quoting says
        # what the scalar is, which it does only where no tag says so.
        @handler.scalar(text, anchor, tag, false, tag.nil?, style)
      end

      def single_quoted
        advance
        out = +""
        loop do
          fail!("found unexpected end of stream") if eof?

          if peek == "'"
            advance
            break unless peek == "'"

            out << "'"
            advance
          elsif peek == "\n"
            out << " "
            advance
            skip_blanks
          else
            out << peek
            advance
          end
        end
        out
      end

      ESCAPES = {
        "0" => "\0", "a" => "\a", "b" => "\b", "t" => "\t", "n" => "\n",
        "v" => "\v", "f" => "\f", "r" => "\r", "e" => "\e", " " => " ", '"' => '"',
        "/" => "/", "\\" => "\\", "N" => "", "_" => " ",
        "L" => " ", "P" => " "
      }.freeze

      def double_quoted
        advance
        out = +""
        loop do
          fail!("found unexpected end of stream") if eof?

          case peek
          when '"'
            advance
            break
          when "\\"
            advance
            out << escape
          when "\n"
            advance
            skip_blanks
            out << " "
          else
            out << peek
            advance
          end
        end
        out
      end

      def escape
        char = peek
        advance
        case char
        when "x" then codepoint(2)
        when "u" then codepoint(4)
        when "U" then codepoint(8)
        when "\n"
          skip_blanks
          ""
        else ESCAPES.fetch(char) { fail!("found unknown escape character") }
        end
      end

      def codepoint(width)
        digits = @text[@at, width].to_s
        fail!("found unknown escape character") unless digits.length == width && digits.match?(/\A\h+\z/)

        advance(width)
        digits.to_i(16).chr(Encoding::UTF_8)
      end

      def fail!(problem, context = nil)
        raise SyntaxError.new(@path, @line + 1, @column + 1, @at, problem, context)
      end

      # --- block scalars --------------------------------------------------

      # `|` keeps the line breaks, `>` folds them. A digit sets the
      # indentation, `-` strips the trailing breaks and `+` keeps them.
      def block_scalar(anchor, tag, indent)
        literal = peek == "|"
        advance
        width = nil
        chomp = :clip
        until line_end?
          case peek
          when "-" then chomp = :strip
          when "+" then chomp = :keep
          when "1".."9" then width = peek.to_i
          when "#" then break
          end
          advance
        end
        skip_line
        text = block_lines(width, indent)
        text = literal ? text : fold_block(text)
        @handler.scalar(chomped(text, chomp), anchor, tag, false, tag.nil?,
                        literal ? Nodes::Scalar::LITERAL : Nodes::Scalar::FOLDED)
      end

      # The lines that belong to a block scalar, with their common
      # indentation taken off.
      def block_lines(width, indent)
        lines = []
        margin = width ? indent + width : nil
        loop do
          from = @at
          spaces = 0
          spaces += 1 while @text[@at + spaces] == " "
          rest = @text[(@at + spaces)...(@text.index("\n", @at + spaces) || @text.length)].to_s
          blank = rest.empty?
          margin ||= spaces unless blank
          break if margin && !blank && spaces < margin
          break if @at >= @text.length

          advance(spaces + rest.length)
          advance unless eof?
          lines << (blank ? "" : " " * (spaces - margin) + rest)
          break if @at == from
        end
        lines.map { |line| "#{line}\n" }.join
      end

      # A folded block joins a line to the next one with a space, and
      # keeps the break where a line is blank or more indented.
      def fold_block(text)
        out = +""
        lines = text.split("\n", -1)
        lines.each_with_index do |line, i|
          out << line
          following = lines[i + 1]
          next if following.nil?

          out << if line.empty? || following.empty? || line.start_with?(" ") || following.start_with?(" ")
                   "\n"
                 else
                   " "
                 end
        end
        out
      end

      def chomped(text, chomp)
        case chomp
        when :strip then text.sub(/\n+\z/, "")
        when :keep then text
        # A block scalar that carried no line at all is empty, and
        # clipping adds no break to nothing.
        else text.empty? ? "" : "#{text.sub(/\n+\z/, '')}\n"
        end
      end

      # --- flow collections ----------------------------------------------

      def flow_node(anchor, tag)
        peek == "[" ? flow_sequence(anchor, tag) : flow_mapping(anchor, tag)
      end

      def flow_sequence(anchor, tag)
        advance
        @handler.start_sequence(anchor, tag, tag.nil?, Nodes::Sequence::FLOW)
        until flow_closed?("]")
          flow_item
          flow_comma
        end
        @handler.end_sequence
      end

      def flow_mapping(anchor, tag)
        advance
        @handler.start_mapping(anchor, tag, tag.nil?, Nodes::Mapping::FLOW)
        until flow_closed?("}")
          flow_pair
          flow_comma
        end
        @handler.end_mapping
      end

      def flow_closed?(close)
        seek_content
        fail!("found unexpected end of stream") if eof?
        return false unless at?(close)

        advance
        true
      end

      def flow_comma
        seek_content
        advance if at?(",")
      end

      # One entry of a flow sequence, which may itself be a `a: b` pair.
      def flow_item
        anchor, tag = properties
        seek_content
        key = flow_scalar_or_node(anchor, tag)
        seek_content
        unless at?(":") && value_ahead?
          replay(key)
          return
        end

        @handler.start_mapping(nil, nil, true, Nodes::Mapping::FLOW)
        replay(key)
        advance
        flow_value
        @handler.end_mapping
      end

      def flow_pair
        anchor, tag = properties
        seek_content
        if at?("?")
          advance
          seek_content
        end
        replay(flow_scalar_or_node(anchor, tag))
        seek_content
        if at?(":")
          advance
          flow_value
        else
          empty_scalar
        end
      end

      def flow_value
        seek_content
        if at?(",") || at?("]") || at?("}")
          empty_scalar
        else
          anchor, tag = properties
          seek_content
          replay(flow_scalar_or_node(anchor, tag))
        end
      end

      # A flow node's events, recorded so a `a: b` pair can put a
      # mapping around them once the `:` shows up.
      def flow_scalar_or_node(anchor, tag)
        events = []
        keep = @handler
        @handler = Recorder.new(events)
        begin
          case peek
          when "[", "{" then flow_node(anchor, tag)
          when "*" then read_alias
          when "'", '"' then quoted_scalar(anchor, tag)
          else
            text = read_while { |c| !",[]{}\n".include?(c) && !(c == ":" && key_break?) && !comment_break?(c) }
            @handler.scalar(text.strip, anchor, tag, tag.nil?, false, Nodes::Scalar::PLAIN)
          end
        ensure
          @handler = keep
        end
        events
      end
    end

    # Keeps the events a lookahead makes, so they can be sent on once
    # the reading knows what the node is.
    class Recorder
      def initialize(events)
        @events = events
      end

      def method_missing(name, *args)
        @events << [name, args]
      end

      def respond_to_missing?(*) = true
    end
  end
end

module Psych
  # Writes the events a handler is given back out as YAML text, the way
  # libyaml writes them: block style, two spaces of indent, and a block
  # sequence level with the mapping key that holds it.
  class Emitter < Handler
    attr_accessor :line_width, :indentation, :canonical

    UNPRINTABLE = /[\u0000-\u0008\u000b-\u001f\u007f-\u009f]/

    def initialize(io, options = nil)
      @io = io
      @indentation = options.respond_to?(:indentation) ? options.indentation : 2
      @line_width = options.respond_to?(:line_width) ? options.line_width : 0
      @canonical = options.respond_to?(:canonical) ? options.canonical : false
      @stack = []
      @carry = nil
    end

    def start_stream(encoding) = nil

    def end_stream = nil

    def start_document(version, tag_directives, implicit)
      @io.write("%YAML #{version.join('.')}\n") if version && !version.empty?
      tag_directives.each { |handle, prefix| @io.write("%TAG #{handle} #{prefix}\n") }
      @stack = []
      @carry = nil
      nil
    end

    def end_document(implicit)
      @io.write("...\n") unless implicit
      nil
    end

    # A tag goes out only where neither the plain nor the quoted form
    # implies it, which is libyaml's rule: `nil` writes nothing at all,
    # and `!ruby/range` writes its tag.
    def scalar(value, anchor, tag, plain, quoted, style)
      head = prefix(anchor, plain || quoted ? nil : tag)
      place(next_slot, join(head, render(value.to_s, plain, quoted, style)))
    end

    def alias(anchor) = place(next_slot, "*#{anchor}")

    def start_sequence(anchor, tag, implicit, style) = open(:sequence, anchor, tag)

    def start_mapping(anchor, tag, implicit, style) = open(:mapping, anchor, tag)

    def end_sequence = close("[]")

    def end_mapping = close("{}")

    private

    def open(kind, anchor, tag)
      @stack << { kind: kind, slot: next_slot, head: prefix(anchor, tag), count: 0, key: nil, indent: 0, opened: false }
      nil
    end

    # An empty collection goes out flow, because block style has no way
    # to spell one.
    def close(empty)
      frame = @stack.pop
      place(frame[:slot], join(frame[:head], empty)) if frame[:count].zero?
      nil
    end

    # Where the node now starting belongs, and whose turn it takes. The
    # collection that holds it writes its own opening line first.
    def next_slot
      frame = @stack[-1]
      return { kind: :root } unless frame

      open_frame(frame)
      frame[:count] += 1
      case frame[:kind]
      when :sequence then { kind: :entry, indent: frame[:indent] }
      else
        frame[:key].nil? ? { kind: :key, frame: frame } : { kind: :value, indent: frame[:indent], frame: frame }
      end
    end

    # The line a collection writes before its first child: nothing at
    # the root but `---`, a `- ` the child shares, or the mapping key
    # the collection is the value of.
    def open_frame(frame)
      return if frame[:opened]

      frame[:opened] = true
      spot = frame[:slot]
      head = frame[:head]
      case spot[:kind]
      when :root
        @io.write(head.empty? ? "---\n" : "--- #{head}\n")
        frame[:indent] = 0
      when :entry
        if head.empty?
          @carry = @carry ? "#{@carry}- " : "#{' ' * spot[:indent]}- "
        else
          line(spot[:indent], "- #{head}")
        end
        frame[:indent] = spot[:indent] + @indentation
      when :value
        line(spot[:indent], join("#{spot[:frame][:key]}:", head))
        frame[:indent] = frame[:kind] == :sequence ? spot[:indent] : spot[:indent] + @indentation
      when :key
        line(spot[:frame][:indent], join("?", head))
        frame[:indent] = spot[:frame][:indent] + @indentation
        spot[:frame][:key] = :complex
      end
    end

    # One finished node's text into the place it belongs.
    def place(spot, text)
      case spot[:kind]
      when :root then @io.write("--- #{text}".rstrip + "\n")
      when :entry then line(spot[:indent], "- #{text}")
      when :key then spot[:frame][:key] = text
      when :value
        frame = spot[:frame]
        frame[:key] == :complex ? line(spot[:indent], ": #{text}") : line(spot[:indent], "#{frame[:key]}: #{text}")
        frame[:key] = nil
      end
      nil
    end

    def line(indent, text)
      @io.write("#{(@carry || ' ' * indent)}#{text}".rstrip + "\n")
      @carry = nil
    end

    def join(*parts) = parts.reject { |part| part.nil? || part.empty? }.join(" ")

    def prefix(anchor, tag)
      join(anchor && "&#{anchor}", tag && written_tag(tag))
    end

    def written_tag(tag)
      return "!!#{tag.delete_prefix('tag:yaml.org,2002:')}" if tag.start_with?("tag:yaml.org,2002:")
      return tag if tag.start_with?("!")

      "!<#{tag}>"
    end

    # --- scalars ---------------------------------------------------------

    def render(value, plain, _quoted, style)
      case style
      when Nodes::Scalar::LITERAL then block_scalar(value, "|")
      when Nodes::Scalar::FOLDED then block_scalar(value, ">")
      when Nodes::Scalar::SINGLE_QUOTED then single(value)
      when Nodes::Scalar::DOUBLE_QUOTED then double(value)
      else
        return value if plain && plain?(value)
        return double(value) if value.match?(UNPRINTABLE) || value.include?("\t")
        return block_scalar(value, "|") if value.include?("\n")

        single(value)
      end
    end

    # Whether the text can be written with no quotes at all. The caller
    # already decided the plain form means what it says; this is only
    # about the characters.
    def plain?(text)
      return true if text.empty?
      return false if text.match?(UNPRINTABLE) || text.include?("\n") || text.include?("\t")
      return false if text.start_with?(" ") || text.end_with?(" ")
      return false if ",[]{}#&*!|>'\"%@`".include?(text[0])
      return false if "-?:".include?(text[0]) && (text.length == 1 || " \t".include?(text[1]))
      return false if text.include?(": ") || text.include?(" #") || text.end_with?(":")

      true
    end

    def single(text) = "'#{text.gsub("'", "''")}'"

    ESCAPES = { "\\" => "\\\\", '"' => '\\"', "\n" => "\\n", "\t" => "\\t",
                "\r" => "\\r", "\0" => "\\0", "\a" => "\\a", "\b" => "\\b",
                "\v" => "\\v", "\f" => "\\f", "\e" => "\\e" }.freeze

    def double(text)
      body = text.gsub(/[\\"\u0000-\u001f\u007f]/) do |char|
        ESCAPES[char] || format("\\x%02x", char.ord)
      end
      "\"#{body}\""
    end

    # `|` keeps the breaks; the chomping marker says what happens to the
    # ones at the end.
    def block_scalar(text, mark)
      chomp = if text.end_with?("\n\n")
                "+"
              else
                text.end_with?("\n") ? "" : "-"
              end
      body = text.sub(/\n\z/, "").split("\n", -1)
      indent = @stack.empty? ? @indentation : @stack[-1][:indent] + @indentation
      "#{mark}#{chomp}\n#{body.map { |row| row.empty? ? '' : ' ' * indent + row }.join("\n")}"
    end
  end
end
