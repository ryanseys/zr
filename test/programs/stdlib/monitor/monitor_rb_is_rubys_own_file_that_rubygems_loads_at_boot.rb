# rubygems loads monitor.rb as ruby starts, so MonitorMixin comes from
# ruby's own file, and a require of it answers false.
p $LOADED_FEATURES.count { |feature| feature.end_with?("/monitor.rb") }
p require("monitor")
p MonitorMixin.instance_method(:mon_enter).source_location.first.end_with?("/monitor.rb")
owner = Object.new.extend(MonitorMixin)
p owner.mon_synchronize { owner.mon_owned? }, owner.instance_variables
p Monitor.instance_method(:mon_enter) == Monitor.instance_method(:enter)
