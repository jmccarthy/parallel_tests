require 'test/unit'
require 'test/unit/ui/console/testrunner'
require 'drb'
require File.dirname(__FILE__) + '/master_runner'

module CI #:nodoc:
  module Reporter #:nodoc:
    class ReportManager            
      def write_report(suite)
        File.open("#{@basename}-#{suite.name.gsub(/[^a-zA-Z0-9]+/, '-')}-#{ENV['TEST_ENV_NUMBER']}.xml", "w") do |f|
          f << suite.to_xml
        end
      end
    end
  end
end

module QueuedTestSuite
  class Test::Unit::TestSuite
    def run(result, &progress_block)


      #TEST
      @tests = @tests[-ENV['MAX_TEST_SUITES'].to_i..-1] if ENV['MAX_TEST_SUITES'].to_i <= @tests.size #for debugging

      yield(STARTED, name)

      @process_number = ENV['TEST_ENV_NUMBER']

      @flattened_tests = flatten_tests

      DRb.start_service
      @master = DRbObject.new(nil, MasterRunner::URL)

      puts "# of TESTS:#{@tests.size}, FLATTENED:#{@flattened_tests.size}, PROCESSOR ##{@process_number}"  
      # debugger

      # wait until either some other test process registers tests or if noone yet started registering (has_more? == false)
      do_with_log('WAITED before entering queue') { while @master.has_more? && !@master.tests_registered?; sleep 1; end }

      if !@master.tests_registered?
        do_with_log("run later #{@flattened_tests.keys.size} tests") { @master.run_tests_later(@flattened_tests.keys, @process_number) }
        do_with_log("closing queue") { @master.close_queue(@process_number) }

        do_with_log('WAITED after entering queue') { while !@master.tests_registered?; sleep 1; end }
      end

      all_test_names = [] 
      per_batch =  ENV['TESTS_BATCH_SIZE'].to_i
      while @master.has_more?
        tests_to_run = do_with_log("next batch of #{per_batch} ", {:modifier => :inspect}) { @master.next_batch(per_batch) }
        all_test_names.concat tests_to_run
        
        # do_with_log("run now #{tests_to_run.size} tests") do
          tests_to_run.each do |test_to_run|
            run_now(test_to_run, result, &progress_block)        
          end  
        # end
      end

      puts "[PROCESS ##{@process_number}] FINISHED RUNNING #{all_test_names.size} tests"     

      yield(FINISHED, name)
    end

    def run_now(test_case_name, result, &progress_block)
      test_case = @flattened_tests[test_case_name]

      if test_case
        test_case.run(result, &progress_block)
      else
        msg = "ERROR: [PROCESS ##{@process_number}] UNABLE to find #{test_case_name}, skipping ..."
        puts msg       
      end  
    end          

    def run_later(test_case_name)
      t_start = Time.now      
      @master.run_later(test_case_name, @process_number)
      t_end = Time.now
      # puts "[PROCESS ##{@process_number}] run later #{test_case_name}, time took: #{t_end - t_start} seconds" 
    end     

    def flatten_tests
      @tests.inject({}) do |flattened_test_cases, test|
        if test.respond_to? :tests
          adj_tests = ENV['MAX_TEST_CASES_PER_SUITE'].to_i <= test.tests.size ? test.tests[-ENV['MAX_TEST_CASES_PER_SUITE'].to_i..-1] : test.tests 
          adj_tests.each do |t|
            flattened_test_cases[t.name] = t
          end  
        else
          flattened_test_cases[test.name] = test
        end
        flattened_test_cases
      end    
    end  

    def do_with_log(message, options={}, &block)
      t_start = Time.now 
      result = yield
      t_end = Time.now  
      result_modifier = result.send(options[:modifier].to_sym) if options[:modifier]
      str = "[PROCESS ##{@process_number}], #{t_end - t_start} sec: #{message}"   
      str << ", value: #{result_modifier}" if result_modifier
      puts str
      result
    end  
  end  
end