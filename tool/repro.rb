# frozen_string_literal: true

require "fileutils"
require "open3"
require "tmpdir"
require_relative "lib/zr/dev"

module Zr
  module Dev
    # Builds the same program from two copies of the tree at two paths.
    # Each copy has a different home, time zone, locale and job count, but
    # the same path root (`zr build --path-root`). The outputs must have the
    # same bytes: a build depends only on its sources and flags, not on
    # where it ran.
    #
    #   zr-dev repro            the native binary and the object
    #   zr-dev repro --wasm     and the wasm module
    #
    # Each copy builds its own runtime, so this tool does two runtime builds
    # (four with wasm).
    class Repro < Command
      summary "Build one program from two copies of the tree at two paths, and compare the bytes"
      usage "[--wasm]"

      def defaults = @wasm = false

      def options(o) = o.on("--wasm", "also build and compare the wasm module") { @wasm = true }

      PATH_ROOT = "/zr"

      # A main file that requires a second file, prints the paths of both,
      # and prints a backtrace through both.
      MAIN = <<~'RUBY'
        require_relative "lib/shape"
        puts __FILE__, Shape.file, Shape.dir
        begin
          Shape.fail!
        rescue => e
          puts e.backtrace.first(2)
        end
      RUBY
      SHAPE = <<~'RUBY'
        module Shape
          def self.file = __FILE__
          def self.dir = __dir__
          def self.fail! = raise("no")
        end
      RUBY

      def run(_argv)
        require_relative "../lib/zr/native/parallel"
        wasm = @wasm
        work = Dir.mktmpdir("zr-repro-")
        puts "work (kept if this fails): #{work}"
        copies = [File.join(work, "a/zr"), File.join(work, "b/other/place/zr")]
        copies.each { |copy| copy_tree(copy) }
        at_once = Native::Parallel.machine_bytes >= 12 * (1 << 30)
        outs = copies.each_with_index.map { |copy, i| [copy, i] }.then do |pairs|
          if at_once
            pairs.map { |copy, i| Thread.new { build(copy, i, wasm) } }.map(&:value)
          else
            pairs.map { |copy, i| build(copy, i, wasm) }
          end
        end
        a, b = outs
        a.each_key do |what|
          next if a[what] == b[what]

          at = a[what].bytes.zip(b[what].bytes).index { |x, y| x != y } || [a[what].bytesize, b[what].bytesize].min
          fail!("the two #{what} differ: #{a[what].bytesize} and #{b[what].bytesize} bytes, first at #{at}; " \
                "both copies are kept in #{work}")
        end
        puts "the same bytes from both copies: #{a.map { |what, bytes| "#{what} #{bytes.bytesize}" }.join(", ")}"
        FileUtils.rm_rf(work)
      end

      # Copies the current tree: tracked and untracked files, but not files
      # that git ignores. Thus uncommitted edits go in, and caches do not.
      def copy_tree(copy)
        files = Dev.tree_files(dir: ROOT) or fail!("git ls-files failed")
        files.each do |file|
          to = File.join(copy, file)
          FileUtils.mkdir_p(File.dirname(to))
          FileUtils.cp(File.join(ROOT, file), to, preserve: true)
        end
        FileUtils.mkdir_p(File.join(copy, "repro/lib"))
        File.write(File.join(copy, "repro/main.rb"), MAIN)
        File.write(File.join(copy, "repro/lib/shape.rb"), SHAPE)
      end

      # Builds the outputs in the copy, with an environment for that copy.
      # It also runs the binary, which must print paths under the path root.
      def build(copy, index, wasm)
        home = File.join(copy, "..", "home").then { |dir| FileUtils.mkdir_p(dir) && File.expand_path(dir) }
        tmp = File.join(home, "tmp").tap { |dir| FileUtils.mkdir_p(dir) }
        env = { "HOME" => home, "TMPDIR" => tmp, "ZR_CACHE" => File.join(home, "cache"), "RUBYOPT" => nil, "RUBYLIB" => nil,
                "TZ" => %w[UTC Asia/Tokyo][index], "LANG" => %w[C en_CA.UTF-8][index], "ZR_JOBS" => %w[2 3][index],
                "BUNDLE_GEMFILE" => nil }
        outs = { "binary" => "main", "object" => "main.o" }
        outs["wasm module"] = "main.wasm" if wasm
        outs.to_h do |what, out|
          emit = { "main.o" => %w[--emit obj], "main.wasm" => %w[--emit wasm] }.fetch(out, [])
          command = [Dev.ruby, File.join(copy, "exe/zr"), "build", "repro/main.rb", "-o", "repro/#{out}", *emit,
                     "--path-root=#{PATH_ROOT}"]
          puts "#{copy}: #{what}"
          text, status = Open3.capture2e(env, *command, chdir: copy)
          fail!("the #{what} did not build in #{copy}:\n#{text}") unless status.success?
          [what, File.binread(File.join(copy, "repro", out))]
        end.tap { |bytes| check_answer(copy, env) if bytes.key?("binary") }
      end

      # Checks that the binary prints each path under the path root.
      def check_answer(copy, env)
        text, status = Open3.capture2e(env, File.join(copy, "repro/main"), chdir: copy)
        want = ["repro/main.rb", "#{PATH_ROOT}/repro/lib/shape.rb", "#{PATH_ROOT}/repro/lib",
                "#{PATH_ROOT}/repro/lib/shape.rb:4:in 'Shape.fail!'", "repro/main.rb:4:in '<main>'"]
        return if status.success? && text.lines(chomp: true) == want

        fail!("the binary in #{copy} answered:\n#{text}\nnot:\n#{want.join("\n")}")
      end
    end
  end
end
