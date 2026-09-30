# frozen_string_literal: true

module Zr
  module Test
    # One program test: a plain Ruby file and the files beside it that say
    # what `ruby` does with it. The names are spinel's, so a spinel test
    # directory runs as it is:
    #
    #   foo.rb                the program
    #   foo.rb.expected       its stdout
    #   foo.rb.err.expected   its stderr; no file means none
    #   foo.rb.args           its arguments, separated by white space
    #   foo.rb.stdin          its stdin; no file means /dev/null
    #
    # and zr's, in the same style:
    #
    #   foo.rb.status          `exit N` or `signal N`; no file means `exit 0`
    #   foo.rb.env             `NAME=value` lines, added to its environment
    #   foo.rb.files/          files that the run directory holds (fixtures)
    #   foo.rb.needs           what the machine must have, one per line:
    #                          `libssl`, or a platform (`macos`, `linux`)
    #   foo.rb.ruby            options for ruby only, such as -W:no-experimental
    #   foo.rb.limits          `build_mb=N` and `run_mb=N` lines
    #   foo.rb.<platform>.expected   stdout on that platform, when it differs
    #
    # `root` is the directory that the program runs in; `rel` is the
    # program's path below it, as the command line gives it. A run copies
    # the program and its files into a new directory, so no run sees what
    # another wrote.
    Case = Data.define(:root, :rel) do
      # The programs below `dir` (a directory or one program) that have an
      # expected output, as Cases whose root is `root`.
      def self.under(dir, root)
        paths = File.file?(dir) ? [dir] : Dir[File.join(dir, "**/*.rb")].sort
        paths.select { |path| !path.include?(".rb.files/") && File.file?("#{path}.expected") }
             .map { |path| new(root, File.expand_path(path).delete_prefix(File.join(File.expand_path(root), ""))) }
      end

      def path = File.join(root, rel)

      def beside(suffix) = "#{path}.#{suffix}"

      def read(suffix) = File.file?(beside(suffix)) ? File.binread(beside(suffix)) : nil

      def source = File.binread(path)

      # The stdout that `platform` gives (`macos`, `linux`, `wasi`).
      def stdout(platform) = read("#{platform}.expected") || read("expected")

      def stderr = read("err.expected") || +"".b

      # `[code, signal]`: a process that a signal stopped has no code.
      def status
        text = read("status")&.strip
        return [0, nil] if text.nil? || text.empty?

        kind, number = text.split
        kind == "signal" ? [nil, Integer(number)] : [Integer(number), nil]
      end

      def args = read("args")&.split || []

      def stdin = read("stdin")

      def env = lines("env").to_h { |line| line.split("=", 2) }

      def needs = lines("needs")

      def ruby_options = read("ruby")&.split || []

      def limits = lines("limits").to_h { |line| line.split("=", 2).then { |name, value| [name.to_sym, Integer(value)] } }

      # The directory of files that the run directory holds, or nil.
      def files = File.directory?(beside("files")) ? beside("files") : nil

      private

      def lines(suffix) = (read(suffix) || "").lines(chomp: true).reject { |line| line.empty? || line.start_with?("#") }
    end
  end
end
