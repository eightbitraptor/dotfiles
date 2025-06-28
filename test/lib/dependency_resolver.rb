require 'set'

module MitamaeTest
  class DependencyResolver
    include Logging
    
    attr_reader :errors
    
    def initialize
      @errors = []
    end
    
    def resolve(test_specs)
      @errors.clear
      spec_map = build_spec_map(test_specs)
      
      # Build dependency graph
      graph = DependencyGraph.new
      
      test_specs.each do |spec|
        graph.add_node(spec.name, spec)
        
        # Add edges for 'requires' dependencies
        spec.dependencies.requires.each do |dep_name|
          if spec_map.key?(dep_name)
            graph.add_edge(dep_name, spec.name)
          else
            @errors << "Test '#{spec.name}' requires missing test '#{dep_name}'"
          end
        end
        
        # Add edges for 'before' dependencies (reverse direction)
        spec.dependencies.before.each do |dep_name|
          if spec_map.key?(dep_name)
            graph.add_edge(spec.name, dep_name)
          else
            @errors << "Test '#{spec.name}' references missing test '#{dep_name}' in 'before'"
          end
        end
      end
      
      # Check for cycles
      if graph.has_cycle?
        cycles = graph.find_cycles
        cycles.each do |cycle|
          @errors << "Circular dependency detected: #{cycle.join(' -> ')}"
        end
        return []
      end
      
      # Perform topological sort
      sorted_names = graph.topological_sort
      
      # Return specs in execution order
      sorted_names.map { |name| spec_map[name] }
    end
    
    def execution_groups(test_specs)
      resolved_specs = resolve(test_specs)
      return [] if @errors.any?
      
      spec_map = build_spec_map(resolved_specs)
      groups = []
      processed = Set.new
      
      resolved_specs.each do |spec|
        next if processed.include?(spec.name)
        
        # Find all specs that can run in parallel with this one
        parallel_group = find_parallel_group(spec, resolved_specs, spec_map, processed)
        
        groups << parallel_group
        processed.merge(parallel_group.map(&:name))
      end
      
      groups
    end
    
    private
    
    def build_spec_map(specs)
      specs.each_with_object({}) { |spec, map| map[spec.name] = spec }
    end
    
    def find_parallel_group(spec, all_specs, spec_map, processed)
      group = [spec]
      candidates = all_specs.reject { |s| processed.include?(s.name) || s.name == spec.name }
      
      candidates.each do |candidate|
        # Check if candidate can run in parallel with all specs in group
        can_parallel = group.all? do |group_spec|
          can_run_parallel?(group_spec, candidate, spec_map)
        end
        
        if can_parallel
          group << candidate
        end
      end
      
      group
    end
    
    def can_run_parallel?(spec1, spec2, spec_map)
      # Can't run in parallel if there's a dependency between them
      return false if depends_on?(spec1, spec2, spec_map)
      return false if depends_on?(spec2, spec1, spec_map)
      
      # Can't run in parallel if they're in different parallel groups
      if spec1.parallel_group && spec2.parallel_group
        return spec1.parallel_group == spec2.parallel_group
      end
      
      # Can run in parallel if no explicit parallel group is set
      spec1.parallel_group.nil? && spec2.parallel_group.nil?
    end
    
    def depends_on?(spec, dependency, spec_map)
      visited = Set.new
      queue = [spec.name]
      
      while !queue.empty?
        current = queue.shift
        return true if current == dependency.name
        
        next if visited.include?(current)
        visited.add(current)
        
        current_spec = spec_map[current]
        next unless current_spec
        
        queue.concat(current_spec.dependencies.requires)
      end
      
      false
    end
  end
  
  class DependencyGraph
    def initialize
      @nodes = {}
      @edges = Hash.new { |h, k| h[k] = Set.new }
      @reverse_edges = Hash.new { |h, k| h[k] = Set.new }
    end
    
    def add_node(name, data = nil)
      @nodes[name] = data
    end
    
    def add_edge(from, to)
      @edges[from].add(to)
      @reverse_edges[to].add(from)
    end
    
    def has_cycle?
      visited = Set.new
      rec_stack = Set.new
      
      @nodes.keys.each do |node|
        if !visited.include?(node) && has_cycle_util?(node, visited, rec_stack)
          return true
        end
      end
      
      false
    end
    
    def find_cycles
      cycles = []
      visited = Set.new
      
      @nodes.keys.each do |node|
        next if visited.include?(node)
        
        path = []
        find_cycles_util(node, visited, path, cycles)
      end
      
      cycles
    end
    
    def topological_sort
      in_degree = calculate_in_degrees
      queue = @nodes.keys.select { |node| in_degree[node] == 0 }
      sorted = []
      
      while !queue.empty?
        node = queue.shift
        sorted << node
        
        @edges[node].each do |neighbor|
          in_degree[neighbor] -= 1
          queue << neighbor if in_degree[neighbor] == 0
        end
      end
      
      if sorted.size != @nodes.size
        raise "Graph has a cycle - topological sort not possible"
      end
      
      sorted
    end
    
    private
    
    def has_cycle_util?(node, visited, rec_stack)
      visited.add(node)
      rec_stack.add(node)
      
      @edges[node].each do |neighbor|
        if !visited.include?(neighbor)
          return true if has_cycle_util?(neighbor, visited, rec_stack)
        elsif rec_stack.include?(neighbor)
          return true
        end
      end
      
      rec_stack.delete(node)
      false
    end
    
    def find_cycles_util(node, visited, path, cycles)
      return if visited.include?(node)
      
      if path.include?(node)
        # Found a cycle
        cycle_start = path.index(node)
        cycles << path[cycle_start..-1] + [node]
        return
      end
      
      path << node
      
      @edges[node].each do |neighbor|
        find_cycles_util(neighbor, visited, path.dup, cycles)
      end
      
      visited.add(node)
    end
    
    def calculate_in_degrees
      in_degree = Hash.new(0)
      
      @nodes.keys.each do |node|
        in_degree[node] ||= 0
      end
      
      @edges.each do |from, to_set|
        to_set.each do |to|
          in_degree[to] += 1
        end
      end
      
      in_degree
    end
  end
end