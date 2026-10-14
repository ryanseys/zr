# frozen_string_literal: true

# Runs a program as `zr-dev host` does (lib/zr/machine/host/launch.rb),
# on the copy of zr that `Suite.pin!` made: CRuby runs zr's kernel and
# core library as Ruby, with no build. The fuzzer compares this answer
# with ruby's and with the binary's, to tell where a fault is.
#
#   ruby host.rb PIN prog.rb
#
# It loads only the pin's files. The caller sets the stack sizes
# (`Machine::Host::STACK`).

pin = File.expand_path(ARGV.shift)
path = ARGV.shift
lib = File.join(pin, "lib")
$LOAD_PATH.unshift(lib)
require File.join(lib, "zr/machine/host/launch")

exit(Zr::Machine::Host.walk(path, ARGV) || 1)
