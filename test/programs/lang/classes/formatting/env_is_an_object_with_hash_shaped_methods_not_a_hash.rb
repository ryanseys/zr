# The P-B core classes: File, Dir, Time, Process, ENV.
#
# Everything here is zone- and machine-independent on purpose: Time uses a
# fixed epoch read in UTC, paths are built under a scratch directory this
# script creates, and nothing prints a real pid/clock/environment value --
# only facts about them. That is what lets the output be diffed against real
# ruby at all.

# --- ENV: an Object with Hash-shaped methods, not a Hash -------------------
p ENV.class
ENV["ZR_TEST_EXAMPLE"] = "set"
p ENV["ZR_TEST_EXAMPLE"]
p ENV.key?("ZR_TEST_EXAMPLE")
p ENV.fetch("ZR_TEST_EXAMPLE")
p ENV.fetch("ZR_TEST_ABSENT", "default")
p ENV.fetch("ZR_TEST_ABSENT") { |k| "computed:#{k}" }
p ENV["ZR_TEST_ABSENT"]
p ENV.delete("ZR_TEST_EXAMPLE")
p ENV.key?("ZR_TEST_EXAMPLE")
p ENV.to_h.class
p ENV.keys.class

