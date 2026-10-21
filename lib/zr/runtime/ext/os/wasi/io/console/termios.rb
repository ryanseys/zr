# frozen_string_literal: true

# WASI's struct termios. No descriptor of a module is a terminal (each
# terminal call fails with ENOTTY), so io/console loads and its methods
# raise as on a pipe. The layout is musl's, as on Linux.
require_relative "../../../linux/io/console/termios"
