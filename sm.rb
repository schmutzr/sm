#!/usr/bin/ruby
# 20140830 rschmutz@netlabs.ch

require "pstore"


# control collection of services

class Controller
  @services = []
  @states = nil

  def initialize(directory)
    @states = PStore.new(directory + "/" + ".states")
    @services = Array.new
    Dir.foreach directory do |file|
      next if file.match /^\./
      service = Service.new
      service.configure do
        eval(File.open(directory + "/" + file).read)
        if name.nil? # no identifier given, use the file name instead
          identifier file
        end
      end
      service.file = directory + "/" + file
      add_service service
    end
  end

  def add_service(service)
    @services << service
    @states.transaction do
      begin
        service.state = @states[service.name]
      rescue
        @states[service.name] = service.state
        @states.commit
      end
    end
  end

  def start_service(service)
    service.start_commands.each do |command|
      service.processes << fork do
        exec command
      end
    end
    service.processes.each { |pid| Process::detach pid }
    @states.transaction do
      @states[service.name] = (service.state = :running)
      @states.commit
    end
  end

  def start
    @services.each do |service|
      start_service service
    end
  end

  def stop_service(service)
    if service.stop_commands.empty? # kill processes the old way
      pid_from_files = service.pidfiles.collect do |pidfile|
        begin
          File.read(pidfile)
        rescue
        end
      end
      (service.processes & pid_from_files).each do |pid|
        begin
          Process::kill "KILL", pid
        rescue
        end
      end
    else # use provided stop commands
      service.stop_commands.each do |command|
        system command
      end
    end
    @states.transaction do
      @states[service.name] = service.state = :stopped
      @states.commit
    end
  end

  def stop
    @services.each do |service|
      stop_service service
    end
  end

  def status_service(service)
    check = nil
    if service.status_commands.empty? # kill processes the old way
      if service.pidfiles.empty?
        pids = service.processes
      else
        pids = service.pidfiles.collect do |pidfile|
          begin
            File.read(pidfile)
          rescue
          end
        end
      end
      if pids.all? do |pid|
        begin
          Process::kill 0, pid
          check = :running 
        rescue
          check = :stopped
        end
      end
      end
    else # use provided status commands
      service.status_commands.all? do |command|
        fork { exec command }
      end
    end
    result = :unknown
    if service.state != :uninitialized
      if check == service.state
        result = :running
      else
        result = :stopped
      end
    end
    return result
  end

  def status
    printf "%-20s%-15s%s\n", "service", "state", "check"
    printf "%--20s%--15s%s\n", "-------", "-----", "-----"
    @services.each do |service|
      state = status_service service
      printf "%-20s%-15s%s\n", service.name, service.state.to_s, state.to_s
    end
  end

  def services
    printf "%-20s%s\n", "service", "definition-file"
    printf "%-20s%s\n", "-------", "---------------"
    @services.each do |service|
      printf "%-20s%s\n", service.name, service.file
    end
  end

  def synchronize_service(service) # ensure service state match persistent state, ie start services in running state
    @states.transaction(true) do # read-only
      begin
        if @states[service.name] == :running
          state = status_service service
          if state != :running
            start_service service
          end
        end
      rescue
      end
    end
  end
end




# container class for a (single despite the legacy arrays) service

class Service
  attr_reader :description, :name, :start_commands, :stop_commands, :status_commands, :pidfiles
  attr_accessor :state, :processes, :file
  @description = ""
  @name = ""
  @processes = []
  @start_commands = []
  @stop_commands = []
  @status_commands = []
  @state = :down
  @file = ""
  @pidfiles = []

  def initialize
    @start_commands = Array.new
    @stop_commands = Array.new
    @status_commands = Array.new
    @pidfiles = Array.new
    @processes = Array.new
    @state = :uninitialized
  end

  def configure(&block)
    instance_eval &block
  end

  def description(description)
    @description = description
  end

  def identifier(name)
    @name = name
  end

  def start(command)
    @start_commands << command
  end

  def stop(command)
    @stop_commands << command
  end

  def status(command)
    @status_commands << command
  end

  def pidfile(pidfile)
    @pidfiles << pidfile
  end

end

controller = Controller.new("services")

controller.services
puts ""
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


# 
# sockets socket | [ socket socket... ]
# states: down starting faulty running disabled stopping
# connections remote-socket
# 
# render
# logging
# notfication
