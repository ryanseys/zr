# Each END block that raises is reported and the next one runs. An error
# in the EXIT trap is the program's error, reported after them.
Signal.trap(:EXIT) { raise "EXIT" }
END { raise "END1" }
END { raise "END2" }
END { puts "END3" }
