# SignalException.new takes a number (through to_int) with an optional
# message, or a signal's name alone, checked as signm2signo checks it.
def t(label)
  p [label, yield]
rescue ArgumentError => e
  p [label, e.class, e.message]
end
t(:none) { SignalException.new }
t(:neg) { SignalException.new(-1) }
t(:bad_sym) { SignalException.new(:XXXXXXXXXX) }
t(:jp) { SignalException.new("\u{30eb 30d3 30fc}") }
t(:sigexit) { SignalException.new("-SIGEXIT") }
t(:exit) { SignalException.new("EXIT") }
t(:big) { SignalException.new(1000) }
bad = Signal.list.reject { |name, no| name == "EXIT" }.reject do |name, no|
  SignalException.new(name).signo == no && SignalException.new(name.to_sym).signo == no && SignalException.new(no).signo == no
end
p bad
p SignalException.new("INT").message
p SignalException.new(:SIGINT).message
p SignalException.new(2).message
p SignalException.new(2, "custom").message
t(:name_and_msg) { SignalException.new("INT", "x") }
p Interrupt.new.message
p Interrupt.new("hi").signo
t(:minus_int) { SignalException.new("-INT") }
t(:minus_sym) { SignalException.new(:"-INT") }
t(:null) { SignalException.new("IN\0T") }
t(:obj) { SignalException.new(Object.new) }
t(:float) { SignalException.new(2.0) }
p SignalException.new("SIGIOT").message
p SignalException.new(:IOT).signo
p SignalException.new("SIGINT").message
p((SignalException.new(2.7) rescue $!))
p((SignalException.new(2.0, "m") rescue $!))
p((SignalException.new(nil) rescue $!))
o = Object.new
def o.to_int = 15
p((SignalException.new(o) rescue $!))
s = Object.new
def s.to_str = "INT"
p((SignalException.new(s) rescue $!))
p((SignalException.new(99.0) rescue $!))
p SignalException.new(0).message
p((SignalException.new(2, "a", "b") rescue $!))
p((SignalException.new("INT", "a") rescue $!))
