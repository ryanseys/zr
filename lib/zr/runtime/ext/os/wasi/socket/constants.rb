# frozen_string_literal: true

# WASI's socket constants. A module opens no socket (the calls fail with
# ENOTSUP, kernel/os/wasi/missing.rb), so the numbers only show. They are
# Linux's, as musl spells them: wasi-libc comes from musl, and a program
# that prints them prints what it prints on Linux.
require_relative "../../linux/socket/constants"
