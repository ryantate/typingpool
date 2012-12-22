module Typingpool
  class Filer

    #Convenience wrapper for CSV files. Makes them Enumerable, so you
    #can iterate through rows with each, map, select, etc. You can
    #also modify in place with each!. See Filer base class for other
    #methods.
    class CSV < Filer
      include Enumerable
      require 'csv'

      #Reads into an array of hashes, with hash keys determined by the
      #first row of the CSV file. Parsing rules are the default for
      #CSV.parse.
      def read
        raw = super or return []
        rows = ::CSV.parse(raw.to_s)
        headers = rows.shift or raise Error::File, "No CSV at #{@path}"
        rows.map{|row| Utility.array_to_hash(row, headers) }
      end

      #Takes array of hashes followed by optional list of keys (by
      #default keys are determined by looking at all the
      #hashes). Lines are written per the defaults of
      #CSV.generate_line.
      def write(hashes, headers=hashes.map{|h| h.keys}.flatten.uniq)
        super(
              ::CSV.generate_line(headers, :encoding => @encoding) + 
              hashes.map do |hash|
                ::CSV.generate_line(headers.map{|header| hash[header] }, :encoding => @encoding)
              end.join
              )
      end

      #Takes an array of arrays, corresponding to the rows, and a list
      #of headers/keys to write at the top.
      def write_arrays(arrays, headers)
        write(arrays.map{|array| Utility.array_to_hash(array, headers) }, headers)
      end

      #Enumerate through the rows, with each row represented by a
      #hash.
      def each
        read.each do |row|
          yield row
        end
      end

      #Same as each, but any changes to the rows will be written back
      #out to the underlying CSV file.
      def each!
        #each_with_index doesn't return the array, so we have to use each
        write(each{|hash| yield(hash) })
      end
    end #CSV
  end #Filer
end #Typingpool
