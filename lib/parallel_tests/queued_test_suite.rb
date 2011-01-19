require 'test/unit'
require 'test/unit/ui/console/testrunner'
require 'drb'
require File.dirname(__FILE__) + '/master_runner'


module QueuedTestSuite
  class Test::Unit::TestSuite
    def run(result, &progress_block)

      yield(STARTED, name)

      process_number = ENV['TEST_ENV_NUMBER']

      DRb.start_service
      @master = DRbObject.new(nil, MasterRunner::URL)

      # @tests = @tests[-5..-1] for debugging
      
      puts "# of TESTS:#{@tests.size}, FLATTENED:#{flatten.size}, PROCESSOR ##{process_number}"  
      # debugger

      # wait until either some other test process registers tests or if noone yet started registering (has_more? == false)
      while @master.has_more? && !@master.tests_registered?; sleep 1; end
      
      @tests.each do |test_case|
        @master.run_later(test_case, process_number)       
      end        
      
      @master.close_queue(process_number)

      while !@master.tests_registered?; sleep 1; end
      
      test_names = [] 
      while @master.has_more?
        tests_to_run = @master.next.tests
        test_names.concat tests_to_run.map(&:name)
        tests_to_run.each do |test_case|
          test_case.run(result, &progress_block)                 
        end  
      end
      
      puts "[PROCESS #{process_number}] FINISHED RUNNING #{test_names.size} tests. NAMES: #{test_names.inspect}"     

      yield(FINISHED, name)
    end        
       
    def flatten
      flattened_test_cases = @tests.inject([]) do |test_cases, test|
        test_cases.concat test.tests if test.respond_to? :tests
      end    
      flattened_test_cases
    end  
  end  
end