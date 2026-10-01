# frozen_string_literal: true

# Rewrites kernel files from the dialect form to the plain form (A6):
#
#   ruby tool/kern_rewrite.rb FILE...
#
# The file becomes one `module Zr::Kern`. `machine def` becomes `def`,
# `Machine.import "f"` becomes `Libc.import :f`, `Machine.struct :X, ...`
# becomes `X = layout ...`, `Machine.sig :name` becomes `Name = fn` (and
# `Machine.call(:name, p, ...)` becomes `Name.call(p, ...)`),
# `Machine.inline`/`collects`/`raw` lose `Machine.`, and a bare call to an
# import becomes `Libc.name(...)`. `zr-dev golden check` then shows that
# the IR did not change. This changes spelling only; the checked build
# finds the sites that need a `_wrap` or `sdiv`.
require_relative "../lib/zr/parse"
require_relative "../lib/zr/target"
require_relative "../lib/zr/runtime_sources"
require_relative "../lib/zr/machine/description"

module Zr
  module KernRewrite
    module_function

    def camel(name) = name.split("_").map(&:capitalize).join

    # The names that some target's kernel imports.
    def imports
      Target.all.flat_map { |target| RuntimeSources.for(target).kernel_files }.uniq.flat_map do |file|
        File.read(file).scan(/^\s*(?:Machine\.import\s+"([^"]+)"|Libc\.import\s+:(\w+))/).flatten.compact
      end.to_set
    end

    def rewrite(source, imports)
      tree = Zr.parse(source).value
      edits = []
      body = tree.statements.body
      body.each { |node| top(node, edits) }
      calls(tree, imports, edits)
      out = source.dup
      edits.sort_by { |at, _, _| -at }.each { |at, len, text| out[at, len] = text }
      wrap(out, inner_lines(out))
    end

    # The lines (from 0) that start inside a string literal, where an
    # indent would change the string.
    def inner_lines(text)
      lines = Set.new
      todo = [Zr.parse(text).value]
      while (node = todo.shift)
        if node.is_a?(Prism::StringNode) || node.is_a?(Prism::InterpolatedStringNode)
          if node.heredoc?
            # The body and the closing line, which `<<-` lets stay where it is.
            body = node.is_a?(Prism::StringNode) ? node.content_loc : node.parts.first&.location
            ((body.start_line - 1)..body.end_line).each { |l| lines << l } if body
          else
            loc = node.location
            ((loc.start_line)...(loc.end_line)).each { |l| lines << l }
          end
        end
        todo.concat(node.compact_child_nodes)
      end
      lines
    end

    def top(node, edits)
      return unless node.is_a?(Prism::CallNode)

      args = node.arguments&.arguments
      machine = node.receiver.is_a?(Prism::ConstantReadNode) && node.receiver.name == :Machine
      if node.name == :machine && node.receiver.nil?
        edits << [node.location.start_offset, 8, ""] # "machine "
      elsif machine && node.name == :import
        edits << [node.location.start_offset, args[0].location.end_offset - node.location.start_offset, "Libc.import :#{args[0].unescaped}"]
      elsif machine && node.name == :struct
        edits << [node.location.start_offset, args[1].location.start_offset - node.location.start_offset, "#{args[0].unescaped} = layout "]
      elsif machine && node.name == :sig
        edits << [node.location.start_offset, args[1].location.start_offset - node.location.start_offset, "#{camel(args[0].unescaped)} = fn "]
      elsif machine && %i[inline collects].include?(node.name)
        edits << [node.location.start_offset, 8, ""] # "Machine."
      elsif machine && node.name == :raw
        raw = Machine::RAW.fetch(args[0].unescaped)
        edits << [node.location.start_offset, node.location.length, "raw :#{raw.name}, [#{raw.params.join(", ")}] => #{raw.ret}"]
      end
    end

    # Calls in def bodies: bare imports and `Machine.call`.
    def calls(node, imports, edits)
      if node.is_a?(Prism::CallNode)
        args = node.arguments&.arguments || []
        if node.receiver.nil? && imports.include?(node.name.to_s) && node.name != :machine && node.name != :sig
          edits << [node.location.start_offset, 0, "Libc."]
        elsif node.name == :call && node.receiver.is_a?(Prism::ConstantReadNode) && node.receiver.name == :Machine
          name = args[0]
          edits << [node.location.start_offset, args[1].location.start_offset - node.location.start_offset, "#{camel(name.unescaped)}.call("]
        end
      end
      node.compact_child_nodes.each { |c| calls(c, imports, edits) }
    end

    # Puts the statements in `module Zr::Kern`, with the file's opening
    # comment left above it.
    def wrap(text, inner)
      lines = text.lines
      head = 0
      head += 1 while head < lines.size && lines[head].start_with?("#")
      head += 1 while head < lines.size && lines[head].strip.empty?
      body = lines[head..].each_with_index.map do |line, i|
        if inner.include?(head + i) then line # a Prism line is from 1: line head+i+1 starts inside a string
        elsif line.strip.empty? then "\n"
        else "  #{line}"
        end
      end
      body.pop while body.last == "\n"
      "#{lines[0, head].join}module Zr::Kern\n#{body.join}end\n"
    end
  end
end

if $PROGRAM_NAME == __FILE__
  imports = Zr::KernRewrite.imports
  ARGV.each do |file|
    source = File.read(file)
    next if source.match?(/^module Zr::Kern$/)

    own = source.scan(/^Machine\.import\s+"([^"]+)"/).flatten
    File.write(file, Zr::KernRewrite.rewrite(source, imports | own))
  end
end
