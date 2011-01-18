require 'test/unit'
require 'test/unit/ui/console/testrunner'
require 'drb'

module QueuedTestSuite
  class Test::Unit::TestSuite
    def run(result, &progress_block)

      yield(STARTED, name)

      DRb.start_service
      master = DRbObject.new(nil, "druby://127.0.0.1:1338")
      
      puts "# of TESTS:#{@tests.size}, PROCESSOR ##{ENV['TEST_ENV_NUMBER']}"  
      # debugger
      
      master.run_tests_later(@tests, ENV['TEST_ENV_NUMBER'].to_i)             
                  
      while master.has_more? 
        test_case = master.next        
        test_case.run(result, &progress_block)            
        puts "run #{test_case.name}"   
      end

      yield(FINISHED, name)
    end
  end  
end