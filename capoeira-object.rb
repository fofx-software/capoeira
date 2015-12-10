assign = proc do |cap, key, val|
  (class << cap; self; end).instance_exec do
    define_method("#{key}=") { |val| assign[self, key, val] }
    
    define_method key do |*args, &blk|
      args.push(blk) if blk
      if Proc === val
        val.curry[*args]
      else
        val
      end
    end
    
    define_method("_#{key}") { val }
  end
end

cap = proc do |*modules|
  modules.each(&:cap)
  
  if !@capped
    @capped = true
    
    (class << self; self; end).instance_exec do
      define_method :method_missing do |name, *args, &blk|
        abbrev = name.to_s.sub(/=$/, '').to_sym
        
        if name != abbrev
          # does not capture brackets in :[]=
          abbrev = abbrev.to_s.match(/\w+/)
          # if was :[]=, match is nil and name is first argument:
          abbrev = (abbrev ? abbrev[0] : args.shift).to_sym
          assign[self, abbrev, *args]
        else
          val = nil
          name = args.shift if name == :[]
          abbrev = name.to_s.sub(/^_/, '').to_sym
          modules.find do |mod|
            if Hash === mod && mod.has_key?(abbrev)
              val = mod[abbrev]
              true
            elsif Proc === mod
              val = mod[self, name, *args]
            end
          end
          if Proc === val
            args.push(blk) if blk
            if abbrev == name
              val = val.curry[self, *args]
            else
              val.apply do |old_val|
                val = proc { |*args| old_val.curry[self, *args] }
              end
            end
          end
        end
        val
      end
    end
  end
  self
end

yes_no = proc do |expect, o, yes = nil, no = nil, blk = nil|
  blk ||= (no || yes)
  if Proc === blk
    !!o == expect ? blk[o] : blk == yes ? o : yes
  else
    !!o == expect ? yes : no || o
  end
end

do_if = proc do |expect, o, *tests, blk|
  is_true = tests.any? ? tests.to_proc[o] : o
  blk[o] if !!is_true == expect
  o
end

apply = proc { |o, blk| blk[o] }

object_utilities = {
  yes?: yes_no.curry[true],
  no?: yes_no.curry[false],
  if_true: do_if.curry[true],
  if_false: do_if.curry[false],
  apply: apply
}

module Capoeira; end

(Capoeira::BasicObject = Class.new(::BasicObject)).instance_exec do
  define_method :cap, &cap
  
  object_utilities.each do |name, body|
    define_method(name) do |*args, &blk|
      args.push(blk) if blk
      body[self, *args]
    end
  end
end

Object.instance_exec do
  define_method :cap, &cap
  
  object_utilities.each do |name, body|
    define_method(name) do |*args, &blk|
      args.push(blk) if blk
      body[self, *args]
    end
  end
end

class NilClass
  def cap *modules
    Capoeira::BasicObject.new.cap *modules
  end
end

Hash.instance_exec do
  define_method :cap do |*modules|
    super *modules
    
    keys.each do |key|
      if Symbol === key
        assign[self, key, self[key]]
      end
    end
    
    old_method_missing = method(:method_missing)
    
    define_singleton_method :method_missing do |name, *args, &blk|
      abbrev = name.to_s.sub(/\=$/,'').to_sym
      self[abbrev] = args[0] if name != abbrev
      args.push(blk) if blk
      old_method_missing[name, *args]
    end
    
    self
  end
end

__END__
person = { full_name: lambda { |p, mi| "#{p.first_name}#{mi ? " #{p.middle_name[0]} " : " "}#{p.last_name}" } }.cap
joe = { first_name: "Joseph", middle_name: "Bradley", last_name: "Swetnam" }.cap person

raise unless joe.full_name(true) == "Joseph B Swetnam"
raise unless joe.full_name(false) == "Joseph Swetnam"
raise unless Proc === joe.full_name
raise unless joe.full_name[false] == "Joseph Swetnam"
raise unless joe.full_name[true] == "Joseph B Swetnam"
raise unless joe._full_name[true] == "Joseph B Swetnam"
raise unless joe._full_name[false] == "Joseph Swetnam"

person = { full_name: lambda { |p, mi = false| "#{p.first_name}#{mi ? " #{p.middle_name[0]} " : " "}#{p.last_name}" } }.cap
joe = { first_name: "Joseph", middle_name: "Bradley", last_name: "Swetnam" }.cap person

raise unless joe.full_name(true) == "Joseph B Swetnam"
raise unless joe.full_name == "Joseph Swetnam"
raise unless joe._full_name.call == "Joseph Swetnam"
raise unless joe._full_name[true] == "Joseph B Swetnam"
raise unless joe._full_name[false] == "Joseph Swetnam"

person = { full_name: proc { |p, mi| "#{p.first_name}#{mi ? " #{p.middle_name[0]} " : " "}#{p.last_name}" } }.cap
joe = { first_name: "Joseph", middle_name: "Bradley", last_name: "Swetnam" }.cap person

raise unless joe.full_name(true) == "Joseph B Swetnam"
raise unless joe.full_name(false) == "Joseph Swetnam"
raise unless Proc === joe.full_name
raise unless joe.full_name[false] == "Joseph Swetnam"
raise unless joe.full_name[true] == "Joseph B Swetnam"
raise unless joe._full_name[true] == "Joseph B Swetnam"
raise unless joe._full_name[false] == "Joseph Swetnam"

person = { full_name: proc { |p, mi = false| "#{p.first_name}#{mi ? " #{p.middle_name[0]} " : " "}#{p.last_name}" } }.cap
joe = { first_name: "Joseph", middle_name: "Bradley", last_name: "Swetnam" }.cap person

raise unless joe.full_name(true) == "Joseph B Swetnam"
raise unless joe.full_name == "Joseph Swetnam"
raise unless joe._full_name.call == "Joseph Swetnam"
raise unless joe._full_name[true] == "Joseph B Swetnam"
raise unless joe._full_name[false] == "Joseph Swetnam"

person = { full_name: proc { |p| "#{p.first_name} #{p.last_name}" } }.cap
joe = { first_name: "Joseph", middle_name: "Bradley", last_name: "Swetnam" }.cap person

raise unless joe.full_name == "Joseph Swetnam"
raise unless joe._full_name.call == "Joseph Swetnam"

joe.birthday = Time.new(1983,4,2)
person.age = proc { |p| ((Time.new - p.birthday) / 60 / 60 / 24 / 365).floor }

raise unless joe.age == 32
raise unless joe.age(true) == joe.age
raise unless Proc === joe._age

get_time = { go: proc { Time.new } }.cap

raise unless Time === get_time.go
raise unless Time === get_time.go(true)
raise unless Proc === get_time._go

animal = { describe: proc { |a| "I am a #{a.species} and I#{a.vertebrate? ? " " : " do not "}have a backbone." } }.cap
vertebrate = { vertebrate?: true }.cap(animal)
person = { species: "homo sapiens" }.cap(animal, vertebrate)

raise unless person.species == "homo sapiens"
raise unless person.vertebrate? == true
raise unless person.describe == "I am a homo sapiens and I have a backbone."
