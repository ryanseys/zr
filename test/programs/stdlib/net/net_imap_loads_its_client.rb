# The bundled net-imap gem loads its client class.
require "net/imap"
p Net::IMAP.class, Net::IMAP.instance_method(:login).arity
