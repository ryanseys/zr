# The tail expression of a Thread body is the value of the thread. It can be
# of any kind: here it is the Hash that Hash#each answers.
t1 = Thread.new { { "a" => 1 }.each { |w, n| } }
p t1.value.class

t2 = Thread.new { { 1 => "a" }.each_pair { |k, v| } }
p t2.value.class

t3 = Thread.new { { "a" => 1 } }
p t3.value.class

# the kinds that already worked
t4 = Thread.new { [1, 2].each { |x| } }
p t4.value.class
t5 = Thread.new { (1..3).each { |x| } }
p t5.value.class
t6 = Thread.new { "abc" }
p t6.value
t7 = Thread.new { [1, 2] }
p t7.value
t8 = Thread.new { 42 }
p t8.value

# a trailing expression after the each, which was the reported workaround
t9 = Thread.new { { "a" => 1 }.each { |w, n| }; 7 }
p t9.value
