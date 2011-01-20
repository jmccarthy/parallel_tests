require 'test/unit'
require 'test/unit/ui/console/testrunner'
require 'drb'
require File.dirname(__FILE__) + '/master_runner'


module QueuedTestSuite
  class Test::Unit::TestSuite
    def run(result, &progress_block)

      
      #TEST
      # @tests = @tests[-2..-1] #for debugging

      yield(STARTED, name)

      @process_number = ENV['TEST_ENV_NUMBER']

      @flattened_tests = flatten_tests

      DRb.start_service
      @master = DRbObject.new(nil, MasterRunner::URL)

      puts "# of TESTS:#{@tests.size}, FLATTENED:#{@flattened_tests.size}, PROCESSOR ##{@process_number}"  
      # debugger

      # wait until either some other test process registers tests or if noone yet started registering (has_more? == false)
      t_start = Time.now
      while @master.has_more? && !@master.tests_registered?; sleep 1; end
      t_end = Time.now
      
      puts "[PROCESS ##{@process_number}] WAITED before entering queue for #{t_end - t_start} seconds"         

      @flattened_tests.keys.each do |test_case_name|
        run_later(test_case_name)
      end        

      @master.close_queue(@process_number)

      t_start = Time.now
      while !@master.tests_registered?; sleep 1; end
      t_end = Time.now
      puts "[PROCESS ##{@process_number}] WAITED after closing queue for #{t_end - t_start} seconds"         

      test_names = [] 
      while @master.has_more?
        t_start = Time.now
        test_to_run = @master.next
        t_end = Time.now
        puts "[PROCESS ##{@process_number}] NEXT TEST: #{test_to_run}, time took: #{t_end - t_start} seconds"         
        test_names << test_to_run
        run_now(test_to_run, result, &progress_block)        
      end

      puts "[PROCESS ##{@process_number}] FINISHED RUNNING #{test_names.size} tests"     

      yield(FINISHED, name)
    end

    def run_now(test_case_name, result, &progress_block)
      test_case = @flattened_tests[test_case_name]

      if test_case
        t_start = Time.now      
        test_case.run(result, &progress_block)
        t_end = Time.now 
        puts "[PROCESS ##{@process_number}] run now #{test_case_name}, time took: #{t_end - t_start} seconds"
      else
        msg = "[PROCESS ##{@process_number}] UNABLE to find #{test_case_name}, skipping ..."
        puts msg       
        raise RuntimeError, msg
      end  

    end          

    def run_later(test_case_name)
      t_start = Time.now      
      @master.run_later(test_case_name, @process_number)
      t_end = Time.now
      puts "[PROCESS ##{@process_number}] run later #{test_case_name}, time took: #{t_end - t_start} seconds" 
    end     

    def flatten_tests
      @tests.inject({}) do |flattened_test_cases, test|
        if test.respond_to? :tests
          test.tests.each do |t|
            flattened_test_cases[t.name] = t
          end  
        else
          flattened_test_cases[test.name] = test
        end
        flattened_test_cases
      end    
    end  
  end  
end