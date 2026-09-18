# frozen_string_literal: true

# The oracle for rt/ext/ze0/ast.rb. It parses each Ruby source twice: once
# with the host's RubyVM::AbstractSyntaxTree (parse.y) and once with the
# prism-to-parse.y translator, and it compares the two trees node for node.
#
#   ruby tools/ast.rb                       every test/**/*.rb file
#   ruby tools/ast.rb test/lang dir/x.rb    the files and directories given
#   ruby tools/ast.rb -e 'a, b = 1, 2'      one source (repeatable)
#
# Options:
#   --show N     print the first N mismatches in full (default 10)
#   --only TEXT  print only the mismatches whose histogram key includes TEXT
#   --dump       print both trees for each source, not only the difference
#   --quiet      print only the summary
#   --failures   print the name of each source that does not match
#   --locations  also compare each node's keyword locations (Node#locations)
#   --tokens     also compare the token lists that keep_tokens: true answers
#
# A file's text after an `__END__` line is data, so the tool parses only the
# part before it. A file that CRuby itself cannot parse is skipped. The tool
# reads one file at a time and keeps no tree after its comparison.

require_relative "../rt/ext/ze0/ast"

class AstOracle
  def initialize(argv)
    @show = 10
    @only = nil
    @dump = false
    @quiet = false
    @failures = false
    @locations = false
    @tokens = false
    @sources = []
    paths = []
    argv = argv.dup
    until argv.empty?
      case (arg = argv.shift)
      when "--show" then @show = Integer(argv.shift)
      when "--only" then @only = argv.shift
      when "--dump" then @dump = true
      when "--quiet" then @quiet = true
      when "--failures" then @failures = true
      when "--locations" then @locations = true
      when "--tokens" then @tokens = true
      when "-e" then @sources << ["-e", argv.shift]
      else paths << arg
      end
    end
    @sources = files_under(paths).lazy.map { |path| [path, nil] } if @sources.empty?
  end

  def run
    @total = @matched = @skipped = @errors = @shown = 0
    @histogram = Hash.new(0)
    @error_kinds = Hash.new(0)
    @sources.each { |name, text| check(name, text || source_of(name)) }
    summary
  end

  private

  def check(name, text)
    begin
      expected = RubyVM::AbstractSyntaxTree.parse(text, keep_tokens: @tokens)
    rescue SyntaxError, ArgumentError, EncodingError
      @skipped += 1
      return
    end
    @total += 1
    begin
      actual = Ze0::AST.parse(text, keep_tokens: @tokens)
    rescue StandardError, ScriptError, SystemStackError => e
      raised(name, e)
      return
    end
    puts "== #{name}", "-- CRuby", dump(expected), "-- translator", dump(actual) if @dump

    found = first_difference(expected, actual)
    found ||= token_difference(expected, actual) if @tokens
    if found.nil?
      @matched += 1
      return
    end
    mismatched(name, *found)
  end

  def raised(name, error)
    @errors += 1
    @error_kinds["#{error.class}: #{error.message[0, 80]}"] += 1
    puts name if @failures
    return if @quiet || @only || @shown >= @show

    @shown += 1
    puts "== #{name}: translator raised #{error.class}: #{error.message}"
    puts error.backtrace.first(6).map { |line| "   #{line}" }
  end

  def mismatched(name, path, expected, actual)
    kind = kind_of(expected) == kind_of(actual) ? kind_of(expected) : "#{kind_of(expected)} -> #{kind_of(actual)}"
    parent = path.last ? path.last.sub(/\[\d+\]\z/, "") : "ROOT"
    key = "#{parent} > #{kind}"
    @histogram[key] += 1
    puts name if @failures
    return if @quiet || @shown >= @show
    return if @only && !key.include?(@only)

    @shown += 1
    puts "== #{name}: #{path.join(' > ')}"
    puts "-- CRuby", clip(dump(expected)), "-- translator", clip(dump(actual))
  end

  def summary
    puts
    rate = @total.zero? ? 0 : (100.0 * @matched / @total).round(1)
    puts "matched #{@matched} / #{@total} (#{rate}%), translator errors #{@errors}, skipped #{@skipped} unparsable"
    unless @histogram.empty?
      puts "first mismatches by parent > node:"
      @histogram.sort_by { |key, count| [-count, key] }.first(40).each { |key, count| puts format("%6d  %s", count, key) }
    end
    return if @error_kinds.empty?

    puts "translator errors:"
    @error_kinds.sort_by { |key, count| [-count, key] }.first(15).each { |key, count| puts format("%6d  %s", count, key) }
  end

  def node?(value)
    value.is_a?(RubyVM::AbstractSyntaxTree::Node) || value.is_a?(Ze0::AST::Node)
  end

  # CRuby 4.0.6 reads a `::A = 1` constant path as a COLON2 and answers a
  # garbage name that crashes on inspect, so the oracle skips that child.
  def children_of(node)
    children = node.children
    if node.type == :CDECL && node?(children[0]) && children[0].type == :COLON3
      children = children.dup
      children[1] = :"(unreadable)"
    end
    children
  end

  # One line per node: type and span; other children appear through inspect.
  def dump(node, depth = 0, out = +"")
    pad = "  " * depth
    if node?(node)
      out << "#{pad}#{head(node).sub(/ \(\d+\)/, '')}\n"
      children_of(node).each { |child| dump(child, depth + 1, out) }
    elsif node.is_a?(Array) && node.any? { |item| node?(item) }
      out << "#{pad}[\n"
      node.each { |item| dump(item, depth + 1, out) }
      out << "#{pad}]\n"
    else
      out << "#{pad}#{node.inspect}\n"
    end
    out
  end

  # What must agree about one child: a node's type, span, child count, and
  # (with --locations) keyword spans; any other value's inspect.
  def head(node)
    if node?(node)
      text = "#{node.type} [#{span(node)}] (#{children_of(node).size})"
      if @locations
        spans = node.locations.drop(1).map { |location| location && span(location) }
        text += " locations=#{spans.inspect}" unless spans.empty?
      end
      text
    elsif node.is_a?(Array) && node.any? { |item| node?(item) }
      "[array of #{node.size}]"
    else
      node.inspect
    end
  end

  def span(thing)
    "#{thing.first_lineno}:#{thing.first_column}-#{thing.last_lineno}:#{thing.last_column}"
  end

  # Answers nil when the trees agree, else [path, expected, actual].
  def first_difference(expected, actual, path = [])
    return [path, expected, actual] if head(expected) != head(actual)

    children =
      if node?(expected) then children_of(expected).zip(children_of(actual))
      elsif expected.is_a?(Array) then expected.zip(actual)
      else return nil
      end
    children.each_with_index do |(want, have), index|
      label = node?(expected) ? "#{expected.type}[#{index}]" : "[#{index}]"
      found = first_difference(want, have, path + [label])
      return found if found
    end
    nil
  end

  def token_difference(expected, actual)
    want = expected.all_tokens
    have = actual.all_tokens
    return nil if want == have

    index = want.zip(have).index { |pair| pair[0] != pair[1] } || want.size
    [["tokens[#{index}]"], want[index].inspect, have[index].inspect]
  end

  def source_of(path)
    text = File.binread(path)
    text = text.byteslice(0, text =~ /^__END__\r?$/n) if text.match?(/^__END__\r?$/n)
    text.force_encoding(Encoding::UTF_8)
  end

  def files_under(args)
    args = ["test"] if args.empty?
    args.flat_map do |arg|
      File.directory?(arg) ? Dir.glob(File.join(arg, "**", "*.rb")).sort : [arg]
    end
  end

  def clip(text, lines = 40)
    rows = text.lines
    rows.size > lines ? rows.first(lines).join + "  ... (#{rows.size - lines} more lines)\n" : text
  end

  def kind_of(value)
    return value.type.to_s if node?(value)
    return "nil" if value.nil?

    value.is_a?(String) && value.start_with?("[") ? "token" : value.class.name
  end
end

if $PROGRAM_NAME == __FILE__
  # parse.y's warnings about the sources themselves are noise here.
  $VERBOSE = nil
  AstOracle.new(ARGV).run
end
