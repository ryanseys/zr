# frozen_string_literal: true

# The same program, built from two copies of the tree at two paths
# under another home, clock zone, locale and job count, with one path
# root (`zr build --path-root`), must come out as the same bytes: a
# build is a function of its sources and its flags, never of where it
# ran.
#
#   rake repro              # the native binary and the object
#   rake repro[wasm]        # and the wasm module
#
# Each copy builds its own runtime under the root, so this takes two
# runtime builds (four with wasm).

require "fileutils"
require "open3"
require "rbconfig"
require "tmpdir"
require_relative "../lib/zr/paths"
require_relative "../lib/zr/native/parallel"

module Repro
  ROOT = Zr::Paths::ROOT
  PATH_ROOT = "/zr"

  # A main file that requires a file of its own and names both, and a
  # backtrace through the two.
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

  module_function

  def run(wasm: false)
    work = Dir.mktmpdir("zr-repro-")
    puts "work (kept if this fails): #{work}"
    copies = [File.join(work, "a/zr"), File.join(work, "b/other/place/zr")]
    copies.each { |copy| copy_tree(copy) }
    at_once = Zr::Native::Parallel.machine_bytes >= 12 * (1 << 30)
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
      abort("rake repro: the two #{what} differ: #{a[what].bytesize} and #{b[what].bytesize} bytes, first at #{at}; " \
            "both copies are kept in #{work}")
    end
    puts "the same bytes from both copies: #{a.map { |what, bytes| "#{what} #{bytes.bytesize}" }.join(', ')}"
    FileUtils.rm_rf(work)
  end

  # The tree as it stands, tracked and untracked files alike, less what
  # git ignores: the edits under test go in, the caches do not.
  def copy_tree(copy)
    files, status = Open3.capture2("git", "ls-files", "-z", "--cached", "--others", "--exclude-standard", chdir: ROOT)
    abort("rake repro: git ls-files failed") unless status.success?
    files.split("\0").each do |file|
      from = File.join(ROOT, file)
      next unless File.file?(from)

      to = File.join(copy, file)
      FileUtils.mkdir_p(File.dirname(to))
      FileUtils.cp(from, to, preserve: true)
    end
    FileUtils.mkdir_p(File.join(copy, "repro/lib"))
    File.write(File.join(copy, "repro/main.rb"), MAIN)
    File.write(File.join(copy, "repro/lib/shape.rb"), SHAPE)
  end

  # The copy's outputs, built in the copy under an environment of its
  # own; the binary also runs, and what it prints must name the root.
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
      command = [RbConfig.ruby, File.join(copy, "exe/zr"), "build", "repro/main.rb", "-o", "repro/#{out}", *emit,
                 "--path-root=#{PATH_ROOT}"]
      puts "#{copy}: #{what}"
      text, status = Open3.capture2e(env, *command, chdir: copy)
      abort("rake repro: the #{what} did not build in #{copy}:\n#{text}") unless status.success?
      [what, File.binread(File.join(copy, "repro", out))]
    end.tap { |bytes| check_answer(copy, env) if bytes.key?("binary") }
  end

  # What the binary prints names every file below the root.
  def check_answer(copy, env)
    text, status = Open3.capture2e(env, File.join(copy, "repro/main"), chdir: copy)
    want = ["repro/main.rb", "#{PATH_ROOT}/repro/lib/shape.rb", "#{PATH_ROOT}/repro/lib",
            "#{PATH_ROOT}/repro/lib/shape.rb:4:in 'Shape.fail!'", "repro/main.rb:4:in '<main>'"]
    return if status.success? && text.lines(chomp: true) == want

    abort("rake repro: the binary in #{copy} answered:\n#{text}\nnot:\n#{want.join("\n")}")
  end
end

desc "Build one program from two copies of the tree at two paths, and compare the bytes (repro[wasm] adds the module)"
task(:repro, [:wasm]) { |_, args| Repro.run(wasm: args[:wasm] == "wasm") }
