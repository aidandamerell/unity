#!/usr/bin/env ruby

require 'tty-prompt'
require 'tty-command'
require 'awesome_print'
require 'colorize'
require 'yaml'
require 'pry'

@prompt = TTY::Prompt.new(interrupt: :exit)

# These are our variables that can be used inside the tool command
INPUT_VARS = {
  # ip: nil,
  # username: nil,
  # password: nil,
  # domain: nil,
  # command: nil,
  # in_file: nil,
  # out_file: nil,
  # range: nil,
}

class Protocol
  @@all_protocols = {}
  @@current = nil

  attr_accessor :name, :actions

  def initialize(**kargs)
    @name = kargs[:name]
    @actions = kargs[:actions] || []
    @@all_protocols[@name] = self
  end


  def self.create_or_find(**kargs)
    existing = @@all_protocols[kargs[:name]]

    return existing if existing

    self.new(**kargs)
  end

  def self.all
    @@all_protocols
  end

  def self.current
    @@current
  end

  def self.current=(value)
    @@current = @@all_protocols[value.upcase]
    # if you reset the protocol, you reset the action and technique
    Action.current = nil
    Technique.current = nil
  end

  def self.pry
    binding.pry
  end

  # Load in the actions you've defined
  def self.load
    YAML.load_file('tools.yml').each do |action|
      proto = Protocol.create_or_find(name: action[:protocol])

      new_action = Action.new(name: action[:name], protocol: proto)
      proto.actions << new_action

      new_action.techniques = action[:techniques].map do |tech|
        Technique
        .new(
          name: tech[:name],
          command: tech[:command],
          priority: tech[:priority],
          action: new_action,
          defaults: tech[:defaults],
          iterate_mode: tech[:iterate_mode],
          iterate_over: tech[:iterate_over],
          iterate_replacer: tech[:iterate_replacer],
          )
      end.sort_by(&:priority).reverse
    end
  end

  def self.reload!
    @@all_protocols = {}
    Protocol.load
  end
end


class Action
  @@current = nil

  attr_accessor :name, :techniques
  attr_reader :protocol

  def initialize(**kargs)
    @name = kargs[:name]
    @protocol = kargs[:protocol]
    @techniques = kargs[:techniques] || []
  end

  def self.current
    @@current
  end
  
  def self.current=(value)
    @@current = value
    Technique.current = nil
  end
end


class Technique
  MAX_STARS = 5

  @@current = nil

  attr_accessor :name, :priority, :command, :required_params, :defaults
  attr_reader :action, :priority_stars, :iterate_mode, :iterate_over, :iterate_replacer

  def initialize(**kargs)
    @name = kargs[:name]
    @priority = kargs[:priority]
    @command = kargs[:command]
    @required_params = kargs[:required_params]
    @defaults = kargs[:defaults]
    @iterate_over = kargs[:iterate_over]
    @iterate_mode = kargs[:iterate_mode]
    @iterate_replacer = kargs[:iterate_replacer]
    @action = kargs[:action]
  end

  def priority_stars
    return '-' unless priority

    left = MAX_STARS - priority
    "*".green * priority + '-'.red * left
  end

  # Hash#merge will use override the FIRST hashes attributes
  # with that found in the second, so let the user override attributes
  # from the defaults
  def get_vars
    return INPUT_VARS if !@@current.defaults

    @@current.defaults.merge INPUT_VARS
  end

  def generate!(override_param = {})
    @@current.command % get_vars.merge(override_param)
  rescue KeyError => error
    warn("Missing Variable: #{error.message}")
  end

  def run!
    if iterate_mode && get_vars[iterate_over.to_sym]
      case iterate_mode
      when 'iterate'
        get_vars[iterate_over.to_sym].split(',').each do |item|
          cmd = generate!(Hash[iterate_replacer.to_sym, item])
          run_command(cmd)
        end
      when 'multi_pass'
        item = get_vars[iterate_over.to_sym].join(', ')
        cmd = generate!(Hash[iterate_replacer.to_sym, item])
        run_command(cmd)
      end
    else
      run_command(generate!)
    end
  end

  def run_command(command)
    cmd = TTY::Command.new(printer: :quiet)

    cmd.run(command)
  rescue TTY::Command::TimeoutExceeded, TTY::Command::ExitError, Errno::ENOENT => e
    puts "Error => #{e.class}: #{e}".red
  end


  def self.current
    @@current
  end
  
  def self.current=(value)
    @@current = value
  end
end

def prompt_details
  "|#{Protocol.current&.name&.blue}| (#{Action.current&.name&.blue}) [#{Technique.current&.name&.blue}]"
end

def var_or_select(prompt, prompt_name, value, action_proc, select_proc)
  if value && !value.empty?
    action_proc.call(value)
  else
    @prompt.select(prompt_name, filter: true) do |menu|
      select_proc.call(menu)
    end
  end
end

def warn(message)
  puts message.yellow
end

def set_var(name, value)
  value = value.join('')
  case name
  when 'protocol', 'proto'
    Protocol.current = var_or_select(
      @prompt,
      "Select Protocol >",
      value,
      Proc.new { |value| Protocol.current = value },
      Proc.new { |menu| Protocol.all.values.each { |proto| menu.choice(proto.name, proto.name) }.sort_by(&:name) }
    )
    warn("Protocol Not Found") if !Protocol.current
  when 'action'
    Action.current = var_or_select(
      @prompt,
      "Select Action >",
      value,
      Proc.new { |value| Protocol.current.actions.find { |a| a.name == value } },
      Proc.new { |menu| Protocol.current.actions.each { |action| menu.choice(action.name, action) } }
    )
    warn("Action Not Found") if !Action.current
  when 'technique', 'tech'

    Technique.current = var_or_select(
      @prompt,
      "Select Technique >",
      value,
      Proc.new { |value| Action.current.techniques.find { |a| a.name == value } },
      Proc.new { |menu|Action.current.techniques.each { |tech| menu.choice("#{tech.name} (#{tech.command.yellow}) [#{tech.priority_stars}]", tech) } }
    )
    warn("Technique Not Found") if !Technique.current
  else
    INPUT_VARS[name.to_sym] = value
  end
end

def show(thing)
  case thing
  when 'all'
    Protocol.all.each do |_key, proto|
      puts proto.name.blue
      proto.actions.each do |action|
        puts " - #{action.name}".green
      end
    end
  when 'actions'
    puts Protocol.current&.actions&.map(&:name)
  when 'options', 'vars'
    ap({
      current_protocol: Protocol.current&.name,
      current_action: Action.current&.name,
      current_technique: {
        name: Technique.current&.name,
        command: Technique.current&.command,
        priority: Technique.current&.priority,
      },
      variables: INPUT_VARS,
    })
  when 'protocol'
    puts Protocol.current&.name
  when 'techniques'
    puts Action.current&.techniques&.map(&:name)
  else
    warn("Unknown Type")
  end
end

def parse_input(input)
  split = input.split(" ")

  case split[0]
  when 'show'
    show(split[1])
  when 'set'
    set_var(split[1], split[2..-1])
  when 'run'
    return warn('No Technique Set') if !Technique.current

    Technique.current.run!
  when 'generate'
    return warn('No Technique Set') if !Technique.current

    puts Technique.current.generate!
  when 'exit'
    exit
  when 'pry'
    Protocol.pry
  when 'reload'
    Protocol.reload!
    puts "Reloading data".blue
  else
    puts 'Unknown command, type help?'.yellow
  end
end

Protocol.load
while true
  parse_input(@prompt.ask("#{prompt_details}>"))
end
