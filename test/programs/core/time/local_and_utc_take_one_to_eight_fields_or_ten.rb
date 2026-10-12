# Time.local, .mktime, .utc and .gm take one to eight fields, or the ten
# that Time#to_a gives, as time_arg does; another count is an
# ArgumentError from the method ruby defines (.mktime is .local).
def show(label)
  p yield
rescue StandardError => e
  p [label, e.class, e.message, e.backtrace_locations.first.label]
end

%i[local mktime utc gm].each do |m|
  [0, 9, 11, 12].each do |n|
    show("#{m}(#{n})") { Time.public_send(m, *Array.new(n, 1)) }
  end
  show("#{m}(1)") { Time.public_send(m, 2000).year }
  show("#{m}(8)") { Time.public_send(m, 2000, 1, 2, 3, 4, 5, 6, "UTC").min }
  show("#{m}(10)") { Time.public_send(m, 5, 4, 3, 2, 1, 2000, nil, nil, false, nil).to_a.first(6) }
end
