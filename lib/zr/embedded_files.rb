# frozen_string_literal: true

require "digest/sha2"
require_relative "parse"
require_relative "session"
require_relative "hir/build/literal_paths"

module Zr
  # The files that a library reads by a path that the build can tell, whose
  # bytes a binary carries, so that the read answers wherever the program
  # runs. rubygems runs `eval File.read(path)` where `path =
  # File.join(__dir__, "rubygems/core_ext/kernel_require.rb")`. A library's
  # Ruby files are compiled in already; only the ones that it reads as
  # data go in as bytes. A path is one from the library's own directory
  # (`__dir__`), and the file must be under one of the library roots, so a
  # read of a system file (`/etc/hosts`) still reads the disk.
  module EmbeddedFiles
    # The reads whose first argument names the file.
    READS = %i[read binread readlines foreach].freeze
    # The text that a file with such a read has, which most files lack, so
    # few files are parsed.
    MENTIONS = /\b(?:File|IO)\.(?:read|binread|readlines|foreach)\b/

    module_function

    # The bytes of each file that the files at `paths` read, by path: only
    # the files under `roots`.
    #: (Array[String] paths, Array[String] roots) -> Hash[String, String]
    def for(paths, roots)
      roots = roots.map { |root| "#{root.chomp("/")}/" }
      paths.each_with_object({}) do |path, out|
        next unless roots.any? { |root| path.start_with?(root) }

        read_by(path).each { |file| out[file] ||= File.binread(file) if roots.any? { |root| file.start_with?(root) } }
      end
    end

    # The files that the file at `path` reads by a path that the build can
    # tell, once for each content.
    #: (String path) -> Array[String]
    def read_by(path)
      text = begin
        File.binread(path)
      rescue SystemCallError
        return []
      end
      return [] unless text.match?(MENTIONS)

      Session.current.memo([:embedded_reads, path, Digest::SHA256.hexdigest(text)]) { scan(text, path) }
    end

    # The reads in `text`, the source of the file at `path`, in order: a
    # local that a path is written to stands for that path where a read
    # takes it.
    #: (String text, String path) -> Array[String]
    def scan(text, path)
      found = [] #: Array[String]
      locals = {} #: Hash[Symbol, String]
      walk = lambda do |node|
        case node
        when Prism::LocalVariableWriteNode
          (known = dir_path(node.value, path)) ? locals[node.name] = known : locals.delete(node.name)
        when Prism::CallNode
          receiver = node.receiver
          arg = node.arguments&.arguments&.first
          if arg && READS.include?(node.name) && receiver.is_a?(Prism::ConstantReadNode) && %i[File IO].include?(receiver.name)
            known = arg.is_a?(Prism::LocalVariableReadNode) ? locals[arg.name] : dir_path(arg, path)
            found << File.expand_path(known) if known && File.file?(known)
          end
        end
        node.compact_child_nodes.each(&walk)
      end
      walk.call(Prism.parse(text, filepath: path).value)
      found.uniq
    end

    # A path that `node` builds from the file's directory, not a bare
    # literal, which names a file wherever the program runs.
    #: (Prism::node node, String path) -> String?
    def dir_path(node, path)
      return nil if node.is_a?(Prism::StringNode)

      Hir::Build::LiteralPaths.literal_path(node, path)
    end
  end
end
