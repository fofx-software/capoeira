require_relative "utilities"

def function *types, &body
  Function.new types, &body
end

module Capoeira
  def self.basic_string str, *modules
    nil.cap({
      to_s: str,
      inspect: str,
      s: str
    }, *modules)
  end
  
  get_file = function do |file|
    basic_string(file, Capoeira::File).apply { |f| f if f.exist? }
  end
  
  get_dir = function { |dir|
    entries_proc = proc do |_, file|
      case file
      when String
        get_file["#{dir}/#{file}"]
      when Symbol
        get_dir["#{dir}/#{file}"]
      end
    end
    
    basic_string(dir, Capoeira::Dir, entries_proc).apply { |d| d if d.exist? }
  }
  
  File = {
    basename:     ::File.method(:basename) + :s,
    read:         ::File.method(:read) + :s,
    marshal_load: ::Marshal.method(:load) + ::File.method(:read) + :s,
    delete:       ::File.method(:delete) + :s,
    write:        function { |f, data = ''| ::File.write(f.to_s, data); f },
    marshal_dump: function { |f, data = ''| ::File.write(f.to_s, Marshal.dump(data)); f },
    relative_path: function { |f, dir|
      [f.s.split("/"), dir.s.split("/")].apply do |f, dir|
        (dir - f).map { ".." }.concat(f - dir).join("/")
      end
    },
    parent: function { |f|
      get_dir[f.s.split("/")[0..-2].join("/")]
    },
    exist?: ::File.method(:exist?) + :s
  }.cap
  
  Dir = {
    basename: function { |dir| dir.s.split("/").last },
    parent: function { |dir| get_dir[dir.s.split("/")[0..-2].join("/")] },
    mkdir: function { |dir, subdir|
      ::Dir.mkdir("#{dir.to_s}/#{subdir}")
      get_dir["#{dir.to_s}/#{subdir}"]
    },
    rmdir: function { |dir, subdir = nil, recursive = false|
      # subdir.files.each(&File.delete) if recursive
      ::Dir.delete("#{dir}/#{subdir}")
    },
    dirs:        function { |dir| ::Dir.dirs(dir.to_s).map(&get_dir) },
    files:       function { |dir| ::Dir.files(dir.to_s).map(&get_file) },
    sfiles:      function { |dir| ::Dir.files(dir.to_s) },
    file:        function { |dir, file| get_file["#{dir}/#{file}"] },
    dir:         function { |dir, subdir| get_dir["#{dir}/#{subdir}"] },
    relative_to: function { |dir, other|
      [dir.s.split("/"), other.s.split("/")].apply do |dir, other|
        (other - dir).map { ".." }.concat(dir - other).join("/")
      end
    },
    exist?: Dir.method(:exist?) + :s
  }.cap
  
  [:write, :marshal_dump, :delete].each do |method_name|
    Dir[method_name] = function { |dir, fn, *args|
      File[method_name]["#{dir}/#{fn}", *args]
    }
  end
  
  Project = {
    dir: function { |p, *subdirs|
      begin
        get_dir[[p.root_dir, *subdirs].join("/")]
      rescue # subdir does not exist
      end
    },
    scp: function { |p, filename, remote_dest = nil|
      p.dir.file(filename).apply do |file|
        remote_dest.yes?(remote_dest, filename).apply do |remote_dest|
          `scp -i #{p.identity_file} #{file} #{p.remote_dir}/#{remote_dest}`
        end
      end
    },
    scpr: function { |p, dir|
      dir.split("/")[0..-2].join("/").apply do |parent_dir|
        `scp -r -i #{p.identity_file} #{p.dir(dir)} #{p.remote_dir}/#{parent_dir}`
      end
    },
    scp_all: function { |p|
      files, dirs = [], []
      (scp_files = proc { |dir, ignore|
        dir.files.each do |file|
          if !ignore["files"] || !ignore["files"].include?(file.basename)
            files.push(file)
          end
        end
        dir.dirs.each do |subdir|
          subdir.basename.apply do |basename|
            if ignore[basename]
              if ignore[basename] != "all"
                scp_files[subdir, ignore[basename]]
              end
            else
              dirs.push(subdir)
            end
          end
        end
      }).call(p.dir, p.scp_ignore)
      files.each do |file|
        file.parent.relative_to(p.dir).apply do |parent|
          `scp -i #{p.identity_file} #{file} #{p.remote_dir}/#{parent}`
        end
      end
      dirs.each do |dir|
        dir.parent.relative_to(p.dir).apply do |parent|
          `scp -r -i #{p.identity_file} #{dir} #{p.remote_dir}/#{parent}`
        end
      end
    }
  }.cap
end
