require 'test/unit'
require 'test/unit/ui/console/testrunner'
require 'drb'
require File.dirname(__FILE__) + '/master_runner'


module QueuedTestSuite
  class Test::Unit::TestSuite
    def run(result, &progress_block)
       
      yield(STARTED, name)

      @process_number = ENV['TEST_ENV_NUMBER']

      DRb.start_service
      @master = DRbObject.new(nil, MasterRunner::URL)

      # @tests = @tests[-2..-1] #for debugging
      
      puts "# of TESTS:#{@tests.size}, FLATTENED:#{flatten_tests.size}, PROCESSOR ##{@process_number}"  
      # debugger

      # wait until either some other test process registers tests or if noone yet started registering (has_more? == false)
      while @master.has_more? && !@master.tests_registered?; sleep 1; end
      
      flatten_tests.each do |test_case|
        run_later(test_case.name)
      end        
      
      @master.close_queue(@process_number)

      while !@master.tests_registered?; sleep 1; end
      
      test_names = [] 
      while @master.has_more?
        test_to_run = @master.next
        test_names << test_to_run
        run_now(test_to_run, result, &progress_block)        
      end
      
      puts "[PROCESS ##{@process_number}] FINISHED RUNNING #{test_names.size} tests. NAMES: #{test_names.inspect}"     

      yield(FINISHED, name)
    end
    
    def run_now(test_case_name, result, &progress_block)
      test_case = flatten_tests.detect { |test| test.name == test_case_name }
      if test_case
        puts "[PROCESS ##{@process_number}] running now #{test_case_name}"       
        test_case.run(result, &progress_block)
      else
        msg = "[PROCESS ##{@process_number}] UNABLE to find #{test_case_name}, skipping ..."
        puts msg       
        raise RuntimeError, msg
      end    
    end          
       
    def run_later(test_case_name)
       puts "[PROCESS ##{@process_number}] running later #{test_case_name}"       
       @master.run_later(test_case_name, @process_number)
    end     
       
    def flatten_tests
      flattened_test_cases = @tests.inject([]) do |test_cases, test|
        test_cases.concat test.tests if test.respond_to? :tests
      end    
      flattened_test_cases
    end  
  end  
end