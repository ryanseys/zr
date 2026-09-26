# frozen_string_literal: true

# Installs a built zr gem into a clean GEM_HOME and runs it as a user
# would: `zr version` and `zr doctor`, then a program as a WASI module
# and as an object. On an Apple Silicon Mac it also runs the program as
# a native binary; on any other host it checks that zr writes a macOS
# binary, refuses to run it, and never starts the compiled compiler's
# self-build. CI and the release workflow run it on the .gem they
# publish.
#
#   ruby .github/scripts/smoke.rb zr-0.1.0.gem [DIR]
#
# DIR (default /opt/zr) holds the gems, the cache and the outputs. CI
# uses the same path on every host, because the runtime carries its
# source paths, and the outputs of two hosts must be the same bytes.

require "fileutils"
require "open3"
require "rbconfig"

gem_file = File.expand_path(ARGV.fetch(0) { abort "usage: ruby .github/scripts/smoke.rb ZR_GEM [DIR]" })
root = ARGV.fetch(1, "/opt/zr")

# A runner cannot write /opt without sudo.
unless File.directory?(root)
  system("sudo", "mkdir", "-p", root, exception: true)
  system("sudo", "chown", ENV.fetch("USER"), root, exception: true)
end

env = { "GEM_HOME" => File.join(root, "gems"), "ZR_CACHE" => File.join(root, "cache"),
        "RUBYOPT" => nil, "BUNDLE_GEMFILE" => nil }
zr = File.join(env["GEM_HOME"], "bin/zr")
smoke = File.join(root, "smoke")
FileUtils.mkdir_p(smoke)
File.write(File.join(smoke, "sum.rb"), "puts [1, 2, 3].sum\n")

# Runs a command in the smoke directory, shows it, and stops the run
# when it fails. Returns its stdout.
run = lambda do |*argv|
  puts "$ #{argv.join(" ")}"
  out, status = Open3.capture2(env, *argv, chdir: smoke)
  print out
  abort "smoke: #{argv.first(2).join(" ")} exited #{status.exitstatus}" unless status.success?
  out
end

# The answer of the sum program, as ruby gives it.
expect = lambda do |got, what|
  abort "smoke: #{what} printed #{got.inspect}, not \"6\\n\"" unless got == "6\n"
end

run.(RbConfig.ruby, "-S", "gem", "install", "--local", gem_file)
run.(zr, "version")
run.(zr, "doctor")

# The first build: a host that cannot run a macOS binary must not start
# the compiled compiler's self-build.
native_host = RbConfig::CONFIG["host_os"].start_with?("darwin") && %w[arm64 aarch64].include?(RbConfig::CONFIG["host_cpu"])
puts "$ #{zr} build sum.rb -o sum.wasm --emit wasm"
_, err, status = Open3.capture3(env, zr, "build", "sum.rb", "-o", "sum.wasm", "--emit", "wasm", chdir: smoke)
$stderr.print err
abort "smoke: zr build --emit wasm exited #{status.exitstatus}" unless status.success?
abort "smoke: this host started the self-build of a compiler it cannot run" if !native_host && err.include?("building the compiler")

run.(zr, "build", "sum.rb", "-o", "sum.o", "--emit", "obj")
expect.(run.("wasmtime", "sum.wasm"), "wasmtime sum.wasm")
expect.(run.(zr, "run", "--emit", "wasm", "sum.rb"), "zr run --emit wasm")

if native_host
  expect.(run.(zr, "run", "sum.rb"), "zr run")
else
  # zr links a macOS arm64 binary on any host, and refuses to run it
  # where it cannot run (status 3).
  run.(zr, "build", "sum.rb", "-o", "sum")
  magic, cpu = File.binread(File.join(smoke, "sum"), 8).unpack("L<L<")
  abort "smoke: sum is not a Mach-O arm64 executable" unless magic == 0xfeedfacf && cpu == 0x0100000c
  _, status = Open3.capture2e(env, zr, "run", "sum.rb", chdir: smoke)
  abort "smoke: zr run of a macOS binary here exited #{status.exitstatus}, not 3" unless status.exitstatus == 3
end

puts "smoke: ok"
