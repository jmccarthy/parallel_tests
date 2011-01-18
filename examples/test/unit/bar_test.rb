require 'test_helper'

class BarTest < Test::Unit::TestCase
  def test_bar1
    duration = 2
    puts "running test case #{name},  for #{duration} seconds"
    sleep duration
    assert true
  end  
  
  def test_bar2
    puts "in test_bar2"
    duration = 5
    puts "running test case #{name},  for #{duration} seconds"
    sleep duration
    assert true
  end

end