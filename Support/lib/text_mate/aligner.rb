# Aligns assignments in source files
module TextMate
  class Aligner
    FALLBACK_REGEXES = ["/(,)(?!$)/","/\}/","/<-/","/\s[-+\/*|]?(=)\s/","/\s(=>)\s/","/:/","/\/\//"].join('ø')

    def initialize(text, patterns = nil, options = {})
      @text         = text
      @regexps_hash = build_regexps_hash(patterns)
    end

    # Formats a single block.
    def format_block(block_dict, regexps_hash)
      text = trim_all_whitespace(block_dict['lines'].join)
      prioritize_regexps(text, regexps_hash).each do |regexp_hash|
        text = align(text, regexp_hash, width(text, regexp_hash['regexp']))
      end
      text
    end

    def build_regexps_hash(alignment_pattern = nil)
      alignment_pattern ||= FALLBACK_REGEXES
      alignment_pattern.
        split('ø').
        map do |r|
          md = r.match("/(.*)/(.*)")
          { "regexp"  => Regexp.new(md[1]),
            "spacing" => md[2] }
        end
    end

    def align(text, regexp_hash, width)
      text.to_a.map do |line|
        if is_all_whitespace(line)
          line
        elsif offset = offset_of_regexp_in_line(line, regexp_hash['regexp'])
          if should_insert_before(line, regexp_hash)
            before = line[0..offset-1]
            before + ' ' * (width - (before.length)) + line[offset..line.length-1]
          else
            before = line[0..offset]
            before + ' ' * (width - (before.length-1)) + line[offset+1..line.length-1]
          end
        else
          line
        end
      end.join
    end

    # Figures out if the spacing should be added before or after the match.
    # This is chosen by the bundle developer by using the regexp options 'a'
    # or 'b' where a is after and b is before
    def should_insert_before(line, regexp_hash)
      !(regexp_hash['spacing'] == "a")
    end

    # Finds the width of the line with the most text before the regexp.
    def width(text, regexp)
      text.split("\n").collect { |line| offset_of_regexp_in_line(line,regexp) }.max
    end

    # The offset of a regexp in a line of text. -1 if it doesn't match
    def offset_of_regexp_in_line(line, regexp)
      if match = regexp.match(line)
        match.offset(match.size > 1 ? 1 : 0)[0]
      else
        -1
      end
    end

    # Checks that the regexp matches every line
    def has_match_for_all(text, regexp)
      text.to_a.all?{ |line| line =~ regexp }
    end

    def left_spacing(line)
      line.chars.take_while { |char| char =~ /\s/ }.join
    end

    # squeeces all whitspace in the line (preserves the left spacing)
    def trim_all_whitespace(text)
      text.to_a.map do |line|
        left_spacing(line) + line.squeeze(" ").squeeze("  ").lstrip #the 2. is a tab
      end.join
    end

    def is_all_whitespace(line)
      if /^\s*$/.match(line)
        true
      else
        false
      end
    end

    # finds the minimum offset of the capture of a regexp across all lines in a text.
    def min_offset_of_regexp(text,regexp_hash)
      min_offset = text.split("\n").map { |line| offset_of_regexp_in_line(line, regexp_hash['regexp']) }.min
      { "min_offset" => min_offset, "regexp_hash" => regexp_hash }
    end

    # sorts and filters the regular expressions so the ones with the captures with the
    # lowest offset comes first. The ones that aren't matched or doesn't need alignment
    # are filtered out
    def prioritize_regexps(text, regexps_hash)
      no_blank_lines = text.to_a.reject { |line| is_all_whitespace(line) }.join
      regexps_hash.
        select  { |rh|    has_match_for_all(no_blank_lines, rh['regexp']) }.
        collect { |rh|    min_offset_of_regexp(no_blank_lines, rh) }.
        select  { |d|     not d['min_offset'].nil? }.
        sort    { |d1,d2| d1['min_offset'] <=> d2['min_offset'] }.
        select  { |d|     d['min_offset'] > 0 }.
        collect { |d|     d['regexp_hash'] }
    end

    # Finds blocks of code to align. It uses the following heuristics:
    #
    #   - A line belongs to the previous block if it has the same indentation
    #
    # returns an array of dictionaries with the keys 'block', 'from', 'to' that
    # expresses which lines the block spans.
    def find_blocks(text)
      lines = text.to_a

      initial = {
        'prev'   => lines[0],
        'blocks' => [{
          'lines' => [],
          'from'  => 0,
          'to'    => 0
        }]
      }

      text.to_a.reduce(initial) do |reduced, line|
        blocks = reduced['blocks']

        if is_all_whitespace(line)
          blocks[blocks.size-1]['lines'] << line
          blocks[blocks.size-1]['to']  = blocks[blocks.size-1]['to'] + 1
          { 'prev' => reduced['prev'], 'blocks' => blocks}
        elsif left_spacing(line) == left_spacing(reduced['prev'])
          blocks[blocks.size-1]['lines'] << line
          blocks[blocks.size-1]['to']  = blocks[blocks.size-1]['to'] + 1
          { 'prev' => line, 'blocks' => blocks}
        else
          blocks << {
            'lines' => [line],
            'from'  => blocks[blocks.size-1]['to'],
            'to'    => blocks[blocks.size-1]['to'] + 1
          }
          { 'prev' => line, 'blocks' => blocks}
        end
      end['blocks']
    end
  end
end

=begin
  Great, lets get to the formatting then.
=end


regexps_hash = TextMate::Align.build_regexps_hash(ENV['TM_SOURCE_ALIGNMENT_PATTERN'])
text    = STDIN.readlines.join

if ENV['TM_SELECTED_TEXT'].nil?
  format_block_containing_line(text, ENV['TM_LINE_NUMBER'].to_i - 1, regexps_hash)
else
  format_all(text, regexps_hash)
end
