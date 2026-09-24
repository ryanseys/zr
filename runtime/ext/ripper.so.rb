# frozen_string_literal: true

# `ripper.so`: the C part of ext/ripper, over prism. CRuby's ripper runs
# parse.y's lexer and parser and calls a method for each token (a scanner
# event) and each rule it reduces (a parser event). Here prism supplies
# both: its lex_compat stream gives every token with ripper's position and
# lexer state, and prism's own Ripper translation walks the tree and gives
# the parser events. The Ruby part, ripper.rb and ripper/*.rb, is ruby's.
require "prism"
require "prism/translation/ripper"

class Ripper
  Version = "0.1.0"

  # The tables ripper/core.rb reads, which ripper/lexer.rb adds to.
  PARSER_EVENT_TABLE = Prism::Translation::Ripper::PARSER_EVENT_TABLE.dup
  SCANNER_EVENT_TABLE = Prism::Translation::Ripper::SCANNER_EVENT_TABLE.dup

  Prism::Translation::Ripper.constants.grep(/\AEXPR_/).each do |name|
    const_set(name, Prism::Translation::Ripper.const_get(name))
  end

  def self.lex_state_name(state) = Prism::Translation::Ripper.lex_state_name(state)

  # The leading spaces and tabs of `input` that make up `width` columns,
  # a tab reaching the next multiple of eight, removed in place, as
  # parse.y's dedent_string removes them. Returns the bytes removed.
  def self.dedent_string(input, width)
    raise TypeError, "no implicit conversion of #{input.class} into String" unless input.is_a?(String)

    columns = 0
    removed = 0
    input.each_byte do |byte|
      break if columns >= width

      if byte == 32
        columns += 1
      elsif byte == 9
        tabbed = (columns / 8 + 1) * 8
        break if tabbed > width

        columns = tabbed
      else
        break
      end
      removed += 1
    end
    input.replace(input.byteslice(removed..))
    removed
  end

  def initialize(src, filename = "(ripper)", lineno = 1)
    if src.respond_to?(:gets)
      text = +""
      while (line = src.gets)
        text << line
      end
      src = text
    end
    raise TypeError, "no implicit conversion of #{src.class} into String" unless src.is_a?(String)

    @cursor = Cursor.new(src, filename.to_s, Integer(lineno))
  end

  def filename = @cursor.filename

  # The position of the event being dispatched, and the lexer's state
  # and token there; nil outside a parse.
  def lineno = @cursor.parsing ? @cursor.lineno : nil
  def column = @cursor.parsing ? @cursor.column : nil
  def state = @cursor.parsing ? @cursor.state : nil
  def token = @cursor.parsing ? @cursor.token : nil

  def error? = @cursor.error
  def end_seen? = @cursor.parsed && !Prism.parse(@cursor.source).data_loc.nil?
  def encoding = Prism.parse(@cursor.source).encoding

  def yydebug = false
  def yydebug=(flag); end
  def debug_output = nil
  def debug_output=(output); end

  # Every token as its scanner event, in order; then the tree as its
  # parser events, where a token in the tree gives the value that its
  # scanner event returned. A second parse finds the input at its end.
  def parse
    raise ArgumentError, "Ripper#parse is not reentrant" if @cursor.parsing
    return nil if @cursor.parsed

    @cursor.parsing = true
    begin
      Events.new(self, @cursor).parse
    ensure
      @cursor.parsing = false
      @cursor.parsed = true
    end
  end

  private

  def dedent_string(input, width) = Ripper.dedent_string(input, width)

  # A parse's source and the positions of its events.
  Cursor = Struct.new(:source, :filename, :first_lineno, :lineno, :column, :state, :token, :parsing, :parsed, :error) do
    def at(line, col, lex_state = state, text = token)
      self.lineno = line
      self.column = col
      self.state = lex_state
      self.token = text
    end
  end
  private_constant :Cursor

  # prism's walk of the tree, which calls each event on the Ripper that
  # requested the parse.
  class Events < Prism::Translation::Ripper
    def initialize(ripper, cursor)
      super(cursor.source, cursor.filename, cursor.first_lineno)
      @ripper = ripper
      @cursor = cursor
      @tokens = Hash.new { |tokens, key| tokens[key] = [] }
    end

    # The scanner events first, each token once, remembered by its line
    # and event; then the parser events.
    def parse
      lexed = Prism.lex_compat(@cursor.source, filepath: @cursor.filename, line: @cursor.first_lineno, version: "current").value
      lexed.each do |(line, col), event, text, lex_state|
        @cursor.at(line, col, lex_state.to_i, text)
        @tokens[[line, event]] << [col, @ripper.__send__(event, text)]
      end
      super
    end

    # A superclass takes the terminator after it, as parse.y's
    # `superclass` rule does, so the body starts with no void statement.
    def visit_class_node(node)
      return super if node.superclass.nil? || node.body.nil?

      constant_path =
        if node.constant_path.is_a?(Prism::ConstantReadNode)
          bounds(node.constant_path.location)
          on_const_ref(on_const(node.constant_path.name.to_s))
        else
          visit(node.constant_path)
        end
      superclass = visit(node.superclass)
      bodystmt = visit_body_node(node.body.location.copy(length: 0), node.body, true)

      bounds(node.location)
      on_class(constant_path, superclass, bodystmt)
    end

    private

    # The value that the scanner event returned for the token at this
    # place in the tree: the token that starts here, or one inside the
    # text, which a squiggly heredoc's lexing has already dedented.
    def token_at(event, text)
      @tokens[[lineno, event]].find { |col, _| col == column } ||
        @tokens[[lineno, event]].find { |col, _| col > column && col < column + text.bytesize }
    end

    def bounds(location)
      super
      @cursor.at(lineno, column)
    end

    # A squiggly heredoc's tokens come from prism's lexer already
    # dedented, as were their scanner events, so no width is left to
    # take off.
    def on_heredoc_dedent(value, _width) = @ripper.__send__(:on_heredoc_dedent, value, 0)

    (PARSER_EVENT_TABLE.keys - [:heredoc_dedent]).each do |event|
      define_method(:"on_#{event}") do |*args|
        @cursor.error = true if event.end_with?("error")
        @ripper.__send__(:"on_#{event}", *args)
      end
    end

    SCANNER_EVENT_TABLE.each_key do |event|
      define_method(:"on_#{event}") do |text|
        found = token_at(:"on_#{event}", text.to_s)
        found ? found.last : @ripper.__send__(:"on_#{event}", text)
      end
    end

    def warn(fmt, *args) = @ripper.__send__(:warn, fmt, *args)
    def warning(fmt, *args) = @ripper.__send__(:warning, fmt, *args)

    def compile_error(message)
      @cursor.error = true
      @ripper.__send__(:compile_error, message)
    end

    def dedent_string(input, width) = @ripper.__send__(:dedent_string, input, width)
  end
  private_constant :Events
end
