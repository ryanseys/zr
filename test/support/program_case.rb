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
    #                          `libssl`, `nonroot`, `argv0`, `dlopen`, or a
    #                          platform (`macos`, `linux`, `linux-gnu`,
    #                          `linux-musl`, `wasi`)
    #   foo.rb.ruby            options for ruby only, such as -W:no-experimental
    #   foo.rb.limits          `build_mb=N` and `run_mb=N` lines
    #   foo.rb.<recording>.expected      stdout on that platform, when it
    #   foo.rb.<recording>.err.expected  differs; and stderr. A recording
    #                                    is `macos`, `wasi`, or on Linux
    #                                    the libc's (`linux-gnu`,
    #                                    `linux-musl`; Runner#recording)
    #
    # `root` is the directory that the program runs in; `rel` is the
    # program's path below it, as the command line gives it. A run copies
    # the program and its files into a new directory, so no run sees what
    # another wrote.
    Case = Data.define(:root, :rel) do
      # The programs below `dir` (a directory or one program) that have an
      # expected output, or with `every` all of them, as Cases whose root is
      # `root`. The files that a program's run directory holds
      # (foo.rb.files/) are no programs.
      def self.under(dir, root, every: false, shallow: false)
        paths = File.file?(dir) ? [dir] : Dir[File.join(dir, shallow ? "*.rb" : "**/*.rb")].sort.reject { |path| path.include?(".rb.files/") }
        paths.filter_map do |path|
          new(root, File.expand_path(path).delete_prefix(File.join(File.expand_path(root), ""))) if every || File.file?("#{path}.expected")
        end
      end

      def path = File.join(root, rel)

      def beside(suffix) = "#{path}.#{suffix}"

      def read(suffix) = File.file?(beside(suffix)) ? File.binread(beside(suffix)) : nil

      def source = File.binread(path)

      # The stdout of the first of `recordings` that has one
      # (Runner#recordings), else the default.
      def stdout(recordings) = recorded(recordings, "expected") || read("expected")

      # The stderr of the first of `recordings` that has one, else the
      # default; no file means none.
      def stderr(recordings = nil) = recorded(recordings, "err.expected") || read("err.expected") || +"".b

      def recorded(recordings, suffix)
        Array(recordings).each do |name|
          text = read("#{name}.#{suffix}")
          return text if text
        end
        nil
      end

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

      # The files that the run directory holds, as `[name, bytes]` in name
      # order, a symbolic link as `-> target`.
      def fixture_parts
        dir = files or return []
        Dir.glob("**/*", File::FNM_DOTMATCH, base: dir).sort.filter_map do |name|
          path = File.join(dir, name)
          next if File.basename(name) == "." || (File.directory?(path) && !File.symlink?(path))

          [name, File.symlink?(path) ? "-> #{File.readlink(path)}" : File.binread(path)]
        end
      end

      private

      def lines(suffix) = (read(suffix) || "").lines(chomp: true).reject { |line| line.empty? || line.start_with?("#") }
    end
  end
end
