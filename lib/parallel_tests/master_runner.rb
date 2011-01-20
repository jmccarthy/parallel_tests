require 'drb'
require 'drb/observer'

$LOAD_PATH << "test"

class MasterRunner

  URL = "druby://127.0.0.1:1345"

  def initialize
    @mutex = Mutex.new
    @queue = Array.new
    @tests_registered = false
    @registering_process_number = nil
  end  

  def run_tests_later(tests, process_number)
    return nil if tests_registered?
    if @registering_process_number.nil? #store the very first process
      @mutex.synchronize do
        @registering_process_number = process_number.to_i if @registering_process_number.nil? #conditional to prevent concurrent overwrite
      end  
    end
    if process_number.to_i == @registering_process_number.to_i #return if the caller is not a registering process
      tests.each do |test|
        @queue << test
      end  
      log_queue_size "run_tests_later(#{tests.size}, #{process_number})"
    else
      log_queue_size "[skipping] run_tests_later(#{tests.size}, #{process_number})"
    end
  end  

  def close_queue(process_number)
    log_queue_size "close_queue(#{process_number}), registered by #{@registering_process_number}"
    if process_number.to_i == @registering_process_number.to_i #return if the caller is not a registering process
      log_queue_size "close_queue(#{process_number})"
      @queue = @queue.uniq
      @tests_registered = true
    else
      log_queue_size "[skipping] close_queue(#{process_number})"
    end
  end  

  def tests_registered?
    @tests_registered
  end 

  def log_queue_size(caller, options={})
    log_index = (options[:log_index] || 25).to_i        
    show = options[:batch_size].to_i >= log_index ? true : @queue.size % log_index <= options[:batch_size].to_i  
    show_max_test_suites = ENV['MAX_TEST_SUITES'].to_i
    show_max_test_cases = ENV['MAX_TEST_CASES_PER_SUITE'].to_i > 0 ? ENV['MAX_TEST_CASES_PER_SUITE'].to_i : 1    
    show ||= show_max_test_suites * show_max_test_cases <= log_index if show_max_test_suites * show_max_test_cases > 0
    puts "[MASTER] QUEUE SIZE (#{caller}):#{@queue.size}, MAX TEST SUITES:#{show_max_test_suites}, MAX TEST CASES PER SUITE:#{show_max_test_cases}" if show
  end

  def next
    test_case = @queue.pop
    log_queue_size 'pop', :batch_size => 1
    test_case
  end  

  def next_batch(limit=1)
    batch = []
    limit = 1 if limit == 0
    limit.times do 
      batch << @queue.pop if has_more? 
    end
    log_queue_size "next_batch(#{limit})", :batch_size => limit  
    batch
  end
  
  def has_more?
    !@queue.empty?
  end      
end  