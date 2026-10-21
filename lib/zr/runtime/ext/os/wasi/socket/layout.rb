# frozen_string_literal: true

# WASI's socket structures. A module opens no socket, so a sockaddr is
# only built and read in memory, as musl lays it out on Linux.
require_relative "../../linux/socket/layout"
