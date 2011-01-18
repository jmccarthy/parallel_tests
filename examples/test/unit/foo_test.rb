require 'test_helper'

class FooTest < Test::Unit::TestCase
  def test_foo1
    duration = 5
    puts "running test case #{name},  for #{duration} seconds"
    sleep duration
    assert true
  end  
  
  def test_foo2
    puts "in test_foo2"
    duration = 2
    puts "running test case #{name},  for #{duration} seconds"
    sleep duration
    assert true
  end

end
