require 'drb'
require 'drb/observer'

$LOAD_PATH << "test"

class MasterRunner

  URL = "druby://127.0.0.1:5678"

  def initialize
    @mutex = Mutex.new
    @test_case_queue = Array.new
    @test_suite_queue = Array.new
    @tests_registered = false
    @registering_process_number = nil
  end  
  
  def run_test_suites_later(tests, process_number)
    run_tests_later(tests, process_number, :test_suite_queue)
  end  
  
  def run_test_cases_later(tests, process_number)
    run_tests_later(tests, process_number, :test_case_queue)
  end
  
  def run_tests_later(tests, process_number, queue_type)
    return nil if tests_registered?
    if @registering_process_number.nil? #store the very first process
      @mutex.synchronize do
        @registering_process_number = process_number.to_i if @registering_process_number.nil? #conditional to prevent concurrent overwrite
      end  
    end
    if process_number.to_i == @registering_process_number.to_i #return if the caller is not a registering process
      tests.each do |test|
        queue_type == :test_case_queue ? @test_case_queue << test : @test_suite_queue << test  
      end  
      log_queue_size "run_tests_later(#{tests.size}, #{process_number}, #{queue_type})", queue_type
    else
      log_queue_size "[skipping] run_tests_later(#{tests.size}, #{process_number}, #{queue_type})", queue_type
    end
  end

  def close_queues(process_number)    
    if process_number.to_i == @registering_process_number.to_i #return if the caller is not a registering process
      [:test_suite_queue, :test_case_queue].each {|q_type| log_queue_size "close_queue(#{process_number}), registered by #{@registering_process_number}", q_type }
      @test_case_queue = @test_case_queue.uniq
      @test_suite_queue = @test_suite_queue.uniq
      @tests_registered = true
    else
      [:test_suite_queue, :test_case_queue].each {|q_type| log_queue_size "close_queue(#{process_number})", q_type }
    end
  end  

  def tests_registered?
    @tests_registered
  end 

  def log_queue_size(caller, queue_type, options={})
    queue = (queue_type == :test_case_queue) ? @test_case_queue : @test_suite_queue
    
    log_index = (options[:log_index] || 25).to_i        
    show = options[:batch_size].to_i >= log_index ? true : queue.size % log_index <= options[:batch_size].to_i  
    show_max_test_suites = ENV['MAX_TEST_SUITES'].to_i
    show_max_test_cases = ENV['MAX_TEST_CASES_PER_SUITE'].to_i > 0 ? ENV['MAX_TEST_CASES_PER_SUITE'].to_i : 1    
    show ||= show_max_test_suites * show_max_test_cases <= log_index if show_max_test_suites * show_max_test_cases > 0
    puts "[MASTER] #{queue_type} QUEUE SIZE (#{caller}):#{queue.size}" if show
  end

  def next_test_cases(limit)
    next_batch(:test_case_queue, limit)
  end
  
  def next_test_suites(limit)
    next_batch(:test_suite_queue, limit)
  end  

  def next_batch(queue_type, limit=1)
    batch = []
    limit = 1 if limit == 0
    limit.times do 
      if queue_type == :test_case_queue
        batch << @test_case_queue.pop if has_more_test_cases? 
      else 
        batch << @test_suite_queue.pop if has_more_test_suites? 
      end        
    end
    log_queue_size "next_batch(#{queue_type}, #{limit})", queue_type, :batch_size => limit  
    batch
  end
  
  def has_more_test_cases?
    has_more?(:test_case_queue)
  end
  
  def has_more_test_suites?
    has_more?(:test_suite_queue)
  end      
  
  def has_more?(queue_type)
    log_queue_size "has_more?(#{queue_type})=#{queue_type == :test_case_queue ? !@test_case_queue.empty? : !@test_suite_queue.empty?}", queue_type
    queue_type == :test_case_queue ? !@test_case_queue.empty? : !@test_suite_queue.empty?
  end
end  