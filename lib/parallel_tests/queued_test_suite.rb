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
    def run(result, &progress_block)

      @tests = @tests[-ENV['MAX_TEST_SUITES'].to_i..-1] if ENV['MAX_TEST_SUITES'].to_i <= @tests.size #for debugging

      yield(STARTED, name)

      @process_number = ENV['TEST_ENV_NUMBER']
      unflattened_test_suites = ENV['NONATOMIC_TEST_SUITES'].to_a.empty? ? [] : ENV['NONATOMIC_TEST_SUITES'].split(',') 

      @flattened_test_cases, @unflattened_test_suites = flatten_tests(@tests, unflattened_test_suites)

      puts "FLATTENED TEST CASES: #{@flattened_test_cases.size}"
      puts "UNFLATTENED TEST SUITES: #{@unflattened_test_suites.size}"

      DRb.start_service
      @master = DRbObject.new(nil, MasterRunner::URL)

      puts "# of TESTS:#{@tests.size}, FLATTENED:#{@flattened_test_cases.size}, PROCESSOR ##{@process_number}"  

      # wait until either some other test process registers tests or if noone yet started registering (has_more? == false)
      do_with_log('WAITED before entering queue') { while @master.has_more_test_suites? && @master.has_more_test_cases? && !@master.tests_registered?; sleep 1; end }

      enqueue_for_later
      run_now(:test_suite_queue, result, &progress_block)
      run_now(:test_case_queue, result, &progress_block)

      yield(FINISHED, name)
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

    def run_now(queue_type, result, &progress_block)
      all_test_names = [] 
      per_batch =  queue_type == :test_case_queue ? ENV['TESTS_BATCH_SIZE'].to_i : 1
      while @master.has_more?(queue_type)
        test_names_to_run = do_with_log("next batch of #{per_batch} #{queue_type}", {:modifier => :inspect}) { @master.next_batch(queue_type, per_batch) }
      
        tests_to_run = (queue_type == :test_case_queue ? @flattened_test_cases : @unflattened_test_suites).slice(*test_names_to_run).values     

        all_test_names.concat tests_to_run.map(&:name)

        tests_to_run.each do |test_case_or_suite|          
          if test_case_or_suite
            test_case_or_suite.run(result, &progress_block)
          else
            puts "[PROCESS ##{@process_number}] ERROR: UNABLE TO FIND #{test_case_or_suite.inspect} )"  
          end
        end
      end

      puts "[PROCESS ##{@process_number}] FINISHED RUNNING #{all_test_names.size} #{queue_type})"
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