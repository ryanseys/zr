# frozen_string_literal: true

# Runs a program as `zr-dev host` does (tool/hosted.rb), on the copy of
# zr that `Suite.pin!` made: CRuby runs zr's kernel and core library as
# Ruby, with no build. The fuzzer compares this answer with ruby's and
# with the binary's, to tell where a fault is.
#
#   ruby host.rb PIN prog.rb
#
# It loads only the pin's files. The caller sets the stack sizes
# (`Commands::Host::STACK`).

pin = File.expand_path(ARGV.shift)
path = ARGV.shift
lib = File.join(pin, "lib")
$LOAD_PATH.unshift(lib)
require File.join(lib, "zr/runtime")
require File.join(lib, "zr/machine/host/walk")

status = nil
Thread.new { status = Zr::Machine::Host::Walk.new.main(path, ARGV) }.join
$stdout.flush
exit(status || 1)
