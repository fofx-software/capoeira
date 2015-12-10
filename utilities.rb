require 'timezone'

class Function < Proc
  def initialize types, params = nil, &body
    @types = types
    @parameters = params || body.parameters
    @body = lambda &body
    super &body
  end
  
  def [] *args
    f = @body.curry[*args]
    Proc === f ? Function.new(&f) : f
  end
  
  def to_s
    inspect
  end
  
  def inspect
    name_with_type = proc do |name, stylized, default = nil|
      # type = @types[name].if_true do |type|
      #   type = [type] unless type.is_a?(Array)
      #   type.map(&:inspect).join("|")
      # end
      nil ? "#{stylized}#{type}" : (default || name)
    end
    
    param_list = @parameters.map do |dscr, name|
      name ||= dscr
      case dscr
        when :opt  then name_with_type[name, "#{name}=>"]
        when :rest then name_with_type[name, "*#{name}", "*#{name}"]
        when :key  then name_with_type[name, "#{name}:"]
      end
    end.join(",")
    
    "#{(@name || "\\").to_s}(#{param_list})"
  end
  
  def call *args
    check_args *args
    check_return super *args
  end
  
  def [] *args
    call *args
  end
  
  def negate
    function { |*args| !self[*args] }
  end
  
  def reflex
    @reflexive = true
    self
  end
  
  def reflexive?
    @reflexive
  end
  
  def curry
    Function.new @types, parameters, &super
  end
  
  private
  def check_args *args
    types = @types.first(@parameters.length)
    args.zip(types).each do |arg, type|
      if type && !(type === arg)
        raise ArgumentError.new "#{type.inspect} doesn't === #{arg.inspect} in #{self}"
      end
    end
  end
  
  def check_return return_val
    return_type,_ = @types.drop(@parameters.length)
    if return_type && !(return_type === return_val)
      raise TypeError.new "#{return_type.inspect} doesn't === #{return_val.inspect} in #{self}"
    end
    return_val
  end
end

module Boolean
  def self.=== other
    TrueClass === other || FalseClass === other
  end
end

class Object
  def is_not? other, &blk
    other === self ? self : blk.call(self)
  end
  
  def is? other, &blk
    other === self ? blk.call(self) : self
  end
  
  def if_found ary, &blk
    ary.include?(self) ? blk.call(self) : self
  end
end

class Array
  def gsub regexp, repl_str = nil
    repl_str, regexp = regexp, /^(.*)$/ unless repl_str
    self.map { |el| el.gsub regexp, repl_str }
  end

  def by_bool bool
    self[bool ? 1 : 0]
  end
  
  def to_proc
    reduce(proc { |o| o }) { |pr, cr| pr + cr }
  end
  
  def >> *args
    to_proc[*args]
  end
  
  def === other
    return false unless Array === other
    slice_length = length > 0 ? length : 1
    other.each_slice(slice_length).reduce(true) do |p, c|
      p && zip(c).reduce(true) { |p, (c, i)| p && c === i }
    end
  end
end

class String
  def match_one *candidates
    candidates.find do |candidate|
      self == candidate
    end
  end
end

class Proc
  def call_until
    call || call_until
  end
  
  def param_print
    param_list = parameters.map do |dscr, name|
      case dscr
        when :opt then name
        when :rest then "*#{name}"
        when :key then "#{name}:"
      end
    end.join(",")
    
    "proc(#{param_list})"
  end
  
  def + other
    function { |*args| self[other.to_proc[*args]] }
  end
end

class Method
  def + other
    to_proc + other
  end
end

class Symbol
  def + other
    self.to_proc + other
  end
end

class File
  def self.currdir file
    File.expand_path File.dirname file
  end
  
  class << self
    alias :curr_dir :currdir
  end
  
  def self.dump filename, data
    write(filename, Marshal.dump(data))
  end
  
  def self.load filename
    Marshal.load(File.read(filename))
  end
end
  
class Dir
  class << self
    path_to = proc { |d, f| "#{File.expand_path(d)}/#{f}" }
    
    define_method :files do |in_dir = ".", full_path = true|
      Dir.entries(in_dir).reject do |f|
        !File.file?(path_to[in_dir, f])
      end.map do |f|
        full_path ? path_to[in_dir, f] : f
      end.sort
    end
    
    define_method :dirs do |in_dir = ".", full_path = true|
      Dir.entries(in_dir).reject do |d|
        File.file?(path_to[in_dir, d]) || d.match(/^\.\.?$/)
      end.map do |d|
        full_path ? path_to[in_dir, d] : d
      end.sort
    end
  end
end

class Time
  def self.eastern
    {
      zone: Timezone::Zone.new(zone: "US/Eastern"),
      new: function { |time| Time.eastern.zone.time_with_offset(time) },
      now: function { Time.eastern.zone.time(Time.new) }
    }.cap
  end
end

class Numeric
  def grtr other
    self > other
  end
  
  def lssr other
    self < other
  end
end
