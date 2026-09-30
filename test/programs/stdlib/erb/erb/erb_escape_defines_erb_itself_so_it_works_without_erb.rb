# erb/escape.so defines the class ERB itself, so the file works alone.
require "erb/escape"
p ERB.class, ERB::Escape.html_escape("<a & 'b'>"), ERB::Escape.singleton_methods, ERB::Escape.private_instance_methods(false)
