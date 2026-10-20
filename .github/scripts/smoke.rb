# frozen_string_literal: true

# Installs a built zr gem into a clean GEM_HOME and runs it as a user
# would: `zr version` and `zr doctor`, then a program as a WASI module,
# as a macOS object and as a macOS binary, which any host builds. On a
# host that runs a target (an Apple Silicon Mac, a Linux), it also
# builds and runs the program as that host's binary. On a host other
# than an Apple Silicon Mac, it checks that zr refuses to run a macOS
# binary (status 3). CI and the release workflow run it on the .gem they
# publish.
#
#   ruby .github/scripts/smoke.rb [--user-cache] [--no-wasmtime] [--import BUNDLE]... zr-0.1.0.gem [DIR]
#
# DIR holds the gems, the cache and the outputs. Its default is /opt/zr:
# the same path on every host, because the runtime carries its source
# paths, and the outputs of two hosts must be the same bytes. With
# --user-cache, zr gets no ZR_CACHE, and uses the cache that a user
# gets (~/Library/Caches/zr or ~/.cache/zr): the stock-ruby jobs test
# that path, and DIR defaults to $RUNNER_TEMP/zr. The install must
# fetch nothing: the gem has no dependencies. --no-wasmtime skips the
# runs of the module, on a host without wasmtime (an Alpine container).
# Each --import BUNDLE is a runtime that `zr cache export` wrote from the
# checkout: the installed gem imports it, and a build for its target
# must then build no runtime, so a runtime has no path of its install.

require "fileutils"
require "json"
require "open3"
require "rbconfig"
require "tmpdir"
require "zlib"

user_cache = !ARGV.delete("--user-cache").nil?
wasmtime = ARGV.delete("--no-wasmtime").nil?
bundles = []
while (at = ARGV.index("--import"))
  bundles << File.expand_path(ARGV.delete_at(at + 1) || abort("smoke: --import needs a bundle"))
  ARGV.delete_at(at)
end
gem_file = File.expand_path(ARGV.fetch(0) { abort "usage: ruby .github/scripts/smoke.rb [--user-cache] [--no-wasmtime] [--import BUNDLE]... GEM [DIR]" })
root = ARGV.fetch(1) { user_cache ? File.join(ENV.fetch("RUNNER_TEMP", Dir.tmpdir), "zr") : "/opt/zr" }

# A runner's user cannot write /opt without sudo; root in a container can.
begin
  FileUtils.mkdir_p(root)
rescue Errno::EACCES
  system("sudo", "mkdir", "-p", root, exception: true)
  system("sudo", "chown", ENV.fetch("USER"), root, exception: true)
end
# The cache below it must be this user's alone (Paths.trusted!), and a
# runner's umask can leave a new directory open to every user.
File.chmod(0o755, root)
# So must each directory above it: on the arm64 Linux runner, every user
# can write /opt, with no sticky bit, and zr refuses a cache below it.
File.dirname(root).then do |dir|
  until dir == "/"
    stat = File.stat(dir)
    system("sudo", "chmod", "o-w", dir, exception: true) if stat.world_writable? && !stat.sticky?
    dir = File.dirname(dir)
  end
end

# GEM_PATH is ruby's own default gems only: no gem that the runner has
# installed can satisfy the install.
env = { "GEM_HOME" => File.join(root, "gems"), "GEM_PATH" => Gem.default_dir, "ZR_CACHE" => (File.join(root, "cache") unless user_cache),
        "RUBYOPT" => nil, "BUNDLE_GEMFILE" => nil }
zr = File.join(env["GEM_HOME"], "bin/zr")
smoke = File.join(root, "smoke")
FileUtils.mkdir_p(smoke)
File.write(File.join(smoke, "sum.rb"), "puts [1, 2, 3].sum\n")

# The targets of the imported bundles (the manifest's second line).
imported = bundles.map { |bundle| Zlib::GzipReader.open(bundle) { |gz| gz.gets && JSON.parse(gz.gets).fetch("target") } }

# Runs a command in the smoke directory, shows it, and stops the run
# when it fails. Returns its stdout. A build for an imported target must
# build no runtime.
run = lambda do |*argv|
  puts "$ #{argv.join(" ")}"
  out, err, status = Open3.capture3(env, *argv, chdir: smoke)
  print out
  $stderr.print err
  abort "smoke: #{argv.first(2).join(" ")} exited #{status.exitstatus}" unless status.success?
  target = argv[argv.index("--target") + 1] if argv.include?("--target")
  target ||= argv.include?("wasm") ? "wasm32-wasi" : Zr::Target.default.triple if defined?(Zr::Target)
  if argv[1] == "build" && imported.include?(target) && err.include?("zr: building")
    abort "smoke: #{argv.join(" ")} built a runtime that #{target}'s bundle holds"
  end
  out
end

# The answer of the sum program, as ruby gives it.
expect = lambda do |got, what|
  abort "smoke: #{what} printed #{got.inspect}, not \"6\\n\"" unless got == "6\n"
end

installed = run.(RbConfig.ruby, "-S", "gem", "install", "--local", gem_file)
abort "smoke: the install fetched a gem; zr must have no dependencies" if installed.include?("Fetching")
# The sparse checkout has no lib/, so the version and the pinned ruby
# come from the gem just installed.
lib = File.join(env["GEM_HOME"], "gems", File.basename(gem_file, ".gem"), "lib")
require File.join(lib, "zr/version.rb")
require File.join(lib, "zr/target.rb")
version = run.(zr, "version")
want = "zr #{Zr::VERSION} (for ruby #{Zr::RUBY_PIN})\n"
abort "smoke: zr version printed #{version.inspect}, not #{want.inspect}" unless version == want
run.(zr, "doctor")
bundles.each { |bundle| run.(zr, "cache", "import", bundle) }
run.(zr, "--help")
run.(zr, "help", "build")

# A bad setting is one line and status 2, with no backtrace.
out, status = Open3.capture2e(env.merge("ZR_JOBS" => "abc"), zr, "build", "sum.rb", "-o", "sum", chdir: smoke)
unless status.exitstatus == 2 && out == %(zr: ZR_JOBS is "abc". Set it to a whole number of 1 or more, for example ZR_JOBS=4.\n)
  abort "smoke: ZR_JOBS=abc gave status #{status.exitstatus} and #{out.inspect}"
end

# The first bytes of each kind of binary: Mach-O arm64, and ELF with
# the machine of its arch.
magic = lambda do |path, target|
  bytes = File.binread(File.join(smoke, path), 20)
  ok = if target.object_format == :macho
         bytes.unpack("L<L<") == [0xfeedfacf, 0x0100000c]
       else
         bytes.start_with?("\x7fELF".b) && bytes.unpack1("@18S<") == { aarch64: 0xb7, x86_64: 0x3e }.fetch(target.arch)
       end
  abort "smoke: #{path} is not a #{target.triple} binary" unless ok
end

darwin = Zr::Target::AARCH64_DARWIN
run.(zr, "build", "sum.rb", "-o", "sum.wasm", "--emit", "wasm")
run.(zr, "build", "sum.rb", "-o", "sum.darwin.o", "--emit", "obj", "--target", darwin.triple)
if wasmtime
  expect.(run.("wasmtime", "sum.wasm"), "wasmtime sum.wasm")
  expect.(run.(zr, "run", "--emit", "wasm", "sum.rb"), "zr run --emit wasm")
end

# zr links a macOS binary on any host.
run.(zr, "build", "sum.rb", "-o", "sum-macos", "--target", darwin.triple)
magic.("sum-macos", darwin)

# The binary of this host's own target, where it runs one and can link it.
host = Zr::Target.host
if host&.linkable?
  expect.(run.(zr, "run", "sum.rb"), "zr run")
  run.(zr, "build", "sum.rb", "-o", "sum")
  magic.("sum", host)
  expect.(run.("./sum"), "./sum")
end

# zr refuses to run a macOS binary where it cannot run (status 3).
unless host == darwin
  out, status = Open3.capture2e(env, zr, "run", "--target", darwin.triple, "sum.rb", chdir: smoke)
  abort "smoke: zr run of a macOS binary here exited #{status.exitstatus}, not 3" unless status.exitstatus == 3
  abort "smoke: zr run here said #{out.inspect}" unless out.include?("To run the program here, use 'zr run --emit wasm sum.rb'")
end

puts "smoke: ok"
