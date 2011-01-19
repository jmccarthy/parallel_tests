require 'test/unit'
require 'test/unit/ui/console/testrunner'
require 'drb'

module QueuedTestSuite
  class Test::Unit::TestSuite
    def run(result, &progress_block)

      yield(STARTED, name)

      DRb.start_service
      master = DRbObject.new(nil, "druby://127.0.0.1:1338")
      
      puts "# of TESTS:#{@tests.size}, FLATTENED:#{flatten.size} PROCESSOR ##{ENV['TEST_ENV_NUMBER']}"  
      # debugger
      
      # puts "RUN TESTS LATER:#{@tests.inspect}"
      master.run_tests_later(flatten, ENV['TEST_ENV_NUMBER'].to_i)             
                  
      while master.has_more? 
        test_case = master.next
        test_case.run(result,&progress_block)            
        puts "run #{test_case.name}"   
      end

      yield(FINISHED, name)
    end
    
    def flatten
      flattened_test_cases = @tests.inject([]) do |test_cases, test|
        test_cases.concat test.tests if test.respond_to? :tests
      end    
      # puts "BEFORE flatten:#{@tests.map {|t| t.name}}"
      # puts "AFTER flatten:#{flattened_test_cases.map {|t| t.name}}"
      flattened_test_cases
    end  
  end  
end