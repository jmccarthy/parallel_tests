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
    puts "[MASTER] QUEUE SIZE (#{caller}):#{@queue.size}" if @queue.size % 25 == 0
  end

  def next
    test_case = @queue.pop
    log_queue_size 'pop'
    test_case
  end  

  def next_batch(limit=0)
    batch = []
    if limit > 0
      limit.times { batch << @queue.pop if has_more?}
    else
      batch << @queue.pop
    end  
    batch
  end

  def has_more?
    !@queue.empty?
  end      
end  