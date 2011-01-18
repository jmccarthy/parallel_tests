require 'drb'
require 'drb/observer'

$LOAD_PATH << "test"

class MasterRunner

  def initialize
    @queue = Array.new
    @tests_registered = false
    @tests_loaded = false
  end  

  def run_later(test_case, process_number)
    if first_process? process_number
      puts "added #{test_case.name} to the queue, QUEUE SIZE:#{@queue.size}"
      @queue << test_case
    else
      puts "skipping #{test_case.name} for processor ##{[process_number]}, QUEUE SIZE:#{@queue.size}"
    end
  end
  
  def run_tests_later(tests, process_number)
    # TODO: synchronize this and release only when loaded
    if first_process?(process_number) && !@tests_registered
      tests.each do |test_case|
        run_later(test_case, process_number)       
        puts "enqueued #{test_case.name}"      
      end        
      close_queue(process_number)
    else
      # TODO: needs synchronization on tests_registered
      
      # puts "wait until all tests are registered, processor ##{process_number}, QUEUE SIZE:#{@queue.size}"
      #       #return only if registered already, TODO: needs synchronization
      #       while !tests_registered?; sleep 1; end
      #       puts "wait over for processor ##{process_number}, QUEUE SIZE:#{@queue.size}"
    end    
  end  
  
  # TODO: call from parallels_tests so that we require all tests and able to add them right here from master rather than from the 1st process
  def preload_tests(test_files)
    return if @tests_loaded 
    puts "REQUIRING FILES:#{test_files.inspect}"
    test_files.each {|f| require f } 
    @tests_loaded = true
  end  

  def close_queue(process_number)
    raise RuntimeError, "Unable to close queue for processor ##{process_number}: only 1st process can do this!" unless first_process?(process_number)
    @queue = @queue.uniq
    @tests_registered = true
  end  

  def tests_registered?
    @tests_registered
  end  

  def next
    test_case = @queue.pop
    puts "popping #{test_case.name} to the queue, QUEUE SIZE:#{@queue.size}"
    test_case
  end  

  def has_more?
    !@queue.empty?
  end    

  private 

  def first_process?(process_number)
    [0, 1].include? process_number # if either no parallelization used or only the first process
  end   
end  