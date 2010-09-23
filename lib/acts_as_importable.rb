module Acts
  module Importable
    
    def self.included(base)
      base.extend(ClassMethods)
    end
    
    module ClassMethods
      
      def acts_as_importable(options = {})
        # Store the import target class with the legacy class
        write_inheritable_attribute :importable_to, options[:to]
        
        # Don't extend or include twice. This will allow acts_as_importable to be called multiple times.
        # eg. once in a parent class and once again in the child class, where it can override some options.
        extend  AMC::Acts::Importable::SingletonMethods unless self.methods.include?('import') && self.methods.include?('import_all')
        include AMC::Acts::Importable::InstanceMethods unless self.included_modules.include?(AMC::Acts::Importable::InstanceMethods)
      end
      
    end # ClassMethods
    
    module SingletonMethods
      def import(id)
        find(id).import
      end

      def import_all
        all.each do |legacy_model|
          legacy_model.import
        end
      end
      
      # This requires a numeric primary key for the legacy tables
      def import_all_in_batches
        each do |legacy_model|
          legacy_model.import
        end
      end

      def lookup(*args)
        lookup_class = Kernel.const_get(read_inheritable_attribute(:importable_to) || "#{self.to_s.split('::').last}")

        lookups[id] ||= if lookup_class.column_names.include?('legacy_id_1')
          
          num_id_columns = 1
          while legacy_class.column_names.include?("legacy_id_#{num_id_columns + 1}")
            num_id_columns += 1
          end
          
          cond_hash = {}
          1.upto(num_id_colums) do |num|
            cond_hash["legacy_id_#{num}"] = args[num -1]
          end
          
          lookup_class.first(:conditions => cond_hash.merge{:legacy_class => self.to_s}).try(:id__)
        else
          lookup_class.first(:conditions => {:legacy_id => id, :legacy_class => self.to_s}).try(:id__)
        end
      end

      def flush_lookups!
        @lookups = {}
      end

      private

      def lookups
        @lookups ||= {}
      end

    end # SingletonMethods
    
    module InstanceMethods
      
      def import
        returning to_model do |new_model|
          if new_model
            new_model.legacy_class  = self.class.to_s if new_model.respond_to?(:"legacy_class=")
            
            if self.class.respond_to?(:primary_keys)
              # The legacy class has composite primary keys
              self.class.primary_keys.each_with_index do |key, index|
                new_model.send(:"legacy_id_#{index+1}=", key.to_s) if new_model.respond_to?(:"legacy_id_#{index+1}=")
              end
            else
              new_model.legacy_id = self.id if new_model.respond_to?(:"legacy_id=")
            end
            
            if !new_model.save
              p new_model.errors
              # TODO log an error that the model failed to save
              # TODO remove the raise once we're out of the development cycle
              raise
            end
          end
        end
      end
    end # InstanceMethods
    
  end
end
