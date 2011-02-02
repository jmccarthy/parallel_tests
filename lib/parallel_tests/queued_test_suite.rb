require 'test/unit'
require 'test/unit/ui/console/testrunner'
require 'drb'
require File.dirname(__FILE__) + '/master_runner'

module CI #:nodoc:
  module Reporter #:nodoc:
    class ReportManager            
      def write_report(suite)
        File.open("#{@basename}-#{suite.name.gsub(/[^a-zA-Z0-9]+/, '-')}-#{ENV['TEST_ENV_NUMBER']}.xml", "w") do |f|
          puts "PROCESS #{ENV['TEST_ENV_NUMBER']} writing REPORT for #{suite.name}, #{suite.testcases.map(&:name).inspect}"
          f << suite.to_xml rescue puts "ERROR WRITING REPORT #{@basename}-#{suite.name.gsub(/[^a-zA-Z0-9]+/, '-')}-#{ENV['TEST_ENV_NUMBER']}.xml"
        end
      end
    end
  end
end

module QueuedTestSuite
  class Test::Unit::TestSuite   
    alias_method :atomic_run, :run 
    def run(result, &progress_block)
      @process_number = ENV['TEST_ENV_NUMBER']
      puts "[PROCESS ##{@process_number}] RUNNING QUEUED TEST SUITE:#{@tests.size} tests loaded : #{@tests.map(&:name)}"  
      yield(STARTED, name)
      run_non_parallel_tests(result, &progress_block)
      run_parallel_tests(result, &progress_block)
      yield(FINISHED, name)
    end

    private

    def run_non_parallel_tests(result, &progress_block)
      if @process_number.to_i == 0 && !ENV['NON_PARALLEL_TESTS'].to_a.empty?
        puts "[PROCESS ##{@process_number}] REQUEST TO DO NON-PARALLEL TESTS #{ENV['NON_PARALLEL_TESTS'].split(',')}"  
        non_queueable_test_names = ENV['NON_PARALLEL_TESTS'].split(',')
        queueable_tests, non_queueable_tests = queueable_tests(@tests, non_queueable_test_names)
        # puts "[PROCESS ##{@process_number}] FIRST DO NON-PARALLEL TESTS #{non_queueable_tests.size}"            
        run_test_suites(non_queueable_tests.values, result, &progress_block)                  
        puts "[PROCESS ##{@process_number}] FINISHED RUNNING #{non_queueable_tests.size} non-parallel tests"
        @tests = queueable_tests.values
        # puts "[PROCESS ##{@process_number}] NOW PROCEED WITH PARALLEL TESTS #{@tests.size}"                    
      end
    end

    def run_parallel_tests(result, &progress_block)
      @tests = @tests[-ENV['MAX_TEST_SUITES'].to_i..-1] if ENV['MAX_TEST_SUITES'].to_i <= @tests.size #for debugging
      unflattened_test_suites = ENV['NON_ATOMIC_TEST_SUITES'].to_a.empty? ? [] : ENV['NON_ATOMIC_TEST_SUITES'].split(',') 
      @flattened_test_cases, @unflattened_test_suites = flatten_tests(@tests, unflattened_test_suites)

      puts "FLATTENED TEST CASES: #{@flattened_test_cases.size}"
      puts "UNFLATTENED TEST SUITES: #{@unflattened_test_suites.size}"

      DRb.start_service
      @master = DRbObject.new(nil, MasterRunner::URL)

      puts "# of TESTS:#{@tests.size}, FLATTENED:#{@flattened_test_cases.size}, PROCESSOR ##{@process_number}"  

      # wait until either some other test process registers tests or if noone yet started registering (has_more? == false)
      do_with_log('WAITED before entering queue') { while @master.has_more_test_suites? && @master.has_more_test_cases? && !@master.tests_registered?; sleep 1; end }
      enqueue_for_later
      pull_and_run(:test_suite_queue, result, &progress_block)
      pull_and_run(:test_case_queue, result, &progress_block)
    end

    def enqueue_for_later
      if !@master.tests_registered?
        [:test_suite_queue, :test_case_queue].each do |queue_type|
          tests_to_enqueue = (queue_type == :test_case_queue) ? @flattened_test_cases.keys : @unflattened_test_suites.keys
          do_with_log("push_for_later(#{queue_type}) #{tests_to_enqueue.size} tests") { @master.run_tests_later(tests_to_enqueue, @process_number, queue_type) }
        end
        do_with_log("closing queue") { @master.close_queues(@process_number) }
        do_with_log('WAITED after entering queue') { while !@master.tests_registered?; sleep 1; end }
      end
    end  

    def pull_and_run(queue_type, result, &progress_block)
      all_tests_counter = 0 
      per_batch =  queue_type == :test_case_queue ? ENV['TESTS_BATCH_SIZE'].to_i : 1
      # puts "RUNNING NOW #{@master.has_more?(:test_case_queue)}"
      while @master.has_more?(queue_type)
        test_names_to_run = do_with_log("next batch of #{per_batch} #{queue_type}", {:modifier => :inspect}) { @master.next_batch(queue_type, per_batch) }
        tests_to_run = (queue_type == :test_case_queue ? @flattened_test_cases : @unflattened_test_suites).slice(*test_names_to_run).values     
        all_tests_counter += run_queued_test_cases_or_suites(tests_to_run, queue_type, result, &progress_block)
      end
      puts "[PROCESS ##{@process_number}] FINISHED RUNNING #{all_tests_counter.size} queued tests (#{queue_type})"
    end  

    def run_queued_test_cases_or_suites(test_cases_or_suites, queue_type, result, &progress_block)
      run_method_name = (queue_type == :test_case_queue) ? :run_test_cases : :run_test_suites
      self.send(run_method_name.to_sym, test_cases_or_suites, result, &progress_block)
      test_cases_or_suites.count
    end

    def run_test_cases(test_cases, result, &progress_block)
      test_cases.each do |test_case|          
        if test_case
          # puts "Running test case #{test_case.name}: #{test_case.respond_to?(:tests) ? test_case.tests.size : 0}"
          test_case.run(result, &progress_block)
        else
          puts "[PROCESS ##{@process_number}] ERROR: UNABLE TO FIND TEST CASE #{test_case.inspect} )"  
        end
      end
    end  

    def run_test_suites(test_suites, result, &progress_block)
      test_suites.each do |test_suite|          
        if test_suite
          puts "TEST SUITE #{test_suite.name} has tests: #{test_suite.respond_to?(:tests) ? test_suite.tests.size : 0}"
          test_suite.atomic_run(result, &progress_block)
        else
          puts "[PROCESS ##{@process_number}] ERROR: UNABLE TO FIND TEST SUITE #{test_suite.inspect} )"  
        end
      end
    end

    def queueable_tests(test_suites, exclude_list)
      test_suites.inject([ActiveSupport::OrderedHash.new, ActiveSupport::OrderedHash.new]) do |queueable_test_suites, test|        
        if !exclude_list.include?(test.name)
          queueable_test_suites[0][test.name] = test 
        else
          queueable_test_suites[1][test.name] = test
        end
        queueable_test_suites #returns [flattened cases, unflattened suites]      
      end
    end  

    def flatten_tests(test_suites, exclude_list)
      test_suites.inject([ActiveSupport::OrderedHash.new, ActiveSupport::OrderedHash.new]) do |flattened_test_cases_or_unflattened_suites, test|
        if test.respond_to?(:tests)
          adj_tests = ENV['MAX_TEST_CASES_PER_SUITE'].to_i <= test.tests.size ? test.tests[-ENV['MAX_TEST_CASES_PER_SUITE'].to_i..-1] : test.tests 
          if !exclude_list.include?(test.name)
            adj_tests.each do |t|            
              flattened_test_cases_or_unflattened_suites[0][t.name] = t
            end  
          else
            flattened_test_cases_or_unflattened_suites[1][test.name] = test
          end
        end
        flattened_test_cases_or_unflattened_suites #returns [flattened cases, unflattened suites]
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