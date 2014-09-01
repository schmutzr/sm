#!/usr/bin/ruby
# 20140901 rschmutz@netlabs.ch


require "sm.rb"

controller = Controller.new("services")

controller.services
puts ""
puts "filter sleep:"
controller.status(/sleep/)
puts ""
puts "all services:"
controller.status
puts ""
controller.start
puts "waiting..."
sleep 10
controller = Controller.new("services")
controller.status
puts ""
controller.stop
puts ""
controller.status
