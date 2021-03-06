require 'parallel'
require 'parallel_tests/grouper'
require 'parallel_tests/railtie'
require 'drb'

class ParallelTests

  VERSION = File.read( File.join(File.dirname(__FILE__),'..','VERSION') ).strip

  # parallel:spec[2,controller] <-> parallel:spec[controller]
  def self.parse_rake_args(args)
    num_processes = Parallel.processor_count
    options = ""
    if args[:count].to_s =~ /^\d*$/ # number or empty
      num_processes = args[:count] unless args[:count].to_s.empty?
      prefix = args[:path_prefix]
      options = args[:options] if args[:options]
    else # something stringy
      prefix = args[:count]
    end
    [num_processes.to_i, prefix.to_s, options]
  end

  # finds all tests and partitions them into groups
  def self.tests_in_groups(root, num_groups, options={})    
    exclude_tests = ENV['EXCLUDE_TESTS'].to_a.empty? ? [] : ENV['EXCLUDE_TESTS'].split(',')
    include_only_tests = ENV['INCLUDE_ONLY_TESTS'].to_a.empty? ? [] : ENV['INCLUDE_ONLY_TESTS'].split(',')
    puts "EXCLUDED TESTS:#{exclude_tests.inspect}"
    puts "INCLUDED ONLY TESTS:#{include_only_tests.inspect}"
    if options[:queue_tests]      
      non_parallel_tests = ENV['NON_PARALLEL_TESTS'].to_a.empty? ? [] : ENV['NON_PARALLEL_TESTS'].split(',')
      non_atomic_test_suites = ENV['NON_ATOMIC_TEST_SUITES'].to_a.empty? ? [] : ENV['NON_ATOMIC_TEST_SUITES'].split(',')
      puts "NON-ATOMIC TEST SUITES:#{non_atomic_test_suites.inspect}"
      puts "NON-PARALLEL TESTS:#{non_parallel_tests.inspect}"
      Grouper.in_groups_for_queue(find_tests(root, exclude_tests, include_only_tests), num_groups, non_parallel_tests)      
    elsif options[:no_sort] == true
      Grouper.in_groups(find_tests(root, exclude_tests, include_only_tests), num_groups)
    else        
      Grouper.in_even_groups_by_size(tests_with_runtime(root,exclude_tests, include_only_tests), num_groups)
    end
  end

  def self.run_tests(test_files, process_number, options)                          
    require_list = test_files.map { |filename| "\"#{filename}\"" }.join(",")
    cmd = "ruby -Itest #{options} -e '[#{require_list}].each {|f| require f }'"    
    execute_command(cmd, process_number)[:stdout]
  end

  def self.execute_command(cmd, process_number)
    cmd = "TEST_ENV_NUMBER=#{test_env_number(process_number)} ; export TEST_ENV_NUMBER; #{cmd}"
    puts "execute_command: #{cmd}"
    f = open("|#{cmd}", 'r')
    all = ''
    while char = f.getc
      char = (char.is_a?(Fixnum) ? char.chr : char) # 1.8 <-> 1.9
      all << char
      print char
      STDOUT.flush
    end
    f.close
    {:stdout => all, :exit_status => $?.exitstatus}
  end

  def self.find_results(test_output)
    test_output.split("\n").map do |line|
      line = line.gsub(/\.|F|\*/,'')
      next unless line_is_result?(line)
      line 
    end.compact
  end

  def self.failed?(results)
    return true if results.empty?
    !! results.detect{|line| line_is_failure?(line)}
  end

  def self.test_env_number(process_number)
    process_number == 0 ? '' : process_number + 1
  end

  protected

  # copied from http://github.com/carlhuda/bundler Bundler::SharedHelpers#find_gemfile
  def self.bundler_enabled?
    return true if Object.const_defined?(:Bundler) 

    previous = nil
    current = File.expand_path(Dir.pwd)

    until !File.directory?(current) || current == previous
      filename = File.join(current, "Gemfile")
      return true if File.exists?(filename)
      current, previous = File.expand_path("..", current), current
    end

    false
  end

  def self.line_is_result?(line)
    line =~ /\d+ failure/
  end

  def self.line_is_failure?(line)
    line =~ /(\d{2,}|[1-9]) (failure|error)/
  end

  def self.test_suffix
    "_test.rb"
  end

  def self.tests_with_runtime(root,exclude_list=[], include_only_list=[])
    tests = find_tests(root, exclude_list, include_only_list)
    runtime_file = File.join(root,'..','tmp','parallel_profile.log')
    lines = File.read(runtime_file).split("\n") rescue []

    # use recorded test runtime if we got enough data
    if lines.size * 1.5 > tests.size
      times = Hash.new(1)
      lines.each do |line|
        test, time = line.split(":")
        times[test] = time.to_f
      end
      tests.sort.map{|test| [test, times[test]] }
    else # use file sizes
      tests.sort.map{|test| [test, File.stat(test).size] }
    end
  end

  def self.find_tests(root,exclude_list=[], include_only_list=[])
    if root.is_a?(Array)
      root
    else
      files = Dir["#{root}**/**/*#{self.test_suffix}"]
      if !include_only_list.empty?                              
        files.delete_if do |f| 
          !include_only_list.detect { |included| f.gsub('_','') =~ /#{included}/i }
        end      
      else  
        exclude_list.each do |excluded|
          files.delete_if { |f| f.gsub('_','') =~ /#{excluded}/i}      
        end
      end        
      files
    end
  end
end