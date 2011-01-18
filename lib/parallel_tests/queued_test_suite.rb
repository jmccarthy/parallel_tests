require 'test/unit'
require 'test/unit/ui/console/testrunner'
require 'drb'

module QueuedTestSuite
  class Test::Unit::TestSuite
    def run(result, &progress_block)

      yield(STARTED, name)

      master = DRbObject.new(nil, "druby://127.0.0.1:1337")
      
      puts "TESTS:#{@tests.size}"  
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