# frozen_string_literal: true

require_relative "version"

module Zr
  # Marks an exception as a refusal: the program uses a form that the
  # marked stage does not support, as opposed to a bug in that stage. A
  # refusal keeps the superclass its stage already raises (`StandardError`,
  # `Backend::Refused`, `NotImplementedError`, ...), so exit codes
  # (`CLI::Commands::Compile#lower`), the program tests' split
  # (`ProgramBuild::REFUSALS`) and the cc
  # fallbacks (`Native::Build`) keep matching on that superclass. `include
  # Zr::Refusal` only lets code ask a class or instance whether it means
  # this, without naming every stage's own `Refused`.
  module Refusal; end

  # The program uses a form that zr does not support. The message gives
  # the file, the line (and the column, where the stage knows it) and the
  # form. `zr` exits with status 3 (`CLI::REFUSED`), and the program
  # tests report an error, unless the target's baseline lists the test.
  class Refused < StandardError
    include Refusal

    # The page that lists what zr supports, for the user who reads a
    # refusal.
    DOCS = "#{DOCS_URL}/reference/support.md".freeze

    # User words for the syntax nodes that zr refuses by their class. A
    # node that is not here gets its class name in words.
    FORMS = {
      "FlipFlop" => "the flip-flop operator (a range as a condition)",
      "MatchLastLine" => "a regexp literal as a condition (`if /re/`)",
      "InterpolatedMatchLastLine" => "an interpolated regexp literal as a condition",
      "PreExecution" => "`BEGIN { }`",
      "PostExecution" => "`END { }`"
    }.freeze

    # The form of a syntax node (a prism node or an HIR node) in words.
    def self.form_of(node)
      name = node.class.name.split("::").last.delete_suffix("Node")
      FORMS.fetch(name) { "#{name.gsub(/(?<=[a-z])(?=[A-Z])/, " ").downcase} (#{name})" }
    end

    # A refusal of `form` at the place in the source.
    def self.unsupported(form, file:, line:, column: nil)
      place = [file, line, column].compact.join(":")
      new("#{place}: zr does not support #{form} yet", file: file, line: line, column: column, form: form)
    end

    attr_reader :file, :line, :column, :form

    # A stage that knows only a message (the linkers, the machine
    # dialect) gives only the message.
    def initialize(message = nil, file: nil, line: nil, column: nil, form: nil)
      super(message)
      @file = file
      @line = line
      @column = column
      @form = form
    end

    # The source line of the refusal, and a caret under its column, or
    # nil when the file cannot be read.
    def excerpt
      return nil unless file && line && File.file?(file)

      text = File.foreach(file).drop(line - 1).first&.chomp
      return nil unless text

      caret = column ? "\n    #{" " * (column - 1)}^" : ""
      "    #{text}#{caret}"
    rescue SystemCallError, IOError, ArgumentError
      nil
    end
  end
end
