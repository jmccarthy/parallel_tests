class ParallelTests
  class Grouper    

    def self.in_groups(items, num_groups)
      [].tap do |groups|
        while ! items.empty?
          (0...num_groups).map do |group_number|
            groups[group_number] ||= []            
            groups[group_number] << items.shift  
          end
        end
      end
    end

    def self.in_even_groups_by_size(items_with_sizes, num_groups)
      items_with_size = smallest_first(items_with_sizes)
      groups = Array.new(num_groups){{:items => [], :size => 0}}
      items_with_size.each do |item, size|
        # always add to smallest group
        smallest = groups.sort_by{|g| g[:size] }.first
        smallest[:items] << item
        smallest[:size] += size
      end

      groups.map{|g| g[:items] }
    end



    def self.smallest_first(files)
      files.sort_by{|item, size| size }.reverse
    end

    def self.in_groups_for_queue(items, num_groups, non_parallel_list = [])
      # return in_groups(items,num_groups)
      [].tap do |groups|
        while !items.empty?
          item = items.shift
          (0...num_groups).map do |group_number|
            groups[group_number] ||= {:files => [], :index => group_number}
            #put all non-paralellizable tests into process #1 (the ones that will only be required and run by one process only)
            if !non_parallel_list.empty? && non_parallel_list.detect { |non_parallel| item.gsub('_','') =~ /#{non_parallel}/i } 
              groups[group_number][:files] << item if group_number == 0
            else
              groups[group_number][:files] << item  
            end
          end
        end
      end      
    end
  end
end