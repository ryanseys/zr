# Struct#[] and #[]= of a missing member raise a NameError that names the
# key as given and the struct as its receiver, as invalid_struct_pos does;
# did_you_mean reads the receiver for its suggestion.
value = Struct.new(:does_exist).new
[-> { value[:doesnt_exist] }, -> { value["doesnt_exist"] }, -> { value[:doesnt_exist] = 1 },
 -> { value["does_exis"] = 1 }].each do |call|
  call.call
rescue NameError => e
  p [e.class, e.message, e.name, e.receiver.equal?(value)]
  puts e.detailed_message(highlight: false)
end
p value.dig(:doesnt_exist) rescue p [$!.class, $!.message]
