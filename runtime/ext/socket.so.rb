# frozen_string_literal: true

# socket.so: ext/socket's C part, in ruby over the kernel's calls
# (runtime/kernel/socket.rb). lib/socket.rb, as the gem ships it, requires
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
