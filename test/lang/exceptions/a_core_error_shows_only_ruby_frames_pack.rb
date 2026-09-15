# A pack or unpack that raises shows the frame of the method the program
# called, and none of the helpers ze0 keeps for itself: CRuby does that
# work in C, with no frame and no constant a program can see.

def show
  yield
rescue => e
  puts "#{e.class}: #{e.message}"
  puts e.backtrace
end

show { "abc".unpack("@9") }
show { "abc".unpack1("x9") }
show { [1].pack(1) }
show { [1].pack("y") }
show { "abc".unpack("m0") }
p Object.constants.include?(:Packing)

__END__
ArgumentError: @ outside of string
lang/exceptions/a_core_error_shows_only_ruby_frames_pack.rb:12:in 'String#unpack'
lang/exceptions/a_core_error_shows_only_ruby_frames_pack.rb:12:in 'block in <main>'
lang/exceptions/a_core_error_shows_only_ruby_frames_pack.rb:6:in 'Object#show'
lang/exceptions/a_core_error_shows_only_ruby_frames_pack.rb:12:in '<main>'
ArgumentError: x outside of string
lang/exceptions/a_core_error_shows_only_ruby_frames_pack.rb:13:in 'String#unpack1'
lang/exceptions/a_core_error_shows_only_ruby_frames_pack.rb:13:in 'block in <main>'
lang/exceptions/a_core_error_shows_only_ruby_frames_pack.rb:6:in 'Object#show'
lang/exceptions/a_core_error_shows_only_ruby_frames_pack.rb:13:in '<main>'
TypeError: no implicit conversion of Integer into String
lang/exceptions/a_core_error_shows_only_ruby_frames_pack.rb:14:in 'Array#pack'
lang/exceptions/a_core_error_shows_only_ruby_frames_pack.rb:14:in 'block in <main>'
lang/exceptions/a_core_error_shows_only_ruby_frames_pack.rb:6:in 'Object#show'
lang/exceptions/a_core_error_shows_only_ruby_frames_pack.rb:14:in '<main>'
ArgumentError: unknown pack directive 'y' in 'y'
lang/exceptions/a_core_error_shows_only_ruby_frames_pack.rb:15:in 'Array#pack'
lang/exceptions/a_core_error_shows_only_ruby_frames_pack.rb:15:in 'block in <main>'
lang/exceptions/a_core_error_shows_only_ruby_frames_pack.rb:6:in 'Object#show'
lang/exceptions/a_core_error_shows_only_ruby_frames_pack.rb:15:in '<main>'
ArgumentError: invalid base64
lang/exceptions/a_core_error_shows_only_ruby_frames_pack.rb:16:in 'String#unpack'
lang/exceptions/a_core_error_shows_only_ruby_frames_pack.rb:16:in 'block in <main>'
lang/exceptions/a_core_error_shows_only_ruby_frames_pack.rb:6:in 'Object#show'
lang/exceptions/a_core_error_shows_only_ruby_frames_pack.rb:16:in '<main>'
false
