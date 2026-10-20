# frozen_string_literal: true

# Derived from the C of CRuby and of its gems (Ruby or BSD-2-Clause); see
# THIRD_PARTY_NOTICES.md.
#
# socket.so: ext/socket's C part, in ruby over the kernel's calls
# (lib/zr/runtime/kernel/socket.rb). lib/socket.rb, as the gem ships it, requires
# this first and then reopens what it defines. Each file here represents
# the C file in its name.
class BasicSocket < IO
end

class Socket < BasicSocket
end

require "socket/constants"
require "socket/layout"
require_relative "socket/init"
require_relative "socket/basicsocket"
require_relative "socket/socket"
require_relative "socket/ipsocket"
require_relative "socket/unixsocket"
require_relative "socket/option"
require_relative "socket/ancdata"
require_relative "socket/addrinfo"
require_relative "socket/ifaddr"
